import Testing
@testable import OptikCore

@Suite struct TurkishNumbersTests {
    @Test(arguments: [
        (0, "sıfır"), (7, "yedi"), (10, "on"), (13, "on üç"), (40, "kırk"), (100, "yüz"), (101, "yüz bir"),
        (250, "iki yüz elli"), (1_000, "bin"), (1_500, "bin beş yüz"), (18_000, "on sekiz bin"),
        (100_000, "yüz bin"), (1_000_000, "bir milyon"), (2_350_000, "iki milyon üç yüz elli bin"),
        (-5, "eksi beş"),
    ])
    func words(number: Int, expected: String) {
        #expect(TurkishNumbers.words(number) == expected)
    }
}

@Suite struct SpeechTextTests {
    @Test(arguments: [
        ("Kuzey Mobilya'dan ₺18.000 geldi.", "Kuzey Mobilya'dan on sekiz bin lira geldi."),
        ("Kalan 18.000 TL.", "Kalan on sekiz bin lira."),
        ("150 lira, dışarıda yemek.", "yüz elli lira, dışarıda yemek."),
        ("₺42,50 harcadın.", "kırk iki lira elli kuruş harcadın."),
        ("Bütçenin %80'i gitti.", "Bütçenin yüzde seksen'i gitti."),
        ("13.00'te Yeliz ile kahve.", "on üçte Yeliz ile kahve."),
        ("Toplantı 16.30'da.", "Toplantı on altı otuzda."),
        ("Saat 9:05.", "Saat dokuz sıfır beş."),
        ("Yarın 3'te buluşma.", "Yarın üçte buluşma."),
        ("3 gün kaldı.", "3 gün kaldı."),
        ("Nüfus 1.250.000 kişi.", "Nüfus bir milyon iki yüz elli bin kişi."),
    ])
    func normalized(input: String, expected: String) {
        #expect(SpeechText.normalized(input) == expected)
    }
}

@Suite struct SentenceChunkerTests {
    @Test func splitsStreamedTextAtSentenceEnds() {
        var chunker = SentenceChunker()
        let r1 = chunker.append("Tamam, ")
        #expect(r1.isEmpty)
        let r2 = chunker.append("kaydettim. Bu ay ")
        #expect(r2 == ["Tamam, kaydettim."])
        let r3 = chunker.append("8.100 kaldı! Başka")
        #expect(r3 == ["Bu ay 8.100 kaldı!"])
        let r4 = chunker.finish()
        #expect(r4 == "Başka")
        let r5 = chunker.finish()
        #expect(r5 == nil)
    }

    @Test func clockTimesAndNumbersDoNotEndSentences() {
        var chunker = SentenceChunker()
        let r6 = chunker.append("Saat 13.00'te kahve var, 18.000 lira da geldi. ")
        #expect(r6 == ["Saat 13.00'te kahve var, 18.000 lira da geldi."])
    }

    @Test func waitsForTheSpaceAfterPunctuation() {
        var chunker = SentenceChunker()
        let r7 = chunker.append("Oldu.")
        #expect(r7.isEmpty)
        let r8 = chunker.append(" Sonra")
        #expect(r8 == ["Oldu."])
    }

    @Test func keepsClosingQuotes() {
        var chunker = SentenceChunker()
        let r9 = chunker.append("\"Geldim.\" dedi ")
        #expect(r9 == ["\"Geldim.\""])
    }
}

@Suite struct SpokenReplyLimiterTests {
    @Test func speaksShortRepliesWhole() {
        var limiter = SpokenReplyLimiter()
        let r10 = limiter.shouldSpeak("Bir.")
        #expect(r10)
        let r11 = limiter.shouldSpeak("İki.")
        #expect(r11)
        let r12 = limiter.shouldSpeak("Üç.")
        #expect(r12)
    }

    @Test func cutsLongRepliesAfterTwoSentences() {
        var limiter = SpokenReplyLimiter()
        let long = String(repeating: "uzun ", count: 30) + "."
        let r13 = limiter.shouldSpeak(long)
        #expect(r13)
        let r14 = limiter.shouldSpeak(long)
        #expect(r14)
        let r15 = limiter.shouldSpeak("Üç.")
        #expect(!r15)
        let r16 = limiter.shouldSpeak("Dört.")
        #expect(!r16)
    }
}

@Suite struct LocalCommandTests {
    @Test(arguments: ["Tamam.", "sus", "Boş ver!", "Optik, vazgeç.", "İptal"])
    func stops(_ text: String) {
        #expect(LocalCommand(text) == .stop)
    }

    @Test(arguments: ["Tamam, yarın 3'te Yeliz'le buluşuyorum", "Kahveye 150 lira verdim", ""])
    func passesTheRestToTheModel(_ text: String) {
        #expect(LocalCommand(text) == nil)
    }
}
