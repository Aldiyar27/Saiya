import Foundation

enum MockData {
    static func month() -> [DailyMetrics] {
        let cal = Calendar.current
        return (0..<30).map { i in
            let day = cal.date(byAdding: .day, value: -(29-i), to: cal.startOfDay(for: Date()))!
            let recent = i >= 23
            let steps = recent ? Double.random(in: 3500...6000) : Double.random(in: 6500...10000)
            return DailyMetrics(date: day, sleepHours: recent ? Double.random(in: 6.0...6.8) : Double.random(in: 7.0...8.0), steps: steps, restingHR: Double.random(in: 58...66), workoutMinutes: i % 3 == 0 ? 35 : 0, activeEnergy: Double.random(in: 300...650), distanceKm: steps / 1300, flights: Double.random(in: 2...12), hrv: Double.random(in: 35...70), respiratoryRate: Double.random(in: 13...18))
        }
    }

    static func sleepNights() -> [SleepNight] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<14).map { i in
            let day = cal.date(byAdding: .day, value: -(13 - i), to: today)!
            let recent = i >= 7
            let hours = recent ? Double.random(in: 6.0...7.0) : Double.random(in: 7.0...8.2)
            let awake = Double.random(in: 0.2...0.5)
            let prev = cal.date(byAdding: .day, value: -1, to: day)!
            let bedMinutes = 22 * 60 + 40 + Int.random(in: 0...(recent ? 120 : 45))
            let bed = prev.addingTimeInterval(Double(bedMinutes) * 60)
            let wake = bed.addingTimeInterval((hours + awake) * 3600)
            let deep = hours * 0.16, rem = hours * 0.22
            return SleepNight(date: day, asleepHours: hours, deepHours: deep, remHours: rem,
                              coreHours: hours - deep - rem, awakeHours: awake,
                              bedtime: bed, wakeTime: wake)
        }
    }
}
