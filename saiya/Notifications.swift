import Foundation
import UserNotifications

/// Данные дня, по которым подбирается текст напоминания.
struct ReminderContext {
    var waterLeft = 0
    var stepsLeft = 0
    var missionsLeft = 0
    var checkedInToday = false
    var sleepDebt = 0.0
}

enum ReminderKind { case water, move, breathe, eyes, posture, mood, mission, sleep }

enum ReminderCopy {
    static func make(at date: Date, slot: Int, ctx: ReminderContext?) -> (title: String, body: String, kind: ReminderKind) {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: date)
        let pool: [ReminderKind]
        switch hour {
        case ..<12: pool = [.water, .mood, .move]
        case 12..<18: pool = [.water, .move, .eyes, .breathe, .mission, .posture]
        case 18..<20: pool = [.water, .mission, .breathe, .move]
        default: pool = [.sleep, .breathe, .mission]
        }

        let ord = cal.ordinality(of: .day, in: .era, for: date) ?? 0
        var kind = pool[(ord + slot) % pool.count]
        if let c = ctx {
            for step in 0..<pool.count {
                let k = pool[(ord + slot + step) % pool.count]
                if isUseful(k, c) { kind = k; break }
            }
        }
        let text = copy(for: kind, ctx: ctx)
        return (text.0, text.1, kind)
    }

    private static func isUseful(_ k: ReminderKind, _ c: ReminderContext) -> Bool {
        switch k {
        case .water: return c.waterLeft > 0
        case .mood: return !c.checkedInToday
        case .mission: return c.missionsLeft > 0
        case .move: return c.stepsLeft > 0
        default: return true
        }
    }

    private static func copy(for k: ReminderKind, ctx: ReminderContext?) -> (String, String) {
        switch k {
        case .water:
            if let c = ctx, c.waterLeft > 0 {
                let left = Int((Double(c.waterLeft) / 50).rounded(.up)) * 50
                return ("Время воды 💧", "До дневной нормы осталось около \(left) мл. Начни со стакана.")
            }
            return ("Время воды 💧", "Стакан воды — самое простое, что можно сделать для себя прямо сейчас.")
        case .move:
            if let c = ctx, c.stepsLeft > 0 {
                return ("Разомнись 🚶", "До цели по шагам осталось \(c.stepsLeft). Пройдись хотя бы 5 минут.")
            }
            return ("Разомнись 🚶", "Встань, потянись и пройдись пару минут.")
        case .breathe:
            return ("Минута дыхания 🌿", "Вдох на 4 счёта, выдох на 6. Повтори 5 раз.")
        case .eyes:
            return ("Отдых для глаз 👀", "Посмотри на что-нибудь вдали 20 секунд — глазам станет легче.")
        case .posture:
            return ("Проверь осанку", "Расправь плечи, опусти их вниз и немного разомни шею.")
        case .mood:
            return ("Как ты сейчас?", "Отметь настроение, энергию и стресс в Saiya — это 10 секунд.")
        case .mission:
            if let c = ctx, c.missionsLeft > 0 {
                return ("Задания дня ⭐", "Осталось заданий: \(c.missionsLeft). Выбери самое лёгкое и начни с него.")
            }
            return ("Задания дня ⭐", "Загляни в задания дня и отметь то, что уже сделал(а).")
        case .sleep:
            if let c = ctx, c.sleepDebt >= 1 {
                return ("Пора готовиться ко сну 🌙",
                        String(format: "За неделю накопилось %.1f ч недосыпа. Приглуши свет и отложи телефон за 30 минут до сна.", c.sleepDebt))
            }
            return ("Пора готовиться ко сну 🌙", "Приглуши свет и отложи телефон за полчаса до сна.")
        }
    }
}

/// Локальные уведомления. iOS не позволяет приложению само просыпаться каждые 2 часа,
/// поэтому напоминания планируются заранее (на 3 дня вперёд) и обновляются при каждом открытии приложения.
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    static let waterCategory = "SAIYA_WATER"
    static let addWaterAction = "SAIYA_ADD_WATER"
    static let prefix = "saiya.reminder."

    private let center = UNUserNotificationCenter.current()

    func configure() {
        center.delegate = self
        let add = UNNotificationAction(identifier: Self.addWaterAction, title: "+250 мл", options: [])
        let category = UNNotificationCategory(identifier: Self.waterCategory, actions: [add],
                                              intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func clear() async {
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map { $0.identifier }.filter { $0.hasPrefix(Self.prefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    func reschedule(enabled: Bool, start: Int, end: Int, interval: Int, ctx: ReminderContext) async {
        await clear()
        guard enabled else { return }
        let status = await authorizationStatus()
        guard status == .authorized || status == .provisional else { return }

        let cal = Calendar.current
        let now = Date()
        let step = max(interval, 1)

        var planned: [(date: Date, slot: Int, today: Bool)] = []
        for offset in 0..<3 {
            guard let day = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now)) else { continue }
            var slot = 0
            var hour = start
            while hour <= end {
                if let d = cal.date(bySettingHour: hour, minute: 0, second: 0, of: day),
                   d > now.addingTimeInterval(60) {
                    planned.append((d, slot, offset == 0))
                }
                slot += 1
                hour += step
            }
        }

        for item in planned.prefix(60) {
            if Task.isCancelled { return }
            let text = ReminderCopy.make(at: item.date, slot: item.slot, ctx: item.today ? ctx : nil)
            let content = UNMutableNotificationContent()
            content.title = text.title
            content.body = text.body
            content.sound = .default
            content.threadIdentifier = "saiya.reminders"
            if text.kind == .water { content.categoryIdentifier = Self.waterCategory }

            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: item.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let id = Self.prefix + String(Int(item.date.timeIntervalSince1970))
            try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }

    func sendTest() async {
        let content = UNMutableNotificationContent()
        content.title = "Saiya"
        content.body = "Так будут выглядеть напоминания. Всё работает 👍"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: "saiya.test", content: content, trigger: trigger))
    }

    // MARK: - Фокус

    private static let focusId = "saiya.focus.end"

    /// Уведомление «время вышло», если пользователь свернул приложение во время сессии фокуса.
    func scheduleFocusEnd(after seconds: TimeInterval) {
        Task {
            let status = await authorizationStatus()
            guard status == .authorized || status == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = "Фокус завершён 🎯"
            content.body = "Отличная работа! Сделай паузу: вода, растяжка, пара глубоких вдохов."
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(seconds, 1), repeats: false)
            try? await center.add(UNNotificationRequest(identifier: Self.focusId, content: content, trigger: trigger))
        }
    }

    func cancelFocusEnd() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.focusId])
        center.removeDeliveredNotifications(withIdentifiers: [Self.focusId])
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Показывать баннер, даже если приложение открыто.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    /// Кнопка «+250 мл» прямо в уведомлении.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == Self.addWaterAction {
            WaterStore.add(250)
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .saiyaWaterChanged, object: nil)
            }
        }
        completionHandler()
    }
}
