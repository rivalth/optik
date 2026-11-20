import Foundation

/// A turn in the conversation that is sent back to the model as history.
public struct ChatMessage: Equatable, Sendable, Codable {
    public enum Role: String, Sendable, Codable {
        case user
        case assistant
    }

    public var role: Role
    public var text: String

    public init(role: Role, text: String) {
        self.role = role
        self.text = text
    }
}

/// One request to the language model.
public struct LLMRequest: Equatable, Sendable {
    public var model: String
    /// The fixed system prompt, cached between turns.
    public var system: String
    /// Per-turn context ("Tur bağlamı"), sent after the cached part.
    public var turnContext: String
    public var messages: [ChatMessage]
    public var maxTokens: Int
    /// Lets the model search the web for what it can't know: match times, weather,
    /// news, opening hours.
    public var webSearch: Bool

    public init(model: String, system: String, turnContext: String, messages: [ChatMessage], maxTokens: Int = 1024,
                webSearch: Bool = true) {
        self.model = model
        self.system = system
        self.turnContext = turnContext
        self.messages = messages
        self.maxTokens = maxTokens
        self.webSearch = webSearch
    }
}

/// Drops a source list at the end of a reply ("Sources:", "Kaynaklar:" and the links
/// after it). Claude Code's web search tells the model to always add one, which a
/// spoken or short on-screen answer doesn't want. Works on streamed text: a line that
/// may open such a list is held back until it is clearly something else.
public struct SourceListFilter: Sendable {
    static let markers = ["sources:", "source:", "kaynaklar:", "kaynak:"]

    /// Line breaks and the start of the line after them, held back.
    private var held = ""
    private var isHolding = false
    private var isDropping = false

    public init() {}

    public mutating func filter(_ text: String) -> String {
        var out = ""
        for character in text {
            guard !isDropping else { break }
            if character.isNewline {
                held.append(character)
                isHolding = true
                continue
            }
            guard isHolding else {
                out.append(character)
                continue
            }
            held.append(character)
            let start = held.drop { $0.isWhitespace || "*#_".contains($0) }.lowercased()
            if start.isEmpty { continue }
            if Self.markers.contains(where: { start.hasPrefix($0) }) {
                isDropping = true
                held = ""
            } else if !Self.markers.contains(where: { $0.hasPrefix(start) }) {
                out += held
                held = ""
                isHolding = false
            }
        }
        return out
    }
}

/// Finds the page a reply is based on, for "open it in the browser".
public enum ReplySource {
    /// The first http(s) link in `text`: a Markdown link's target, or a bare link.
    public static func firstLink(in text: String) -> URL? {
        let pattern = #"https?://[^\s)\]>"']+"#
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        var link = String(text[range])
        while let last = link.last, ".,;:!?".contains(last) { link.removeLast() }
        return URL(string: link)
    }
}

/// Joins the text of a reply that the model wrote in several pieces around a tool
/// call ("Bakıyorum." … search … "Maç 20.00'de."), so the pieces don't run together.
/// Text blocks that follow each other directly (citations split a sentence into
/// several) are joined as they are.
public struct ReplyTextJoiner: Sendable {
    private var hasText = false
    private var pendingBreak = false

    public init() {}

    /// A content block (or, in Claude Code, a new message) started.
    public mutating func blockStarted(isText: Bool) {
        if !isText, hasText { pendingBreak = true }
    }

    /// The text to pass on for `delta`.
    public mutating func text(_ delta: String) -> String {
        defer { hasText = true }
        guard pendingBreak else { return delta }
        pendingBreak = false
        return delta.first?.isWhitespace == true ? delta : " " + delta
    }
}

/// What the model streams back.
public enum LLMEvent: Equatable, Sendable {
    case text(String)
    /// A web page the reply is based on: one Optik read, or the first one it cites.
    case source(URL)
    /// The reply ended. `stopReason` is the API's, e.g. "end_turn", "max_tokens", "refusal".
    case finished(stopReason: String?, usage: LLMUsage)
}

public struct LLMUsage: Equatable, Sendable {
    public var inputTokens = 0
    public var outputTokens = 0
    public var cacheReadInputTokens = 0
    public var cacheCreationInputTokens = 0

    public init(inputTokens: Int = 0, outputTokens: Int = 0, cacheReadInputTokens: Int = 0, cacheCreationInputTokens: Int = 0) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadInputTokens = cacheReadInputTokens
        self.cacheCreationInputTokens = cacheCreationInputTokens
    }
}

public enum LLMError: Error, Equatable, Sendable {
    case missingKey
    /// No connection, or the connection dropped.
    case offline
    /// The API answered with an error status.
    case http(status: Int, type: String?)
    case malformedResponse
    /// Claude Code, used without an API key, did not answer: not installed, not
    /// signed in, or it stopped with an error.
    case claudeCodeFailed
}

/// The language model, behind a protocol so tests use a fake (`CLAUDE.md`).
public protocol LLMClient: Sendable {
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<LLMEvent, Error>
    /// Opens the connection ahead of the first request, so the TLS handshake is not
    /// on the reply's critical path. Optional.
    func warmUp() async
}

public extension LLMClient {
    func warmUp() async {}
}
