import Foundation

/// Сравнивает последние 7 дней с личной нормой (предыдущие дни).
struct MetricDelta: Identifiable {
    enum Kind: String { case sleep, steps, heart, workout, energy, distance, flights, hrv, respiratory, screen }
    let kind: Kind
    let recent: Double?
    let baseline: Double?
    var id: String { kind.rawValue }

    var title: String {
        switch kind {
        case .sleep: "Сон"
        case .steps: "Шаги"
        case .heart: "Пульс покоя"
        case .workout: "Тренировки"
        case .energy: "Активные калории"
        case .distance: "Дистанция"
        case .flights: "Этажи"
        case .hrv: "HRV"
        case .respiratory: "Дыхание"
        case .screen: "Экранное время"
        }
    }
    var icon: String {
        switch kind {
        case .sleep: "moon.zzz.fill"
        case .steps: "figure.walk"
        case .heart: "heart.fill"
        case .workout: "dumbbell.fill"
        case .energy: "flame.fill"
        case .distance: "figure.walk.motion"
        case .flights: "stairs"
        case .hrv: "waveform.path.ecg"
        case .respiratory: "lungs.fill"
        case .screen: "iphone"
        }
    }
    /// Для пульса покоя рост — не «хорошо», но мы не оцениваем медицински, только описываем отличие.
    var higherIsBetter: Bool { kind != .heart && kind != .respiratory && kind != .screen }

    var change: Double? {
        guard let r = recent, let b = baseline, b > 0 else { return nil }
        return (r - b) / b
    }
    var isWorse: Bool {
        guard let c = change else { return false }
        return higherIsBetter ? c < -0.15 : c > 0.15
    }
    var isBetter: Bool {
        guard let c = change else { return false }
        return higherIsBetter ? c > 0.15 : c < -0.15
    }

    func format(_ v: Double?) -> String {
        guard let v else { return "—" }
        switch kind {
        case .sleep:
            let m = Int((v * 60).rounded())
            return "\(m / 60)ч \(m % 60)м"
        case .steps: return Int(v).formatted()
        case .heart: return "\(Int(v.rounded())) уд/мин"
        case .workout: return "\(Int(v.rounded())) мин/нед"
        case .energy: return "\(Int(v.rounded())) ккал"
        case .distance: return String(format: "%.1f км", v)
        case .flights: return "\(Int(v.rounded())) этажей"
        case .hrv: return String(format: "%.0f мс", v)
        case .respiratory: return String(format: "%.1f/мин", v)
        case .screen: return String(format: "%.1f ч", v)
        }
    }
    var promptLine: String {
        let pct = change.map { String(format: "%+.0f%%", $0 * 100) } ?? "нет данных"
        return "\(title): сейчас \(format(recent)), обычно \(format(baseline)) (\(pct))"
    }
}

enum BaselineEngine {
    static func compute(_ metrics: [DailyMetrics], checkIns: [CheckIn] = []) -> [MetricDelta] {
        let sorted = metrics.sorted { $0.date < $1.date }
        let recent = Array(sorted.suffix(7))
        var base = Array(sorted.dropLast(min(7, sorted.count)))
        if base.count < 5 { base = sorted }   // мало истории — берём всё

        func avg(_ xs: [Double?]) -> Double? {
            let v = xs.compactMap { $0 }
            return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
        }
        var result = [
            MetricDelta(kind: .sleep, recent: avg(recent.map(\.sleepHours)), baseline: avg(base.map(\.sleepHours))),
            MetricDelta(kind: .steps, recent: avg(recent.map(\.steps)), baseline: avg(base.map(\.steps))),
            MetricDelta(kind: .heart, recent: avg(recent.map(\.restingHR)), baseline: avg(base.map(\.restingHR))),
            MetricDelta(kind: .workout,
                        recent: avg(recent.map { $0.workoutMinutes }).map { $0 * 7 },
                        baseline: avg(base.map { $0.workoutMinutes }).map { $0 * 7 }),
            MetricDelta(kind: .energy, recent: avg(recent.map(\.activeEnergy)),
                        baseline: avg(base.map(\.activeEnergy))),
            MetricDelta(kind: .distance, recent: avg(recent.map(\.distanceKm)),
                        baseline: avg(base.map(\.distanceKm))),
            MetricDelta(kind: .flights, recent: avg(recent.map(\.flights)),
                        baseline: avg(base.map(\.flights))),
            MetricDelta(kind: .hrv, recent: avg(recent.map(\.hrv)),
                        baseline: avg(base.map(\.hrv))),
            MetricDelta(kind: .respiratory, recent: avg(recent.map(\.respiratoryRate)),
                        baseline: avg(base.map(\.respiratoryRate)))
        ]

        // Экранное время берём из ручных отметок (iOS не отдаёт его приложению напрямую).
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let withScreen = checkIns.compactMap { c in c.screenHours.map { (c.date, $0) } }
        let rec = withScreen.filter { $0.0 >= weekAgo }.map(\.1)
        let old = withScreen.filter { $0.0 < weekAgo }.map(\.1)
        if !rec.isEmpty {
            result.append(MetricDelta(kind: .screen,
                                      recent: rec.reduce(0, +) / Double(rec.count),
                                      baseline: old.count >= 3 ? old.reduce(0, +) / Double(old.count) : nil))
        }
        return result
    }

