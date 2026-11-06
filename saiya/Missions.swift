import Foundation

struct MissionContext {
    var weather: WeatherInfo?
    var freeEveningHours: Double?
    var hour: Int
    var sleepWorse: Bool
    var moveWorse: Bool
    var screenWorse: Bool

    var rainy: Bool { weather?.isRainy ?? false }
}

struct MissionTemplate {
    let category: String
    let title: String
    let detail: String
    let xp: Int
    var fits: (MissionContext) -> Bool = { _ in true }
}

enum MissionBook {
    private static func t(_ category: String, _ title: String, _ detail: String, _ xp: Int,
                          _ fits: @escaping (MissionContext) -> Bool = { _ in true }) -> MissionTemplate {
        MissionTemplate(category: category, title: title, detail: detail, xp: xp, fits: fits)
    }

    static let catalog: [MissionTemplate] = [
        // Движение
        t("move", "Прогулка 20 минут", "Выйди на свежий воздух на 20 минут — без спешки.", 20, { !$0.rainy }),
        t("move", "Вечерняя прогулка", "Вечером выйди пройтись на 20–30 минут.", 25, { !$0.rainy && ($0.freeEveningHours ?? 2) >= 1 }),
        t("move", "Домашняя тренировка", "15 минут лёгкой зарядки или упражнений дома.", 20, { $0.rainy }),
        t("move", "Лестница вместо лифта", "Сегодня поднимайся по лестнице там, где это возможно.", 15),
        t("move", "5 минут растяжки", "Растяни шею, плечи, спину и ноги.", 10),
        t("move", "30 приседаний за день", "Три подхода по 10 приседаний в удобное время.", 15),
        t("move", "Разминка каждый час", "Если сидишь за работой — вставай на 2 минуты каждый час.", 15),
        t("move", "Звонок на ходу", "Следующий телефонный разговор проведи во время ходьбы.", 15),

        // Ум и спокойствие
        t("mind", "Дыхание 4–6", "5 минут: вдох на 4 счёта, выдох на 6.", 15),
        t("mind", "Три хорошие вещи", "Запиши три вещи, за которые ты благодарен(на) сегодня.", 15),
        t("mind", "Тихие 10 минут", "10 минут без музыки и экрана — просто посиди или пройдись.", 15),
        t("mind", "Разгрузи голову", "Выпиши на бумагу все дела и мысли, которые крутятся в голове.", 10),
        t("mind", "Короткая медитация", "5 минут наблюдения за дыханием. Можно с закрытыми глазами.", 15),

        // Сон
        t("sleep", "Отбой по режиму", "Ляг сегодня в своё обычное время (± 30 минут).", 15),
        t("sleep", "Экраны прочь", "За 30 минут до сна убери телефон и ноутбук.", 20),
        t("sleep", "Спальня для сна", "Проветри комнату и приглуши свет за час до сна.", 10),
        t("sleep", "Кофеин до обеда", "Сегодня без кофе и энергетиков после 15:00.", 15),
        t("sleep", "Мягкий вечер", "Тёплый душ или спокойная книга перед сном.", 15),

        // Фокус и экран
        t("focus", "Час без уведомлений", "Включи режим «Не беспокоить» на один рабочий час.", 15),
        t("focus", "Обед без телефона", "Поешь, не держа телефон в руках.", 15),
        t("focus", "Чистка уведомлений", "Отключи уведомления у трёх приложений, которые отвлекают.", 15, { $0.screenWorse }),
        t("focus", "Один экран", "Час работы или учёбы только с одним открытым окном.", 10),
        t("focus", "Телефон в другой комнате", "Оставь телефон в другой комнате на 30 минут.", 20),

        // Общение
        t("social", "Тёплое сообщение", "Напиши близкому человеку просто так, без повода.", 15),
        t("social", "Позвони, а не пиши", "Сегодня позвони другу или родственнику.", 20),
        t("social", "Добрые слова", "Скажи кому-нибудь искреннее спасибо или комплимент.", 10),

        // Вода
        t("water", "Стакан воды с утра", "Выпей стакан воды до завтрака.", 10, { $0.hour < 12 }),
        t("water", "Вода вместо сладкого", "Замени один сладкий напиток водой или чаем без сахара.", 10),
        t("water", "Бутылка на виду", "Поставь воду на стол и допей её до конца дня.", 10),

        // Еда
        t("food", "Овощи или фрукты", "Добавь порцию овощей или фруктов к одному приёму пищи.", 10),
        t("food", "Спокойный завтрак", "Позавтракай не торопясь и без телефона.", 10, { $0.hour < 12 }),
        t("food", "Лёгкий ужин", "Постарайся поужинать за 2–3 часа до сна.", 10, { $0.hour < 20 })
    ]

