import AppKit
import OptikCore
import SwiftUI

extension Color {
    /// A SwiftUI color from a design token.
    init(_ token: RGBA) {
        self.init(
            .sRGB,
            red: Double(token.red) / 255,
            green: Double(token.green) / 255,
            blue: Double(token.blue) / 255,
            opacity: token.alpha
        )
    }
}

extension NSColor {
    /// An AppKit color from a design token, for Core Animation layers.
    convenience init(_ token: RGBA) {
        self.init(
            srgbRed: CGFloat(token.red) / 255,
            green: CGFloat(token.green) / 255,
            blue: CGFloat(token.blue) / 255,
            alpha: CGFloat(token.alpha)
        )
    }
}
