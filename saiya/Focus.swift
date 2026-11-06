import SwiftUI

/// Таймер фокуса: одна задача, без отвлечений. За завершённую сессию — XP.
struct FocusView: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var minutes = 25
    @State private var endDate: Date?
    @State private var now = Date()
    @State private var finished = false

    private let options = [10, 25, 45]
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var running: Bool { endDate != nil }
    private var total: Double { Double(minutes * 60) }
    private var remaining: Double {
        guard let e = endDate else { return total }
        return max(e.timeIntervalSince(now), 0)
    }
    private var progress: Double { 1 - remaining / max(total, 1) }
    private var timeText: String {
        let s = Int(remaining.rounded(.up))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    var body: some View {
        Nav {
            VStack(spacing: 22) {
                Spacer()
                ZStack {
                    Circle().stroke(Theme.peach.opacity(0.18), lineWidth: 16)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Theme.peach, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: progress)
                    VStack(spacing: 4) {
                        Text(timeText)
                            .font(.system(size: 54, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text(running ? "В фокусе" : finished ? "Готово!" : "Готов?")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 270, height: 270)

                Group {
                    if running {
                        Text("Положи телефон экраном вниз и займись одной задачей.")
                    } else if finished {
                        Text("Отличная работа! Сделай паузу: вода, растяжка, пара глубоких вдохов.")
                    } else {
                        Text("Выбери длительность и начни. Если выйти из приложения, придёт уведомление, когда время закончится.")
                    }
                }
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .padding(.horizontal)

                Card {
                    HStack {
                        Label("Сегодня", systemImage: "timer").font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(vm.focusMinutesToday) мин · всего \(vm.focusMinutesTotal) мин")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Spacer()
                controls
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Фокус")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
            .onReceive(ticker) { t in
                now = t
                if let e = endDate, t >= e { complete() }
            }
            .onDisappear { if running { stop() } }
        }
    }

    @ViewBuilder private var controls: some View {
        if running {
            Button("Остановить") { stop() }.buttonStyle(.bordered)
        } else {
            VStack(spacing: 12) {
                Picker("Длительность", selection: $minutes) {
                    ForEach(options, id: \.self) { Text("\($0) мин").tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: minutes) { _ in finished = false }
                Button { start() } label: {
                    Text(finished ? "Ещё одна сессия" : "Начать").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(Theme.peach)
            }
        }
    }

    private func start() {
        finished = false
        now = Date()
        endDate = now.addingTimeInterval(total)
        NotificationManager.shared.scheduleFocusEnd(after: total)
        Haptics.tap()
    }

    private func stop() {
        endDate = nil
        NotificationManager.shared.cancelFocusEnd()
    }

    private func complete() {
        endDate = nil
        finished = true
        NotificationManager.shared.cancelFocusEnd()
        vm.completeFocus(minutes: minutes)
    }
}
