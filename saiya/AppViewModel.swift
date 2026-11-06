import Foundation
import SwiftUI
import UserNotifications

@MainActor
final class AppViewModel: ObservableObject {
    static let bonusXP = 20

    @Published var deltas: [MetricDelta] = []
    @Published var insight: AIInsight?
    @Published var missions: [Mission] = []
    @Published var checkIns: [CheckIn] = []
    @Published var xp = 0
    @Published var chat: [ChatMessage] = []
    @Published var isLoading = false
    @Published var isSending = false
    @Published var usingDemoData = false
    @Published var notice: String?
    @Published var healthSnapshot = HealthSnapshot()
    @Published var healthHistory: [DailyMetrics] = []
    @Published var waterEntries: [WaterEntry] = []
    @Published var waterGoal = 2000
    @Published var stepGoal = 8000
    @Published var sleepNights: [SleepNight] = []
    @Published var userName = ""  { didSet { store.set(userName, forKey: "userName") } }
    @Published var breathTotal = 0
    @Published var sleepGoal: Double = 8 { didSet { store.set(sleepGoal, forKey: "sleepGoal"); evaluateAutoMissions() } }
    @Published var context = DayContext()
    @Published var patternNote: String?
    @Published var useCalendar = true { didSet { store.set(useCalendar, forKey: "useCalendar") } }
    @Published var useWeather = true { didSet { store.set(useWeather, forKey: "useWeather") } }
    @Published var aiEnabled = false { didSet { store.set(aiEnabled, forKey: "aiEnabled") } }
    @Published var journal: [JournalEntry] = []
    @Published var focusLog: [FocusSession] = []
    /// Растёт каждый раз, когда нужно показать конфетти.
    @Published var celebration = 0
    /// Короткое всплывающее сообщение сверху.
    @Published var toast: String?

    // Напоминания
    @Published var remindersEnabled = true { didSet { store.set(remindersEnabled, forKey: "remindersEnabled"); handleReminderToggle() } }
    @Published var reminderStart = 10 { didSet { store.set(reminderStart, forKey: "reminderStart"); scheduleReminders() } }
    @Published var reminderEnd = 20 { didSet { store.set(reminderEnd, forKey: "reminderEnd"); scheduleReminders() } }
    @Published var reminderInterval = 2 { didSet { store.set(reminderInterval, forKey: "reminderInterval"); scheduleReminders() } }
    @Published var notificationsDenied = false

    private let health = HealthKitManager()
    private let ai = AIService()
    private let calendar = CalendarService()
    private let location = LocationProvider()
    private let store = UserDefaults.standard
    private var reminderTask: Task<Void, Never>?
    private var lastHealthRefresh: Date?

    init() {
        checkIns = load("checkIns") ?? []
        missions = load("missions") ?? []
        chat = load("chat") ?? []
        journal = load("journal") ?? []
        focusLog = load("focusLog") ?? []
        userName = store.string(forKey: "userName") ?? ""
        breathTotal = store.integer(forKey: "breathTotal")
        xp = store.integer(forKey: "xp")
        useCalendar = (store.object(forKey: "useCalendar") as? Bool) ?? true
        useWeather = (store.object(forKey: "useWeather") as? Bool) ?? true
        aiEnabled = (store.object(forKey: "aiEnabled") as? Bool) ?? false
        waterEntries = WaterStore.load()
        waterGoal = WaterStore.goal
        stepGoal = store.integer(forKey: "stepGoal") == 0 ? 8000 : store.integer(forKey: "stepGoal")
        let savedSleepGoal = store.double(forKey: "sleepGoal")
        sleepGoal = savedSleepGoal == 0 ? 8 : savedSleepGoal
        remindersEnabled = (store.object(forKey: "remindersEnabled") as? Bool) ?? true
        reminderStart = (store.object(forKey: "reminderStart") as? Int) ?? 10
        reminderEnd = (store.object(forKey: "reminderEnd") as? Int) ?? 20
        reminderInterval = (store.object(forKey: "reminderInterval") as? Int) ?? 2
        if let first = missions.first, !Calendar.current.isDateInToday(first.date) { missions = [] }
    }

