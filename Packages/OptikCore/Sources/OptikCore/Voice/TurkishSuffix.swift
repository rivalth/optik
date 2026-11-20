import Foundation

/// Turkish case endings for names Optik says, such as the browser's.
public enum TurkishSuffix {
    /// Names whose spelling hides how they are said ("Chrome" is "krom").
    private static let spoken: [String: String] = [
        "chrome": "krom", "google chrome": "krom", "arc": "ark", "edge": "ec", "brave": "breyv",
        "opera": "opera", "firefox": "fayırfoks", "safari": "safari", "dia": "dia",
    ]

    /// "Dia’da", "Safari’de", "Chrome’da", "Arc’ta": the locative, after an apostrophe.
    public static func locative(_ name: String) -> String {
        let lowered = name.lowercased(with: Locale(identifier: "tr_TR"))
        let said = spoken[lowered] ?? lowered
        let backVowels: Set<Character> = ["a", "ı", "o", "u"]
        let frontVowels: Set<Character> = ["e", "i", "ö", "ü"]
        let lastVowel = said.last { backVowels.contains($0) || frontVowels.contains($0) }
        let vowel = lastVowel.map { frontVowels.contains($0) } == true ? "e" : "a"
        let hard: Set<Character> = ["f", "s", "t", "k", "ç", "ş", "h", "p", "x"]
        let consonant = said.last.map { hard.contains($0) } == true ? "t" : "d"
        return "\(name)’\(consonant)\(vowel)"
    }
}
