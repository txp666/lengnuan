import SwiftUI
#if os(macOS)
import AppKit
#endif

// 手机布局：iPhone 上为 true，Mac 上为 false。
// Mac 上的预览 / 截图程序（-D PREVIEW_HARNESS）可以在运行时切换，用来画 iPhone 界面。
#if PREVIEW_HARNESS
var phoneLayout = true
/// 导出截图时为 true：菜单等系统控件换成静态图案（ImageRenderer 画不出来）
var isExporting = false
#elseif os(iOS)
let phoneLayout = true
let isExporting = false
#else
let phoneLayout = false
let isExporting = false
#endif

/// 尺寸：iPhone / Mac 窗口 / Mac 菜单栏
struct Metrics {
    let compact: Bool
    var width: CGFloat? { phoneLayout ? nil : (compact ? 300 : 340) }
    var padding: CGFloat { phoneLayout ? 20 : (compact ? 14 : 18) }
    var spacing: CGFloat { phoneLayout ? 14 : (compact ? 10 : 14) }
    var dial: CGFloat { phoneLayout ? 236 : (compact ? 168 : 200) }
    var arcWidth: CGFloat { phoneLayout ? 15 : 11 }
    var tempFont: CGFloat { phoneLayout ? 76 : (compact ? 48 : 56) }
    var roundButton: CGFloat { phoneLayout ? 56 : (compact ? 40 : 46) }
    var powerButton: CGFloat { phoneLayout ? 70 : (compact ? 52 : 58) }
    var chipHeight: CGFloat { phoneLayout ? 60 : (compact ? 48 : 52) }
    var chipMin: CGFloat { phoneLayout ? 68 : 54 }
    var fanHeight: CGFloat { phoneLayout ? 38 : 30 }
    var cardPadding: CGFloat { phoneLayout ? 14 : 10 }
    var cardRadius: CGFloat { phoneLayout ? 22 : 14 }
}

private func quitApp() {
    #if os(macOS)
    NSApplication.shared.terminate(nil)
    #endif
}

private let brandGradient: [Color] = allModes.first { $0.id == "cool" }?.gradient ?? offGradient

// MARK: - 背景

/// 整个界面的底色：顶部按当前模式染一层淡淡的颜色
struct ACBackground: View {
    @EnvironmentObject var store: ACStore
    @Environment(\.colorScheme) private var scheme

    private var colors: [Color] {
        store.loggedIn && !store.state.isEmpty ? store.state.gradient : brandGradient
    }

    private var base: Color {
        #if os(iOS)
        return Color(uiColor: .systemGroupedBackground)
        #else
        if phoneLayout { return scheme == .dark ? .black : Color(red: 0.95, green: 0.95, blue: 0.97) }
        if isExporting { return scheme == .dark ? Color(white: 0.13) : Color(white: 0.93) }
        return Color(nsColor: .windowBackgroundColor)
        #endif
    }

    var body: some View {
        ZStack {
            base
            LinearGradient(
                colors: [colors[0].opacity(scheme == .dark ? 0.45 : 0.32),
                         colors[1].opacity(scheme == .dark ? 0.12 : 0.08),
                         base.opacity(0)],
                startPoint: .top, endPoint: .center
            )
        }
        .animation(.easeInOut(duration: 0.45), value: store.state.power)
        .animation(.easeInOut(duration: 0.45), value: store.state.mode?.id)
    }
}

struct RootView: View {
    @EnvironmentObject var store: ACStore
    var compact = false

    var body: some View {
        Group {
            if !store.loggedIn {
                LoginView(compact: compact)
            } else if store.current == nil {
                VStack(spacing: 12) {
                    if store.loading {
                        ProgressView()
                        Text("正在读取设备…").foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.orange)
                        Text(store.error ?? "没有找到线控器").multilineTextAlignment(.center)
                        HStack {
                            Button("重试") { Task { await store.start() } }
                            Button("退出登录") { store.logout() }
                        }
                    }
                }
                .padding(24)
                .frame(width: Metrics(compact: compact).width)
            } else {
                ControlView(compact: compact)
            }
        }
        .background(Group {
            if !phoneLayout && !compact { ACBackground() }
        })
        .onAppear { store.viewAppeared() }
        .onDisappear { store.viewDisappeared() }
    }
}

