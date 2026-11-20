import Foundation
import Testing
@testable import OptikCore

@Suite struct EndpointDetectorTests {
    /// 20 ms frames at the given levels, starting at t = 0.
    private func run(_ detector: inout EndpointDetector, _ levels: [(Double, Int)], from start: Double = 0) -> [EndpointDetector.Event] {
        var time = start
        var events: [EndpointDetector.Event] = []
        for (level, frames) in levels {
            for _ in 0..<frames {
                time += 0.02
                if let event = detector.process(level: level, at: time) { events.append(event) }
            }
        }
        return events
    }

    @Test func findsAnUtteranceInAQuietRoom() {
        var detector = EndpointDetector()
        let events = run(&detector, [(-70, 25), (-30, 50), (-70, 40)])
        #expect(events.count == 2)
        guard case .speechStarted(let start) = events.first, case .speechEnded(let end) = events.last else {
            Issue.record("expected start and end"); return
        }
        // Smoothing takes one frame to cross the minimum speech level.
        #expect(abs(start - 0.54) < 0.001)
        // 0.7 s of silence after the speech ended at 1.5 s, plus smoothing.
        #expect(abs(end - 2.26) < 0.03)
    }

    @Test func startupSilenceDoesNotSinkTheFloor() {
        var detector = EndpointDetector()
        // A microphone starts with digital zeros, then the room at -60 dB.
        let events = run(&detector, [(-100, 10), (-60, 25), (-30, 50), (-60, 40)])
        #expect(events.count == 2)
        #expect(detector.noiseFloor >= -75)
    }

    @Test func floorFollowsARoomThatGetsLouder() {
        var detector = EndpointDetector()
        // Quiet at first, then a fan or automatic gain lifts the room to -50 dB.
        let early = run(&detector, [(-75, 25), (-50, 150)])
        #expect(abs(detector.noiseFloor + 50) < 0.5)
        // Speech over the louder room still starts and ends on time.
        let events = run(&detector, [(-20, 50), (-50, 50)], from: 3.5)
        #expect(events.count == 2)
        guard case .speechEnded(let end) = events.last else { Issue.record("no end"); return }
        #expect(end < 4.5 + 0.8)
        _ = early
    }

    @Test func roomNoiseAfterSpeechDoesNotStartAgain() {
        var detector = EndpointDetector()
        var pattern: [(Double, Int)] = [(-60, 50), (-25, 50)]
        // After speech the room wavers by a few dB, as it does after voice processing.
        for _ in 0..<40 { pattern += [(-58, 3), (-52, 2)] }
        let events = run(&detector, pattern)
        #expect(events.count == 2)
    }

    /// A video in the room: speech-like bursts between -58 and -40 dB.
    private func video(seconds: Int) -> [(Double, Int)] {
        var pattern: [(Double, Int)] = []
        for _ in 0..<(seconds * 2) { pattern += [(-42, 8), (-55, 4), (-40, 6), (-58, 7)] }
        return pattern
    }

    @Test func aVideoInTheRoomIsNotTheUser() {
        var detector = EndpointDetector()
        let events = run(&detector, video(seconds: 10))
        #expect(events.isEmpty)
    }

    @Test func theUserIsHeardOverAVideo() {
        var detector = EndpointDetector()
        let before = run(&detector, video(seconds: 4))
        #expect(before.isEmpty)
        // The user, close to the microphone, says a short sentence; the video goes on.
        let events = run(&detector, [(-24, 60)] + video(seconds: 4), from: 4)
        #expect(events.count == 2)
        guard case .speechEnded(let end) = events.last else { Issue.record("no end"); return }
        // Ends about 0.7 s after the user stopped at 5.2 s, not when the video does.
        #expect(end < 5.2 + 1.2)
    }

    @Test func strongSpeechIsMeasured() {
        var detector = EndpointDetector()
        _ = run(&detector, [(-70, 50), (-30, 25)])
        #expect(detector.isSpeaking)
        #expect(detector.strongSpeech > 0.3)
        var faint = EndpointDetector()
        _ = run(&faint, [(-60, 50), (-45, 25)])
        #expect(faint.isSpeaking)
        #expect(faint.strongSpeech == 0)
    }

    @Test func steadyNoiseIsNotSpeech() {
        var detector = EndpointDetector()
        let events = run(&detector, [(-45, 300)])
        #expect(events.isEmpty)
        #expect(abs(detector.noiseFloor + 45) < 0.001)
    }

