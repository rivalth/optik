import Foundation

/// Optik's pre-recorded sentences (`llm/sabit-cumleler.json`, `assets/sesler/konusma/`).
/// A custom voice's copies in Application Support win over the bundled Jessica ones.
enum FixedPhrases {
    struct Phrase: Decodable, Sendable {
        let id: String
        let metin: String
    }

    private struct File: Decodable {
        let cumleler: [Phrase]
    }

    static let all: [Phrase] = {
        guard let url = Bundle.main.url(forResource: "sabit-cumleler", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data)
        else { return [] }
        return file.cumleler
    }()

    static var customFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Optik/konusma", directoryHint: .isDirectory)
    }

    static func url(for id: String) -> URL? {
        let custom = customFolder.appending(path: "\(id).wav")
        if FileManager.default.fileExists(atPath: custom.path) { return custom }
        return Bundle.main.url(forResource: id, withExtension: "wav")
    }

    static func text(for id: String) -> String? {
        all.first { $0.id == id }?.metin
    }

    /// One of the variants of a meaning ("efendim" → efendim-1...3), picked at random.
    static func variant(_ prefix: String) -> Phrase? {
        all.filter { $0.id.hasPrefix(prefix + "-") && url(for: $0.id) != nil }.randomElement()
    }
}
