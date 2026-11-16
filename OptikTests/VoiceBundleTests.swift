import Foundation
import OptikCore
import Testing
@testable import Optik

/// The voice pipeline's files ship inside the app.
struct VoiceBundleTests {
    @Test func systemPromptIsBundled() throws {
        let url = try #require(Bundle.main.url(forResource: "sistem-istemi", withExtension: "md"))
        let prompt = try #require(SystemPrompt.extract(fromMarkdown: String(contentsOf: url, encoding: .utf8)))
        #expect(prompt.hasPrefix("Sen Optik'sin"))
    }

    @Test func modelNamesAreBundled() throws {
        let url = try #require(Bundle.main.url(forResource: "modeller", withExtension: "json"))
        let models = try LLMModels.decode(from: Data(contentsOf: url))
        #expect(models.voice.hasPrefix("claude-"))
    }

    @Test func everyFixedPhraseHasItsRecording() {
        #expect(FixedPhrases.all.count == 18)
        for phrase in FixedPhrases.all {
            #expect(FixedPhrases.url(for: phrase.id) != nil, "\(phrase.id).wav is missing")
        }
    }

    @Test func greetingIsAnEfendimVariant() throws {
        let phrase = try #require(FixedPhrases.variant("efendim"))
        #expect(phrase.id.hasPrefix("efendim-"))
    }

    @Test func toolsAndVoiceNotesStayOutOfTheApp() {
        #expect(Bundle.main.url(forResource: "araclar", withExtension: "json") == nil)
        #expect(Bundle.main.url(forResource: "ses-kimligi", withExtension: "md") == nil)
    }

    @Test func microphoneUsageIsExplained() {
        let text = Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") as? String
        #expect(text?.isEmpty == false)
    }
}
