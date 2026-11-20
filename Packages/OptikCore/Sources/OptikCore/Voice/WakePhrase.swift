import Foundation

/// Whether a transcript starts with Optik's name, the way speech recognition
/// writes it down ("Optik", "Optik?", "Optic", "Obtik", "Uptake").
public enum WakePhrase {
    private static let spellings = ["optik", "optic", "obtik", "optık", "optiğ", "abtik", "aptik", "uptik", "uptake", "optek"]

    public static func startsWithName(_ transcript: String) -> Bool {
        nameLength(in: transcript) != nil
    }

    /// What was said after the name, or nil when the transcript does not start
    /// with it. "Optik, bugün hava nasıl?" → "bugün hava nasıl?"; "Optik?" → "".
    public static func remainder(_ transcript: String) -> String? {
        guard let words = nameLength(in: transcript) else { return nil }
        let tokens = transcript.split(whereSeparator: \.isWhitespace)
        let rest = tokens.dropFirst(words).joined(separator: " ")
        return rest.trimmingCharacters(in: CharacterSet.letters.union(.decimalDigits).inverted.subtracting(.punctuationCharacters).union(.whitespaces))
            .drop { !$0.isLetter && !$0.isNumber }
            .description
    }

    /// How many words the name takes (1, or 2 when split as "Op tik").
    private static func nameLength(in transcript: String) -> Int? {
        let words = transcript
            .split(whereSeparator: \.isWhitespace)
            .map { $0.lowercased(with: Locale(identifier: "tr_TR")).filter(\.isLetter) }
        guard let first = words.first(where: { !$0.isEmpty }), first == words[0] else { return nil }
        if spellings.contains(where: { first.hasPrefix($0) }) { return 1 }
        // "Op tik": the recognizer sometimes splits the word.
        if first.count <= 3, words.count > 1, spellings.contains(where: { (first + words[1]).hasPrefix($0) }) { return 2 }
        return nil
    }
}
