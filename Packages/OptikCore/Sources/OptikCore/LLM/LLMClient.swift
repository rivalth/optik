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

    public init(model: String, system: String, turnContext: String, messages: [ChatMessage], maxTokens: Int = 1024) {
        self.model = model
        self.system = system
        self.turnContext = turnContext
        self.messages = messages
        self.maxTokens = maxTokens
    }
}

/// What the model streams back.
public enum LLMEvent: Equatable, Sendable {
    case text(String)
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
