import SwiftUI

struct BreathView: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var minutes = 1
    @State private var running = false
    @State private var finished = false
    @State private var label = "Готов?"
    @State private var scale: CGFloat = 0.55
    @State private var left = 0
    @State private var task: Task<Void, Never>?

    var body: some View {
        Nav {
            VStack(spacing: 24) {
                Spacer()
                ZStack {
                    Circle().fill(Theme.mint.opacity(0.15)).frame(width: 260, height: 260)
                    Circle().fill(Theme.gradient).frame(width: 260, height: 260).scaleEffect(scale)
                }
                Text(label).font(.system(.title, design: .rounded).weight(.bold))
                if running {
                    Text("Осталось \(left / 60):\(String(format: "%02d", left % 60))")
                        .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                } else if finished {
                    Text("Хорошо получилось. Заметь, как ты себя чувствуешь.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                } else {
                    Text("Вдох 4 сек, пауза 2, выдох 6").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                controls
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Подышать")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
            .onDisappear { task?.cancel() }
        }
    }

    @ViewBuilder private var controls: some View {
        if running {
            Button("Остановить") { stop() }.buttonStyle(.bordered)
        } else {
            VStack(spacing: 12) {
                Picker("Длительность", selection: $minutes) {
                    ForEach([1, 2, 3], id: \.self) { Text("\($0) мин").tag($0) }
                }.pickerStyle(.segmented)
                Button { start() } label: {
                    Text(finished ? "Ещё раз" : "Начать").frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).tint(Theme.mint)
            }
        }
    }

    private func start() {
        finished = false
        running = true
        left = minutes * 60
        task = Task { @MainActor in
            let phases: [(String, Int, CGFloat)] = [("Вдох", 4, 1.0), ("Задержи", 2, 1.0), ("Выдох", 6, 0.55)]
            outer: while left > 0 {
                for p in phases {
                    if Task.isCancelled { break outer }
                    label = p.0
                    Haptics.tap()
                    withAnimation(.easeInOut(duration: Double(p.1))) { scale = p.2 }
                    for _ in 0..<p.1 {
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        if Task.isCancelled { break outer }
                        left -= 1
                        if left <= 0 { break outer }
                    }
                }
            }
            running = false
            if !Task.isCancelled {
                finished = true
                label = "Готово"
                withAnimation { scale = 0.55 }
                vm.completeBreathing()
                Haptics.success()
            }
        }
    }

    private func stop() {
        task?.cancel()
        running = false
        label = "Готов?"
        withAnimation { scale = 0.55 }
    }
}
