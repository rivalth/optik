import CoreGraphics

/// Geometry of the character in its 180 × 200 design box, y pointing down.
/// Source: `assets/animasyon/optik.css` and `docs/03-karakter.md` section 1.
/// Frames are relative to the parent layer named in each comment.
///
/// Paths are built once and never mutated (`CGPath`, not `CGMutablePath`), so sharing
/// them across threads is safe; hence `nonisolated(unsafe)`.
enum CharacterGeometry {
    static let designSize = CGSize(width: 180, height: 200)

    // MARK: Root

    /// golge: ellipse under the feet. Parent: root.
    static let shadowFrame = CGRect(x: 45, y: 184, width: 90, height: 12)
    static let shadowOpacity: Float = 0.4

    /// dokun / hareket: everything except the shadow, pivots on the bottom center. Parent: root.
    static let bodyFrame = CGRect(x: 0, y: 0, width: 180, height: 192)

    // MARK: Body (hareket)

    /// salin: shell and inner wall sway together, pivot bottom center. Parent: body.
    static let swayFrame = CGRect(x: 0, y: 0, width: 180, height: 160)

    /// ic-duvar: the inside of the shell seen through the break. Parent: sway.
    /// Same box and outline as the shell, clipped to `ellipse(60px 11px at 60px 131px)`,
    /// so it fills every notch of the zigzag without showing past the egg's sides.
    static let innerWallFrame = shellFrame

    nonisolated(unsafe) static let innerWallPath: CGPath = shellOutline.intersection(
        CGPath(ellipseIn: CGRect(x: 0, y: 120, width: 120, height: 22), transform: nil)
    )

    /// bacak: legs pivot on their top center. Parent: body.
    static let legSize = CGSize(width: 30, height: 46)
    static let leftLegOrigin = CGPoint(x: 58, y: 144)
    static let rightLegOrigin = CGPoint(x: 92, y: 144)
    static let legLineWidth: CGFloat = 5

