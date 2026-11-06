import SwiftUI
import Charts

/// Сводка за последние 7 дней. Считается локально из данных, уже лежащих в приложении.
struct WeeklyReport {
    var avgSleep: Double?
    var avgSteps: Double?
    var stepGoalDays = 0
    var waterDays = 0
    var checkInCount = 0
    var avgMood: Double?
    var focusMinutes = 0
    var journalCount = 0
    var bestStepsDate: Date?
    var bestSteps: Double?
    var highlights: [String] = []
    var rangeText = ""

    var shareText: String {
        var lines = ["Моя неделя в Saiya (\(rangeText))"]
        if let s = avgSleep { lines.append("😴 Сон в среднем: \(SleepAnalytics.hm(s))") }
        if let s = avgSteps { lines.append("🚶 Шагов в день: \(Int(s).formatted())") }
        lines.append("💧 Норма воды: \(waterDays) из 7 дней")
        if let m = avgMood { lines.append("🙂 Среднее настроение: \(String(format: "%.1f", m)) из 5") }
        if focusMinutes > 0 { lines.append("🎯 Фокус: \(focusMinutes) мин") }
        if journalCount > 0 { lines.append("✍️ Записей в дневнике: \(journalCount)") }
        return lines.joined(separator: "\n")
    }

    static func make(history: [DailyMetrics], nights: [SleepNight], water: [WaterDay],
                     checkIns: [CheckIn], focus: [FocusSession], journal: [JournalEntry],
                     stepGoal: Int, waterGoal: Int, sleepGoal: Double) -> WeeklyReport {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let from = cal.date(byAdding: .day, value: -6, to: today) ?? today

        var r = WeeklyReport()
        r.rangeText = "\(from.formatted(.dateTime.day().month(.abbreviated))) – \(today.formatted(.dateTime.day().month(.abbreviated)))"

        let days = history.sorted { $0.date < $1.date }.suffix(7)
        let steps = days.compactMap { $0.steps }
        if !steps.isEmpty { r.avgSteps = steps.reduce(0, +) / Double(steps.count) }
        r.stepGoalDays = steps.filter { $0 >= Double(stepGoal) }.count
        if let best = days.filter({ $0.steps != nil }).max(by: { ($0.steps ?? 0) < ($1.steps ?? 0) }) {
            r.bestStepsDate = best.date
            r.bestSteps = best.steps
        }

        let sleep = nights.suffix(7).map { $0.asleepHours }
        if !sleep.isEmpty { r.avgSleep = sleep.reduce(0, +) / Double(sleep.count) }

        r.waterDays = water.filter { $0.ml >= waterGoal }.count

        let week = checkIns.filter { $0.date >= from }
        r.checkInCount = week.count
        if !week.isEmpty { r.avgMood = Double(week.reduce(0) { $0 + $1.mood }) / Double(week.count) }

        r.focusMinutes = focus.filter { $0.date >= from }.reduce(0) { $0 + $1.minutes }
        r.journalCount = journal.filter { $0.date >= from }.count

        if let d = r.bestStepsDate, let s = r.bestSteps, s > 0 {
            r.highlights.append("Больше всего шагов — \(d.formatted(.dateTime.weekday(.wide))): \(Int(s).formatted())")
        }
        if let s = r.avgSleep {
            if s >= sleepGoal { r.highlights.append("Сон в среднем достиг цели — отличный режим 🌙") }
            else if s >= sleepGoal - 1 { r.highlights.append("До цели по сну не хватает меньше часа в день — попробуй лечь чуть раньше") }
            else { r.highlights.append("Сон ниже цели — это самое выгодное место, чтобы подтянуть неделю") }
        }
        if r.waterDays >= 5 { r.highlights.append("Водная неделя: норма выполнена в \(r.waterDays) днях 💧") }
        if r.stepGoalDays >= 4 { r.highlights.append("Цель по шагам выполнена в \(r.stepGoalDays) днях 🚶") }
        if let m = r.avgMood, m >= 4 { r.highlights.append("Настроение в основном приподнятое 🙂") }
        if r.focusMinutes >= 60 { r.highlights.append("Больше часа глубокого фокуса за неделю 🎯") }
        if r.highlights.isEmpty {
            r.highlights.append("Отмечай день и пей воду — тогда итоги недели станут точнее")
        }
        return r
    }
}

