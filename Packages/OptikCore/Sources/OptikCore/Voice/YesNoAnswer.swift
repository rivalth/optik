import Foundation

/// A short yes or no to a question Optik asked ("Sayfayı tarayıcında açayım mı?"),
/// understood on the spot without asking the LLM. Only the whole answer counts:
/// "evet ama önce saati söyle" goes to the LLM.
public enum YesNoAnswer: Equatable, Sendable {
    case yes
    case no

    private static let yesPhrases: Set<String> = [
        "evet", "evet aç", "aç", "açabilirsin", "aç bakalım", "aç lütfen", "lütfen aç", "olur", "tamam",
        "tamam aç", "he", "hı hı", "ıhı", "evet lütfen", "isterim", "açar mısın", "göster", "olur aç",
    ]
    private static let noPhrases: Set<String> = [
        "hayır", "yok", "gerek yok", "istemiyorum", "açma", "boş ver", "boşver", "hayır gerek yok",
        "yok gerek yok", "şimdi değil", "sonra", "vazgeç", "yok sağ ol", "hayır teşekkürler",
    ]

    public init?(_ transcript: String) {
        let words = transcript
            .lowercased(with: Locale(identifier: "tr_TR"))
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty }
        let withoutName = words.first == "optik" ? Array(words.dropFirst()) : words
        let phrase = withoutName.joined(separator: " ")
        if Self.yesPhrases.contains(phrase) {
            self = .yes
        } else if Self.noPhrases.contains(phrase) {
            self = .no
        } else {
            return nil
        }
    }
}
