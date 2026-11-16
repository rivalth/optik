import QuartzCore

/// Builds Core Animation transforms the way CSS reads a transform list:
/// `translateY(-3px) rotate(1.5deg)` applies the rightmost function first.
enum CSSTransform {
    enum Function {
        case translate(CGFloat, CGFloat)
        case rotate(degrees: CGFloat)
        case scale(CGFloat, CGFloat)

        var matrix: CATransform3D {
            switch self {
            case let .translate(x, y): CATransform3DMakeTranslation(x, y, 0)
            case let .rotate(degrees): CATransform3DMakeRotation(degrees * .pi / 180, 0, 0, 1)
            case let .scale(x, y): CATransform3DMakeScale(x, y, 1)
            }
        }
    }

    static func make(_ functions: Function...) -> CATransform3D {
        make(functions)
    }

    static func make(_ functions: [Function]) -> CATransform3D {
        // CATransform3DConcat(a, b) applies a, then b.
        functions.reversed().reduce(CATransform3DIdentity) { CATransform3DConcat($0, $1.matrix) }
    }

    static let identity = CATransform3DIdentity
}

/// CSS timing functions.
enum CSSTiming {
    static var ease: CAMediaTimingFunction { CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1) }
    static var easeIn: CAMediaTimingFunction { CAMediaTimingFunction(controlPoints: 0.42, 0, 1, 1) }
    static var easeOut: CAMediaTimingFunction { CAMediaTimingFunction(controlPoints: 0, 0, 0.58, 1) }
    static var easeInOut: CAMediaTimingFunction { CAMediaTimingFunction(controlPoints: 0.42, 0, 0.58, 1) }
    static var linear: CAMediaTimingFunction { CAMediaTimingFunction(name: .linear) }

    static func cubicBezier(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float) -> CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: x1, y1, x2, y2)
    }
}
