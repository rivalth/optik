import OptikCore
import SwiftUI

/// Fonts bundled under `Resources/Fonts` and registered through `ATSApplicationFontsPath`.
/// Both are variable fonts; the weight picks the instance.
enum OptikFont {
    /// Headings and numbers: Space Grotesk 700.
    static func heading(size: Double) -> Font {
        .custom(DesignTokens.Typography.headingFamily, fixedSize: size).weight(.bold)
    }

    /// Body text: Inter 400 / 500 / 600.
    static func body(size: Double, weight: Font.Weight = .regular) -> Font {
        .custom(DesignTokens.Typography.bodyFamily, fixedSize: size).weight(weight)
    }
}
