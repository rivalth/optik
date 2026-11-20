import Testing
@testable import OptikCore

struct TranscriptFilterTests {
    typealias Segment = TranscriptFilter.Segment

    @Test func soundTagsAreRemoved() {
        #expect(TranscriptFilter.clean("(Müzik) Spotify'ı aç") == "Spotify'ı aç")
        #expect(TranscriptFilter.clean("[Alkış] ♪ ♪") == "")
        #expect(TranscriptFilter.clean("*gülüşmeler* tamam") == "tamam")
        #expect(TranscriptFilter.clean("...") == "")
    }

    @Test func subtitleInventionsAreDropped() {
        #expect(TranscriptFilter.clean("Altyazı M.K.") == "")
        #expect(TranscriptFilter.clean("İzlediğiniz için teşekkürler.") == "")
        #expect(TranscriptFilter.clean("Abone olmayı unutmayın!") == "")
    }

    @Test func realRequestsMentioningTheseWordsStay() {
        #expect(TranscriptFilter.clean("YouTube'da abone olduğum kanalı aç") == "YouTube'da abone olduğum kanalı aç")
        #expect(TranscriptFilter.clean("Bir müziği çal") == "Bir müziği çal")
        #expect(TranscriptFilter.clean("example.com'u aç") == "example.com'u aç")
        #expect(TranscriptFilter.clean("Altyazıyı aç") == "Altyazıyı aç")
    }

    @Test func loopsAndDoubtfulStretchesAreDropped() {
        let loop = Segment(text: "evet evet evet evet evet evet", compressionRatio: 3.1)
        let doubtful = Segment(text: "Bakara.", noSpeechProbability: 0.5, averageLogProbability: -1.3)
        let real = Segment(text: "Spotify'ı aç.", noSpeechProbability: 0.02, averageLogProbability: -0.2)
        #expect(TranscriptFilter.text(of: [loop, real]) == "Spotify'ı aç.")
        #expect(TranscriptFilter.text(of: [doubtful]) == "")
        #expect(TranscriptFilter.text(of: [real, doubtful]) == "Spotify'ı aç.")
    }

    @Test func thanksStayOnlyWhenSure() {
        let sure = Segment(text: "Teşekkürler.", noSpeechProbability: 0.05, averageLogProbability: -0.3)
        let unsure = Segment(text: "Teşekkürler.", noSpeechProbability: 0.35, averageLogProbability: -0.5)
        #expect(TranscriptFilter.text(of: [sure]) == "Teşekkürler.")
        #expect(TranscriptFilter.text(of: [unsure]) == "")
    }

    @Test func hintsCarryTheNames() {
        #expect(SpeechHints.terms(userName: "Ada").prefix(2) == ["Optik", "Ada"])
        #expect(SpeechHints.terms(userName: "  ").first == "Optik")
        #expect(SpeechHints.whisperPrompt(userName: "Ada") == "Optik, Ada.")
        #expect(SpeechHints.whisperPrompt(userName: nil) == "Optik.")
    }
}
