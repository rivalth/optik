import OptikCore
import Testing
@testable import Optik

@MainActor
struct QuickAskModelTests {
    @Test func wordsJoinBackIntoTheText() {
        let text = "Yarın 11.00’de  Bilgisayar Ağları var.\nSonra kahve. "
        let words = QuickAskModel.words(in: text)
        #expect(words.joined() == text)
        #expect(words.first == "Yarın ")
        #expect(words.count == 7)
    }

    @Test func eachWordStartsAfterThePreviousOne() {
        let model = QuickAskModel()
        model.appendReply("Yarın 11.00’de ")
        model.appendReply("Bilgisayar Ağları var.")
        #expect(model.wordStarts.count == 5)
        for (earlier, later) in zip(model.wordStarts, model.wordStarts.dropFirst()) {
            #expect(later.timeIntervalSince(earlier) >= QuickAskModel.wordDelay - 0.000_1)
        }
    }

    @Test func moodFollowsTheBox() {
        let model = QuickAskModel()
        #expect(model.mood == .waiting)
        model.text = "Yarın"
        #expect(model.mood == .listening)
        model.text = ""
        model.isWaiting = true
        #expect(model.mood == .thoughtful)
        model.appendReply("Yarın")
        #expect(model.mood == .happy)
        model.showError("Olmadı.")
        #expect(model.mood == .alert)
    }
}

@MainActor
struct QuickAskAskingTests {
    @Test func askingWhenOfferingALinkOrEndingWithAQuestion() {
        let model = QuickAskModel()
        model.appendReply("Hangi maçı diyorsun?")
        #expect(model.mood == .asking)
        model.clearReply()
        model.appendReply("Maç 20.00’de.")
        #expect(model.mood == .happy)
        model.isOfferingLink = true
        #expect(model.mood == .asking)
    }
}
