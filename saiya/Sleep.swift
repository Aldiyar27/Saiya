import SwiftUI
import Charts
import UIKit

/// Простая аналитика сна. Это описание режима, а не медицинская оценка.
enum SleepAnalytics {
    /// Минуты от полудня-предыдущего дня: 23:30 → 1410, 00:30 → 1470 (чтобы отбой после полуночи считался корректно).
    static func bedtimeMinutes(_ d: Date) -> Double {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        var m = Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
        if m < 12 * 60 { m += 24 * 60 }
        return m
    }

    static func clock(_ minutes: Double) -> String {
        let m = Int(minutes.rounded()) % (24 * 60)
        return String(format: "%02d:%02d", m / 60, m % 60)
    }

    static func hm(_ hours: Double) -> String {
        let m = Int((hours * 60).rounded())
        return "\(m / 60)ч \(m % 60)м"
    }

    static func regularity(_ nights: [SleepNight]) -> (avgBed: Double, spread: Double)? {
        let xs = nights.compactMap { $0.bedtime }.map { bedtimeMinutes($0) }
        guard xs.count >= 3 else { return nil }
        let mean = xs.reduce(0, +) / Double(xs.count)
        let variance = xs.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(xs.count)
        return (mean, variance.squareRoot())
    }

    static func regularityLabel(_ spread: Double) -> String {
        if spread < 30 { return "Стабильный" }
        if spread < 60 { return "Немного плавает" }
        return "Нерегулярный"
    }

    static func debt(_ nights: [SleepNight], goal: Double) -> Double {
        nights.map { max(0, goal - $0.asleepHours) }.reduce(0, +)
    }

    /// 0–100: продолжительность (60%), доля бодрствования (15%, если есть), стабильность отбоя (25%, если хватает ночей).
    static func score(_ n: SleepNight, recent: [SleepNight], goal: Double) -> Int {
        var parts: [(Double, Double)] = [(min(n.asleepHours / max(goal, 1), 1) * 100, 0.6)]
        if let awake = n.awakeHours, n.asleepHours > 0 {
            let efficiency = n.asleepHours / (n.asleepHours + awake)
            parts.append((min(efficiency / 0.95, 1) * 100, 0.15))
        }
        if let r = regularity(recent) {
            parts.append((max(0, 1 - r.spread / 120) * 100, 0.25))
        }
        let weight = parts.map { $0.1 }.reduce(0, +)
        let total = parts.map { $0.0 * $0.1 }.reduce(0, +)
        return Int((total / weight).rounded())
    }

    static func tip(last: SleepNight, recent: [SleepNight], goal: Double) -> String {
        if last.asleepHours < goal - 1 {
            return "Сегодня ляг на 30–40 минут раньше и за полчаса до сна убери экраны — так проще вернуться к норме."
        }
        if let r = regularity(recent), r.spread >= 60 {
            return "Время отбоя заметно плавает. Попробуй держать одно время засыпания с разбросом не больше 30 минут."
        }
        if last.asleepHours >= goal {
            return "Хорошая ночь по продолжительности. Держи тот же режим."
        }
        return "Немного не дотянул до цели. Сегодня можно лечь чуть раньше обычного."
    }
}

struct SleepView: View {
    @EnvironmentObject var vm: AppViewModel
    private var recent: [SleepNight] { Array(vm.nights.suffix(7)) }

