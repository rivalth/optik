import CoreGraphics
import OptikCore
import Testing
@testable import Optik

/// Checks the drawing against the numbers in `docs/03-karakter.md` section 1.
struct CharacterGeometryTests {
    /// Converts a point in hole coordinates to the 180 × 200 design box.
    private func inDesignBox(_ point: CGPoint) -> CGPoint {
        let shell = CharacterGeometry.shellFrame.origin
        let hole = CharacterGeometry.holeFrame.origin
        return CGPoint(x: shell.x + hole.x + point.x, y: shell.y + hole.y + point.y)
    }

    @Test func defaultEyeCentersMatchDocs() {
        let centers = CharacterGeometry.eyeCenterX(width: 10)
        #expect(inDesignBox(CGPoint(x: centers.left, y: CharacterGeometry.eyeRowCenterY)) == CGPoint(x: 78.5, y: 71))
        #expect(inDesignBox(CGPoint(x: centers.right, y: CharacterGeometry.eyeRowCenterY)) == CGPoint(x: 101.5, y: 71))
    }

    @Test func beakTriangleMatchesDocs() {
        let frame = CharacterGeometry.beakFrame
        #expect(inDesignBox(frame.origin) == CGPoint(x: 85, y: 81))
        #expect(inDesignBox(CGPoint(x: frame.maxX, y: frame.minY)) == CGPoint(x: 95, y: 81))
        #expect(inDesignBox(CGPoint(x: frame.midX, y: frame.maxY)) == CGPoint(x: 90, y: 88))
    }

    @Test func legsMatchDocs() {
        // Leg line (73,146)→(73,178), toes (62,187) (73,188) (84,187).
        let origin = CharacterGeometry.leftLegOrigin
        #expect(CGPoint(x: origin.x + 15, y: origin.y + 2) == CGPoint(x: 73, y: 146))
        #expect(CGPoint(x: origin.x + 15, y: origin.y + 34) == CGPoint(x: 73, y: 178))
        #expect(CGPoint(x: origin.x + 4, y: origin.y + 43) == CGPoint(x: 62, y: 187))
        #expect(CharacterGeometry.rightLegOrigin.x + 15 == 107)
    }

    @Test func shellFillsItsBoxAndIsCutByTheBreak() {
        let box = CGRect(origin: .zero, size: CharacterGeometry.shellFrame.size)
        let outline = CharacterGeometry.shellOutline.boundingBox
        #expect(abs(outline.width - box.width) < 0.01)
        #expect(abs(outline.height - box.height) < 0.01)
        let cut = CharacterGeometry.shellPath.boundingBox
        // The zigzag reaches 89% of the height at its deepest point.
        #expect(cut.maxY < box.height * 0.9)
        #expect(cut.maxY > box.height * 0.85)
    }

    @Test func shadeSitsOnTheLowerRight() {
        // Inset shadow offset (-10, -12): a crescent inside the right edge, nothing on the left.
        let shade = CharacterGeometry.shellShadePath
        let box = CharacterGeometry.shellFrame.size
        #expect(shade.contains(CGPoint(x: box.width - 3, y: box.height * 0.6)))
        #expect(!shade.contains(CGPoint(x: 3, y: box.height * 0.6)))
        #expect(!shade.contains(CGPoint(x: box.width / 2, y: box.height / 2)))
    }

    @Test func holeIsIrregular() {
        // Guard against "tidying up" the hole into something symmetric.
        let points = CharacterGeometry.holePercent
        let mirrored = points.map { (100 - $0.0, $0.1) }
        #expect(Set(points.map { "\($0.0),\($0.1)" }) != Set(mirrored.map { "\($0.0),\($0.1)" }))
        #expect(points.count == 14)
    }

    @Test func happyEyeRadiiAreClampedLikeCSS() {
        let eye = EyeShape.eyes(for: .happy).left
        // 7+7 on a 10 wide edge: CSS scales every radius by 10/14.
        #expect(abs(eye.radii.0 - 5) < 0.001)
        #expect(abs(eye.radii.2 - 10.0 / 7) < 0.001)
    }

    @Test(arguments: Mood.allCases)
    func eyePathsInterpolate(mood: Mood) {
        // Same element count for every mood, or Core Animation snaps instead of morphing.
        func elementCount(_ path: CGPath) -> Int {
            var count = 0
            path.applyWithBlock { _ in count += 1 }
            return count
        }
        let reference = elementCount(EyeShape.eyes(for: .waiting).left.path(centeredAt: .zero))
        let eyes = EyeShape.eyes(for: mood)
        #expect(elementCount(eyes.left.path(centeredAt: .zero)) == reference)
        #expect(elementCount(eyes.right.path(centeredAt: .zero)) == reference)
    }
}
