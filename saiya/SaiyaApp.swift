import SwiftUI
import Combine

@main
struct SaiyaApp: App {
    @StateObject private var vm = AppViewModel()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        NotificationManager.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(vm)
                .tint(Theme.mint)
                .task { await vm.start() }
                .onChange(of: scenePhase) { phase in
                    if phase == .active { vm.becameActive() }
                }
                .onReceive(NotificationCenter.default.publisher(for: .saiyaWaterChanged).receive(on: DispatchQueue.main)) { _ in
                    vm.reloadWater()
                }
        }
    }
}
