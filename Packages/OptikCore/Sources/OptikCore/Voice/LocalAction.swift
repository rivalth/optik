import Foundation

/// Something Optik does on this Mac on the spot, without asking Claude: open an app,
/// search the web, play a song. "Dia'yı aç, sonra kahve makinesi arat" is two of them.
public enum LocalAction: Equatable, Sendable {
    /// Open (or bring forward) an installed app, by its name as listed.
    case openApp(String)
    case quitApp(String)
    /// The default browser, or the browser named.
    case openBrowser
    /// A web search in a browser (`browser` nil: the last one or the default).
    case search(String, browser: String?)
    case openSite(URL, browser: String?)
    /// Find a song, artist or album in Spotify and play the first result.
    case play(String)
    case media(MediaControl)
    case youtube(YouTubeTarget)
}

public enum MediaControl: String, Equatable, Sendable {
    case play, pause, next, previous
}

/// One part of what the user said: something Optik can do itself, or something
/// for Claude.
public enum CommandClause: Equatable, Sendable {
    case local(LocalAction)
    case other(String)
}

/// Splits a sentence into clauses and recognizes the ones Optik can do itself.
/// Pure and fast (no model), so it runs on every partial transcript while the
/// user is still talking.
public struct LocalCommandParser: Sendable {
    /// Installed apps by the names they are called (lowercased): "spotify" → "Spotify".
    private let apps: [(spoken: String, name: String)]
    private let browsers: Set<String>

    public static let spotify = "Spotify"
    /// Not an app but a site, used as the context the next clause is about.
    public static let youtube = "YouTube"

    /// - Parameters:
    ///   - appNames: installed apps' names as the system shows them ("Dia", "Notlar").
    ///   - browserNames: those of them that are web browsers.
    public init(appNames: [String], browserNames: [String] = []) {
        var apps: [(String, String)] = []
        for name in appNames {
            apps.append((Self.normalize(name), name))
            for alias in Self.aliases[name.lowercased()] ?? [] { apps.append((alias, name)) }
        }
        // Longest first, so "google chrome" wins over a shorter name inside it.
        self.apps = apps.sorted { $0.0.count > $1.0.count }
        browsers = Set(browserNames)
    }

    /// How speech recognition tends to write some app names.
    private static let aliases: [String: [String]] = [
        "spotify": ["spotifay", "spotfy", "spotifiy"],
        "dia": ["diya"],
        "google chrome": ["chrome", "krom"],
        "safari": ["safari"],
        "code": ["vs code", "visual studio code"],
        "whatsapp": ["vatsap", "whatsap"],
    ]

    // MARK: Clauses

