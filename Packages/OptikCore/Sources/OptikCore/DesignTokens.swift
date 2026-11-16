/// Design tokens. The single source of truth is `assets/tasarim-tokenlari.json`;
/// `DesignTokensTests` fails if these values drift from it.
public enum DesignTokens {

    // MARK: - Colors

    public enum Palette {
        /// zemin: window background
        public static let background = RGBA(hex: 0x12131C)
        /// yuzey: cards, bottom bar, speech bubble
        public static let surface = RGBA(hex: 0x1C1E2B)
        /// yuzey2: secondary button, empty progress track
        public static let surfaceSecondary = RGBA(hex: 0x262939)
        /// metin: primary text
        public static let text = RGBA(hex: 0xF2F0E9)
        /// metinSoluk: secondary text
        public static let textMuted = RGBA(hex: 0xA3A6B8)
        /// cizgi: dashed border, tag outline
        public static let line = RGBA(hex: 0x5B5F78)
        /// cizgiGuclu: checkbox outline
        public static let lineStrong = RGBA(hex: 0x7A7F9C)
        /// vurgu: default accent (primary button, selected day, legs and beak)
        public static let accent = RGBA(hex: 0xFF8A3D)
        /// vurguSecenekleri: accent colors the user can pick
        public static let accentOptions: [RGBA] = [
            RGBA(hex: 0xFF8A3D), RGBA(hex: 0x7C9BFF), RGBA(hex: 0xF25F8B), RGBA(hex: 0xE9C46A),
        ]
        /// vurguUstuMetin: text on accent and mint
        public static let onAccent = RGBA(hex: 0x12131C)
        /// nane: done, progress, selected tab, microphone dot
        public static let mint = RGBA(hex: 0x5EE0C8)
        /// uyari: warning mark. Always this value, independent of the accent setting.
        public static let warning = RGBA(hex: 0xFF8A3D)
        /// adacik: notch island
        public static let island = RGBA(hex: 0x000000)
        /// naneIz: mint progress track
        public static let mintTrack = RGBA(hex: 0x5EE0C8, alpha: 0.18)
        /// uyariIz: warning progress track
        public static let warningTrack = RGBA(hex: 0xFF8A3D, alpha: 0.22)
    }

    /// Character colors. Legs and beak use the accent color.
    public enum CharacterPalette {
        public static let shell = RGBA(hex: 0xF4EDE0)
        public static let shellShade = RGBA(hex: 0x000000, alpha: 0.07)
        public static let speck = RGBA(hex: 0xDDD0BA)
        public static let crack = RGBA(hex: 0xCFC2AC)
        public static let innerWall = RGBA(hex: 0xA3957F)
        public static let hole = RGBA(hex: 0x2A2521)
        public static let eye = RGBA(hex: 0xFFF4D6)
    }

    public enum CoopPalette {
        public static let frame = RGBA(hex: 0x5A3A1E)
        public static let inside = RGBA(hex: 0x1E140B)
        public static let door = RGBA(hex: 0xB07A42)
        public static let straw = RGBA(hex: 0xE9C46A)
    }

    // MARK: - Typography

    public enum Typography {
        public static let headingFamily = "Space Grotesk"
        public static let headingWeight = 700
        public static let bodyFamily = "Inter"
        public static let bodyWeights = [400, 500, 600]

        public static let screenTitleSize = 26.0
        public static let sectionTitleSize = 18.0
        public static let cardTitleSize = 16.0
        public static let bodySize = 15.0
        public static let secondarySize = 13.0
        public static let labelSize = 11.0
    }

    // MARK: - Shape and spacing

    public enum Radius {
        public static let card = 18.0
        public static let button = 22.0
        public static let speechBubble = 20.0
        public static let bottomBar = 24.0
        public static let progressBar = 4.0
    }

    public enum Spacing {
        public static let screenEdge = 20.0
        public static let cardInner = 16.0
        public static let betweenCards = 10.0
        public static let betweenSections = 20.0
    }

    public static let minimumTapTarget = 44.0

    // MARK: - Notch island

    public enum Island {
        public struct Size: Hashable, Sendable {
            public let width: Double
            public let height: Double
            public let bottomCornerRadius: Double
        }

        /// bekliyor
        public static let idle = Size(width: 312, height: 38, bottomCornerRadius: 18)
        /// efendim, dinliyor, haber veriyor
        public static let open = Size(width: 460, height: 150, bottomCornerRadius: 40)
        /// yanitliyor
        public static let reply = Size(width: 480, height: 214, bottomCornerRadius: 40)

        public static let transitionMilliseconds = 450
        public static let transitionCurve = CubicBezier(0.3, 1.25, 0.5, 1)
    }

    // MARK: - Motion

    public enum Motion {
        /// Eye and beak shape changes.
        public static let shapeTransitionMilliseconds = 280
        public static let overshootCurve = CubicBezier(0.3, 1.5, 0.5, 1)
        public static let tapBounceMilliseconds = 550
        /// `kutlama` and the tap reaction return to the screen's own mood after this window.
        public static let transientMoodMilliseconds = 2000...2800
    }
}
