import AppIntents
import SwiftUI
import WidgetKit

// MARK: - 数据

struct ACEntry: TimelineEntry {
    let date: Date
    let state: ACState?
    let name: String
    let loggedIn: Bool

    static func cached() -> ACEntry {
        let c = Storage.controller
        var state = Storage.lastState.map { ACState(values: $0, xkqType: c?.xkqType ?? "9") }
        state?.overlay(Storage.constants)
        return ACEntry(date: Date(), state: state, name: c?.name ?? "约克空调",
                       loggedIn: Storage.session != nil)
    }

    static let sample = ACEntry(date: Date(), state: .sample(), name: "卧室", loggedIn: true)
}

struct ACProvider: TimelineProvider {
    func placeholder(in context: Context) -> ACEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (ACEntry) -> Void) {
        completion(context.isPreview ? .sample : .cached())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ACEntry>) -> Void) {
        // 刚发过指令：先显示预期状态，等面板确认后再去云端读
        let optimistic = Storage.optimisticUntil
        if Date() < optimistic {
            completion(Timeline(entries: [.cached()], policy: .after(optimistic.addingTimeInterval(2))))
            return
        }
        Task { @MainActor in
            var entry = ACEntry.cached()
            if Storage.session != nil {
                ACService.shared.reloadSession()
                if let s = try? await ACService.shared.fetchState(reclaim: false) {
                    entry = ACEntry(date: Date(), state: s, name: Storage.controller?.name ?? entry.name,
                                    loggedIn: true)
                }
            }
            var next = Date().addingTimeInterval(15 * 60)
            if let end = entry.state?.timerEnd, end > Date() {
                next = min(next, end.addingTimeInterval(70))   // 定时到点后刷新
            }
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }
}

// MARK: - 共用的显示数据

private struct Look {
    let entry: ACEntry
    var s: ACState? { entry.state }
    var on: Bool { s?.power ?? false }
    var colors: [Color] { s?.gradient ?? offGradient }
    var symbol: String { on ? (s?.mode?.symbol ?? "snowflake") : "power" }
    var temp: String { s?.setpoint.map { fmtTemp($0) } ?? "--" }
    var modeName: String { on ? (s?.mode?.name ?? "") : "已关机" }
    var room: String? { s?.roomTemp.map { "室内\($0)°" } }
    var subtitle: String { [modeName, room].compactMap { $0 }.joined(separator: " · ") }
    var ready: Bool { entry.loggedIn && s != nil }
    var timerClock: String? { s?.timerEnd.map { clockText($0) } }
    var timerText: String? { s?.timerText }
}

/// 主屏小组件的背景：按模式的渐变（关机为灰）
struct WidgetBackdrop: View {
    let state: ACState?
    var body: some View {
        let colors = state?.gradient ?? (allModes.first { $0.id == "cool" }?.gradient ?? offGradient)
        ZStack {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            // 右上角一点高光，层次感
            RadialGradient(colors: [Color.white.opacity(0.22), .clear], center: .topTrailing,
                           startRadius: 0, endRadius: 160)
        }
    }
}

// MARK: - 主屏：小号

struct SmallWidgetView: View {
    let entry: ACEntry
    private var l: Look { Look(entry: entry) }

    var body: some View {
        if !l.ready {
            NotReadyView(loggedIn: entry.loggedIn)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                WidgetHeader(symbol: l.symbol, name: entry.name, badge: l.timerClock)
                Spacer(minLength: 0)
                BigTemp(text: l.temp, on: l.on, size: 44)
                Text(l.subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    WidgetButton(intent: AdjustTemperatureIntent(direction: .down), symbol: "minus",
                                 solid: false, tint: l.colors[1])
                    WidgetButton(intent: TogglePowerIntent(), symbol: "power", solid: l.on, tint: l.colors[1])
                    WidgetButton(intent: AdjustTemperatureIntent(direction: .up), symbol: "plus",
                                 solid: false, tint: l.colors[1])
                }
                .frame(height: 34)
            }
        }
    }
}

// MARK: - 主屏：中号

struct MediumWidgetView: View {
    let entry: ACEntry
    private var l: Look { Look(entry: entry) }

    private var modes: [ACModeOption] {
        let supported = Set((l.s?.shownModes ?? []).map(\.id))
        return [ACModeOption.cool, .heat, .fan, .dry, .auto].filter { supported.contains($0.rawValue) }
            .prefix(4).map { $0 }
    }

    var body: some View {
        if !l.ready {
            NotReadyView(loggedIn: entry.loggedIn)
        } else {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    WidgetHeader(symbol: l.symbol, name: entry.name)
                    Spacer(minLength: 0)
                    BigTemp(text: l.temp, on: l.on, size: 54)
                    Text(l.subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if let t = l.timerText {
                        Label(t, systemImage: "timer")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.top, 2)
                    } else if l.on, let f = l.s?.fan {
                        Text("风速 \(f.name)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        WidgetButton(intent: AdjustTemperatureIntent(direction: .down), symbol: "minus",
                                     solid: false, tint: l.colors[1])
                        WidgetButton(intent: TogglePowerIntent(), symbol: "power", solid: l.on, tint: l.colors[1])
                        WidgetButton(intent: AdjustTemperatureIntent(direction: .up), symbol: "plus",
                                     solid: false, tint: l.colors[1])
                    }
                    .frame(height: 46)
                    HStack(spacing: 8) {
                        ForEach(modes, id: \.self) { m in
                            let def = allModes.first { $0.id == m.rawValue }
                            WidgetModeButton(intent: SetModeIntent(mode: m),
                                             symbol: def?.symbol ?? "circle",
                                             name: def?.name ?? "",
                                             selected: l.on && l.s?.mode?.id == m.rawValue,
                                             tint: def?.color ?? l.colors[1])
                        }
                    }
                    .frame(height: 44)
                }
                .frame(width: 168)
            }
        }
    }
}

