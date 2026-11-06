import Foundation
import HealthKit

/// Единственная точка доступа приложения к Apple Health / HealthKit.
final class HealthKitManager {
    private let store = HKHealthStore()
    private let cal = Calendar.current

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .flightsClimbed)!,
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
            HKObjectType.quantityType(forIdentifier: .respiratoryRate)!,
            HKObjectType.quantityType(forIdentifier: .bodyMass)!,
            HKObjectType.workoutType()
        ]
        return types
    }

    func requestAuthorization() async throws {
        guard isAvailable else { return }
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    /// Реальные данные из Apple Health за последние N дней.
    func fetchDailyMetrics(days: Int = 30) async -> [DailyMetrics] {
        let start = cal.startOfDay(for: cal.date(byAdding: .day, value: -(days - 1), to: Date())!)

        async let sleep = sleepByDay(from: start)
        async let steps = dailyStat(.stepCount, .cumulativeSum, HKUnit.count(), from: start)
        async let hr = dailyStat(.restingHeartRate, .discreteAverage,
                                  HKUnit.count().unitDivided(by: .minute()), from: start)
        async let workouts = workoutMinutesByDay(from: start)
        async let energy = dailyStat(.activeEnergyBurned, .cumulativeSum, .kilocalorie(), from: start)
        async let distance = dailyStat(.distanceWalkingRunning, .cumulativeSum, .meter(), from: start)
        async let flights = dailyStat(.flightsClimbed, .cumulativeSum, .count(), from: start)
        async let hrv = dailyStat(.heartRateVariabilitySDNN, .discreteAverage, .secondUnit(with: .milli), from: start)
        async let respiratory = dailyStat(.respiratoryRate, .discreteAverage,
                                           HKUnit.count().unitDivided(by: .minute()), from: start)

        let (s, st, h, w, e, d, f, v, rr) =
            await (sleep, steps, hr, workouts, energy, distance, flights, hrv, respiratory)

        return (0..<days).compactMap { offset in
            guard let day = cal.date(byAdding: .day, value: offset, to: start) else { return nil }
            return DailyMetrics(
                date: day,
                sleepHours: s[day],
                steps: st[day],
                restingHR: h[day],
                workoutMinutes: w[day] ?? 0,
                activeEnergy: e[day],
                distanceKm: d[day].map { $0 / 1000 },
                flights: f[day],
                hrv: v[day],
                respiratoryRate: rr[day]
            )
        }
    }

    func fetchSnapshot(days: Int = 7) async -> HealthSnapshot {
        let metrics = await fetchDailyMetrics(days: days)
        let latestWeight = await latestQuantity(.bodyMass, unit: .gramUnit(with: .kilo))
        let recent = metrics.suffix(7)

        func average(_ values: [Double?]) -> Double? {
            let xs = values.compactMap { $0 }
            guard !xs.isEmpty else { return nil }
            return xs.reduce(0, +) / Double(xs.count)
        }

        return HealthSnapshot(
            weightKg: latestWeight,
            latestHeartRate: average(recent.map(\.restingHR)),
            latestHRV: average(recent.map(\.hrv)),
            latestRespiratoryRate: average(recent.map(\.respiratoryRate)),
            latestActiveEnergy: average(recent.map(\.activeEnergy)),
            latestDistanceKm: average(recent.map(\.distanceKm)),
            latestSteps: average(recent.map(\.steps)),
            latestWorkoutMinutes: recent.map(\.workoutMinutes).reduce(0, +),
            updatedAt: Date()
        )
    }

    // MARK: - Сон по ночам: стадии, время отбоя и пробуждения

    func fetchSleepNights(days: Int = 14) async -> [SleepNight] {
        let start = cal.startOfDay(for: cal.date(byAdding: .day, value: -(days - 1), to: Date())!)
        let from = cal.date(byAdding: .hour, value: -12, to: start)!
        return await withCheckedContinuation { cont in
            let pred = HKQuery.predicateForSamples(withStart: from, end: Date())
            let q = HKSampleQuery(
                sampleType: HKCategoryType(.sleepAnalysis),
                predicate: pred,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { [cal] _, samples, _ in
                let list = (samples as? [HKCategorySample]) ?? []
                cont.resume(returning: HealthKitManager.buildNights(list, cal: cal, from: start))
            }
            store.execute(q)
        }
    }

    private typealias Interval = (start: Date, end: Date)

    private static func merge(_ list: [Interval]) -> [Interval] {
        var out: [Interval] = []
        for iv in list.sorted(by: { $0.start < $1.start }) {
            if let last = out.last, iv.start <= last.end {
                out[out.count - 1] = (last.start, max(last.end, iv.end))
            } else {
                out.append(iv)
            }
        }
        return out
    }

    private static func length(_ list: [Interval]) -> Double {
        list.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) } / 3600
    }

    private static func buildNights(_ samples: [HKCategorySample], cal: Calendar, from start: Date) -> [SleepNight] {
        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleep.rawValue,
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue
        ]
        var asleep: [Date: [Interval]] = [:]
        var deep: [Date: [Interval]] = [:]
        var rem: [Date: [Interval]] = [:]
        var core: [Date: [Interval]] = [:]
        var awake: [Date: [Interval]] = [:]
        var inBed: [Date: [Interval]] = [:]

        for s in samples {
            let day = cal.startOfDay(for: s.endDate)
            guard day >= start else { continue }
            let iv: Interval = (s.startDate, s.endDate)
            let v = s.value
            if asleepValues.contains(v) { asleep[day, default: []].append(iv) }
            if v == HKCategoryValueSleepAnalysis.inBed.rawValue { inBed[day, default: []].append(iv) }
            if v == HKCategoryValueSleepAnalysis.asleepDeep.rawValue { deep[day, default: []].append(iv) }
            else if v == HKCategoryValueSleepAnalysis.asleepREM.rawValue { rem[day, default: []].append(iv) }
            else if v == HKCategoryValueSleepAnalysis.asleepCore.rawValue { core[day, default: []].append(iv) }
            else if v == HKCategoryValueSleepAnalysis.awake.rawValue { awake[day, default: []].append(iv) }
        }

        func hoursOrNil(_ list: [Interval]?) -> Double? {
            guard let list, !list.isEmpty else { return nil }
            return length(merge(list))
        }

        var days = asleep
        var estimated = Set<Date>()
        for (d, l) in inBed where days[d] == nil { days[d] = l; estimated.insert(d) }

        var result: [SleepNight] = []
        for (day, list) in days {
            let merged = merge(list)
            let total = length(merged)
            guard total > 0, total < 16 else { continue }

            // Промежутки до 90 минут считаем одним сном; основная часть — самая длинная.
            var sessions: [[Interval]] = []
            for iv in merged {
                if let lastEnd = sessions.last?.last?.end, iv.start.timeIntervalSince(lastEnd) <= 90 * 60 {
                    sessions[sessions.count - 1].append(iv)
                } else {
                    sessions.append([iv])
                }
            }
            let main = sessions.max(by: { length($0) < length($1) }) ?? []
            let bed = main.first?.start
            let wake = main.last?.end

            var awakeH: Double? = nil
            if let b = bed, let w = wake {
                let inside = (awake[day] ?? []).filter { $0.end > b && $0.start < w }
                awakeH = hoursOrNil(inside)
            }

            result.append(SleepNight(date: day, asleepHours: total,
                                     deepHours: hoursOrNil(deep[day]),
                                     remHours: hoursOrNil(rem[day]),
                                     coreHours: hoursOrNil(core[day]),
                                     awakeHours: awakeH,
                                     bedtime: bed, wakeTime: wake,
                                     isEstimate: estimated.contains(day)))
        }
        return result.sorted { $0.date < $1.date }
    }

    private func dailyStat(
        _ id: HKQuantityTypeIdentifier,
        _ option: HKStatisticsOptions,
        _ unit: HKUnit,
        from start: Date
    ) async -> [Date: Double] {
        await withCheckedContinuation { cont in
            let type = HKQuantityType(id)
            let q = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: nil,
                options: option,
                anchorDate: start,
                intervalComponents: DateComponents(day: 1)
            )

            q.initialResultsHandler = { _, results, _ in
                var out: [Date: Double] = [:]
                results?.enumerateStatistics(from: start, to: Date()) { stat, _ in
                    let quantity = option == .cumulativeSum
                        ? stat.sumQuantity()
                        : stat.averageQuantity()

                    if let value = quantity?.doubleValue(for: unit) {
                        out[self.cal.startOfDay(for: stat.startDate)] = value
                    }
                }
                cont.resume(returning: out)
            }
            store.execute(q)
        }
    }

    private func latestQuantity(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        await withCheckedContinuation { cont in
            let type = HKQuantityType(id)
            let predicate = HKQuery.predicateForSamples(
                withStart: cal.date(byAdding: .day, value: -30, to: Date()),
                end: Date()
            )
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

            let q = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                let sample = samples?.first as? HKQuantitySample
                cont.resume(returning: sample?.quantity.doubleValue(for: unit))
            }
            store.execute(q)
        }
    }

    private func sleepByDay(from start: Date) async -> [Date: Double] {
        await withCheckedContinuation { cont in
            let pred = HKQuery.predicateForSamples(withStart: start, end: Date())
            let q = HKSampleQuery(
                sampleType: HKCategoryType(.sleepAnalysis),
                predicate: pred,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { [cal] _, samples, _ in
                var out: [Date: Double] = [:]

                // Только реальные состояния сна, не inBed/awake.
                let asleepValues: Set<Int> = [
                    HKCategoryValueSleepAnalysis.asleep.rawValue,
                    HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue
                ]

                // Группируем интервалы по дню пробуждения и объединяем пересечения,
                // чтобы сон из нескольких источников (iPhone, Watch, приложения) не считался дважды.
                var intervals: [Date: [(Date, Date)]] = [:]
                for sample in (samples as? [HKCategorySample]) ?? []
                    where asleepValues.contains(sample.value) {
                    let day = cal.startOfDay(for: sample.endDate)
                    intervals[day, default: []].append((sample.startDate, sample.endDate))
                }
                // Запасной вариант: если за день нет «asleep», берём «в кровати» (iPhone без Watch).
                var bedOnly: [Date: [(Date, Date)]] = [:]
                for sample in (samples as? [HKCategorySample]) ?? []
                    where sample.value == HKCategoryValueSleepAnalysis.inBed.rawValue {
                    bedOnly[cal.startOfDay(for: sample.endDate), default: []].append((sample.startDate, sample.endDate))
                }
                for (day, list) in bedOnly where intervals[day] == nil { intervals[day] = list }
                for (day, list) in intervals {
                    var total: TimeInterval = 0
                    var current: (Date, Date)?
                    for iv in list.sorted(by: { $0.0 < $1.0 }) {
                        if let c = current {
                            if iv.0 <= c.1 {
                                current = (c.0, max(c.1, iv.1))
                            } else {
                                total += c.1.timeIntervalSince(c.0)
                                current = iv
                            }
                        } else {
                            current = iv
                        }
                    }
                    if let c = current { total += c.1.timeIntervalSince(c.0) }
                    out[day] = total / 3600
                }
                cont.resume(returning: out)
            }
            store.execute(q)
        }
    }

    private func workoutMinutesByDay(from start: Date) async -> [Date: Double] {
        await withCheckedContinuation { cont in
            let pred = HKQuery.predicateForSamples(withStart: start, end: Date())
            let q = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: pred,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { [cal] _, samples, _ in
                var out: [Date: Double] = [:]
                for workout in (samples as? [HKWorkout]) ?? [] {
                    out[cal.startOfDay(for: workout.startDate), default: 0] +=
                        workout.duration / 60
                }
                cont.resume(returning: out)
            }
            store.execute(q)
        }
    }
}
