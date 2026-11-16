import OptikCore
import SwiftUI

/// UserDefaults keys. Moves to the `settings` table once the database lands (stage 3).
enum SettingsKey {
    static let accentColor = "accentColor"
    static let soundEffectsEnabled = "soundEffectsEnabled"
    /// ⌘ ⌘ summons Optik. On by default; needs Input Monitoring.
    static let summonWithDoubleCommand = "summonWithDoubleCommand"
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
