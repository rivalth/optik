import CoreGraphics
import OptikCore

/// One eye: size, corner radii (CSS `border-radius`, clamped like CSS), rotation and offset.
struct EyeShape: Equatable {
    var width: CGFloat
    var height: CGFloat
    /// top-left, top-right, bottom-right, bottom-left
    var radii: (CGFloat, CGFloat, CGFloat, CGFloat)
    var rotationDegrees: CGFloat = 0
    var offset: CGSize = .zero

    static func == (a: EyeShape, b: EyeShape) -> Bool {
        a.width == b.width && a.height == b.height
            && a.radii.0 == b.radii.0 && a.radii.1 == b.radii.1
            && a.radii.2 == b.radii.2 && a.radii.3 == b.radii.3
            && a.rotationDegrees == b.rotationDegrees && a.offset == b.offset
    }

    init(width: CGFloat, height: CGFloat, radius: CGFloat, rotationDegrees: CGFloat = 0, offset: CGSize = .zero) {
        self.init(width: width, height: height, radii: (radius, radius, radius, radius),
                  rotationDegrees: rotationDegrees, offset: offset)
    }

    init(width: CGFloat, height: CGFloat, radii: (CGFloat, CGFloat, CGFloat, CGFloat),
         rotationDegrees: CGFloat = 0, offset: CGSize = .zero) {
        self.width = width
        self.height = height
        // CSS scales all radii down by the same factor when adjacent radii overflow a side.
        let factor = min(
            1,
            width / max(radii.0 + radii.1, .ulpOfOne),
            height / max(radii.1 + radii.2, .ulpOfOne),
            width / max(radii.2 + radii.3, .ulpOfOne),
            height / max(radii.3 + radii.0, .ulpOfOne)
        )
        self.radii = (radii.0 * factor, radii.1 * factor, radii.2 * factor, radii.3 * factor)
        self.rotationDegrees = rotationDegrees
        self.offset = offset
    }

    /// The eyes for a mood: (left, right). Values from `.optik.<mood> .goz` in optik.css.
    static func eyes(for mood: Mood) -> (left: EyeShape, right: EyeShape) {
        switch mood {
        case .waiting:
            let eye = EyeShape(width: 10, height: 13, radius: 5)
            return (eye, eye)
        case .happy:
            let eye = EyeShape(width: 10, height: 7, radii: (7, 7, 2, 2))
            return (eye, eye)
        case .listening:
            let eye = EyeShape(width: 11, height: 14, radius: 5)
            return (eye, eye)
        case .thoughtful:
            let shift = CGSize(width: 3, height: -3)
            return (EyeShape(width: 10, height: 13, radius: 5, offset: shift),
                    EyeShape(width: 10, height: 9, radius: 5, offset: shift))
        case .alert:
            let eye = EyeShape(width: 12, height: 12, radius: 6)
            return (eye, eye)
        case .celebrating:
            let eye = EyeShape(width: 11, height: 11, radius: 3, rotationDegrees: 45)
            return (eye, eye)
        case .sleepy:
            let eye = EyeShape(width: 12, height: 3, radius: 2)
            return (eye, eye)
        }
    }

    /// The outline centered on `center`. Always 4 lines and 4 curves, so paths of
    /// different moods can be interpolated by Core Animation.
    func path(centeredAt center: CGPoint) -> CGPath {
        let w = width, h = height
        let (tl, tr, br, bl) = radii
        let k: CGFloat = 0.5522847498 // circle approximation with cubic curves
        let x0 = -w / 2, y0 = -h / 2, x1 = w / 2, y1 = h / 2

        let path = CGMutablePath()
        path.move(to: CGPoint(x: x0 + tl, y: y0))
        path.addLine(to: CGPoint(x: x1 - tr, y: y0))
        path.addCurve(to: CGPoint(x: x1, y: y0 + tr),
                      control1: CGPoint(x: x1 - tr + tr * k, y: y0),
                      control2: CGPoint(x: x1, y: y0 + tr - tr * k))
        path.addLine(to: CGPoint(x: x1, y: y1 - br))
        path.addCurve(to: CGPoint(x: x1 - br, y: y1),
                      control1: CGPoint(x: x1, y: y1 - br + br * k),
                      control2: CGPoint(x: x1 - br + br * k, y: y1))
        path.addLine(to: CGPoint(x: x0 + bl, y: y1))
        path.addCurve(to: CGPoint(x: x0, y: y1 - bl),
                      control1: CGPoint(x: x0 + bl - bl * k, y: y1),
                      control2: CGPoint(x: x0, y: y1 - bl + bl * k))
        path.addLine(to: CGPoint(x: x0, y: y0 + tl))
        path.addCurve(to: CGPoint(x: x0 + tl, y: y0),
                      control1: CGPoint(x: x0, y: y0 + tl - tl * k),
                      control2: CGPoint(x: x0 + tl - tl * k, y: y0))
        path.closeSubpath()

        let transform = CGAffineTransform(translationX: center.x + offset.width, y: center.y + offset.height)
            .rotated(by: rotationDegrees * .pi / 180)
        return path.copy(using: [transform])!
    }
}
