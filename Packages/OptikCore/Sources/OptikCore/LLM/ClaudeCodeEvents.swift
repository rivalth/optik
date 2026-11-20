import Foundation

/// Turns the JSON lines of `claude -p --output-format stream-json
/// --include-partial-messages` into `LLMEvent`s. Only the streamed text and the
/// final result matter; everything else is skipped.
public struct ClaudeCodeEvents: Sendable {
    public private(set) var finished = false
    private var joiner = ReplyTextJoiner()
    private var sources = SourceListFilter()
    private var foundSource = false

    public init() {}

    public mutating func decode(_ line: String) throws -> LLMEvent? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String
        else { return nil }
        switch type {
        case "stream_event":
            guard let event = object["event"] as? [String: Any] else { return nil }
            switch event["type"] as? String {
            case "content_block_start":
                let block = event["content_block"] as? [String: Any]
                joiner.blockStarted(isText: block?["type"] as? String == "text")
                return nil
            case "message_start":
                // After a tool call Claude Code goes on in a new message.
                joiner.blockStarted(isText: false)
                return nil
            case "content_block_delta":
                guard let delta = event["delta"] as? [String: Any],
                      delta["type"] as? String == "text_delta",
                      let text = delta["text"] as? String, !text.isEmpty
                else { return nil }
                let kept = sources.filter(joiner.text(text))
                return kept.isEmpty ? nil : .text(kept)
            default:
                return nil
            }
        case "assistant":
            // The whole message again: a page Claude Code read, or the links it cites.
            guard !foundSource,
                  let message = object["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]]
            else { return nil }
            let fetched = content.lazy
                .filter { $0["type"] as? String == "tool_use" && $0["name"] as? String == "WebFetch" }
                .compactMap { ($0["input"] as? [String: Any])?["url"] as? String }
                .compactMap { ReplySource.firstLink(in: $0) }
                .first
            let cited = content.lazy
                .filter { $0["type"] as? String == "text" }
                .compactMap { ($0["text"] as? String).flatMap(ReplySource.firstLink(in:)) }
                .first
            guard let link = fetched ?? cited else { return nil }
            foundSource = true
            return .source(link)
        case "result":
            finished = true
            if object["is_error"] as? Bool == true || (object["subtype"] as? String).map({ $0 != "success" }) == true {
                throw LLMError.claudeCodeFailed
            }
            let usage = object["usage"] as? [String: Any] ?? [:]
            return .finished(
                stopReason: object["stop_reason"] as? String ?? "end_turn",
                usage: LLMUsage(
                    inputTokens: usage["input_tokens"] as? Int ?? 0,
                    outputTokens: usage["output_tokens"] as? Int ?? 0,
                    cacheReadInputTokens: usage["cache_read_input_tokens"] as? Int ?? 0,
                    cacheCreationInputTokens: usage["cache_creation_input_tokens"] as? Int ?? 0
                )
            )
        default:
            return nil
        }
    }
}