    /// "Dia'yı aç, sonra kahve arat ve ilk sonuca tıkla" → three clauses.
    /// "YouTube'dan kanalı açıp son videoyu aç" → two: a verb ending in -ıp joins
    /// the next one.
    public static func clauses(in text: String) -> [String] {
        var parts = [text]
        for separator in [",", ";", ". ", " sonra ", " ardından ", " daha sonra ", " ve sonra ", " sonrasında "] {
            parts = parts.flatMap { $0.components(separatedBy: separator) }
        }
        // "kahve arat ve ilk sonuca tıkla": "ve" joins two commands only after a verb,
        // so "Tom ve Jerry'yi aç" stays one.
        parts = parts.flatMap(splitAfterVerbs)
        return parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) }
            .filter { !$0.isEmpty && !["ve", "sonra", "ardından"].contains($0.lowercased()) }
    }

    static let verbs: Set<String> = ["aç", "başlat", "çalıştır", "kapat", "çal", "oynat", "dinlet", "arat", "ara", "git", "gir", "durdur", "geç"]

    private static func splitAfterVerbs(_ part: String) -> [String] {
        // "açıp", "arayıp": the clause ends there, as the plain verb.
        var pieces: [[String]] = [[]]
        for word in part.split(separator: " ").map(String.init) {
            if let base = converbs[normalize(word)] {
                pieces[pieces.count - 1].append(base)
                pieces.append([])
            } else {
                pieces[pieces.count - 1].append(word)
            }
        }
        var result: [String] = []
        for piece in pieces.map({ $0.joined(separator: " ") }) where !piece.isEmpty {
            var current = piece
            while let range = current.range(of: " ve ") {
                let left = String(current[..<range.lowerBound])
                let lastWord = left.split(separator: " ").last.map { normalize(String($0)) } ?? ""
                guard verbs.contains(lastWord) || verbForms[lastWord] != nil else { break }
                result.append(left)
                current = String(current[range.upperBound...])
            }
            result.append(current)
        }
        return result
    }

    // MARK: Verb forms

    /// How a request ends besides the plain verb: "aç", "açar mısın", "açsana",
    /// "açabilir misin lütfen". Words dropped from the end before reading the verb.
    private static let politeWords: Set<String> = [
        "lütfen", "mısın", "misin", "musun", "müsün", "mı", "mi", "mu", "mü", "bakalım", "hemen", "şimdi", "bana",
    ]

    /// Inflected forms of the verbs to the plain verb: "açar" → "aç".
    static let verbForms: [String: String] = {
        var forms: [String: String] = [:]
        for verb in verbs.union(["izle", "göster", "bul"]) {
            for form in inflections(of: verb) { forms[form] = verb }
        }
        return forms
    }()

    /// The -ıp forms alone ("açıp" → "aç"), which end a clause.
    static let converbs: [String: String] = {
        var forms: [String: String] = [:]
        for verb in verbs.union(["izle", "göster", "bul"]) { forms[converb(of: verb)] = verb }
        return forms
    }()

    private static func inflections(of verb: String) -> [String] {
        let vowels = verb.filter { "aeıioöuü".contains($0) }
        guard let last = vowels.last else { return [] }
        let back = "aıou".contains(last)
        let a = back ? "a" : "e"
        let i = switch last {
        case "a", "ı": "ı"
        case "e", "i": "i"
        case "o", "u": "u"
        default: "ü"
        }
        let endsInVowel = "aeıioöuü".contains(verb.last!)
        // "git" softens before a vowel: gider, gidebilir.
        let stem = verb == "git" ? "gid" : verb
        let joiner = endsInVowel ? "y" : ""
        let aorist = endsInVowel ? verb + "r" : (vowels.count == 1 && verb != "bul" ? stem + a + "r" : stem + i + "r")
        let past = "çfhkpsşt".contains(verb.last!) ? "t" : "d"
        return [
            aorist,
            verb + "s" + a + "n" + a,                         // açsana
            stem + joiner + a + "bilir",                      // açabilir
            stem + joiner + i + "ver",                        // açıver
            verb + past + i + "k" + "t" + a + "n",            // açtıktan
            stem + joiner + i + "n",                          // açın
            converb(of: verb),
        ]
    }

    private static func converb(of verb: String) -> String {
        let last = verb.last { "aeıioöuü".contains($0) } ?? "a"
        let i = switch last {
        case "a", "ı": "ı"
        case "e", "i": "i"
        case "o", "u": "u"
        default: "ü"
        }
        let stem = verb == "git" ? "gid" : verb
        return "aeıioöuü".contains(verb.last!) ? stem + "y" + i + "p" : stem + i + "p"
    }

    /// The clauses already finished in a sentence still being spoken: everything
    /// before the last separator. "Spotify'ı aç, sonra Tar" → ["Spotify'ı aç"].
    public static func finishedClauses(inPartial text: String) -> [String] {
        let separators = [",", ";", ". ", " sonra ", " ardından "]
        var cut: String.Index?
        for separator in separators {
            if let range = text.range(of: separator, options: .backwards), range.upperBound > (cut ?? text.startIndex) {
                cut = range.lowerBound
            }
        }
        guard let cut else { return [] }
        return clauses(in: String(text[..<cut]))
    }

    /// Every clause, recognized in order. A clause sets the app the next ones are
    /// about: after "Spotify'ı aç", "Tarkan'ı aç" plays a song.
    public func parse(_ text: String, context: String? = nil) -> [CommandClause] {
        var app = context
        var result: [CommandClause] = []
        for clause in Self.clauses(in: text) {
            guard var action = recognize(clause, app: app) else {
                result.append(.other(clause))
                continue
            }
            switch action {
            case .openApp(let name), .quitApp(let name): app = name
            case .play, .media: app = Self.spotify
            case .openSite(let url, _) where url.host()?.hasSuffix("youtube.com") == true: app = Self.youtube
            case .search(_, let browser), .openSite(_, let browser): app = browser ?? app
            case .openBrowser: break
            case .youtube(let target):
                app = Self.youtube
                // "kanalı açıp son videosunu aç": one step, the newest video.
                if case .latestVideo(nil) = target, case .local(.youtube(.open(let channel))) = result.last {
                    result.removeLast()
                    action = .youtube(.latestVideo(channel))
                }
            }
            result.append(.local(action))
        }
        return result
    }

    // MARK: One clause

    public func recognize(_ clause: String, app: String? = nil) -> LocalAction? {
        var words = Self.normalize(clause, keepingApostrophes: true).split(separator: " ").map(String.init)
        while words.count > 1, let last = words.last, Self.politeWords.contains(last) { words.removeLast() }
        guard let spoken = words.last else { return nil }
        let verb = Self.verbForms[spoken] ?? spoken
        let text = (words.dropLast() + [verb]).joined(separator: " ")
        let objectWords = Array(words.dropLast())
        let object = objectWords.joined(separator: " ")

        if let control = Self.mediaControl(text) {
            // A bare "devam et" is about music only in Spotify; otherwise it is
            // "go on" for Claude (after typing a password, say).
            let bare = ["devam et", "devam ettir"].contains(text.replacingOccurrences(of: "'", with: ""))
            if !bare || app == Self.spotify { return .media(control) }
            return nil
        }
        if let target = youtube(objectWords, verb: verb, app: app) {
            if target == .open("") { return .openSite(YouTubePage.home, browser: browserIn(app)) }
            return .youtube(target)
        }

        switch verb {
        case "aç", "başlat", "çalıştır":
            guard !object.isEmpty else { return nil }
            if Self.browserWords.contains(Self.stripSuffix(object)) { return .openBrowser }
            if let site = Self.site(object) { return .openSite(site, browser: browserIn(app)) }
            if let name = appName(object) { return .openApp(name) }
            // "Spotify'ı aç, Tarkan'ı aç": with Spotify in front, the rest is music.
            if app == Self.spotify { return .play(Self.stripSuffix(object)) }
            return nil
        case "kapat":
            guard !object.isEmpty, let name = appName(object) else { return nil }
            return .quitApp(name)
        case "çal", "oynat", "dinlet":
            // "Spotify'da Tarkan çal": the place first, then the song.
            var song = objectWords
            if let first = song.first, appName(first) == Self.spotify { song.removeFirst() }
            let query = Self.stripSuffix(song.joined(separator: " "))
            if query.isEmpty || Self.musicWords.contains(query) { return .media(.play) }
            return .play(query)
        case "arat", "ara":
            // "ara" also means "call": only a search when a browser or a search
            // engine is named, or a browser is what the user is in.
            var rest = objectWords
            var browser = browserIn(app)
            var named = false
            if let first = rest.first {
                let place = Self.stripSuffix(first)
                if ["google", "internet", "internette", "webde"].contains(place) || ["googleda", "internette"].contains(first) {
                    rest.removeFirst()
                    named = true
                } else if let name = appName(first), browsers.contains(name) {
                    rest.removeFirst()
                    browser = name
                    named = true
                }
            }
            guard verb != "ara" || named || browser != nil else { return nil }
            let query = Self.stripSuffix(rest.joined(separator: " "))
            guard !query.isEmpty else { return nil }
            return .search(query, browser: browser)
        case "git", "gir":
            guard let site = Self.site(object) else { return nil }
            return .openSite(site, browser: browserIn(app))
        default:
            return nil
        }
    }

    /// "YouTube'dan cyberrulz'u aç", "YouTube'u aç", "Tarkan'ın en son videosunu
    /// aç", and after YouTube: "son videosunu aç", "Kuzu Kuzu'yu aç".
    private func youtube(_ objectWords: [String], verb: String, app: String?) -> YouTubeTarget? {
        let opens: Set<String> = ["aç", "çal", "oynat", "izle", "göster", "bul", "başlat"]
        let searches: Set<String> = ["arat", "ara"]
        guard opens.contains(verb) || searches.contains(verb) else { return nil }
        var rest = objectWords
        var named = false
        if let first = rest.first, Self.isYouTube(first) {
            rest.removeFirst()
            named = true
        }
        // "en son videosunu", "son yüklediği videoyu", "en yeni videosu".
        let latestWords: Set<String> = ["en", "son", "yeni", "sonuncu", "yüklediği", "attığı", "paylaştığı"]
        if opens.contains(verb), let video = rest.lastIndex(where: { $0.hasPrefix("video") }),
           rest[..<video].contains(where: { ["son", "yeni", "sonuncu"].contains($0) }) {
            let channel = Self.stripSuffix(rest[..<video].filter { !latestWords.contains($0) }.joined(separator: " "))
            return .latestVideo(channel.isEmpty ? nil : channel)
        }
        // "Emir'i ara" is a phone call unless YouTube is named.
        guard named || (app == Self.youtube && verb != "ara") else { return nil }
        let query = Self.stripSuffix(rest.joined(separator: " "))
        if query.isEmpty { return named ? .open("") : nil }
        // After YouTube, apps and sites still mean themselves.
        if !named, appName(query) != nil || Self.site(query) != nil { return nil }
        return searches.contains(verb) ? .search(query) : .open(query)
    }

    /// "youtube", "youtube'dan", "youtubeda", "yutup".
    private static func isYouTube(_ word: String) -> Bool {
        let plain = word.replacingOccurrences(of: "'", with: "")
        for name in ["youtube", "yutup", "yutub", "youtub"] where plain.hasPrefix(name) {
            let ending = String(plain.dropFirst(name.count))
            if endings.contains(ending) || ["dan", "den", "tan", "ten", "ndan", "nden"].contains(ending) { return true }
        }
        return false
    }

    private func browserIn(_ app: String?) -> String? {
        app.flatMap { browsers.contains($0) ? $0 : nil }
    }

    /// The installed app a phrase names, with Turkish endings: "dia'yı", "spotifyı",
    /// "notları", "google chrome'u".
    public func appName(_ phrase: String) -> String? {
        let base = Self.stripSuffix(phrase)
        let joined = phrase.replacingOccurrences(of: "'", with: "")
        for app in apps {
            if base == app.spoken { return app.name }
            if joined.hasPrefix(app.spoken), Self.endings.contains(String(joined.dropFirst(app.spoken.count))) {
                return app.name
            }
        }
        return nil
    }

    // MARK: Words

    private static let browserWords: Set<String> = ["tarayıcı", "tarayıcıyı", "tarayıcımı", "browser", "browserı", "interneti", "web tarayıcısını"]
    private static let musicWords: Set<String> = ["müzik", "müziği", "şarkı", "şarkıyı", "bir şarkı", "bir şey"]

    /// Case endings an app or song name can carry: accusative, dative, locative.
    private static let endings: Set<String> = [
        "", "ı", "i", "u", "ü", "yı", "yi", "yu", "yü", "nı", "ni", "nu", "nü",
        "a", "e", "ya", "ye", "na", "ne", "da", "de", "ta", "te", "nda", "nde",
    ]

    private static func mediaControl(_ text: String) -> MediaControl? {
        let plain = text.replacingOccurrences(of: "'", with: "")
        let pause = ["durdur", "duraklat", "müziği durdur", "şarkıyı durdur", "müziği kapat", "şarkıyı kapat", "spotifyı durdur"]
        let play = ["devam et", "müziği aç", "müziği başlat", "devam ettir", "müziğe devam et", "şarkıya devam et"]
        let next = ["sonraki şarkı", "sonraki şarkıya geç", "sıradaki şarkı", "şarkıyı geç", "sonrakine geç", "geç", "bunu geç"]
        let previous = ["önceki şarkı", "önceki şarkıya geç", "önceki şarkıyı aç", "bir önceki şarkı"]
        if pause.contains(plain) { return .pause }
        if play.contains(plain) { return .play }
        if next.contains(plain) { return .next }
        if previous.contains(plain) { return .previous }
        return nil
    }

    /// "youtube.com", "youtube nokta com", "eksisozluk.com'a" → a URL.
    static func site(_ phrase: String) -> URL? {
        var text = stripSuffix(phrase).replacingOccurrences(of: " nokta ", with: ".")
        // Spoken addresses come back with Turkish letters: "ekşi sözlük" → "eksisozluk".
        let ascii: [Character: Character] = ["ş": "s", "ç": "c", "ğ": "g", "ı": "i", "ö": "o", "ü": "u"]
        text = String(text.map { ascii[$0] ?? $0 })
        text = text.replacingOccurrences(of: " ", with: "")
        let tlds = [".com.tr", ".com", ".org", ".net", ".io", ".dev", ".app", ".tr", ".co", ".edu", ".gov"]
        guard tlds.contains(where: { text.hasSuffix($0) }), text.count > 4,
              text.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }) else { return nil }
        return URL(string: "https://\(text)")
    }

    /// Cuts the ending after an apostrophe: "kuzu kuzu'yu" → "kuzu kuzu".
    static func stripSuffix(_ phrase: String) -> String {
        guard let apostrophe = phrase.lastIndex(of: "'") else { return phrase }
        return String(phrase[..<apostrophe]).trimmingCharacters(in: .whitespaces)
    }

    /// Lowercased in Turkish, curly apostrophes made straight, punctuation and
    /// extra spaces removed (dots are kept for web addresses).
    static func normalize(_ text: String, keepingApostrophes: Bool = false) -> String {
        let lowered = text.lowercased(with: Locale(identifier: "tr_TR"))
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
        let kept = lowered.map { character -> Character in
            if character.isLetter || character.isNumber || character == "." || character == "-" { return character }
            if character == "'" { return keepingApostrophes ? "'" : " " }
            return " "
        }
        return String(kept).split(separator: " ").joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
    }
}