    func start() async {
        if health.isAvailable { await refreshHealth(requestAccess: true) } else { useDemoData() }
        await refreshInsight()
        await refreshContext()
        await refreshInsight(replaceMission: true)
        postDailyGreeting()
        await setupReminders()
    }

    /// Вызывается, когда приложение снова стало активным (в том числе после полуночи).
    func becameActive() {
        waterEntries = WaterStore.load()
        objectWillChange.send()
        if let first = missions.first, !Calendar.current.isDateInToday(first.date) {
            Task { await refreshInsight() }
        }
        // Сон и шаги могли появиться, пока приложение было закрыто.
        if let t = lastHealthRefresh, Date().timeIntervalSince(t) > 300 {
            Task { await refreshHealth() }
        }
        evaluateAutoMissions()
        Task { await refreshNotificationStatus() }
        scheduleReminders()
    }

    func refreshContext() async {
        var ctx = DayContext()
        if useCalendar, await calendar.requestAccess() {
            let r = calendar.todaySummary()
            ctx.eventsToday = r.count
            ctx.freeEveningHours = r.freeEvening
        }
        if useWeather, let loc = await location.currentLocation() {
            ctx.weather = await WeatherService.fetch(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude)
        }
        context = ctx
    }

    private func recomputeDeltas() {
        deltas = BaselineEngine.compute(healthHistory, checkIns: checkIns)
        patternNote = BaselineEngine.weekPattern(healthHistory)
    }

    private var fullSummary: String {
        var text = BaselineEngine.promptSummary(deltas, checkIns: checkIns, context: context, pattern: patternNote)
        var extra: [String] = []
        let week = Array(nights.suffix(7))
        if !week.isEmpty {
            extra.append(String(format: "Сон: цель %.1f ч, недосып за неделю %.1f ч", sleepGoal, SleepAnalytics.debt(week, goal: sleepGoal)))
        }
        if let r = SleepAnalytics.regularity(week) {
            extra.append("Сон: средний отбой около \(SleepAnalytics.clock(r.avgBed)), разброс ±\(Int(r.spread.rounded())) мин")
        }
        extra.append("Вода сегодня: \(waterML) из \(waterGoal) мл")
        text += "\n" + extra.joined(separator: "\n")
        return text
    }

    var aiReady: Bool { aiEnabled && AIConfig.isConfigured }

    func saveKey(_ key: String) {
        Keychain.set(key.trimmingCharacters(in: .whitespacesAndNewlines), for: "geminiKey")
        objectWillChange.send()
    }

    func wipe() {
        for k in ["checkIns", "missions", "mission", "chat", "xp", "waterML", "waterEntries", "waterGoalML",
                  "stepGoal", "manualSleep", "sleepGoal", "missionBonusDay",
                  "userName", "breathTotal", "breathDay", "greetingDay",
                  "journal", "focusLog"] {
            store.removeObject(forKey: k)
        }
        Keychain.set("", for: "geminiKey")
        checkIns = []; missions = []; chat = []; xp = 0
        journal = []; focusLog = []
        waterEntries = []; waterGoal = 2000; stepGoal = 8000
        sleepGoal = 8; userName = ""; breathTotal = 0
        recomputeDeltas()
        Task { await NotificationManager.shared.clear() }
        Task { await refreshInsight() }
    }

    func refreshHealth(requestAccess: Bool = false) async {
        isLoading = true
        lastHealthRefresh = Date()
        defer { isLoading = false }
        guard health.isAvailable else { useDemoData(); return }
        do {
            if requestAccess { try await health.requestAuthorization() }
            healthHistory = await health.fetchDailyMetrics(days: 30)
            healthSnapshot = await health.fetchSnapshot(days: 7)
            sleepNights = await health.fetchSleepNights(days: 14)
            recomputeDeltas()
            usingDemoData = false
            if healthHistory.allSatisfy({ $0.sleepHours == nil && $0.steps == nil && $0.restingHR == nil && $0.activeEnergy == nil && $0.distanceKm == nil && $0.hrv == nil }) {
                notice = "HealthKit подключён, но история пока пустая. Добавь данные в «Здоровье» или Apple Watch."
            } else { notice = "Данные Apple Health обновлены" }
            evaluateAutoMissions()
        } catch {
            notice = "Доступ к HealthKit не получен. Можно продолжить в демо-режиме."
            useDemoData()
        }
    }

