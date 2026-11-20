import Foundation
import OptikCore
import Testing

struct LocalCommandParserTests {
    let parser = LocalCommandParser(
        appNames: ["Dia", "Spotify", "Safari", "Google Chrome", "Notlar", "Takvim", "WhatsApp"],
        browserNames: ["Dia", "Safari", "Google Chrome"]
    )

    @Test func opensAndQuitsApps() {
        #expect(parser.recognize("Dia'yı aç") == .openApp("Dia"))
        #expect(parser.recognize("diayı aç.") == .openApp("Dia"))
        #expect(parser.recognize("Spotifyı başlat") == .openApp("Spotify"))
        #expect(parser.recognize("Google Chrome’u aç") == .openApp("Google Chrome"))
        #expect(parser.recognize("krom aç") == .openApp("Google Chrome"))
        #expect(parser.recognize("Notları aç") == .openApp("Notlar"))
        #expect(parser.recognize("Spotify'ı kapat") == .quitApp("Spotify"))
        #expect(parser.recognize("tarayıcıyı aç") == .openBrowser)
        #expect(parser.recognize("kapat") == nil)
    }

    @Test func searchesAndOpensSites() {
        #expect(parser.recognize("Google'da kahve makinesi ara") == .search("kahve makinesi", browser: nil))
        #expect(parser.recognize("kahve makinesi arat") == .search("kahve makinesi", browser: nil))
        #expect(parser.recognize("Dia'da Bayern Köln maçı ara") == .search("bayern köln maçı", browser: "Dia"))
        #expect(parser.recognize("youtube.com'a git") == .openSite(URL(string: "https://youtube.com")!, browser: nil))
        #expect(parser.recognize("ekşi sözlük nokta com aç") == .openSite(URL(string: "https://eksisozluk.com")!, browser: nil))
        #expect(parser.recognize("eksisozluk nokta com aç") == .openSite(URL(string: "https://eksisozluk.com")!, browser: nil))
        // "Emir'i ara" is a phone call, not a search.
        #expect(parser.recognize("Emir'i ara") == nil)
    }

    @Test func playsMusic() {
        #expect(parser.recognize("Spotify'da Tarkan çal") == .play("tarkan"))
        #expect(parser.recognize("Kuzu Kuzu'yu çal") == .play("kuzu kuzu"))
        #expect(parser.recognize("müzik çal") == .media(.play))
        #expect(parser.recognize("şarkıyı durdur") == .media(.pause))
        #expect(parser.recognize("sonraki şarkı") == .media(.next))
        #expect(parser.recognize("devam et", app: "Spotify") == .media(.play))
        // Otherwise "go on" is for Claude (after the user typed a password).
        #expect(parser.recognize("devam et") == nil)
        #expect(parser.recognize("müziğe devam et") == .media(.play))
    }

    @Test func clausesCarryTheAppForward() {
        let clauses = parser.parse("Dia'yı aç, sonra Bayern Köln maçı arat ve ilk sonuca tıkla")
        #expect(clauses == [
            .local(.openApp("Dia")),
            .local(.search("bayern köln maçı", browser: "Dia")),
            .other("ilk sonuca tıkla"),
        ])
        #expect(LocalCommandParser.clauses(in: "Tom ve Jerry'yi aç") == ["Tom ve Jerry'yi aç"])
        #expect(parser.parse("Spotify'ı aç, Tarkan'ı aç") == [.local(.openApp("Spotify")), .local(.play("tarkan"))])
        #expect(parser.parse("Dia'yı aç sonra Bayern maçı ara") == [
            .local(.openApp("Dia")), .local(.search("bayern maçı", browser: "Dia")),
        ])
        #expect(parser.parse("yarın hava nasıl") == [.other("yarın hava nasıl")])
    }

    @Test func politeAndJoinedVerbForms() {
        #expect(parser.recognize("Dia'yı açar mısın") == .openApp("Dia"))
        #expect(parser.recognize("Spotify'ı açabilir misin lütfen") == .openApp("Spotify"))
        #expect(parser.recognize("Kuzu Kuzu'yu çalsana") == .play("kuzu kuzu"))
        #expect(parser.recognize("kahve makinesi aratır mısın") == .search("kahve makinesi", browser: nil))
        #expect(parser.recognize("Spotify'ı kapatır mısın") == .quitApp("Spotify"))
        #expect(LocalCommandParser.clauses(in: "Dia'yı açıp maç saatini arat") == ["Dia'yı aç", "maç saatini arat"])
        #expect(LocalCommandParser.clauses(in: "Spotify'ı açtıktan sonra Tarkan çal") == ["Spotify'ı açtıktan", "Tarkan çal"])
        #expect(parser.recognize("Spotify'ı açtıktan") == .openApp("Spotify"))
    }

    @Test func youTube() {
        #expect(parser.recognize("YouTube'dan cyberrulz'u aç") == .youtube(.open("cyberrulz")))
        #expect(parser.recognize("youtube'u aç") == .openSite(YouTubePage.home, browser: nil))
        #expect(parser.recognize("YouTube'da kedi videoları arat") == .youtube(.search("kedi videoları")))
        #expect(parser.recognize("Tarkan'ın en son videosunu aç") == .youtube(.latestVideo("tarkan")))
        #expect(parser.recognize("son videoyu aç", app: "YouTube") == .youtube(.latestVideo(nil)))
        #expect(parser.recognize("Kuzu Kuzu'yu aç", app: "YouTube") == .youtube(.open("kuzu kuzu")))
        #expect(parser.recognize("Emir'i ara", app: "YouTube") == nil)
        #expect(parser.recognize("Dia'yı aç", app: "YouTube") == .openApp("Dia"))
        // The sentence that started it: one step, the channel's newest video.
        #expect(parser.parse("youtube'dan cyberrulz'u açıp en son videosunu açar mısın")
            == [.local(.youtube(.latestVideo("cyberrulz")))])
        #expect(parser.parse("YouTube'u aç, sonra cyberrulz'u aç")
            == [.local(.openSite(YouTubePage.home, browser: nil)), .local(.youtube(.open("cyberrulz")))])
    }

    @Test func finishedClausesOfASentenceStillSpoken() {
        #expect(LocalCommandParser.finishedClauses(inPartial: "Spotify'ı aç, sonra Tar") == ["Spotify'ı aç"])
        #expect(LocalCommandParser.finishedClauses(inPartial: "Spotify'ı aç") == [])
        #expect(LocalCommandParser.finishedClauses(inPartial: "Dia'yı aç, kahve arat, sonra il") == ["Dia'yı aç", "kahve arat"])
    }
}
