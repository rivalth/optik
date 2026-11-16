/// The notch island's states (`docs/01-urun.md` 1.1).
public enum IslandPhase: String, CaseIterable, Sendable {
    /// bekliyor: closed, door shut, Optik inside the coop.
    case idle
    /// efendim: just summoned, Optik jumps out and says "Efendim?".
    case wake
    /// dinliyor: listening to the user.
    case listening
    /// yanitliyor: showing and speaking the reply.
    case replying
    /// haber veriyor: Optik came out on its own with a reminder or briefing.
    case announcing

    public var isOpen: Bool { self != .idle }

    public var size: DesignTokens.Island.Size {
        switch self {
        case .idle: DesignTokens.Island.idle
        case .replying: DesignTokens.Island.reply
        case .wake, .listening, .announcing: DesignTokens.Island.open
        }
    }

    /// Optik's mood in each state, as in `tasarim-kaynak/03-mac-centik.dc.html`.
    /// While idle Optik is hidden in the coop; the mood is what it shows when peeking.
    public var mood: Mood {
        switch self {
        case .idle: .sleepy
        case .wake: .listening
        case .listening: .thoughtful
        case .replying: .happy
        case .announcing: .alert
        }
    }
}

/// Something Optik says on its own: a reminder, a due payment, a briefing.
public struct Announcement: Equatable, Sendable {
    public let text: String
    public let mood: Mood

    public init(text: String, mood: Mood = .alert) {
        self.text = text
        self.mood = mood
    }
}