    @Test func shortClicksAreIgnored() {
        var detector = EndpointDetector()
        let events = run(&detector, [(-70, 25), (-20, 3), (-70, 25)])
        #expect(events.isEmpty)
    }

    @Test func aBreathDoesNotEndTheSentence() {
        var detector = EndpointDetector()
        let events = run(&detector, [(-70, 25), (-30, 40), (-70, 20), (-30, 40), (-70, 40)])
        #expect(events.count == 2)
    }

    @Test func endsAnEndlessUtterance() {
        var detector = EndpointDetector()
        detector.configuration.maximumUtterance = 2
        let events = run(&detector, [(-70, 25), (-30, 200)])
        #expect(events.count >= 2)
        guard events.count >= 2, case .speechEnded(let end) = events[1] else { Issue.record("no end"); return }
        #expect(abs(end - 2.52) < 0.03)
    }

    @Test func levelOfSilenceAndFullScale() {
        #expect(EndpointDetector.level(of: [Float](repeating: 0, count: 10)) == -100)
        #expect(abs(EndpointDetector.level(of: [Float](repeating: 1, count: 10))) < 0.001)
        #expect(abs(EndpointDetector.level(of: [Float](repeating: 0.1, count: 10)) + 20) < 0.001)
    }
}

@Suite struct ServerSentEventParserTests {
    @Test func parsesEvents() {
        var parser = ServerSentEventParser()
        let lines = ["event: message_start", "data: {\"a\":1}", "", ": ping", "data: x", "data: y", ""]
        let events = lines.compactMap { parser.feed(line: $0) }
        #expect(events == [
            .init(name: "message_start", data: "{\"a\":1}"),
            .init(name: "message", data: "x\ny"),
        ])
    }
}

@Suite struct ClaudeMessagesTests {
    @Test func requestCachesTheSystemPromptOnly() throws {
        let request = LLMRequest(model: "claude-haiku-5-5", system: "Sen Optik'sin.", turnContext: "Şimdi: 13.42",
                                 messages: [ChatMessage(role: .user, text: "Saat kaç?")])
        let json = try #require(try JSONSerialization.jsonObject(with: ClaudeMessages.body(for: request)) as? [String: Any])
        #expect(json["model"] as? String == "claude-haiku-5-5")
        #expect(json["stream"] as? Bool == true)
        let system = try #require(json["system"] as? [[String: Any]])
        #expect(system.count == 2)
        #expect((system[0]["cache_control"] as? [String: String])?["type"] == "ephemeral")
        #expect(system[1]["cache_control"] == nil)
        #expect(system[1]["text"] as? String == "Şimdi: 13.42")
        #expect((json["thinking"] as? [String: String])?["type"] == "disabled")
        #expect((json["output_config"] as? [String: String])?["effort"] == "low")
        let messages = try #require(json["messages"] as? [[String: String]])
        #expect(messages == [["role": "user", "content": "Saat kaç?"]])
    }

    @Test func requestCanSearchTheWeb() throws {
        var request = LLMRequest(model: "claude-haiku-5-5", system: "Sen Optik'sin.", turnContext: "",
                                 messages: [ChatMessage(role: .user, text: "Maç kaçta?")])
        let json = try #require(try JSONSerialization.jsonObject(with: ClaudeMessages.body(for: request)) as? [String: Any])
        let tools = try #require(json["tools"] as? [[String: Any]])
        #expect(tools.count == 1)
        #expect(tools[0]["type"] as? String == "web_search_20250305")
        #expect(tools[0]["name"] as? String == "web_search")
        #expect(tools[0]["max_uses"] as? Int == 3)
        #expect((tools[0]["user_location"] as? [String: String])?["timezone"] == "Europe/Istanbul")

        request.webSearch = false
        let without = try #require(try JSONSerialization.jsonObject(with: ClaudeMessages.body(for: request)) as? [String: Any])
        #expect(without["tools"] == nil)
    }