    /// `M15 2V34 M15 34L4 43 M15 34V44 M15 34L26 43`, in leg coordinates.
    nonisolated(unsafe) static let legPath: CGPath = {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 15, y: 2)); path.addLine(to: CGPoint(x: 15, y: 34))
        path.move(to: CGPoint(x: 15, y: 34)); path.addLine(to: CGPoint(x: 4, y: 43))
        path.move(to: CGPoint(x: 15, y: 34)); path.addLine(to: CGPoint(x: 15, y: 44))
        path.move(to: CGPoint(x: 15, y: 34)); path.addLine(to: CGPoint(x: 26, y: 43))
        return path
    }()

    // MARK: Shell (kabuk), parent: sway

    static let shellFrame = CGRect(x: 30, y: 6, width: 120, height: 156)

    /// `border-radius: 50% 50% 50% 50% / 62% 62% 38% 38%` on a 120 × 156 box:
    /// a half ellipse on top (ry 96.72) and a flatter one below (ry 59.28).
    nonisolated(unsafe) static let shellOutline: CGPath = {
        let width = shellFrame.width
        let height = shellFrame.height
        let rx = width / 2
        let topRY = height * 0.62
        let bottomRY = height - topRY
        let center = CGPoint(x: rx, y: topRY)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: topRY))
        addQuarterEllipse(path, center: center, rx: rx, ry: topRY, from: .pi, to: 1.5 * .pi)
        addQuarterEllipse(path, center: center, rx: rx, ry: topRY, from: 1.5 * .pi, to: 2 * .pi)
        addQuarterEllipse(path, center: center, rx: rx, ry: bottomRY, from: 0, to: 0.5 * .pi)
        addQuarterEllipse(path, center: center, rx: rx, ry: bottomRY, from: 0.5 * .pi, to: .pi)
        path.closeSubpath()
        return path
    }()

    /// The zigzag break at the bottom of the shell, as percentages of the shell box.
    static let shellBreakPercent: [(Double, Double)] = [
        (0, 0), (100, 0), (100, 80), (90, 87), (80, 79), (69, 88), (58, 80),
        (47, 89), (36, 80), (25, 88), (15, 79), (6, 86), (0, 80),
    ]

    nonisolated(unsafe) static let shellBreak: CGPath = polygon(shellBreakPercent, in: shellFrame.size)

    /// The visible shell: outline cut by the zigzag break.
    nonisolated(unsafe) static let shellPath: CGPath = shellOutline.intersection(shellBreak)

    /// `box-shadow: inset -10px -12px 0 rgba(0,0,0,.07)`: the crescent on the lower right.
    nonisolated(unsafe) static let shellShadePath: CGPath = {
        let shifted = shellOutline.copy(using: [CGAffineTransform(translationX: -10, y: -12)])!
        return shellOutline.subtracting(shifted).intersection(shellBreak)
    }()

    /// benek: specks, in shell coordinates.
    static let speckFrames: [CGRect] = [
        CGRect(x: 22, y: 34, width: 7, height: 7),
        CGRect(x: 90, y: 28, width: 5, height: 5),
        CGRect(x: 94, y: 100, width: 6, height: 6),
    ]

    /// catlak: `M89 60L98 54L101 45 M32 80L24 86L22 95`, in shell coordinates.
    nonisolated(unsafe) static let crackPath: CGPath = {
        let path = CGMutablePath()
        path.addLines(between: [CGPoint(x: 89, y: 60), CGPoint(x: 98, y: 54), CGPoint(x: 101, y: 45)])
        path.addLines(between: [CGPoint(x: 32, y: 80), CGPoint(x: 24, y: 86), CGPoint(x: 22, y: 95)])
        return path
    }()
    static let crackLineWidth: CGFloat = 1.6

    // MARK: Hole (delik), parent: shell

    static let holeFrame = CGRect(x: 26, y: 50, width: 68, height: 40)

    /// Deliberately irregular and asymmetric. Do not tidy it up.
    static let holePercent: [(Double, Double)] = [
        (100, 50), (87.5, 66.7), (81.2, 87.2), (58.3, 89.1), (38.5, 96.1), (22.4, 81.7),
        (3.6, 68.7), (7.1, 47.7), (6.3, 27.8), (25.4, 18.5), (41.1, 4.4), (60, 9.7),
        (81.2, 11.5), (88.5, 32),
    ]

    nonisolated(unsafe) static let holePath: CGPath = polygon(holePercent, in: holeFrame.size)

    /// The hole is a centered flex column: eye row (14 high), 3 gap, beak (7 high).
    /// Content is 24 high in a 40 high box, so it starts at y = 8.
    static let eyeRowCenterY: CGFloat = 8 + 7
    static let eyeGap: CGFloat = 13

    /// Eye centers for a given eye width; the row is centered horizontally.
    static func eyeCenterX(width: CGFloat) -> (left: CGFloat, right: CGFloat) {
        let rowStart = (holeFrame.width - (2 * width + eyeGap)) / 2
        let left = rowStart + width / 2
        return (left, left + width + eyeGap)
    }

    /// gaga: triangle under the eyes, pivots on its top center. Parent: hole.
    static let beakFrame = CGRect(x: 29, y: 25, width: 10, height: 7)
    nonisolated(unsafe) static let beakPath: CGPath = {
        let path = CGMutablePath()
        path.addLines(between: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 5, y: 7)])
        path.closeSubpath()
        return path
    }()

    // MARK: Extras, parent: body (drawn behind the shell, as in the CSS)

    struct Sparkle {
        let frame: CGRect
        let usesAccent: Bool
    }

    /// pul a–d. a and d are mint, b and c use the accent color.
    static let sparkles: [Sparkle] = [
        Sparkle(frame: CGRect(x: 18, y: 10, width: 10, height: 10), usesAccent: false),
        Sparkle(frame: CGRect(x: 150, y: 6, width: 8, height: 8), usesAccent: true),
        Sparkle(frame: CGRect(x: 4, y: 96, width: 8, height: 8), usesAccent: true),
        Sparkle(frame: CGRect(x: 166, y: 100, width: 10, height: 10), usesAccent: false),
    ]

    /// zz: three "z" letters on the same spot, staggered in time. Space Grotesk 700, 16.
    static let sleepLetterOrigin = CGPoint(x: 142, y: 50)
    static let sleepLetterFontSize: CGFloat = 16

    /// unlem: "!" in Space Grotesk 700, 30, line-height 1.
    static let alertMarkOrigin = CGPoint(x: 150, y: 2)
    static let alertMarkFontSize: CGFloat = 30

    // MARK: Helpers

    private static func polygon(_ percent: [(Double, Double)], in size: CGSize) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: percent.map { CGPoint(x: $0.0 / 100 * size.width, y: $0.1 / 100 * size.height) })
        path.closeSubpath()
        return path
    }

    /// Adds an elliptical arc from `start` to `end` (radians, y down), continuing the current point.
    private static func addQuarterEllipse(
        _ path: CGMutablePath, center: CGPoint, rx: CGFloat, ry: CGFloat, from start: CGFloat, to end: CGFloat
    ) {
        let transform = CGAffineTransform(translationX: center.x, y: center.y).scaledBy(x: rx, y: ry)
        path.addArc(center: .zero, radius: 1, startAngle: start, endAngle: end, clockwise: false, transform: transform)
    }
}
