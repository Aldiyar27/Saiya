import SwiftUI

struct RootView: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var confettiID = 0
    @State private var showConfetti = false

    var body: some View {
        TabView {
            TodayView().tabItem { Label("Сегодня", systemImage: "sparkles") }
            HealthView().tabItem { Label("Здоровье", systemImage: "heart.fill") }
            SleepView().tabItem { Label("Сон", systemImage: "moon.zzz.fill") }
            ChatView().tabItem { Label("Saiya", systemImage: "bubble.left.and.bubble.right.fill") }
            JourneyView().tabItem { Label("Путь", systemImage: "trophy.fill") }
        }
        .tint(Theme.mint)
        .overlay(alignment: .top) {
            if let text = vm.toast {
                ToastView(text: text)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay {
            if showConfetti { ConfettiView().id(confettiID) }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: vm.toast)
        .onChange(of: vm.celebration) { _ in
            confettiID += 1
            showConfetti = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { showConfetti = false }
        }
    }
}