// MARK: - 登录

struct LoginView: View {
    @EnvironmentObject var store: ACStore
    var compact = false
    @State private var phone = ""
    @State private var password = ""
    @State private var code = ""
    @State private var useSMS = false
    @State private var remember = true
    @State private var codeSent = false

    private var canSubmit: Bool {
        !phone.isEmpty && (useSMS ? !code.isEmpty : !password.isEmpty) && !store.loading
    }

    var body: some View {
        VStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: brandGradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 64, height: 64)
                .overlay(Image(systemName: "snowflake").font(.system(size: 30, weight: .semibold)).foregroundColor(.white))
                .shadow(color: brandGradient[1].opacity(0.35), radius: 10, y: 4)
                .padding(.top, phoneLayout ? 40 : 4)
            VStack(spacing: 4) {
                Text("冷暖").font(.title2.bold())
                Text("用「约克智慧家」账号登录").font(.callout).foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                Picker("", selection: $useSMS) {
                    Text("密码").tag(false)
                    Text("短信验证码").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                TextField("手机号", text: $phone)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    #endif

                if useSMS {
                    HStack {
                        TextField("验证码", text: $code)
                            .textFieldStyle(.roundedBorder)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            #endif
                        Button(codeSent ? "重新发送" : "获取验证码") {
                            Task { codeSent = await store.requestCode(phone: phone) }
                        }
                        .disabled(phone.isEmpty)
                    }
                } else {
                    SecureField("密码", text: $password)
                        .textFieldStyle(.roundedBorder)
                    Toggle("记住密码（存在钥匙串，掉线时自动重连）", isOn: $remember)
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(Metrics(compact: compact).cardPadding + 4)
            .background(CardBackground(radius: Metrics(compact: compact).cardRadius))

            Button {
                Task {
                    if useSMS {
                        await store.loginSMS(phone: phone, code: code)
                    } else {
                        await store.login(phone: phone, password: password, remember: remember)
                    }
                }
            } label: {
                HStack {
                    if store.loading { ProgressView().controlSize(.small) }
                    Text("登录").fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(!canSubmit)

            if let e = store.error {
                Text(e).font(.caption).foregroundColor(.red).multilineTextAlignment(.center)
            } else if let m = store.message {
                Text(m).font(.caption).foregroundStyle(.secondary)
            }

            Text("同一账号只能在一处登录：这里登录后，手机上的约克智慧家会被挤下线。建议另注册一个账号，在 App 里邀请进同一个家庭。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            #if os(macOS)
            if compact {
                Divider()
                Button("退出冷暖") { quitApp() }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
            #endif
        }
        .padding(compact ? 16 : 24)
        .frame(width: Metrics(compact: compact).width)
        .onAppear { if phone.isEmpty { phone = store.phone } }
    }
}

// MARK: - 控制

struct ControlView: View {
    @EnvironmentObject var store: ACStore
    var compact = false
    #if os(iOS)
    @State private var showHelp = false
    #endif
    @State private var confirmFilter = false

    private var m: Metrics { Metrics(compact: compact) }
    private var s: ACState { store.state }
    private var colors: [Color] { s.gradient }

    var body: some View {
        VStack(spacing: m.spacing) {
            header
            if store.sessionLost { sessionBanner }
            if let rs = s.runningState { runningBanner(rs) }
            if s.filterDue { filterBanner }
            dialSection
            modeCard
            if s.hasFan { fanCard }
            funcCard
            timerCard
            statusLine
            #if os(macOS)
            if compact { footer }
            #endif
        }
        .padding(m.padding)
        .frame(width: m.width)
        .animation(.easeOut(duration: 0.2), value: s.power)
        .animation(.easeOut(duration: 0.2), value: s.mode?.id)
        #if os(iOS)
        .sheet(isPresented: $showHelp) { SiriHelpView() }
        .sensoryFeedback(.selection, trigger: store.displayTemp)
        .sensoryFeedback(.impact(weight: .medium), trigger: s.power)
        #endif
    }

    // 标题：线控器名 + 在线状态 + 菜单
    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                if store.controllers.count > 1 {
                    Picker("", selection: Binding(
                        get: { store.current?.code ?? "" },
                        set: { store.select(code: $0) }
                    )) {
                        ForEach(store.controllers) { c in Text(c.name).tag(c.code) }
                    }
                    .labelsHidden()
                    .fixedSize()
                } else {
                    Text(store.current?.name ?? "")
                        .font(phoneLayout ? .title2.weight(.bold) : .headline)
                        .lineLimit(1)
                }
                HStack(spacing: 5) {
                    Circle().fill(statusColor).frame(width: 6, height: 6)
                    Text(statusText).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isExporting {
                menuLabel
            } else {
                headerMenu
            }
        }
    }

    private var menuLabel: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: phoneLayout ? 17 : 13, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: phoneLayout ? 38 : 28, height: phoneLayout ? 38 : 28)
            .background(CircleBackground())
            .contentShape(Circle())
    }

    private var headerMenu: some View {
        Menu {
            Button("刷新") { Task { await store.fullRefresh() } }
            Button("重新读取设备") { Task { await store.start() } }
            #if os(iOS)
            Button("Siri 与自动化") { showHelp = true }
            #endif
            Divider()
            Button("退出登录", role: .destructive) { store.logout() }
            #if os(macOS)
            if compact {
                Button("退出冷暖") { quitApp() }
            }
            #endif
        } label: {
            menuLabel
        }
        #if os(macOS)
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        #endif
    }

    private var statusColor: Color {
        if store.sessionLost { return .orange }
        if store.online == false { return .red }
        return store.stale ? .gray : .green
    }

    private var statusText: String {
        if store.sessionLost { return "未连接" }
        if store.online == false { return "线控器离线" }
        if store.stale { return "同步中…" }
        var t = "在线"
        if let r = s.roomTemp { t += " · 室内 \(r)°C" }
        return t
    }

    private var sessionBanner: some View {
        HStack {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
            Text("账号在其他设备登录了").font(.callout)
            Spacer()
            Button("重新连接") { store.reconnect() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.orange.opacity(0.15)))
    }

    private func runningBanner(_ text: String) -> some View {
        HStack {
            ProgressView().controlSize(.small)
            Text(text).font(.callout.weight(.medium))
            Spacer()
            if s.stoppableFunc != nil {
                Button("停止") { store.stopRunning() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(colors[1].opacity(0.15)))
    }

    private var filterBanner: some View {
        HStack {
            Image(systemName: "aqi.medium")
            Text("滤网需要清洗").font(.callout)
            Spacer()
            Button("已清洗，复位") { confirmFilter = true }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.teal.opacity(0.15)))
        .confirmationDialog("滤网清洗好了吗？", isPresented: $confirmFilter, titleVisibility: .visible) {
            Button("已清洗，复位提醒") { store.resetFilter() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("复位后线控器会重新开始计算滤网使用时间。")
        }
    }

    // MARK: 表盘 + 按钮

    private var dialSection: some View {
        VStack(spacing: m.spacing) {
            TempDial(
                fraction: s.fraction(of: store.displayTemp),
                colors: colors,
                active: s.power && s.hasTemp,
                size: m.dial,
                lineWidth: m.arcWidth
            ) {
                VStack(spacing: phoneLayout ? 2 : 0) {
                    HStack(spacing: 4) {
                        Image(systemName: s.power ? (s.mode?.symbol ?? "power") : "power")
                        Text(s.power ? (s.mode?.name ?? "") : "已关机")
                    }
                    .font((phoneLayout ? Font.subheadline : Font.caption).weight(.semibold))
                    .foregroundColor(s.power ? colors[1] : .secondary)

                    if s.hasTemp {
                        HStack(alignment: .top, spacing: 1) {
                            Text(store.displayTemp.map(fmtTemp) ?? "--")
                                .font(.system(size: m.tempFont, weight: .light, design: .rounded))
                                .monospacedDigit()
                                .contentTransition(.numericText())
                            Text("°C")
                                .font(.system(size: m.tempFont * 0.26, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                                .padding(.top, m.tempFont * 0.16)
                        }
                        .foregroundColor(s.power ? .primary : .secondary)
                        .animation(.easeOut(duration: 0.2), value: store.displayTemp)
                    } else {
                        Text("—")
                            .font(.system(size: m.tempFont * 0.8, weight: .light, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text("此模式不设温度").font(.caption).foregroundStyle(.secondary)
                    }

                    if s.hasTemp {
                        let range = s.limits(for: s.mode?.id)
                        Text("\(fmtTemp(range.0))° – \(fmtTemp(range.1))°")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            HStack(spacing: phoneLayout ? 30 : 20) {
                RoundButton(symbol: "minus", size: m.roundButton) { store.nudgeTemp(-1) }
                    .disabled(!canSetTemp)
                PowerButton(on: s.power, colors: colors, size: m.powerButton, busy: store.busy) {
                    store.togglePower()
                }
                .disabled(store.busy || s.isEmpty)
                RoundButton(symbol: "plus", size: m.roundButton) { store.nudgeTemp(1) }
                    .disabled(!canSetTemp)
            }
        }
        .padding(.top, phoneLayout ? 4 : 0)
    }

    private var canSetTemp: Bool {
        !s.isEmpty && s.hasTemp && !s.lockTemp && store.displayTemp != nil
    }

    // MARK: 模式 / 风速

    private var modeCard: some View {
        Card(title: "模式", detail: s.lockMode ? "面板已锁定" : nil, metrics: m) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: m.chipMin), spacing: 8)], spacing: 8) {
                ForEach(s.shownModes) { mode in
                    ModeChip(mode: mode, selected: s.power && s.mode == mode, height: m.chipHeight) {
                        store.setMode(mode.id)
                    }
                    .disabled(s.lockMode || s.isEmpty)
                }
            }
        }
    }

    private var fanCard: some View {
        Card(title: "风速", detail: s.lockFan ? "面板已锁定" : s.fan?.name, metrics: m) {
            HStack(spacing: 3) {
                ForEach(s.shownFans) { f in
                    let selected = s.fan == f
                    Button {
                        store.setFan(f.id)
                    } label: {
                        Text(f.name)
                            .font(.system(size: phoneLayout ? 14 : 12, weight: selected ? .semibold : .regular))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity, minHeight: m.fanHeight)
                            .background(
                                RoundedRectangle(cornerRadius: m.fanHeight * 0.3, style: .continuous)
                                    .fill(selected ? (s.power ? colors[1] : Color.gray) : Color.clear)
                            )
                            .foregroundColor(selected ? .white : .primary)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(s.lockFan || s.isEmpty)
                }
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: m.fanHeight * 0.3 + 3, style: .continuous)
                .fill(Color.primary.opacity(0.06)))
        }
    }

    // MARK: 附加功能

    @ViewBuilder
    private var funcCard: some View {
        let funcs = s.offeredFuncs
        if !funcs.isEmpty {
            let active = s.activeFuncIds
            Card(title: "功能", detail: nil, metrics: m) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4),
                          spacing: phoneLayout ? 12 : 8) {
                    ForEach(funcs) { f in
                        FuncChip(def: f, active: active.contains(f.id),
                                 available: s.funcBlockedReason(f.id) == nil,
                                 tint: colors[1]) {
                            store.toggleFunc(f.id)
                        }
                    }
                }
            }
        }
    }

    // MARK: 定时

    private var timerCard: some View {
        Card(title: "定时", detail: nil, metrics: m) {
            HStack(spacing: 10) {
                Image(systemName: s.timerEnd != nil ? "timer.circle.fill" : "timer")
                    .font(.system(size: phoneLayout ? 24 : 18, weight: .medium))
                    .foregroundColor(s.timerEnd != nil ? colors[1] : .secondary)
                if let end = s.timerEnd {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.timerText ?? "")
                            .font((phoneLayout ? Font.body : Font.callout).weight(.semibold))
                        TimelineView(.periodic(from: Date(), by: 30)) { ctx in
                            Text(remainingText(until: end, now: ctx.date))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 4)
                    if store.timerBusy {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("取消") { store.setTimer(hours: nil) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                } else {
                    Text(s.power ? "到点自动关机" : "到点自动开机")
                        .font(phoneLayout ? .body : .callout)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    if store.timerBusy {
                        ProgressView().controlSize(.small)
                    } else {
                        timerMenu
                    }
                }
            }
        }
        .disabled(s.isEmpty)
    }

    @ViewBuilder
    private var timerMenu: some View {
        if isExporting {
            timerMenuLabel
        } else {
            timerMenuReal
        }
    }

    private var timerMenuLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: "plus")
            Text("设定")
        }
        .font(.system(size: phoneLayout ? 15 : 12, weight: .semibold))
        .foregroundColor(s.power ? colors[1] : .primary)
        .padding(.horizontal, phoneLayout ? 14 : 10)
        .frame(height: phoneLayout ? 34 : 26)
        .background(Capsule().fill((s.power ? colors[1] : Color.primary).opacity(0.12)))
        .contentShape(Capsule())
    }

