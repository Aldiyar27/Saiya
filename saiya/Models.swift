import Foundation

struct DailyMetrics: Identifiable, Codable {
    var id: Date { date }
    let date: Date
    var sleepHours: Double?
    var steps: Double?
    var restingHR: Double?
    var workoutMinutes: Double
    var activeEnergy: Double?
    var distanceKm: Double?
    var flights: Double?
    var hrv: Double?
    var respiratoryRate: Double?
}

struct HealthSnapshot: Codable {
    var weightKg: Double? = nil
    var latestHeartRate: Double? = nil
    var latestHRV: Double? = nil
    var latestRespiratoryRate: Double? = nil
    var latestActiveEnergy: Double? = nil
    var latestDistanceKm: Double? = nil
    var latestSteps: Double? = nil
    var latestWorkoutMinutes: Double? = nil
    var updatedAt: Date? = nil
}

struct CheckIn: Identifiable, Codable {
    var id = UUID()
    var date = Date()
    let mood: Int
    let energy: Int
    let stress: Int
    var screenHours: Double? = nil
    /// Короткая заметка к отметке дня (необязательно).
    var note: String? = nil
}

/// Запись в дневнике благодарности / мыслей.
struct JournalEntry: Identifiable, Codable {
    var id = UUID()
    var date = Date()
    var mood: Int
    var text: String
}

/// Завершённая сессия фокуса.
struct FocusSession: Identifiable, Codable {
    var id = UUID()
    var date = Date()
    var minutes: Int
}

struct AIInsight: Codable {
    var summary: String
    var missionTitle: String
    var missionDetail: String
    var xp: Int
}

struct Mission: Identifiable, Codable {
    var id = UUID()
    var title: String
    var detail: String
    var xp: Int
    var isDone = false
    var date = Date()
    /// main, move, water, mind, sleep, focus, social, food
    var category: String? = nil
    /// Если задано — задание засчитывается автоматически (steps, water, checkin, sleep).
    var auto: String? = nil
}

struct WaterEntry: Identifiable, Codable {
    var id = UUID()
    var date = Date()
    var ml: Int
}

/// Одна ночь сна. `date` — день пробуждения.
struct SleepNight: Identifiable, Codable {
    var id: Date { date }
    let date: Date
    var asleepHours: Double
    var deepHours: Double? = nil
    var remHours: Double? = nil
    var coreHours: Double? = nil
    var awakeHours: Double? = nil
    var bedtime: Date? = nil
    var wakeTime: Date? = nil
    var quality: Int? = nil
    /// true — стадий сна нет, взято время «в кровати» (например, только iPhone без Apple Watch).
    var isEstimate = false
}

struct Badge: Identifiable {
    let id: String
    let icon: String
    let title: String
    let detail: String
    let unlocked: Bool
}

struct ChatMessage: Identifiable, Codable {
    enum Role: String, Codable { case user, assistant }
    var id = UUID()
    let role: Role
    let text: String
}
