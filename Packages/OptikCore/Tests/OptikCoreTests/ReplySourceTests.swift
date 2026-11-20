import Foundation
import OptikCore
import Testing

struct ReplySourceTests {
    @Test func findsTheFirstLink() {
        #expect(ReplySource.firstLink(in: "Kaynak: [Aspor](https://www.aspor.com.tr/futbol/mac).")?.absoluteString
            == "https://www.aspor.com.tr/futbol/mac")
        #expect(ReplySource.firstLink(in: "Bak: https://example.com/a?b=1, sonra.")?.absoluteString == "https://example.com/a?b=1")
        #expect(ReplySource.firstLink(in: "Bağlantı yok.") == nil)
    }

    @Test func claudeCodeReportsTheReadPageFirst() throws {
        var events = ClaudeCodeEvents()
        let fetch = #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"WebFetch","input":{"url":"https://example.com/fikstur","prompt":"saat"}}]}}"#
        let cited = #"{"type":"assistant","message":{"content":[{"type":"text","text":"Maç 20.00’de.\n\nSources:\n- [A](https://example.com/haber)"}]}}"#
        #expect(try events.decode(fetch) == .source(URL(string: "https://example.com/fikstur")!))
        #expect(try events.decode(cited) == nil)
    }

    @Test func claudeCodeReportsACitedLink() throws {
        var events = ClaudeCodeEvents()
        let cited = #"{"type":"assistant","message":{"content":[{"type":"text","text":"Maç 20.00’de.\n\nSources:\n- [A](https://example.com/haber)"}]}}"#
        #expect(try events.decode(cited) == .source(URL(string: "https://example.com/haber")!))
    }

    @Test func apiCitationIsASource() throws {
        var decoder = ClaudeMessages.StreamDecoder()
        let event = ServerSentEventParser.Event(name: "content_block_delta", data: #"{"type":"content_block_delta","index":1,"delta":{"type":"citations_delta","citation":{"type":"web_search_result_location","url":"https://example.com/mac","title":"Maç"}}}"#)
        #expect(try decoder.decode(event) == .source(URL(string: "https://example.com/mac")!))
        #expect(try decoder.decode(event) == nil)
    }
}

struct YesNoAnswerTests {
    @Test func understandsShortAnswers() {
        #expect(YesNoAnswer("Evet.") == .yes)
        #expect(YesNoAnswer("Optik, aç bakalım") == .yes)
        #expect(YesNoAnswer("tamam") == .yes)
        #expect(YesNoAnswer("Hayır, gerek yok") == .no)
        #expect(YesNoAnswer("yok") == .no)
    }

    @Test func leavesLongerAnswersToTheModel() {
        #expect(YesNoAnswer("evet ama önce saati söyle") == nil)
        #expect(YesNoAnswer("yarın hava nasıl") == nil)
    }
}

struct TurkishSuffixTests {
    @Test func locativeFollowsTheSound() {
        #expect(TurkishSuffix.locative("Dia") == "Dia’da")
        #expect(TurkishSuffix.locative("Safari") == "Safari’de")
        #expect(TurkishSuffix.locative("Google Chrome") == "Google Chrome’da")
        #expect(TurkishSuffix.locative("Arc") == "Arc’ta")
        #expect(TurkishSuffix.locative("Firefox") == "Firefox’ta")
        #expect(TurkishSuffix.locative("Edge") == "Edge’de")
    }
}

struct AskingMoodTests {
    @Test func aQuestionInTheReplyShowsTheAskingMood() {
        var machine = IslandStateMachine()
        machine.handle(.summon)
        machine.handle(.reply("Maç 20.00’de."))
        #expect(machine.mood == .happy)
        machine.handle(.reply("Maç 20.00’de.\nSayfayı Dia’da açayım mı?"))
        #expect(machine.mood == .asking)
        #expect(IslandStateMachine.isQuestion("Hangisi?” "))
        #expect(!IslandStateMachine.isQuestion("Ne? Tamam, kaydettim."))
    }
}
