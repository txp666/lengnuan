// 只在 Mac 上用的界面预览 / 截图程序（scripts/preview.command、scripts/screenshots.command 编译）。
// 用演示数据把 iPhone 界面、Mac 界面和各种小组件画出来，不联网。
//   YorkPreview                 打开预览窗口
//   YorkPreview --export <目录>  把截图导出成 PNG 后退出
import AppKit
import SwiftUI

// MARK: - 演示数据

enum Demo {
    /// 制冷 26°，开着睡眠，1.5 小时后关机
    static var cooling: ACState {
        var s = ACState.sample(power: true, mode: "cool", temp: 26)
        s.values["sleep"] = "1"
        s.applyTimer(hours: 1.5, turnOn: false, reply: [:])
        return s
    }

    /// 制热 24.5°，2 小时后关机
    static var heating: ACState {
        var s = ACState.sample(power: true, mode: "heat", temp: 24.5)
        s.values["wire_controller_wind_auto"] = "0"
        s.values["wire_controller_wind_mid"] = "1"
        s.applyTimer(hours: 2, turnOn: false, reply: [:])
        return s
    }

    static var off: ACState { .sample(power: false, mode: "cool", temp: 26) }

    static func entry(_ s: ACState) -> ACEntry {
        ACEntry(date: Date(), state: s, name: "卧室", loggedIn: true)
    }
}

// MARK: - 程序入口

@main
@MainActor
struct PreviewApp: App {
    @StateObject private var coolStore = ACStore(demo: true, demoState: Demo.cooling)
    @StateObject private var offStore = ACStore(demo: true, demoState: Demo.off)

    init() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--export"), i + 1 < args.count {
            Exporter.run(to: URL(fileURLWithPath: args[i + 1]))
            exit(0)
        }
    }

    var body: some Scene {
        WindowGroup("冷暖 · 界面预览") {
            HStack(alignment: .top, spacing: 18) {
                PhoneScreen(store: coolStore, scroll: true).environment(\.colorScheme, .dark)
                PhoneScreen(store: offStore, scroll: true).environment(\.colorScheme, .light)
                WidgetBoard()
            }
            .padding(18)
            .background(Color(white: 0.32))
        }
        .windowResizability(.contentSize)
    }
}

// MARK: - 画面

/// 一部 iPhone：状态栏 + App 界面
struct PhoneScreen: View {
    @ObservedObject var store: ACStore
    var scroll = false

    var body: some View {
        ZStack(alignment: .top) {
            ACBackground().frame(width: 393, height: 852)
            if scroll {
                ScrollView { content }
            } else {
                content
            }
        }
        .environmentObject(store)
        // 内容比屏幕高时从顶部排起，底部被裁掉（和手机上没滚动时一样）
        .frame(width: 393, height: 852, alignment: .top)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 50, style: .continuous))
    }

    private var content: some View {
        VStack(spacing: 0) {
            StatusBar()
            RootView()
            Spacer(minLength: 0)
        }
    }
}

/// 带边框和灵动岛的 iPhone 外框（截图用）
struct PhoneFrame: View {
    @ObservedObject var store: ACStore

    var body: some View {
        PhoneScreen(store: store)
            .overlay(alignment: .top) {
                Capsule().fill(Color.black).frame(width: 124, height: 36).padding(.top, 11)
            }
            .padding(11)
            .background(RoundedRectangle(cornerRadius: 61, style: .continuous).fill(Color(white: 0.07)))
            .overlay(RoundedRectangle(cornerRadius: 61, style: .continuous)
                .stroke(Color(white: 0.35), lineWidth: 1.5))
    }
}

struct StatusBar: View {
    var body: some View {
        HStack {
            Text("9:41").font(.system(size: 17, weight: .semibold))
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "cellularbars")
                Image(systemName: "wifi")
                Image(systemName: "battery.100")
            }
            .font(.system(size: 15, weight: .semibold))
        }
        .padding(.horizontal, 34)
        .frame(height: 54)
    }
}