    private var timerMenuReal: some View {
        let action = s.power ? "关机" : "开机"
        return Menu {
            ForEach(commonTimerHours, id: \.self) { h in
                Button("\(timerDurationText(h))后\(action)") { store.setTimer(hours: h) }
            }
            Menu("更多时长") {
                ForEach(timerHours.filter { !commonTimerHours.contains($0) }, id: \.self) { h in
                    Button("\(timerDurationText(h))后\(action)") { store.setTimer(hours: h) }
                }
            }
        } label: {
            timerMenuLabel
        }
        #if os(macOS)
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        #endif
    }

    // MARK: 状态行

    private var statusLine: some View {
        VStack(spacing: 4) {
            if !s.alarms.isEmpty {
                Label("故障代码 \(s.alarms.joined(separator: ", "))", systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
            }
            if s.lockTemp {
                Label("面板锁定了温度", systemImage: "lock.fill").foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                if store.busy || store.loading { ProgressView().controlSize(.small) }
                if let e = store.error, !store.sessionLost {
                    Label(e, systemImage: "exclamationmark.circle").foregroundColor(.red)
                } else if let msg = store.message {
                    Text(msg).foregroundStyle(.secondary)
                }
            }
        }
        .font(.caption)
        .multilineTextAlignment(.center)
        .frame(minHeight: 16)
    }

    #if os(macOS)
    private var footer: some View {
        HStack {
            Button("打开主窗口") {
                NSApplication.shared.activate(ignoringOtherApps: true)
                for w in NSApplication.shared.windows where w.canBecomeMain { w.makeKeyAndOrderFront(nil) }
            }
            Spacer()
            Button("退出") { quitApp() }
        }
        .buttonStyle(.borderless)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    #endif
}

// MARK: - 组件

/// 270° 的温度圆环，缺口朝下
struct TempDial<Content: View>: View {
    let fraction: Double
    let colors: [Color]
    let active: Bool
    let size: CGFloat
    let lineWidth: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(Color.primary.opacity(0.08), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(135))
            Circle()
                .trim(from: 0, to: max(0.001, 0.75 * fraction))
                .stroke(
                    AngularGradient(colors: colors, center: .center,
                                    startAngle: .degrees(0), endAngle: .degrees(270)),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(135))
                .opacity(active ? 1 : 0.22)
                .shadow(color: active ? colors[1].opacity(0.35) : .clear, radius: 6)
                .animation(.easeOut(duration: 0.3), value: fraction)
            content()
        }
        .frame(width: size, height: size)
    }
}

