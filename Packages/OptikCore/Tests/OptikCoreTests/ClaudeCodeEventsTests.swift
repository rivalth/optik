import OptikCore
import Testing

struct ClaudeCodeEventsTests {
    @Test func streamsTextAndFinishes() throws {
        var events = ClaudeCodeEvents()
        let lines = [
            #"{"type":"system","subtype":"init","model":"claude-haiku-5-5"}"#,
            #"{"type":"stream_event","event":{"type":"message_start","message":{}}}"#,
            #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Yarın "}}}"#,
            #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"güneşli."}}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"text","text":"Yarın güneşli."}]}}"#,
            #"{"type":"result","subtype":"success","is_error":false,"result":"Yarın güneşli.","stop_reason":"end_turn","usage":{"input_tokens":12,"output_tokens":5,"cache_read_input_tokens":800,"cache_creation_input_tokens":0}}"#,
        ]
        let decoded = try lines.compactMap { try events.decode($0) }
        #expect(decoded == [
            .text("Yarın "), .text("güneşli."),
            .finished(stopReason: "end_turn", usage: LLMUsage(inputTokens: 12, outputTokens: 5, cacheReadInputTokens: 800)),
        ])
        #expect(events.finished)
    }

    @Test func textAfterASearchStartsWithASpace() throws {
        var events = ClaudeCodeEvents()
        let lines = [
            #"{"type":"stream_event","event":{"type":"message_start","message":{}}}"#,
            #"{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}}"#,
            #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Bakıyorum."}}}"#,
            #"{"type":"stream_event","event":{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","name":"WebSearch","input":{}}}}"#,
            #"{"type":"stream_event","event":{"type":"message_start","message":{}}}"#,
            #"{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}}"#,
            #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Maç 20.00’de."}}}"#,
        ]
        let text = try lines.compactMap { try events.decode($0) }.map { event -> String in
            if case .text(let delta) = event { return delta }
            return ""
        }.joined()
        #expect(text == "Bakıyorum. Maç 20.00’de.")
    }

    @Test func anErrorResultThrows() {
        var events = ClaudeCodeEvents()
        #expect(throws: LLMError.claudeCodeFailed) {
            try events.decode(#"{"type":"result","subtype":"success","is_error":true,"result":"Not logged in"}"#)
        }
    }

    @Test func skipsWhatIsNotJSON() throws {
        var events = ClaudeCodeEvents()
        #expect(try events.decode("not json") == nil)
        #expect(try events.decode("") == nil)
    }
}