    var body: some View {
        Nav {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    lastNightCard
                    statsGrid
                    chartCard
                    tipCard
                    goalCard
                }.padding()
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Сон")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { Task { await vm.refreshHealth() } } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(vm.isLoading)
                }
            }
        }
    }

    // MARK: - Карточки

    @ViewBuilder private var lastNightCard: some View {
        if let n = vm.lastNight {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(vm.nightLabel(n), systemImage: "moon.zzz.fill").font(.headline)
                        Spacer()
                        Text("\(SleepAnalytics.score(n, recent: recent, goal: vm.sleepGoal))/100")
                            .font(.caption.bold())
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Theme.mint.opacity(0.18), in: Capsule())
                    }
                    Text(SleepAnalytics.hm(n.asleepHours))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                    ProgressView(value: min(n.asleepHours / max(vm.sleepGoal, 1), 1)).tint(Theme.blue)
                    Text("Цель: \(SleepAnalytics.hm(vm.sleepGoal))").font(.caption).foregroundStyle(.secondary)
                    if let b = n.bedtime, let w = n.wakeTime {
                        Label("\(b.formatted(date: .omitted, time: .shortened)) → \(w.formatted(date: .omitted, time: .shortened))",
                              systemImage: "bed.double.fill").font(.subheadline)
                    }
                    if let q = n.quality {
                        Text("Самочувствие после сна: \(q) из 5").font(.caption).foregroundStyle(.secondary)
                    }
                    stages(n)
                    if n.isEstimate {
                        Text("Время в кровати из Здоровья, без стадий сна").font(.caption2).foregroundStyle(.secondary)
                    } else {
                        Text("Данные из Apple Health").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Сон", systemImage: "moon.zzz.fill").font(.headline)
                    Text("В Apple Health пока нет сна. Включи «Сон» в приложении «Здоровье» или носи Apple Watch ночью. Если данные там есть, а тут пусто — проверь доступ: Настройки → Здоровье → Доступ к данным → Saiya.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button {
                        if let url = URL(string: "x-apple-health://") { UIApplication.shared.open(url) }
                    } label: {
                        Label("Открыть «Здоровье»", systemImage: "heart.text.square")
                    }.buttonStyle(.borderedProminent).tint(Theme.primary)
                }
            }
        }
    }

    @ViewBuilder private func stages(_ n: SleepNight) -> some View {
        let parts: [(String, Double?, Color)] = [
            ("Глубокий", n.deepHours, Theme.primary),
            ("REM", n.remHours, Theme.blue),
            ("Базовый", n.coreHours, Theme.mint),
            ("Бодрствование", n.awakeHours, Theme.peach)
        ]
        let total = parts.compactMap { $0.1 }.reduce(0, +)
        if total > 0 {
            VStack(alignment: .leading, spacing: 8) {
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(parts.indices, id: \.self) { i in
                            if let h = parts[i].1, h > 0 {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(parts[i].2)
                                    .frame(width: max(4, (geo.size.width - 6) * h / total))
                            }
                        }
                    }
                }.frame(height: 14)
                ForEach(parts.indices, id: \.self) { i in
                    if let h = parts[i].1, h > 0 {
                        HStack {
                            Circle().fill(parts[i].2).frame(width: 8, height: 8)
                            Text(parts[i].0).font(.caption)
                            Spacer()
                            Text(SleepAnalytics.hm(h)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var statsGrid: some View {
        let avg = recent.isEmpty ? nil : recent.map { $0.asleepHours }.reduce(0, +) / Double(recent.count)
        let reg = SleepAnalytics.regularity(recent)
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MiniStat(title: "Среднее за неделю", value: avg.map { SleepAnalytics.hm($0) } ?? "—",
                     icon: "chart.bar.fill", color: Theme.blue)
            MiniStat(title: "Недосып за неделю",
                     value: recent.isEmpty ? "—" : SleepAnalytics.hm(SleepAnalytics.debt(recent, goal: vm.sleepGoal)),
                     icon: "battery.25", color: Theme.peach)
            MiniStat(title: "Средний отбой", value: reg.map { SleepAnalytics.clock($0.avgBed) } ?? "—",
                     icon: "bed.double.fill", color: Theme.mint)
            MiniStat(title: "Режим",
                     value: reg.map { SleepAnalytics.regularityLabel($0.spread) } ?? "—",
                     icon: "clock.fill", color: Theme.lime)
        }
    }

    @ViewBuilder private var chartCard: some View {
        let nights = Array(vm.nights.suffix(14))
        if !nights.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Последние ночи").font(.headline)
                    Chart {
                        ForEach(nights) { n in
                            BarMark(x: .value("Ночь", n.date, unit: .day), y: .value("Часы", n.asleepHours))
                                .foregroundStyle(n.asleepHours >= vm.sleepGoal ? Theme.mint : Theme.peach)
                        }
                        RuleMark(y: .value("Цель", vm.sleepGoal))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                            .foregroundStyle(Color.secondary)
                    }
                    .chartYScale(domain: 0...max(10, (nights.map { $0.asleepHours }.max() ?? 8) + 1))
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day)) { _ in
                            AxisValueLabel(format: .dateTime.weekday(.narrow))
                        }
                    }
                    .frame(height: 190)
                    Text("Пунктир — твоя цель").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder private var tipCard: some View {
        if let n = vm.lastNight {
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Совет", systemImage: "lightbulb.fill").font(.headline)
                    Text(SleepAnalytics.tip(last: n, recent: recent, goal: vm.sleepGoal)).font(.subheadline)
                    Text("Это описание твоего режима, а не медицинская оценка.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var goalCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Цель по сну").font(.headline)
                Stepper("\(SleepAnalytics.hm(vm.sleepGoal))", value: $vm.sleepGoal, in: 5...11, step: 0.5)
            }
        }
    }
}
