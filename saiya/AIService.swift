import Foundation

actor AIService {
    private let systemPrompt = """
    Ты — Saiya, дружелюбный помощник по повседневным привычкам. Говоришь по-русски, коротко и тепло, на «ты».
    Ты сравниваешь человека с его собственной нормой. Ты НЕ врач: не ставишь диагнозов, не говоришь о болезнях, \
    рисках и лекарствах. Описываешь изменения поведения и предлагаешь маленькие безопасные шаги.
    Если самочувствие плохое несколько дней или мешает жизни — мягко советуешь поговорить со специалистом.
    При признаках кризиса или мыслях о самоповреждении — поддержи человека и посоветуй срочно обратиться \
    к близким или в экстренную службу своей страны.
    """

    private let chatPrompt = """
    Ты — Saiya, живой собеседник в приложении про привычки и самочувствие. Пиши как друг в мессенджере, по-русски, на «ты».
    Стиль: одно-два коротких предложения, очень редко три. Без списков, без markdown, без заголовков, без канцелярита \
    и без вступлений вроде «Конечно!» или «Отличный вопрос». Максимум один вопрос за сообщение, и не в каждом. \
    Эмодзи изредка, не больше одного. Не пересказывай слова человека, а реагируй на них и на настроение. \
    Если человек делится плохим — сначала по-человечески отзовись и только потом, если уместно, предложи один маленький шаг. \
    Цифры из данных (сон, шаги, вода) упоминай только когда это к месту и по-человечески, не перечисляй.
    Ты НЕ врач: не ставишь диагнозов, не говоришь о болезнях, рисках и лекарствах. Если плохое самочувствие тянется \
    несколько дней или мешает жить — мягко посоветуй поговорить со специалистом.
    При признаках кризиса или мыслях о самоповреждении — поддержи и посоветуй срочно обратиться к близким или в экстренную службу своей страны.
    """

    private struct Part: Codable { let text: String }
    private struct Content: Codable { let role: String?; let parts: [Part] }
    private struct GenConfig: Encodable {
        var temperature = 0.6
        var responseMimeType: String?
    }
    private struct Req: Encodable {
        let systemInstruction: Content
        let contents: [Content]
        let generationConfig: GenConfig
    }
    private struct Resp: Decodable {
        struct Candidate: Decodable { let content: Content }
        let candidates: [Candidate]?
    }

    private func send(system: String, contents: [Content], json: Bool, temperature: Double = 0.6) async throws -> String {
        let url = URL(string: "\(AIConfig.baseURL)/models/\(AIConfig.model):generateContent")!
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue(AIConfig.apiKey, forHTTPHeaderField: "x-goog-api-key")
        let body = Req(systemInstruction: Content(role: nil, parts: [Part(text: system)]),
                       contents: contents,
                       generationConfig: GenConfig(temperature: temperature, responseMimeType: json ? "application/json" : nil))
        r.httpBody = try JSONEncoder().encode(body)

        let (data, resp) = try await URLSession.shared.data(for: r)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let decoded = try JSONDecoder().decode(Resp.self, from: data)
        return decoded.candidates?.first?.content.parts.map(\.text).joined() ?? ""
    }

    func insight(summary: String) async throws -> AIInsight {
        let prompt = """
        Данные пользователя (последние 7 дней против его нормы, плюс контекст дня). Если уместно, учти погоду и свободное время вечером в миссии:
        \(summary)

        Верни ТОЛЬКО JSON: {"summary": "1–2 предложения о том, что изменилось", \
        "missionTitle": "короткое название", "missionDetail": "одно конкретное действие на сегодня, до 30 минут", \
        "xp": число от 10 до 30}
        """
        let text = try await send(system: systemPrompt,
                                  contents: [Content(role: "user", parts: [Part(text: prompt)])],
                                  json: true)
        return try JSONDecoder().decode(AIInsight.self, from: Data(text.utf8))
    }

    func chat(history: [ChatMessage], context: String, name: String) async throws -> String {
        var msgs = Array(history.suffix(14))
        while let first = msgs.first, first.role == .assistant { msgs.removeFirst() }
        let contents = msgs.map {
            Content(role: $0.role == .user ? "user" : "model", parts: [Part(text: $0.text)])
        }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let who = clean.isEmpty ? "" : "\nЧеловека зовут \(clean). Называй по имени изредка, не в каждом сообщении."
        return try await send(
            system: chatPrompt + who + "\n\nКонтекст о человеке (используй только к месту, не пересказывай цифры):\n" + context,
            contents: contents, json: false, temperature: 0.9)
    }
}