    /// Список заданий на день: главное (AI или локальное), 3 из каталога и автоматические.
    static func daily(main: AIInsight, deltas: [MetricDelta], context: DayContext,
                      stepGoal: Int, waterGoal: Int, sleepGoal: Double,
                      hasSleepData: Bool, now: Date = Date()) -> [Mission] {
        let cal = Calendar.current
        let ctx = MissionContext(
            weather: context.weather,
            freeEveningHours: context.freeEveningHours,
            hour: cal.component(.hour, from: now),
            sleepWorse: deltas.contains { $0.kind == .sleep && $0.isWorse },
            moveWorse: deltas.contains { ($0.kind == .steps || $0.kind == .workout) && $0.isWorse },
            screenWorse: deltas.contains { $0.kind == .screen && $0.isWorse }
        )
        let ord = cal.ordinality(of: .day, in: .era, for: now) ?? 0

        var list: [Mission] = [
            Mission(title: main.missionTitle, detail: main.missionDetail, xp: main.xp, category: "main")
        ]

        // Какие категории показать: сначала то, что сейчас важнее, потом по очереди.
        let order = ["move", "mind", "sleep", "focus", "social", "water", "food"]
        var priority: [String] = []
        if ctx.sleepWorse { priority.append("sleep") }
        if ctx.moveWorse { priority.append("move") }
        if ctx.screenWorse { priority.append("focus") }
        let rotated = (0..<order.count).map { order[($0 + ord) % order.count] }
        var categories: [String] = []
        for c in priority + rotated where !categories.contains(c) { categories.append(c) }

        var picked = 0
        for c in categories {
            if picked >= 3 { break }
            let options = catalog.filter { $0.category == c && $0.fits(ctx) && $0.title != main.missionTitle }
            if options.isEmpty { continue }
            let tpl = options[(ord + picked) % options.count]
            list.append(Mission(title: tpl.title, detail: tpl.detail, xp: tpl.xp, category: tpl.category))
            picked += 1
        }

        list.append(Mission(title: "Норма шагов", detail: "Дойди до \(stepGoal.formatted()) шагов.",
                            xp: 25, category: "move", auto: "steps"))
        list.append(Mission(title: "Норма воды", detail: "Выпей \(waterGoal) мл воды за день.",
                            xp: 20, category: "water", auto: "water"))
        list.append(Mission(title: "Минута дыхания", detail: "Открой «Подышать» на экране «Сегодня» и пройди упражнение.",
                            xp: 10, category: "mind", auto: "breath"))
        list.append(Mission(title: "Отметь день", detail: "Отметь настроение, энергию и стресс.",
                            xp: 10, category: "mind", auto: "checkin"))
        list.append(Mission(title: "Запись в дневник", detail: "Напиши пару строк в «Дневнике» на экране «Сегодня».",
                            xp: 10, category: "mind", auto: "journal"))
        if hasSleepData {
            list.append(Mission(title: "Ночь по цели",
                                detail: "Засчитается, если прошлая ночь была не короче \(SleepAnalytics.hm(sleepGoal)).",
                                xp: 20, category: "sleep", auto: "sleep"))
        }
        return list
    }
}
