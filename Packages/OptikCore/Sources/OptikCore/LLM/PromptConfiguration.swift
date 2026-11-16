import Foundation

/// Model names, from `llm/modeller.json` (`docs/02-mimari.md` 3.3: never in code).
public struct LLMModels: Equatable, Sendable, Decodable {
    /// Voice turns, quick records, short answers.
    public var voice: String
    /// Briefings, reports, planning.
    public var deep: String

    enum CodingKeys: String, CodingKey {
        case voice = "sesli_tur"
        case deep = "uzun_is"
    }

    public init(voice: String, deep: String) {
        self.voice = voice
        self.deep = deep
    }

    public static func decode(from data: Data) throws -> LLMModels {
        try JSONDecoder().decode(LLMModels.self, from: data)
    }
}

public enum SystemPrompt {
    /// The text under "## İstem" in `llm/sistem-istemi.md`: the first ```text block.
    public static func extract(fromMarkdown markdown: String) -> String? {
        guard let heading = markdown.range(of: "## İstem"),
              let open = markdown.range(of: "```text\n", range: heading.upperBound..<markdown.endIndex),
              let close = markdown.range(of: "\n```", range: open.upperBound..<markdown.endIndex)
        else { return nil }
        return String(markdown[open.upperBound..<close.lowerBound])
    }
}

/// The "Tur bağlamı" block (`llm/sistem-istemi.md`), rebuilt every turn.
public struct TurnContext: Sendable {
    public enum Trigger: String, Sendable {
        case wakeWord = "uyandırma kelimesi"
        case shortcut = "klavye kısayolu"
        case click = "adacığa tıklama"
    }

    public var userName: String?
    public var now: Date
    public var trigger: Trigger
    /// Stage 2: Optik has no tools yet, so it must not claim it saved anything.
    public var toolsAvailable: Bool

    public init(userName: String?, now: Date, trigger: Trigger, toolsAvailable: Bool = false) {
        self.userName = userName
        self.now = now
        self.trigger = trigger
        self.toolsAvailable = toolsAvailable
    }

    public static let timeZone = TimeZone(identifier: "Europe/Istanbul")!

    public var text: String {
        var lines: [String] = []
        if let userName, !userName.isEmpty { lines.append("Kullanıcı: \(userName)") }
        lines.append("Şimdi: \(Self.formatted(now)) (Europe/Istanbul)")
        lines.append("Tetikleyen: \(trigger.rawValue)")
        if !toolsAvailable {
            lines.append("Not: Bu sürümde araç yok. Veri okuyamaz, kaydedemez ve hatırlatıcı kuramazsın. Böyle bir istekte bunu tek cümleyle söyle, kaydetmiş gibi davranma.")
        }
        return lines.joined(separator: "\n")
    }

    /// "2026-11-16 Pazartesi 13.42"
    static func formatted(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: date)
        let weekdays = ["Pazar", "Pazartesi", "Salı", "Çarşamba", "Perşembe", "Cuma", "Cumartesi"]
        let weekday = weekdays[(parts.weekday ?? 1) - 1]
        func two(_ value: Int?) -> String { String(format: "%02d", value ?? 0) }
        return "\(parts.year ?? 0)-\(two(parts.month))-\(two(parts.day)) \(weekday) \(two(parts.hour)).\(two(parts.minute))"
    }
}

/// The last few turns, sent back as history (`docs/02-mimari.md` 3.3: last 5 turns).
public struct ConversationHistory: Sendable, Equatable {
    public private(set) var messages: [ChatMessage] = []
    public var maximumTurns: Int

    public init(maximumTurns: Int = 5) {
        self.maximumTurns = maximumTurns
    }

    public mutating func append(user: String, assistant: String) {
        messages.append(ChatMessage(role: .user, text: user))
        messages.append(ChatMessage(role: .assistant, text: assistant))
        let overflow = messages.count - maximumTurns * 2
        if overflow > 0 { messages.removeFirst(overflow) }
    }

    public mutating func clear() { messages.removeAll() }

    /// History plus the new user message.
    public func request(adding userText: String) -> [ChatMessage] {
        messages + [ChatMessage(role: .user, text: userText)]
    }
}
