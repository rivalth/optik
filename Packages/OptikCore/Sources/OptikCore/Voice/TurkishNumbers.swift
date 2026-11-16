/// Turkish number words, for text that is read aloud ("18.000" → "on sekiz bin").
public enum TurkishNumbers {
    private static let ones = ["", "bir", "iki", "üç", "dört", "beş", "altı", "yedi", "sekiz", "dokuz"]
    private static let tens = ["", "on", "yirmi", "otuz", "kırk", "elli", "altmış", "yetmiş", "seksen", "doksan"]
    private static let scales: [(value: Int, word: String)] = [
        (1_000_000_000_000, "trilyon"), (1_000_000_000, "milyar"), (1_000_000, "milyon"), (1_000, "bin"),
    ]

    /// `0` → "sıfır", `1000` → "bin" (never "bir bin"), `-5` → "eksi beş".
    public static func words(_ number: Int) -> String {
        if number == 0 { return "sıfır" }
        if number < 0 { return "eksi " + words(number == .min ? .max : -number) }
        var parts: [String] = []
        var rest = number
        for scale in scales where rest >= scale.value {
            let count = rest / scale.value
            rest %= scale.value
            // "bin", "iki bin"; but "bir milyon".
            if scale.value == 1_000 && count == 1 {
                parts.append(scale.word)
            } else {
                parts.append((count >= 1_000 ? words(count) : belowThousand(count)) + " " + scale.word)
            }
        }
        if rest > 0 { parts.append(belowThousand(rest)) }
        return parts.joined(separator: " ")
    }

    private static func belowThousand(_ number: Int) -> String {
        var parts: [String] = []
        let hundreds = number / 100
        if hundreds > 0 { parts.append(hundreds == 1 ? "yüz" : ones[hundreds] + " yüz") }
        let rest = number % 100
        if rest / 10 > 0 { parts.append(tens[rest / 10]) }
        if rest % 10 > 0 { parts.append(ones[rest % 10]) }
        return parts.joined(separator: " ")
    }
}