    func useDemoData() {
        healthHistory = MockData.month()
        sleepNights = MockData.sleepNights()
        healthSnapshot = HealthSnapshot(
            latestHeartRate: healthHistory.last?.restingHR,
            latestActiveEnergy: healthHistory.last?.activeEnergy,
            latestDistanceKm: healthHistory.last?.distanceKm,
            latestSteps: healthHistory.last?.steps,
            latestWorkoutMinutes: healthHistory.last?.workoutMinutes,
            updatedAt: Date()
        )
        recomputeDeltas()
        usingDemoData = true
        notice = "Демо-режим: показатели примерные, они не заменяют данные HealthKit."
    }

    // MARK: - Инсайт и задания

    func refreshInsight(replaceMission: Bool = false) async {
        var result = LocalInsight.make(deltas, context: context)
        if aiReady {
            do { result = try await ai.insight(summary: fullSummary) }
            catch { notice = "AI временно недоступен — использую локальный совет." }
        }
        insight = result

        let stale = missions.first.map { !Calendar.current.isDateInToday($0.date) } ?? true
        if stale {
            missions = MissionBook.daily(main: result, deltas: deltas, context: context,
                                         stepGoal: stepGoal, waterGoal: waterGoal, sleepGoal: sleepGoal,
                                         hasSleepData: lastNight != nil)
            save(missions, "missions")
            evaluateAutoMissions()
        } else if replaceMission, let i = missions.firstIndex(where: { $0.category == "main" }), !missions[i].isDone {
            missions[i].title = result.missionTitle
            missions[i].detail = result.missionDetail
            missions[i].xp = result.xp
            save(missions, "missions")
        }
        scheduleReminders()
    }

    var missionsDone: Int { missions.filter { $0.isDone }.count }
    var allMissionsDone: Bool { !missions.isEmpty && missionsDone == missions.count }

    func completeMission(_ id: UUID) {
        guard let i = missions.firstIndex(where: { $0.id == id }), !missions[i].isDone else { return }
        finish(at: i)
        scheduleReminders()
    }

    private func finish(at i: Int) {
        missions[i].isDone = true
        Haptics.success()
        addXP(missions[i].xp)
        if missions.allSatisfy({ $0.isDone }) {
            let today = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
            if store.double(forKey: "missionBonusDay") != today {
                store.set(today, forKey: "missionBonusDay")
                addXP(Self.bonusXP, celebrate: true)
                showToast("Все задания дня выполнены! +\(Self.bonusXP) XP 🎉")
            }
        }
        save(missions, "missions")
    }

    /// Начисляет XP; при переходе на новый уровень запускает конфетти и показывает сообщение.
    private func addXP(_ amount: Int, celebrate: Bool = false) {
        let before = level
        xp += amount
        store.set(xp, forKey: "xp")
        if level > before {
            celebration += 1
            Haptics.success()
            showToast("Новый уровень \(level) · \(Levels.title(level)) 🎉")
        } else if celebrate {
            celebration += 1
        }
    }

