import Foundation

/// Text rules for what Optik says aloud (`llm/ses-kimligi.md`, "Okuma kuralları").
public enum SpeechText {
    /// Rewrites money, percentages, clock times and grouped numbers as words, so the
    /// voice reads them the Turkish way: "₺18.000" → "on sekiz bin lira",
    /// "13.00" → "on üç", "%80" → "yüzde seksen", "3'te" → "üçte". Small plain
    /// numbers ("3 gün") stay as they are.
    public static func normalized(_ text: String) -> String {
        var result = text
        // ₺18.000 / ₺18.000,50
        result = replace(#"₺\s?(\d{1,3}(?:\.\d{3})+|\d+)(?:,(\d{1,2}))?"#, in: result) { groups in
            money(groups[1], kurus: groups[2])
        }
        // 18.000 TL / 18.000 lira
        result = replace(#"\b(\d{1,3}(?:\.\d{3})+|\d+)(?:,(\d{1,2}))?\s?(?:TL|lira)\b"#, in: result) { groups in
            money(groups[1], kurus: groups[2])
        }
        // %80
        result = replace(#"%\s?(\d+)"#, in: result) { groups in
            "yüzde " + TurkishNumbers.words(Int(groups[1]) ?? 0)
        }
        // 13.00, 9:30 (never 18.000: exactly two digits after the separator).
        result = replace(#"\b([01]?\d|2[0-3])[.:]([0-5]\d)(?!\d|[.,]\d)(?:['’]([a-zçğıöşü]+))?"#, in: result) { groups in
            clock(hour: Int(groups[1]) ?? 0, minute: Int(groups[2]) ?? 0) + groups[3]
        }
        // 18.000 alone.
        result = replace(#"\b(\d{1,3}(?:\.\d{3})+)\b(?![,]\d)"#, in: result) { groups in
            TurkishNumbers.words(Int(groups[1].replacingOccurrences(of: ".", with: "")) ?? 0)
        }
        // 3'te, 1'de: the suffix joins the word.
        result = replace(#"\b(\d+)['’]([a-zçğıöşü]+)"#, in: result) { groups in
            TurkishNumbers.words(Int(groups[1]) ?? 0) + groups[2]
        }
        return result
    }

    /// Replies longer than this are cut to their first two sentences when spoken;
    /// the whole text still shows on the island.
    public static let spokenLengthLimit = 220

    private static func money(_ amount: String, kurus: String) -> String {
        let lira = Int(amount.replacingOccurrences(of: ".", with: "")) ?? 0
        var words = TurkishNumbers.words(lira) + " lira"
        if let cents = Int(kurus.count == 1 ? kurus + "0" : kurus), cents > 0 {
            words += " " + TurkishNumbers.words(cents) + " kuruş"
        }
        return words
    }

    private static func clock(hour: Int, minute: Int) -> String {
        let hourWords = TurkishNumbers.words(hour)
        switch minute {
        case 0: return hourWords
        case 1..<10: return hourWords + " sıfır " + TurkishNumbers.words(minute)
        default: return hourWords + " " + TurkishNumbers.words(minute)
        }
    }

    /// Regex replace with capture groups (missing groups are empty strings).
    private static func replace(_ pattern: String, in text: String, with transform: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let source = text as NSString
        var output = ""
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            output += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let groups = (0..<match.numberOfRanges).map { index -> String in
                let range = match.range(at: index)
                return range.location == NSNotFound ? "" : source.substring(with: range)
            }
            output += transform(groups)
            cursor = match.range.location + match.range.length
        }
        output += source.substring(from: cursor)
        return output
    }
}

/// Splits a streamed reply into sentences, so the first one can be spoken while the
/// rest is still being written (`docs/02-mimari.md` 3.3).
public struct SentenceChunker: Sendable {
    private var buffer = ""

    public init() {}

    /// Adds streamed text and returns the sentences it completed.
    public mutating func append(_ text: String) -> [String] {
        buffer += text
        var sentences: [String] = []
        while let end = Self.sentenceEnd(in: buffer) {
            let sentence = buffer[..<end].trimmingCharacters(in: .whitespacesAndNewlines)
            buffer = String(buffer[end...])
            if !sentence.isEmpty { sentences.append(sentence) }
        }
        return sentences
    }

    /// Whatever is left when the stream ends.
    public mutating func finish() -> String? {
        let rest = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = ""
        return rest.isEmpty ? nil : rest
    }

    /// The index after a sentence's closing punctuation (and any closing quotes),
    /// when whitespace follows it. "13.00" and "18.000" never end a sentence.
    private static func sentenceEnd(in text: String) -> String.Index? {
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if ".!?…".contains(character) {
                var end = text.index(after: index)
                while end < text.endIndex, "\"'”’)".contains(text[end]) { end = text.index(after: end) }
                if end < text.endIndex, text[end].isWhitespace { return end }
            }
            index = text.index(after: index)
        }
        return nil
    }
}

/// Decides which streamed sentences are spoken: always the first two, later ones only
/// while the whole reply stays within `SpeechText.spokenLengthLimit`.
public struct SpokenReplyLimiter: Sendable {
    private var spokenCount = 0
    private var totalLength = 0
    private var stopped = false

    public init() {}

    public mutating func shouldSpeak(_ sentence: String) -> Bool {
        totalLength += sentence.count + (spokenCount > 0 ? 1 : 0)
        guard !stopped else { return false }
        if spokenCount < 2 || totalLength <= SpeechText.spokenLengthLimit {
            spokenCount += 1
            return true
        }
        stopped = true
        return false
    }
}
