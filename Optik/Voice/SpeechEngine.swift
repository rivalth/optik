import Foundation

/// Which engine turns the user's sentence into text (`docs/02-mimari.md` 3.2). The
/// wake word is always heard by Whisper on this Mac, whatever is chosen here.
enum SpeechEngine: String, CaseIterable, Identifiable, Sendable {
    /// WhisperKit, on this Mac.
    case whisper
    /// Apple's dictation model (macOS 26), on this Mac.
    case dictation
    /// ElevenLabs Scribe, in the cloud: the sentence's audio leaves the Mac. Off
    /// unless the user picks it.
    case scribe

    var id: String { rawValue }

    static let `default` = SpeechEngine.whisper

    static var selected: SpeechEngine {
        let chosen = UserDefaults.standard.string(forKey: SettingsKey.speechEngine).flatMap(SpeechEngine.init) ?? .default
        return chosen.isAvailable ? chosen : .default
    }

    var isAvailable: Bool {
        switch self {
        case .whisper, .scribe: true
        case .dictation: if #available(macOS 26, *) { true } else { false }
        }
    }

    /// Whether the sentence's audio leaves the Mac.
    var isCloud: Bool { self == .scribe }

    var localizedName: String {
        switch self {
        case .whisper: String(localized: "Whisper (bu Mac'te)")
        case .dictation: String(localized: "Apple dikte (bu Mac'te)")
        case .scribe: String(localized: "ElevenLabs Scribe (bulutta)")
        }
    }
}
