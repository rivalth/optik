import Foundation

/// The Claude Messages API wire format: request body and streamed events.
/// Plain HTTP (there is no official Swift SDK), version `2026-10-21`.
public enum ClaudeMessages {
    public static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    public static let modelsEndpoint = URL(string: "https://api.anthropic.com/v1/models")!
    public static let apiVersion = "2026-10-21"

    /// The JSON body for a streaming request.
    ///
    /// - The system prompt is one cached block; the per-turn context follows it in a
    ///   second block, after the cache breakpoint, so it never invalidates the cache.
    /// - Voice turns need the first words fast: thinking off, effort low.
    public static func body(for request: LLMRequest) throws -> Data {
        let body = Body(
            model: request.model,
            max_tokens: request.maxTokens,
            stream: true,
            system: [
                SystemBlock(text: request.system, cache_control: CacheControl()),
                SystemBlock(text: request.turnContext, cache_control: nil),
            ].filter { !$0.text.isEmpty },
            messages: request.messages.map { Message(role: $0.role.rawValue, content: $0.text) },
            thinking: Thinking(type: "disabled"),
            output_config: OutputConfig(effort: "low")
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(body)
    }

    private struct Body: Encodable {
        var model: String
        var max_tokens: Int
        var stream: Bool
        var system: [SystemBlock]
        var messages: [Message]
        var thinking: Thinking
        var output_config: OutputConfig
    }

    private struct SystemBlock: Encodable {
        var type = "text"
        var text: String
        var cache_control: CacheControl?
    }

    private struct CacheControl: Encodable {
        var type = "ephemeral"
    }

    private struct Message: Encodable {
        var role: String
        var content: String
    }

    private struct Thinking: Encodable {
        var type: String
    }

    private struct OutputConfig: Encodable {
        var effort: String
    }

    // MARK: Stream

    /// Folds streamed events into `LLMEvent`s. Keeps usage across `message_start`
    /// and `message_delta`.
    public struct StreamDecoder: Sendable {
        private var usage = LLMUsage()
        private var stopReason: String?

        public init() {}

        public mutating func decode(_ event: ServerSentEventParser.Event) throws -> LLMEvent? {
            guard let data = event.data.data(using: .utf8) else { throw LLMError.malformedResponse }
            let payload: Payload
            do {
                payload = try JSONDecoder().decode(Payload.self, from: data)
            } catch {
                throw LLMError.malformedResponse
            }
            switch payload.type {
            case "message_start":
                if let start = payload.message?.usage { merge(start) }
            case "content_block_delta":
                if payload.delta?.type == "text_delta", let text = payload.delta?.text, !text.isEmpty {
                    return .text(text)
                }
            case "message_delta":
                if let reason = payload.delta?.stop_reason { stopReason = reason }
                if let delta = payload.usage { merge(delta) }
            case "message_stop":
                return .finished(stopReason: stopReason, usage: usage)
            case "error":
                throw LLMError.http(status: 0, type: payload.error?.type)
            default:
                break
            }
            return nil
        }

        private mutating func merge(_ other: Usage) {
            if let value = other.input_tokens { usage.inputTokens = value }
            if let value = other.output_tokens { usage.outputTokens = value }
            if let value = other.cache_read_input_tokens { usage.cacheReadInputTokens = value }
            if let value = other.cache_creation_input_tokens { usage.cacheCreationInputTokens = value }
        }
    }

    private struct Payload: Decodable {
        var type: String
        var message: StartMessage?
        var delta: Delta?
        var usage: Usage?
        var error: APIError?
    }

    private struct StartMessage: Decodable {
        var usage: Usage?
    }

    private struct Delta: Decodable {
        var type: String?
        var text: String?
        var stop_reason: String?
    }

    struct Usage: Decodable {
        var input_tokens: Int?
        var output_tokens: Int?
        var cache_read_input_tokens: Int?
        var cache_creation_input_tokens: Int?
    }

    private struct APIError: Decodable {
        var type: String?
    }

    /// The error type from an error response body (`{"type":"error","error":{"type":...}}`).
    public static func errorType(in body: Data) -> String? {
        struct Envelope: Decodable {
            struct Inner: Decodable { var type: String? }
            var error: Inner?
        }
        return (try? JSONDecoder().decode(Envelope.self, from: body))?.error?.type
    }
}