    /// Будни против выходных по шагам.
    static func weekPattern(_ metrics: [DailyMetrics]) -> String? {
        let cal = Calendar.current
        let wd = metrics.filter { !cal.isDateInWeekend($0.date) }.compactMap(\.steps)
        let we = metrics.filter { cal.isDateInWeekend($0.date) }.compactMap(\.steps)
        guard wd.count >= 8, we.count >= 3 else { return nil }
        let a = wd.reduce(0, +) / Double(wd.count)
        let b = we.reduce(0, +) / Double(we.count)
        guard a > 0, b > 0 else { return nil }
        if b / a >= 1.4 {
            return "В будни ты проходишь в среднем \(Int(a).formatted()) шагов, а на выходных — \(Int(b).formatted()). Давай добавим маленькую прогулку в будний день."
        }
        if a / b >= 1.4 {
            return "В будни ты проходишь в среднем \(Int(a).formatted()) шагов, а на выходных — только \(Int(b).formatted()). Попробуй выходной выход на воздух."
        }
        return nil
    }

    static func promptSummary(_ deltas: [MetricDelta], checkIns: [CheckIn],
                              context: DayContext = DayContext(), pattern: String? = nil) -> String {
        var lines = deltas.map(\.promptLine)
        let last = checkIns.suffix(3)
        if !last.isEmpty {
            let f = { (k: KeyPath<CheckIn, Int>) in
                String(format: "%.1f", Double(last.map { $0[keyPath: k] }.reduce(0, +)) / Double(last.count))
            }
            lines.append("Самочувствие (1–5, последние отметки): настроение \(f(\.mood)), энергия \(f(\.energy)), стресс \(f(\.stress))")
        }
        if let pattern { lines.append("Паттерн недели: \(pattern)") }
        lines.append(contentsOf: context.promptLines)
        return lines.joined(separator: "\n")
    }
}

/// Запасной вариант без AI — простые правила с учётом погоды и календаря.
enum LocalInsight {
    static func make(_ deltas: [MetricDelta], context: DayContext = DayContext()) -> AIInsight {
        let worse = deltas.filter(\.isWorse)
        let names = worse.map { $0.title.lowercased() }.joined(separator: ", ")
        let sleepWorse = worse.contains { $0.kind == .sleep }
        let moveWorse = worse.contains { $0.kind == .steps || $0.kind == .workout }
        let screenWorse = worse.contains { $0.kind == .screen }

        if sleepWorse {
            return AIInsight(summary: "Сон за последнюю неделю ниже твоей обычной нормы\(screenWorse ? ", а экранное время выше" : ""). Сегодня стоит беречь вечер.",
                             missionTitle: "Лёгкий вечер",
                             missionDetail: "30 минут без телефона перед сном.", xp: 20)
        }
        if moveWorse || screenWorse {
            let summary = "Изменения по сравнению с твоей нормой: \(names). Хватит маленького шага."
            if let w = context.weather, w.isRainy {
                return AIInsight(summary: summary, missionTitle: "Домашний вечер",
                                 missionDetail: "На улице \(w.summary): 15 минут растяжки, а потом фильм без телефона в руках.", xp: 20)
            }
            if let w = context.weather, let f = context.freeEveningHours, f >= 1 {
                return AIInsight(summary: summary, missionTitle: "Вечерняя прогулка",
                                 missionDetail: "Сегодня \(w.tempC)°C, \(w.summary), вечером свободно около \(String(format: "%.0f", f)) ч. Выйди на 20 минут.", xp: 25)
            }
            return AIInsight(summary: summary, missionTitle: "20 минут на воздухе",
                             missionDetail: "Выйди на прогулку в любое удобное время.", xp: 20)
        }
        return AIInsight(summary: "Сейчас ты в своём привычном ритме. Закрепим это.",
                         missionTitle: "Закрепить ритм",
                         missionDetail: "Ляг сегодня в своё обычное время.", xp: 10)
    }
}
