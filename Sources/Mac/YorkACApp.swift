import SwiftUI

@main
@MainActor
struct YorkACApp: App {
    @StateObject private var store = ACStore()

    var body: some Scene {
        WindowGroup("约克空调") {
            RootView()
                .environmentObject(store)
        }
        .windowResizability(.contentSize)

        // 菜单栏：显示当前温度，点一下就能控制，不用开窗口
        MenuBarExtra {
            RootView(compact: true)
                .environmentObject(store)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: store.menuSymbol)
                Text(store.menuTitle)
            }
        }
        .menuBarExtraStyle(.window)
    }
}
