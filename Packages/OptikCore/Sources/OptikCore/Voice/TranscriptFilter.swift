import Foundation

/// Cleans what speech recognition heard before Optik acts on it. Whisper was trained
/// on subtitled video, so on noise or silence it writes what subtitles say rather
/// than what was said: "(Müzik)", "Altyazı M.K.", "İzlediğiniz için teşekkürler".
/// Those must never reach the LLM as if the user had said them.
public enum TranscriptFilter {
    /// One stretch of recognized speech with the model's own confidence. Engines
    /// that give no numbers (Apple dictation) use `init(text:)`.
    public struct Segment: Equatable, Sendable {
        public var text: String
        /// Whisper's estimate that the stretch holds no speech, 0…1.
        public var noSpeechProbability: Double
        /// The mean log probability of the words, ≤ 0. Near 0 is sure.
        public var averageLogProbability: Double
        /// Text length over its zip length. High when a phrase repeats in a loop.
        public var compressionRatio: Double

        public init(text: String, noSpeechProbability: Double = 0, averageLogProbability: Double = 0, compressionRatio: Double = 1) {
            self.text = text
            self.noSpeechProbability = noSpeechProbability
            self.averageLogProbability = averageLogProbability
            self.compressionRatio = compressionRatio
        }

        /// A loop ("evet evet evet…") the model fell into on noise.
        var isRepetitive: Bool { compressionRatio > TranscriptFilter.maxCompressionRatio }

        /// Probably not speech: WhisperKit already drops stretches above 0.6 with a
        /// mean log probability under -1; this also drops the weaker ones in between.
        var isDoubtful: Bool {
            noSpeechProbability > TranscriptFilter.doubtfulNoSpeech
                && averageLogProbability < TranscriptFilter.doubtfulLogProbability
        }

        /// Not sure enough to believe a phrase that is also a common invention.
        var isUnsure: Bool {
            noSpeechProbability > TranscriptFilter.unsureNoSpeech
                || averageLogProbability < TranscriptFilter.unsureLogProbability
        }
    }

    static let maxCompressionRatio = 2.4
    static let doubtfulNoSpeech = 0.4
    static let doubtfulLogProbability = -1.0
    static let unsureNoSpeech = 0.25
    static let unsureLogProbability = -0.7

    /// Subtitle lines Whisper writes on its own. Dropped whenever they are the
    /// whole utterance; nobody asks their assistant these.
    static let inventions: [String] = [
        "altyazı", "altyazı mk", "mk", "altyazılar", "altyazı m k",
        "izlediğiniz için teşekkürler", "izlediğiniz için teşekkür ederim", "izlediğiniz için teşekkür ederiz",
        "abone olmayı unutmayın", "abone ol", "abone olun", "beğenmeyi ve abone olmayı unutmayın",
        "bir sonraki videoda görüşmek üzere", "videoyu beğenmeyi unutmayın",
        "thanks for watching", "thank you for watching", "subtitles by the amaraorg community",
    ]

    /// Things the user may truly say, which Whisper also invents on noise. Kept
    /// only when the model was sure of them.
    static let suspects: [String] = [
        "teşekkürler", "teşekkür ederim", "teşekkür ederiz", "sağ olun", "hoşça kalın", "görüşmek üzere",
        "thank you", "you",
    ]

    /// The text worth acting on: doubtful and looping stretches dropped, sound tags
    /// removed, and an utterance that is only a subtitle invention emptied.
    public static func text(of segments: [Segment]) -> String {
        let kept = segments.filter { !$0.isRepetitive && !$0.isDoubtful }
        let text = clean(kept.map(\.text).joined(separator: " "))
        let key = normalized(text)
        if suspects.contains(key), kept.contains(where: \.isUnsure) { return "" }
        return text
    }

    /// Removes sound tags and subtitle inventions from text with no confidence numbers.
    public static func clean(_ text: String) -> String {
        var result = text
        // "(Müzik)", "[Alkış]", "*gülüşmeler*", "♪ … ♪": the model describing sound.
        for pattern in [#"\([^)]{0,40}\)"#, #"\[[^\]]{0,40}\]"#, #"\*[^*]{0,40}\*"#, #"[♪♫🎵🎶]+"#] {
            result = result.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        result = result.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if inventions.contains(normalized(result)) { return "" }
        // Only punctuation left.
        if !result.contains(where: { $0.isLetter || $0.isNumber }) { return "" }
        return result
    }

    /// Lowercased Turkish, letters, digits and single spaces only: "Altyazı M.K." → "altyazı mk".
    static func normalized(_ text: String) -> String {
        let lower = text.lowercased(with: Locale(identifier: "tr_TR"))
        let kept = lower.map { $0.isLetter || $0.isNumber ? $0 : $0 == "." ? "\u{0}" : " " }
        return String(kept).replacingOccurrences(of: "\u{0}", with: "")
            .split(separator: " ").joined(separator: " ")
    }
}

/// Words the user says that a general speech model does not expect: Optik's name,
/// the user's name, the apps Optik runs and the English words a Turkish developer
/// mixes into a sentence. Given to the engine as a hint, never as text to write.
public enum SpeechHints {
    public static let apps = ["Spotify", "YouTube", "Slack", "WhatsApp", "Safari", "Finder", "Xcode"]
    public static let developerTerms = [
        "pull request", "commit", "merge", "branch", "push", "bug", "deploy", "staging", "production", "log",
        "Docker", "container", "Kubernetes", "pod", "restart", "endpoint", "timeout", "token", "JWT", "API",
        "frontend", "backend", "build", "test", "review", "release",
    ]

    /// Everything, for engines that take a word list (Apple dictation).
    public static func terms(userName: String?) -> [String] {
        var terms = ["Optik"]
        if let name = userName?.trimmingCharacters(in: .whitespaces), !name.isEmpty { terms.append(name) }
        return terms + apps + developerTerms
    }

    /// A short "previous text" for Whisper, which continues in the style of what it
    /// is given. Names only: every prompt token is decoded one at a time before the
    /// speech, and a sentence of developer terms doubled the large model's time on
    /// an M2 (8 s → 16 s) for a few better words.
    public static func whisperPrompt(userName: String?) -> String {
        var names = "Optik"
        if let name = userName?.trimmingCharacters(in: .whitespaces), !name.isEmpty { names += ", \(name)" }
        return names + "."
    }
}
