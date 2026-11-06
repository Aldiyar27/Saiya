import SwiftUI
import Charts

extension Notification.Name {
    /// Отправляется, когда воду добавили из уведомления (приложение могло быть закрыто).
    static let saiyaWaterChanged = Notification.Name("saiyaWaterChanged")
}

/// Хранилище воды. Работает без AppViewModel, чтобы кнопка «+250 мл» в уведомлении
/// могла записать воду, даже если приложение не запущено.
enum WaterStore {
    private static let entriesKey = "waterEntries"
    private static let goalKey = "waterGoalML"

    static func load() -> [WaterEntry] {
        guard let data = UserDefaults.standard.data(forKey: entriesKey),
              let list = try? JSONDecoder().decode([WaterEntry].self, from: data) else { return [] }
        return list
    }

    static func save(_ list: [WaterEntry]) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let trimmed = list.filter { $0.date >= cutoff }
        UserDefaults.standard.set(try? JSONEncoder().encode(trimmed), forKey: entriesKey)
    }

    @discardableResult
    static func add(_ ml: Int, at date: Date = Date()) -> [WaterEntry] {
        var list = load()
        list.append(WaterEntry(date: date, ml: ml))
        save(list)
        return list
    }

    static func total(on day: Date, in list: [WaterEntry]) -> Int {
        list.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }.reduce(0) { $0 + $1.ml }
    }

    static var goal: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: goalKey)
            return v == 0 ? 2000 : v
        }
        set { UserDefaults.standard.set(newValue, forKey: goalKey) }
    }
}

struct WaterDay: Identifiable {
    let date: Date
    let ml: Int
    var id: Date { date }
}

struct WaterView: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var custom = 300.0

    var body: some View {
        Nav {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    progressCard
                    quickCard
                    goalCard
                    logCard
                    weekCard
                }.padding()
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Вода")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
    }

    private var progressCard: some View {
        Card {
            VStack(spacing: 14) {
                ZStack {
                    Circle().stroke(Theme.blue.opacity(0.15), lineWidth: 16)
                    Circle()
                        .trim(from: 0, to: vm.waterProgress)
                        .stroke(Theme.blue, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut, value: vm.waterProgress)
                    VStack(spacing: 2) {
                        Text("\(vm.waterML)").font(.system(size: 40, weight: .bold, design: .rounded))
                        Text("из \(vm.waterGoal) мл").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 170, height: 170)
                .frame(maxWidth: .infinity)

                if vm.waterML >= vm.waterGoal {
                    Label("Норма на сегодня выполнена", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.mint)
                } else {
                    Text("Осталось \(vm.waterGoal - vm.waterML) мл")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var quickCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Добавить").font(.headline)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
                    ForEach([150, 250, 330, 500], id: \.self) { ml in
                        Button("+\(ml)") { vm.addWater(ml) }
                            .buttonStyle(.borderedProminent).tint(Theme.blue)
                    }
                }
                Divider()
                Slider(value: $custom, in: 50...1000, step: 50).tint(Theme.blue)
                Button { vm.addWater(Int(custom)) } label: {
                    Label("Добавить \(Int(custom)) мл", systemImage: "plus.circle.fill").frame(maxWidth: .infinity)
                }.buttonStyle(.bordered)
            }
        }
    }

    private var goalCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Дневная норма").font(.headline)
                Stepper("\(vm.waterGoal) мл",
                        value: Binding(get: { vm.waterGoal }, set: { vm.setWaterGoal($0) }),
                        in: 1000...5000, step: 250)
                if let suggested = vm.suggestedWaterGoal, suggested != vm.waterGoal {
                    Button("Ориентир по весу: \(suggested) мл — применить") { vm.setWaterGoal(suggested) }
                        .font(.footnote)
                }
                Text("Это общий ориентир, а не медицинская рекомендация. Потребность зависит от жары, нагрузки и самочувствия.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var logCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Сегодня").font(.headline)
                    Spacer()
                    if !vm.todayWaterEntries.isEmpty {
                        Button("Отменить последнее") { vm.undoWater() }.font(.caption)
                    }
                }
                if vm.todayWaterEntries.isEmpty {
                    Text("Пока ничего не записано.").font(.footnote).foregroundStyle(.secondary)
                } else {
                    ForEach(vm.todayWaterEntries) { e in
                        HStack {
                            Image(systemName: "drop.fill").foregroundStyle(Theme.blue)
                            Text(e.date.formatted(date: .omitted, time: .shortened))
                            Spacer()
                            Text("\(e.ml) мл").monospacedDigit()
                            Button { vm.removeWater(e.id) } label: {
                                Image(systemName: "trash").foregroundStyle(.secondary)
                            }.buttonStyle(.plain)
                        }.font(.subheadline)
                    }
                }
            }
        }
    }

    private var weekCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Неделя").font(.headline)
                Chart {
                    ForEach(vm.waterWeek) { d in
                        BarMark(x: .value("День", d.date, unit: .day), y: .value("мл", d.ml))
                            .foregroundStyle(d.ml >= vm.waterGoal ? Theme.blue : Theme.blue.opacity(0.4))
                    }
                    RuleMark(y: .value("Норма", vm.waterGoal))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                        .foregroundStyle(Color.secondary)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisValueLabel(format: .dateTime.weekday(.narrow))
                    }
                }
                .frame(height: 170)
                let reached = vm.waterWeek.filter { $0.ml >= vm.waterGoal }.count
                Text("Норма выполнена в \(reached) из 7 дней").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
