import Foundation
import Testing
@testable import Optik

struct ScribeTranscriberTests {
    @Test func audioIsSixteenBitLittleEndian() {
        let data = ScribeTranscriber.pcm16([0, 1, -1, 2])
        #expect(data.count == 8)
        #expect(Array(data) == [0x00, 0x00, 0xFF, 0x7F, 0x01, 0x80, 0xFF, 0x7F])
    }

    @Test func keyTermsFitTheLimits() {
        let terms = ["Optik", "an extremely long phrase here"] + (1...60).map { "terim\($0)" }
        let kept = ScribeTranscriber.keyTerms(terms)
        #expect(kept.count == ScribeTranscriber.maxTerms)
        #expect(kept.first == "Optik")
        #expect(!kept.contains("an extremely long phrase here"))
    }

    @Test func chunkMessageCarriesTheAudio() throws {
        let message = ScribeTranscriber.chunkMessage(Data([1, 2, 3]), commit: true)
        let object = try #require(try JSONSerialization.jsonObject(with: Data(message.utf8)) as? [String: Any])
        #expect(object["message_type"] as? String == "input_audio_chunk")
        #expect(object["audio_base_64"] as? String == "AQID")
        #expect(object["commit"] as? Bool == true)
        #expect(object["sample_rate"] as? Int == 16_000)
    }

    @Test func serverEvents() {
        #expect(ScribeEvent(json: #"{"message_type":"committed_transcript","text":"Spotify'ı aç."}"#) == .committed("Spotify'ı aç."))
        #expect(ScribeEvent(json: #"{"message_type":"partial_transcript","text":"Spo"}"#) == .partial("Spo"))
        #expect(ScribeEvent(json: #"{"message_type":"quota_exceeded","error":"…"}"#) == .error("quota_exceeded"))
        #expect(ScribeEvent(json: "not json") == nil)
    }
}