// MARK: - 锁屏

struct CircularWidgetView: View {
    let entry: ACEntry
    private var l: Look { Look(entry: entry) }

    var body: some View {
        ZStack {
            #if os(iOS)
            AccessoryWidgetBackground()
            #endif
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(Color.white.opacity(0.25), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(135))
                .padding(5)
            if l.on {
                Circle()
                    .trim(from: 0, to: max(0.001, 0.75 * (l.s?.fraction(of: l.s?.setpoint) ?? 0)))
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(135))
                    .padding(5)
                    .widgetAccentable()
            }
            VStack(spacing: -1) {
                Text(l.on ? l.temp : "关")
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.6)
                Image(systemName: l.symbol).font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(.white)
        }
    }
}

struct RectangularWidgetView: View {
    let entry: ACEntry
    private var l: Look { Look(entry: entry) }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: l.symbol)
                Text(entry.name).lineLimit(1)
            }
            .font(.system(size: 14, weight: .semibold))
            .widgetAccentable()
            Text(l.on ? "\(l.modeName) \(l.temp)°C" : "已关机")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
            if let t = l.timerText {
                Label(t, systemImage: "timer").font(.system(size: 13)).foregroundStyle(.secondary)
            } else if let r = l.room {
                Text(r).font(.system(size: 13)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct InlineWidgetView: View {
    let entry: ACEntry
    private var l: Look { Look(entry: entry) }

    var body: some View {
        let main = l.on ? "\(l.modeName) \(l.temp)°" : "空调已关"
        Label(l.room.map { "\(main) · \($0)" } ?? main, systemImage: l.symbol)
    }
}

// MARK: - 小部件

private struct WidgetHeader: View {
    let symbol: String
    let name: String
    var badge: String? = nil
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 12, weight: .bold))
            Text(name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            Spacer(minLength: 2)
            if let b = badge {
                HStack(spacing: 2) {
                    Image(systemName: "timer")
                    Text(b)
                }
                .font(.system(size: 10, weight: .bold))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.white.opacity(0.22)))
                .lineLimit(1)
                .fixedSize()
            }
        }
        .foregroundStyle(.white.opacity(0.92))
        .widgetAccentable()
    }
}

private struct BigTemp: View {
    let text: String
    let on: Bool
    let size: CGFloat
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(text)
                .font(.system(size: size, weight: .medium, design: .rounded))
                .contentTransition(.numericText())
                .invalidatableContent()
            Text("°")
                .font(.system(size: size * 0.6, weight: .medium, design: .rounded))
        }
        .foregroundStyle(.white.opacity(on ? 1 : 0.55))
        .minimumScaleFactor(0.6)
        .lineLimit(1)
    }
}

struct NotReadyView: View {
    let loggedIn: Bool
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "snowflake").font(.title2)
            Text(loggedIn ? "打开 App 同步状态" : "打开 App 登录")
                .font(.caption.weight(.medium))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct WidgetButton<I: AppIntent>: View {
    let intent: I
    let symbol: String
    let solid: Bool
    let tint: Color

    var body: some View {
        Button(intent: intent) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(minHeight: 32)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(solid ? Color.white : Color.white.opacity(0.22))
                )
                .foregroundStyle(solid ? tint : Color.white)
        }
        .buttonStyle(.plain)
    }
}

struct WidgetModeButton<I: AppIntent>: View {
    let intent: I
    let symbol: String
    let name: String
    let selected: Bool
    let tint: Color

    var body: some View {
        Button(intent: intent) {
            VStack(spacing: 2) {
                Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                Text(name).font(.system(size: 10, weight: .semibold)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(selected ? Color.white : Color.white.opacity(0.18))
            )
            .foregroundStyle(selected ? tint : Color.white)
        }
        .buttonStyle(.plain)
    }
}

#if !PREVIEW_HARNESS

// MARK: - 小组件配置

struct ACWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ACEntry

    var body: some View {
        switch family {
        case .systemMedium:
            MediumWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackdrop(state: entry.state) }
        case .accessoryCircular:
            CircularWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        case .accessoryRectangular:
            RectangularWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        case .accessoryInline:
            InlineWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        default:
            SmallWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackdrop(state: entry.state) }
        }
    }
}

struct ACStatusWidget: Widget {
    let kind = "YorkACStatus"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ACProvider()) { entry in
            ACWidgetView(entry: entry)
        }
        .configurationDisplayName("约克空调")
        .description("查看状态，直接开关、调温、切模式")
        .supportedFamilies([.systemSmall, .systemMedium,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

/// 控制中心 / 锁定屏幕 / 操作按钮 的开关（iOS 18+）
@available(iOS 18.0, *)
struct ACPowerControl: ControlWidget {
    static let kind = "YorkACPowerControl"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind, provider: Provider()) { value in
            ControlWidgetToggle("约克空调", isOn: value, action: SetPowerIntent()) { running in
                Label(running ? "开" : "关", systemImage: running ? "snowflake" : "power")
            }
            .tint(.blue)
        }
        .displayName("空调开关")
        .description("一键开关约克空调")
    }

    struct Provider: ControlValueProvider {
        var previewValue: Bool { false }

        func currentValue() async throws -> Bool {
            isOn(Storage.lastState?[keyPower])
        }
    }
}

@main
struct YorkACWidgets: WidgetBundle {
    var body: some Widget {
        ACStatusWidget()
        if #available(iOS 18.0, *) {
            ACPowerControl()
        }
    }
}

#endif
