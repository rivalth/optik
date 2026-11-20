import Foundation

/// Pure state of the notch island. The app feeds it events and renders the result;
/// timers, sounds and speech live in the app and react to phase changes.
public struct IslandStateMachine: Equatable, Sendable {
    public enum Event: Equatable, Sendable {
        /// Shortcut, click on the island or (later) the wake word.
        case summon
        /// "Efendim?" finished; start listening.
        case greeted
        /// No speech for 8 s, or the user pressed Esc.
        case dismiss
        /// What the user said so far, shown live while listening.
        case transcript(String)
        /// Back to listening from a reply: the user interrupted or keeps talking.
        case listen
        case reply(String)
        /// The reply was spoken and its time on screen ran out.
        case replyFinished
        case announce(Announcement)
        /// The announcement was shown long enough.
        case announcementFinished
        /// A full-screen app or a presentation covers the island's screen.
        case fullScreenChanged(Bool)
    }

    public private(set) var phase: IslandPhase = .idle
    public private(set) var replyText: String?
    public private(set) var transcript: String?
    public private(set) var currentAnnouncement: Announcement?
    /// Announcements waiting for a moment when Optik may come out on its own.
    public private(set) var pending: [Announcement] = []
    public private(set) var isFullScreenActive = false

    public init() {}

    /// The idle island hides over full-screen apps; anything the user asked for still shows.
    public var isVisible: Bool { phase.isOpen || !isFullScreenActive }

    /// While Optik's reply asks something ("Dia’da açayım mı?") it waits with a "?".
    public var mood: Mood {
        if let currentAnnouncement { return currentAnnouncement.mood }
        if phase == .replying, let replyText, Self.isQuestion(replyText) { return .asking }
        return phase.mood
    }

    /// True when `text` ends with a question mark (closing quotes and spaces aside).
    public static func isQuestion(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"”’»)")))
        return trimmed.hasSuffix("?")
    }

    /// Returns true when anything visible changed.
    @discardableResult
    public mutating func handle(_ event: Event) -> Bool {
        let before = self
        switch event {
        case .summon:
            // Summoning always wins. An announcement on screen counts as seen.
            if phase != .wake {
                currentAnnouncement = nil
                replyText = nil
                transcript = nil
                phase = .wake
            }
        case .greeted:
            if phase == .wake { phase = .listening }
        case .dismiss:
            close()
        case .transcript(let text):
            // Speaking over "Efendim?" counts as listening already.
            if phase == .wake || phase == .listening {
                transcript = text
                phase = .listening
            }
        case .listen:
            if phase == .replying || phase == .wake {
                replyText = nil
                transcript = nil
                phase = .listening
            }
        case .reply(let text):
            if phase == .wake || phase == .listening || phase == .replying {
                replyText = text
                transcript = nil
                phase = .replying
            }
        case .replyFinished:
            if phase == .replying { close() }
        case .announce(let announcement):
            pending.append(announcement)
            deliverIfPossible()
        case .announcementFinished:
            if phase == .announcing { close() }
        case .fullScreenChanged(let active):
            isFullScreenActive = active
            deliverIfPossible()
        }
        return before != self
    }

    private mutating func close() {
        phase = .idle
        replyText = nil
        transcript = nil
        currentAnnouncement = nil
        deliverIfPossible()
    }

    /// Optik comes out on its own only when the island is closed and nothing covers it.
    private mutating func deliverIfPossible() {
        guard phase == .idle, !isFullScreenActive, !pending.isEmpty else { return }
        currentAnnouncement = pending.removeFirst()
        phase = .announcing
    }
}