    @Test func textAroundASearchDoesNotRunTogether() throws {
        let stream = """
        data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Bakıyorum."}}

        data: {"type":"content_block_start","index":1,"content_block":{"type":"server_tool_use","id":"srvtoolu_1","name":"web_search","input":{}}}

        data: {"type":"content_block_start","index":2,"content_block":{"type":"web_search_tool_result","tool_use_id":"srvtoolu_1","content":[]}}

        data: {"type":"content_block_start","index":3,"content_block":{"type":"text","text":""}}

        data: {"type":"content_block_delta","index":3,"delta":{"type":"text_delta","text":"Maç "}}

        data: {"type":"content_block_start","index":4,"content_block":{"type":"text","text":""}}

        data: {"type":"content_block_delta","index":4,"delta":{"type":"text_delta","text":"20.00’de."}}

        """
        var parser = ServerSentEventParser()
        var decoder = ClaudeMessages.StreamDecoder()
        var text = ""
        for line in stream.components(separatedBy: "\n") {
            if let event = parser.feed(line: line), case .text(let delta)? = try decoder.decode(event) { text += delta }
        }
        #expect(text == "Bakıyorum. Maç 20.00’de.")
    }

    @Test func decodesAStream() throws {
        let stream = """
        event: message_start
        data: {"type":"message_start","message":{"id":"msg_1","usage":{"input_tokens":12,"cache_read_input_tokens":900,"cache_creation_input_tokens":0,"output_tokens":1}}}

        event: content_block_start
        data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Saat "}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"on üç."}}

        event: message_delta
        data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":7}}

        event: message_stop
        data: {"type":"message_stop"}

        """
        var parser = ServerSentEventParser()
        var decoder = ClaudeMessages.StreamDecoder()
        var events: [LLMEvent] = []
        for line in stream.components(separatedBy: "\n") {
            if let event = parser.feed(line: line), let decoded = try decoder.decode(event) { events.append(decoded) }
        }
        #expect(events == [
            .text("Saat "), .text("on üç."),
            .finished(stopReason: "end_turn", usage: LLMUsage(inputTokens: 12, outputTokens: 7, cacheReadInputTokens: 900)),
        ])
    }

    @Test func streamErrorsThrow() {
        var decoder = ClaudeMessages.StreamDecoder()
        let event = ServerSentEventParser.Event(name: "error", data: #"{"type":"error","error":{"type":"overloaded_error"}}"#)
        #expect(throws: LLMError.http(status: 0, type: "overloaded_error")) {
            var copy = decoder
            _ = try copy.decode(event)
        }
    }
}

@Suite struct PromptConfigurationTests {
    @Test func extractsTheSystemPrompt() {
        let markdown = "# Başlık\n\n## İstem\n\nAçıklama\n\n```text\nSen Optik'sin.\nİkinci satır.\n```\n\n## Tur bağlamı\n\n```text\nKullanıcı: Ada\n```\n"
        #expect(SystemPrompt.extract(fromMarkdown: markdown) == "Sen Optik'sin.\nİkinci satır.")
    }

    @Test func decodesModels() throws {
        let models = try LLMModels.decode(from: Data(#"{"_aciklama":"x","sesli_tur":"claude-haiku-5-5","uzun_is":"claude-sonnet-5-5"}"#.utf8))
        #expect(models == LLMModels(voice: "claude-haiku-5-5", deep: "claude-sonnet-5-5"))
    }

    @Test func turnContextInIstanbulTime() {
        // 2026-11-16 10:42 UTC is 13.42 in Istanbul, a Monday.
        let date = Date(timeIntervalSince1970: 1_794_825_720)
        let context = TurnContext(userName: "Ada", now: date, trigger: .shortcut)
        #expect(context.text.hasPrefix("Kullanıcı: Ada\nŞimdi: 2026-11-16 Pazartesi 13.42 (Europe/Istanbul)\nTetikleyen: klavye kısayolu"))
        #expect(context.text.contains("araç yok"))
        #expect(!TurnContext(userName: nil, now: date, trigger: .wakeWord, toolsAvailable: true).text.contains("Not:"))
    }

    @Test func historyKeepsTheLastTurns() {
        var history = ConversationHistory(maximumTurns: 2)
        for index in 1...3 { history.append(user: "u\(index)", assistant: "a\(index)") }
        #expect(history.messages.map(\.text) == ["u2", "a2", "u3", "a3"])
        #expect(history.request(adding: "u4").last == ChatMessage(role: .user, text: "u4"))
    }
}

@Suite struct TurnLatencyTests {
    @Test func encodesTheDocumentedKeys() {
        var latency = TurnLatency()
        latency.wakeToIsland = 1
        latency.speechEndToTranscript = 300
        latency.transcriptToFirstToken = 400
        latency.firstTokenToFirstAudio = 250
        #expect(latency.speechEndToFirstAudio == 950)
        #expect(latency.json == #"{"first_token_to_first_audio":250,"speech_end_to_transcript":300,"transcript_to_first_token":400,"wake_to_island":1}"#)
    }
}