    func showToast(_ text: String) {
        toast = text
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let self, self.toast == text else { return }
            self.toast = nil
        }
    }

    // MARK: - Баланс дня

    var dayScore: DayScore {
        let cal = Calendar.current
        var parts: [ScorePart] = []
        if let n = lastNight, cal.isDateInToday(n.date) {
            parts.append(ScorePart(id: "sleep", title: "Сон", icon: "moon.zzz.fill",
                                   value: min(n.asleepHours / max(sleepGoal, 1), 1), weight: 25,
                                   detail: "\(SleepAnalytics.hm(n.asleepHours)) из \(SleepAnalytics.hm(sleepGoal))",
                                   color: Theme.blue))
        }
        parts.append(ScorePart(id: "steps", title: "Шаги", icon: "figure.walk",
                               value: min(Double(todaySteps) / Double(max(stepGoal, 1)), 1), weight: 20,
                               detail: "\(todaySteps.formatted()) из \(stepGoal.formatted())", color: Theme.mint))
        parts.append(ScorePart(id: "water", title: "Вода", icon: "drop.fill",
                               value: waterProgress, weight: 15,
                               detail: "\(waterML) из \(waterGoal) мл", color: Theme.blue))
        if !missions.isEmpty {
            parts.append(ScorePart(id: "missions", title: "Задания", icon: "checklist",
                                   value: Double(missionsDone) / Double(missions.count), weight: 25,
                                   detail: "\(missionsDone) из \(missions.count) выполнено", color: Theme.peach))
        }
        if let c = checkIns.last(where: { cal.isDateInToday($0.date) }) {
            let raw = Double(c.mood + c.energy + (6 - c.stress) - 3) / 12
            parts.append(ScorePart(id: "mood", title: "Самочувствие", icon: "face.smiling.fill",
                                   value: min(max(raw, 0), 1), weight: 15,
                                   detail: "по сегодняшней отметке", color: Theme.lime))
        }
        return DayScore(parts: parts)
    }

    // MARK: - Дневник

    var journalToday: [JournalEntry] { journal.filter { Calendar.current.isDateInToday($0.date) } }

    func addJournal(text: String, mood: Int) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        journal.append(JournalEntry(mood: min(max(mood, 1), 5), text: clean))
        journal = Array(journal.suffix(300))
        save(journal, "journal")
        Haptics.success()
        showToast("Запись сохранена ✍️")
        evaluateAutoMissions()
    }

    func deleteJournal(_ id: UUID) {
        journal.removeAll { $0.id == id }
        save(journal, "journal")
    }

    // MARK: - Фокус

    var focusMinutesToday: Int {
        focusLog.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.minutes }
    }
    var focusMinutesTotal: Int { focusLog.reduce(0) { $0 + $1.minutes } }

    func completeFocus(minutes: Int) {
        guard minutes >= 5 else { return }
        focusLog.append(FocusSession(minutes: minutes))
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date.distantPast
        focusLog = focusLog.filter { $0.date >= cutoff }
        save(focusLog, "focusLog")
        let reward = max(minutes / 2, 5)
        addXP(reward, celebrate: true)
        showToast("Фокус завершён: +\(reward) XP 🎯")
    }

    func clearChat() {
        chat = []
        save(chat, "chat")
    }

    var weeklyReport: WeeklyReport {
        WeeklyReport.make(history: healthHistory, nights: nights, water: waterWeek, checkIns: checkIns,
                          focus: focusLog, journal: journal,
                          stepGoal: stepGoal, waterGoal: waterGoal, sleepGoal: sleepGoal)
    }

    /// Автоматические задания: шаги, вода, отметка дня, сон.
    func evaluateAutoMissions() {
        for i in missions.indices where !missions[i].isDone {
            guard let key = missions[i].auto else { continue }
            let ok: Bool
            switch key {
            case "steps": ok = todaySteps >= stepGoal
            case "water": ok = waterML >= waterGoal
            case "checkin": ok = checkIns.contains { Calendar.current.isDateInToday($0.date) }
            case "sleep":
                ok = lastNight.map { Calendar.current.isDateInToday($0.date) && $0.asleepHours >= sleepGoal } ?? false
            case "breath": ok = breathedToday
            case "journal": ok = !journalToday.isEmpty
            default: ok = false
            }
            if ok { finish(at: i) }
        }
    }

    func add(_ checkIn: CheckIn) {
        checkIns.append(checkIn)
        checkIns = Array(checkIns.suffix(30))
        save(checkIns, "checkIns")
        recomputeDeltas()
        evaluateAutoMissions()
        Task { await refreshInsight() }
    }

    // MARK: - Вода

    var waterML: Int { WaterStore.total(on: Date(), in: waterEntries) }
    var waterProgress: Double { min(Double(waterML) / Double(max(waterGoal, 1)), 1) }
    var todayWaterEntries: [WaterEntry] {
        waterEntries.filter { Calendar.current.isDateInToday($0.date) }.sorted { $0.date > $1.date }
    }
    var waterWeek: [WaterDay] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<7).reversed().map { offset in
            let day = cal.date(byAdding: .day, value: -offset, to: today)!
            return WaterDay(date: day, ml: WaterStore.total(on: day, in: waterEntries))
        }
    }
    /// Ориентир ~30 мл на кг веса, округлённый до 50 мл. Только если вес есть в Health.
    var suggestedWaterGoal: Int? {
        guard let kg = healthSnapshot.weightKg, kg > 20 else { return nil }
        let raw = Int((kg * 30 / 50).rounded()) * 50
        return min(max(raw, 1000), 5000)
    }

    func addWater(_ amount: Int = 250) {
        guard amount > 0, amount <= 2000 else { return }
        waterEntries = WaterStore.add(amount)
        Haptics.tap()
        waterChanged()
    }

    func removeWater(_ id: UUID) {
        waterEntries.removeAll { $0.id == id }
        WaterStore.save(waterEntries)
        waterChanged()
    }

    func undoWater() {
        if let last = todayWaterEntries.first { removeWater(last.id) }
    }

    func resetWater() {
        let today = waterEntries.filter { Calendar.current.isDateInToday($0.date) }.map { $0.id }
        waterEntries.removeAll { today.contains($0.id) }
        WaterStore.save(waterEntries)
        waterChanged()
    }

    func setWaterGoal(_ goal: Int) {
        waterGoal = goal
        WaterStore.goal = goal
        waterChanged()
    }

    /// Вода добавлена из уведомления, пока приложение было закрыто.
    func reloadWater() {
        waterEntries = WaterStore.load()
        waterChanged()
    }

    private func waterChanged() {
        evaluateAutoMissions()
        scheduleReminders()
    }

    func setStepGoal(_ goal: Int) {
        stepGoal = goal
        store.set(goal, forKey: "stepGoal")
        evaluateAutoMissions()
    }

    // MARK: - Сон

    /// Сон берётся только из Apple Health.
    var nights: [SleepNight] { sleepNights.sorted { $0.date < $1.date } }

    var lastNight: SleepNight? { nights.last }

    var sleepAverageText: String {
        let week = nights.suffix(7)
        guard !week.isEmpty else { return "—" }
        return SleepAnalytics.hm(week.map { $0.asleepHours }.reduce(0, +) / Double(week.count))
    }

    func nightLabel(_ n: SleepNight) -> String {
        Calendar.current.isDateInToday(n.date) ? "Прошлая ночь" : "Ночь до \(n.date.formatted(date: .abbreviated, time: .omitted))"
    }

    // MARK: - Напоминания

    private var reminderContext: ReminderContext {
        ReminderContext(
            waterLeft: max(waterGoal - waterML, 0),
            stepsLeft: max(stepGoal - todaySteps, 0),
            missionsLeft: missions.filter { !$0.isDone }.count,
            checkedInToday: checkIns.contains { Calendar.current.isDateInToday($0.date) },
            sleepDebt: SleepAnalytics.debt(Array(nights.suffix(7)), goal: sleepGoal)
        )
    }

    func scheduleReminders() {
        reminderTask?.cancel()
        reminderTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled, let self else { return }
            await NotificationManager.shared.reschedule(
                enabled: self.remindersEnabled,
                start: self.reminderStart, end: self.reminderEnd, interval: self.reminderInterval,
                ctx: self.reminderContext)
        }
    }

    func setupReminders() async {
        guard remindersEnabled else { return }
        if await NotificationManager.shared.authorizationStatus() == .notDetermined {
            _ = await NotificationManager.shared.requestAuthorization()
        }
        await refreshNotificationStatus()
        scheduleReminders()
    }

    private func handleReminderToggle() {
        Task {
            if remindersEnabled { await setupReminders() } else { scheduleReminders() }
        }
    }

    func refreshNotificationStatus() async {
        notificationsDenied = (await NotificationManager.shared.authorizationStatus() == .denied)
    }

    func sendTestReminder() {
        Task {
            if await NotificationManager.shared.authorizationStatus() == .notDetermined {
                _ = await NotificationManager.shared.requestAuthorization()
            }
            await refreshNotificationStatus()
            await NotificationManager.shared.sendTest()
        }
    }

    // MARK: - Дыхание, приветствие, награды

    var breathedToday: Bool {
        store.double(forKey: "breathDay") == Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
    }

    func completeBreathing() {
        store.set(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970, forKey: "breathDay")
        breathTotal += 1
        store.set(breathTotal, forKey: "breathTotal")
        evaluateAutoMissions()
    }

    /// Раз в день Saiya сам пишет первым — коротко и по-человечески, без обращения к AI.
    func postDailyGreeting() {
        let today = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        guard store.double(forKey: "greetingDay") != today else { return }
        store.set(today, forKey: "greetingDay")
        let hour = Calendar.current.component(.hour, from: Date())
        let hi = hour < 12 ? "Доброе утро" : hour < 18 ? "Привет" : "Добрый вечер"
        let name = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        var text = name.isEmpty ? "\(hi)!" : "\(hi), \(name)!"
        if let n = lastNight, Calendar.current.isDateInToday(n.date) {
            let h = SleepAnalytics.hm(n.asleepHours)
            if n.asleepHours < sleepGoal - 1 { text += " По данным «Здоровья» ты спал \(h) — маловато. Как себя чувствуешь?" }
            else if n.asleepHours >= sleepGoal { text += " Сон — \(h), отличная ночь 🙂 Какое настроение?" }
            else { text += " Сон — \(h). Как настроение сегодня?" }
        } else {
            text += " Как ты сегодня?"
        }
        chat.append(ChatMessage(role: .assistant, text: text))
        save(chat, "chat")
    }

    var badges: [Badge] {
        let week = Array(nights.suffix(7))
        let goodNights = week.filter { $0.asleepHours >= sleepGoal }.count
        let waterDays = waterWeek.filter { $0.ml >= waterGoal }.count
        let steady = (SleepAnalytics.regularity(week)?.spread).map { $0 < 30 } ?? false
        let walked = healthHistory.suffix(7).contains { ($0.steps ?? 0) >= Double(stepGoal) }
        return [
            Badge(id: "first", icon: "face.smiling", title: "Первая отметка", detail: "Отметь самочувствие", unlocked: !checkIns.isEmpty),
            Badge(id: "streak3", icon: "flame.fill", title: "3 дня подряд", detail: "Серия отметок", unlocked: streak >= 3),
            Badge(id: "streak7", icon: "flame.circle.fill", title: "Неделя подряд", detail: "7 дней серии", unlocked: streak >= 7),
            Badge(id: "water1", icon: "drop.fill", title: "Водный день", detail: "Выполни норму воды", unlocked: waterDays >= 1),
            Badge(id: "water5", icon: "drop.circle.fill", title: "Водная неделя", detail: "Норма в 5 из 7 дней", unlocked: waterDays >= 5),
            Badge(id: "sleep3", icon: "moon.stars.fill", title: "Выспаться", detail: "3 ночи по цели за неделю", unlocked: goodNights >= 3),
            Badge(id: "steady", icon: "clock.badge.checkmark.fill", title: "Ровный режим", detail: "Отбой с разбросом до 30 мин", unlocked: steady),
            Badge(id: "walk", icon: "figure.walk", title: "Ходок", detail: "Достигни цели по шагам", unlocked: walked),
            Badge(id: "breath", icon: "wind", title: "Выдох", detail: "Пройди упражнение дыхания", unlocked: breathTotal >= 1),
            Badge(id: "all", icon: "checkmark.seal.fill", title: "Чистый день", detail: "Выполни все задания дня", unlocked: allMissionsDone),
            Badge(id: "lvl3", icon: "trophy.fill", title: "Уровень 3", detail: "Набери 200 XP", unlocked: level >= 3),
            Badge(id: "lvl5", icon: "star.circle.fill", title: "Уровень 5", detail: "Набери 400 XP", unlocked: level >= 5),
            Badge(id: "focus1", icon: "timer", title: "В потоке", detail: "Заверши сессию фокуса", unlocked: !focusLog.isEmpty),
            Badge(id: "focus100", icon: "scope", title: "Глубокая работа", detail: "100 минут фокуса суммарно", unlocked: focusMinutesTotal >= 100),
            Badge(id: "journal3", icon: "book.closed.fill", title: "Автор дня", detail: "3 записи в дневнике", unlocked: journal.count >= 3),
            Badge(id: "score80", icon: "bolt.heart.fill", title: "Баланс 80+", detail: "Баланс дня не ниже 80", unlocked: dayScore.value >= 80)
        ]
    }

    /// Режет ответ AI на 1–3 коротких «сообщения» и убирает markdown.
    static func bubbles(from raw: String) -> [String] {
        let stripped = raw.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "__", with: "")
        let lines: [String] = stripped.split(separator: "\n", omittingEmptySubsequences: true).map { line in
            var l = line.trimmingCharacters(in: .whitespaces)
            while l.hasPrefix("#") { l.removeFirst() }
            for b in ["- ", "• ", "* "] where l.hasPrefix(b) { l.removeFirst(b.count) }
            return l.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }

        var out: [String] = []
        for c in lines {
            if c.count <= 160 { out.append(c); continue }
            var cur = ""
            c.enumerateSubstrings(in: c.startIndex..., options: .bySentences) { sub, _, _, _ in
                guard let sentence = sub?.trimmingCharacters(in: .whitespaces), !sentence.isEmpty else { return }
                if !cur.isEmpty && cur.count + sentence.count > 140 { out.append(cur); cur = sentence }
                else { cur = cur.isEmpty ? sentence : cur + " " + sentence }
            }
            if !cur.isEmpty { out.append(cur) }
        }
        if out.isEmpty { return [raw.trimmingCharacters(in: .whitespacesAndNewlines)] }
        if out.count > 3 { out = Array(out.prefix(2)) + [out.dropFirst(2).joined(separator: " ")] }
        return out
    }

    // MARK: - Прочее

    var todaySteps: Int { Int(healthHistory.last?.steps ?? healthSnapshot.latestSteps ?? 0) }
    var level: Int { xp / 100 + 1 }
    var streak: Int {
        let days = Set(checkIns.map { Calendar.current.startOfDay(for: $0.date) })
        var result = 0; var cursor = Calendar.current.startOfDay(for: Date())
        while days.contains(cursor) { result += 1; cursor = Calendar.current.date(byAdding: .day, value: -1, to: cursor)! }
        return result
    }

    func send(_ text: String) async {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines); guard !clean.isEmpty else { return }
        chat.append(ChatMessage(role: .user, text: clean)); save(chat, "chat")
        if Self.looksLikeCrisis(clean) {
            chat.append(ChatMessage(role: .assistant, text: "Мне важно, что ты это написал(а). Пожалуйста, свяжись с близким человеком или экстренной службой своей страны прямо сейчас. Я могу остаться здесь и поговорить.")); save(chat, "chat"); return
        }
        guard aiReady else {
            chat.append(ChatMessage(role: .assistant, text: "Я пока без AI, отвечаю по-простому: \(insight?.summary ?? "данных пока мало"). Включи AI кнопкой вверху — поболтаем нормально 🙂")); save(chat, "chat"); return
        }
        isSending = true; defer { isSending = false }
        do {
            let ctx = fullSummary
            let reply = try await ai.chat(history: chat, context: ctx, name: userName)
            for (i, part) in Self.bubbles(from: reply).enumerated() {
                if i > 0 { try? await Task.sleep(nanoseconds: 800_000_000) }
                chat.append(ChatMessage(role: .assistant, text: part)); save(chat, "chat")
            }
        } catch { chat.append(ChatMessage(role: .assistant, text: "Не получилось связаться с AI. Проверь интернет.")); save(chat, "chat") }
    }

    private static func looksLikeCrisis(_ t: String) -> Bool {
        ["не хочу жить", "покончить с собой", "суицид", "убить себя", "навредить себе"].contains { t.lowercased().contains($0) }
    }
    private func save<T: Encodable>(_ value: T?, _ key: String) { store.set(try? JSONEncoder().encode(value), forKey: key) }
    private func load<T: Decodable>(_ key: String) -> T? { store.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) } }
}
