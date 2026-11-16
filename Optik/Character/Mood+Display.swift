import OptikCore
import SwiftUI

extension Mood {
    /// Name shown in the UI. Matches the labels of `assets/animasyon/optik-demo.html`.
    var localizedName: String {
        switch self {
        case .waiting: String(localized: "Bekliyor")
        case .happy: String(localized: "Mutlu")
        case .listening: String(localized: "Dinliyor")
        case .thoughtful: String(localized: "Düşünceli")
        case .alert: String(localized: "Hatırlatma")
        case .celebrating: String(localized: "Kutlama")
        case .sleepy: String(localized: "Uykulu")
        }
    }
}