/// 小组件合集：主屏小号 / 中号 + 锁屏
struct WidgetBoard: View {
    var wallpaper = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 18) {
                home(Demo.cooling, 170, 170) { SmallWidgetView(entry: Demo.entry(Demo.cooling)) }
                home(Demo.off, 170, 170) { SmallWidgetView(entry: Demo.entry(Demo.off)) }
            }
            home(Demo.heating, 358, 170) { MediumWidgetView(entry: Demo.entry(Demo.heating)) }
            home(Demo.cooling, 358, 170) { MediumWidgetView(entry: Demo.entry(Demo.cooling)) }
            HStack(spacing: 14) {
                lock(76, 76) { CircularWidgetView(entry: Demo.entry(Demo.cooling)) }
                lock(76, 76) { CircularWidgetView(entry: Demo.entry(Demo.off)) }
                lock(172, 76) { RectangularWidgetView(entry: Demo.entry(Demo.heating)) }
            }
            lock(358, 30) { InlineWidgetView(entry: Demo.entry(Demo.cooling)) }
        }
        .padding(wallpaper ? 26 : 0)
        .background(Group {
            if wallpaper {
                LinearGradient(colors: [Color(red: 0.20, green: 0.22, blue: 0.42), Color(red: 0.42, green: 0.25, blue: 0.45),
                                        Color(red: 0.85, green: 0.48, blue: 0.40)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        })
        .environment(\.colorScheme, .dark)
    }

    private func home<V: View>(_ s: ACState, _ w: CGFloat, _ h: CGFloat, @ViewBuilder _ v: () -> V) -> some View {
        v()
            .padding(16)
            .frame(width: w, height: h)
            .background(WidgetBackdrop(state: s))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
    }

    private func lock<V: View>(_ w: CGFloat, _ h: CGFloat, @ViewBuilder _ v: () -> V) -> some View {
        v()
            .frame(width: w, height: h)
            .background(RoundedRectangle(cornerRadius: h > 40 ? 20 : 8, style: .continuous)
                .fill(Color.black.opacity(0.3)))
    }
}

/// Mac 窗口（带标题栏）
struct MacWindowShot: View {
    @ObservedObject var store: ACStore

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(Color(red: 1.0, green: 0.37, blue: 0.34)).frame(width: 12, height: 12)
                Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.18)).frame(width: 12, height: 12)
                Circle().fill(Color(red: 0.16, green: 0.79, blue: 0.25)).frame(width: 12, height: 12)
                Spacer()
                Text("冷暖").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Color.clear.frame(width: 52, height: 12)
            }
            .padding(.horizontal, 14)
            .frame(height: 30)
            RootView()
        }
        .background(ACBackground())
        .environmentObject(store)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
    }
}

// MARK: - 导出

@MainActor
enum Exporter {
    static func run(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        isExporting = true
        let cool = ACStore(demo: true, demoState: Demo.cooling)
        let heat = ACStore(demo: true, demoState: Demo.heating)

        phoneLayout = true
        save(PhoneFrame(store: cool).padding(24).environment(\.colorScheme, .dark), "iphone-dark", dir)
        save(PhoneFrame(store: heat).padding(24).environment(\.colorScheme, .light), "iphone-light", dir)
        save(WidgetBoard(wallpaper: true), "widgets", dir)

        phoneLayout = false
        save(MacWindowShot(store: cool).padding(24).environment(\.colorScheme, .dark), "mac", dir)

        phoneLayout = true
        let banner = HStack(alignment: .center, spacing: 28) {
            PhoneFrame(store: cool).environment(\.colorScheme, .dark)
            PhoneFrame(store: heat).environment(\.colorScheme, .light)
            WidgetBoard(wallpaper: true).clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
        }
        .padding(40)
        .background(Color(white: 0.11))
        save(banner, "banner", dir, scale: 1.5)
    }

    private static func save<V: View>(_ view: V, _ name: String, _ dir: URL, scale: CGFloat = 2) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let cg = renderer.cgImage else {
            print("✗ \(name)：渲染失败")
            return
        }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        let url = dir.appendingPathComponent(name + ".png")
        do {
            try png.write(to: url)
            print("✓ \(url.lastPathComponent)  \(cg.width)×\(cg.height)")
        } catch {
            print("✗ \(name)：\(error.localizedDescription)")
        }
    }
}
