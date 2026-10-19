import SwiftUI

@main
@MainActor
struct LengnuanApp: App {
    @StateObject private var store = ACStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ZStack {
                ACBackground().ignoresSafeArea()
                ScrollView {
                    RootView()
                        .frame(maxWidth: 520)
                        .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .environmentObject(store)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { store.becameActive() }
            }
        }
    }
}