struct MoodPoint: Identifiable {
    let id = UUID()
    let date: Date
    let series: String
    let value: Int
}

/// График настроения, энергии и стресса по отметкам дня.
struct MoodChart: View {
    let checkIns: [CheckIn]

    private static let names = ["Настроение", "Энергия", "Стресс"]

    private var points: [MoodPoint] {
        checkIns.suffix(14).flatMap { c in
            [MoodPoint(date: c.date, series: Self.names[0], value: c.mood),
             MoodPoint(date: c.date, series: Self.names[1], value: c.energy),
             MoodPoint(date: c.date, series: Self.names[2], value: c.stress)]
        }
    }

    var body: some View {
        if checkIns.count < 2 {
            VStack(spacing: 6) {
                Image(systemName: "chart.xyaxis.line").font(.title2).foregroundStyle(.secondary)
                Text("Нужно хотя бы две отметки дня, чтобы увидеть динамику")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity).frame(height: 120)
        } else {
            Chart(points) { p in
                LineMark(x: .value("Дата", p.date, unit: .day),
                         y: .value("Балл", p.value),
                         series: .value("Показатель", p.series))
                    .foregroundStyle(by: .value("Показатель", p.series))
                    .interpolationMethod(.catmullRom)
                PointMark(x: .value("Дата", p.date, unit: .day),
                          y: .value("Балл", p.value))
                    .foregroundStyle(by: .value("Показатель", p.series))
                    .symbolSize(24)
            }
            .chartForegroundStyleScale(domain: Self.names, range: [Theme.mint, Theme.peach, Theme.rose])
            .chartYScale(domain: 1...5)
            .frame(height: 190)
        }
    }
}

struct WeeklyView: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let r = vm.weeklyReport
        return Nav {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header(r)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        MiniStat(title: "Сон, среднее", value: r.avgSleep.map { SleepAnalytics.hm($0) } ?? "—",
                                 icon: "moon.zzz.fill", color: Theme.blue)
                        MiniStat(title: "Шагов в день", value: r.avgSteps.map { Int($0).formatted() } ?? "—",
                                 icon: "figure.walk", color: Theme.mint)
                        MiniStat(title: "Норма воды", value: "\(r.waterDays) из 7",
                                 icon: "drop.fill", color: Theme.blue)
                        MiniStat(title: "Настроение", value: r.avgMood.map { String(format: "%.1f / 5", $0) } ?? "—",
                                 icon: "face.smiling.fill", color: Theme.peach)
                        MiniStat(title: "Фокус, мин", value: "\(r.focusMinutes)",
                                 icon: "timer", color: Theme.peach)
                        MiniStat(title: "Записей в дневнике", value: "\(r.journalCount)",
                                 icon: "book.closed.fill", color: Theme.mint)
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Самочувствие").font(.headline)
                            MoodChart(checkIns: vm.checkIns)
                        }
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Главное за неделю", systemImage: "sparkles").font(.headline)
                            ForEach(r.highlights, id: \.self) { h in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.mint)
                                    Text(h).font(.subheadline)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Итоги недели")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    ShareLink(item: r.shareText) { Image(systemName: "square.and.arrow.up") }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } }
            }
        }
    }

    private func header(_ r: WeeklyReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(r.rangeText).font(.subheadline).opacity(0.8)
            Text("Твоя неделя").font(.system(.title, design: .rounded).weight(.bold))
            Text("Уровень \(vm.level) · \(Levels.title(vm.level)) · серия \(vm.streak) дн.").font(.caption.bold())
        }
        .foregroundStyle(.white)
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}