struct PowerButton: View {
    let on: Bool
    let colors: [Color]
    let size: CGFloat
    var busy = false
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(on ? AnyShapeStyle(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                             : AnyShapeStyle(Color.primary.opacity(0.08)))
                    .shadow(color: on ? colors[1].opacity(0.45) : .clear, radius: 10, y: 4)
                if busy {
                    ProgressView().controlSize(.small).tint(on ? .white : .primary)
                } else {
                    Image(systemName: "power")
                        .font(.system(size: size * 0.36, weight: .semibold))
                        .foregroundColor(on ? .white : .primary)
                }
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .opacity(enabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(on ? "关机" : "开机")
    }
}

struct RoundButton: View {
    let symbol: String
    let size: CGFloat
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundColor(.primary)
                .frame(width: size, height: size)
                .background(CircleBackground())
                .overlay(Circle().stroke(Color.primary.opacity(0.06), lineWidth: 1))
                .contentShape(Circle())
                .opacity(enabled ? 1 : 0.35)
        }
        .buttonStyle(.plain)
    }
}

struct ModeChip: View {
    let mode: ModeDef
    let selected: Bool
    let height: CGFloat
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            VStack(spacing: phoneLayout ? 6 : 4) {
                Image(systemName: mode.symbol)
                    .font(.system(size: phoneLayout ? 19 : 15, weight: .medium))
                Text(mode.name)
                    .font(.system(size: phoneLayout ? 13 : 11, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: height)
            .background(
                RoundedRectangle(cornerRadius: height * 0.28, style: .continuous)
                    .fill(selected
                          ? AnyShapeStyle(LinearGradient(colors: mode.gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                          : AnyShapeStyle(Color.primary.opacity(0.06)))
            )
            .foregroundColor(selected ? .white : mode.color)
            .contentShape(RoundedRectangle(cornerRadius: height * 0.28, style: .continuous))
            .opacity(enabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
    }
}

/// 附加功能按钮：圆形图标 + 名字；当前不能用的变暗（点了会提示原因）
struct FuncChip: View {
    let def: FuncDef
    let active: Bool
    let available: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        let size: CGFloat = phoneLayout ? 48 : 36
        Button(action: action) {
            VStack(spacing: phoneLayout ? 6 : 4) {
                Image(systemName: def.symbol)
                    .font(.system(size: size * 0.4, weight: .medium))
                    .frame(width: size, height: size)
                    .background(Circle().fill(active ? AnyShapeStyle(tint) : AnyShapeStyle(Color.primary.opacity(0.08))))
                    .foregroundColor(active ? .white : .primary)
                Text(def.name)
                    .font(.system(size: phoneLayout ? 12 : 10, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundColor(active ? tint : .primary)
            }
            .frame(maxWidth: .infinity)
            .opacity(available || active ? 1 : 0.35)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(def.name + (active ? "，已打开" : ""))
    }
}

/// 带小标题的圆角卡片
struct Card<Content: View>: View {
    let title: String
    let detail: String?
    let metrics: Metrics
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: phoneLayout ? 10 : 8) {
            HStack {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if let d = detail { Text(d).font(.caption).foregroundStyle(.secondary) }
            }
            content()
        }
        .padding(metrics.cardPadding)
        .background(CardBackground(radius: metrics.cardRadius))
    }
}

/// 卡片底色：iPhone 上是系统分组背景色（和“设置”App 一样），Mac 上是毛玻璃
struct CardBackground: View {
    let radius: CGFloat
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if phoneLayout || isExporting {
            shape.fill(solidCardColor(scheme))
        } else {
            shape.fill(.regularMaterial)
        }
    }
}

struct CircleBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if phoneLayout || isExporting {
            Circle().fill(solidCardColor(scheme))
        } else {
            Circle().fill(.regularMaterial)
        }
    }
}

func solidCardColor(_ scheme: ColorScheme) -> Color {
    #if os(iOS)
    return Color(uiColor: .secondarySystemGroupedBackground)
    #else
    if phoneLayout { return scheme == .dark ? Color(white: 0.11) : .white }
    return scheme == .dark ? Color(white: 0.2) : .white
    #endif
}
