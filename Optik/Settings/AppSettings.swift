import OptikCore
import SwiftUI

/// UserDefaults keys. Moves to the `settings` table once the database lands (stage 3).
enum SettingsKey {
    static let accentColor = "accentColor"
    static let soundEffectsEnabled = "soundEffectsEnabled"
    /// ⌘ ⌘ summons Optik. On by default; needs Input Monitoring.
    static let summonWithDoubleCommand = "summonWithDoubleCommand"
    /// Saying "Optik" summons Optik. Off by default: the microphone stays on.
    static let summonWithWakeWord = "summonWithWakeWord"
    /// With a voice profile, Optik reacts only to the user's voice. On by default.
    static let onlyMyVoice = "onlyMyVoice"
    /// Optik speaks its replies. Off: replies are only shown, and no speech is
    /// synthesized or requested at all. On by default.
    static let speakReplies = "speakReplies"
    /// The user's name, for the model's turn context.
    static let userName = "userName"
    /// `SpeechModel` raw value.
    static let speechModel = "speechModel"
    /// `SpeechEngine` raw value: what writes down the user's sentence.
    static let speechEngine = "speechEngine"
}

/// The accent colors the user can pick (`vurguSecenekleri`).
enum AccentChoice: String, CaseIterable, Identifiable {
    case orange = "#FF8A3D"
    case blue = "#7C9BFF"
    case pink = "#F25F8B"
    case yellow = "#E9C46A"

    var id: String { rawValue }

    var color: RGBA { RGBA(hexString: rawValue) ?? DesignTokens.Palette.accent }

    var localizedName: String {
        switch self {
        case .orange: String(localized: "Turuncu")
        case .blue: String(localized: "Mavi")
        case .pink: String(localized: "Pembe")
        case .yellow: String(localized: "Sarı")
        }
    }

    static let `default` = AccentChoice.orange
}
