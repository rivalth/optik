import OptikCore
import SwiftUI

/// The coop door, 48 × 58 (`docs/03-karakter.md` 4, `tasarim-kaynak/03-mac-centik.dc.html`).
/// `isOpen` swings the door leaf 108° on its left edge in 0.35 s.
struct CoopDoorView: View {
    var isOpen: Bool
    var reduceMotion = false

    static let size = CGSize(width: 48, height: 58)

    var body: some View {
        ZStack(alignment: .topLeading) {
            UnevenRoundedRectangle(topLeadingRadius: 24, bottomLeadingRadius: 4,
                                   bottomTrailingRadius: 4, topTrailingRadius: 24)
                .fill(Color(DesignTokens.CoopPalette.frame))
                .frame(width: 48, height: 58)
            archedOpening
                .fill(Color(DesignTokens.CoopPalette.inside))
                .frame(width: 38, height: 53)
                .offset(x: 5, y: 5)
            leaf
                .frame(width: 38, height: 53)
                .modifier(DoorSwing(angle: isOpen ? -108 : 0))
                .animation(reduceMotion ? nil : .timingCurve(0.25, 0.1, 0.25, 1, duration: 0.35), value: isOpen)
                .offset(x: 5, y: 5)
            straw(x: -7, y: 53, width: 16, angle: -18)
            straw(x: 40, y: 54, width: 14, angle: 14)
            straw(x: 45, y: 49, width: 10, angle: -32)
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
    }

    private var archedOpening: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 19, bottomLeadingRadius: 0,
                               bottomTrailingRadius: 0, topTrailingRadius: 19)
    }

    private var leaf: some View {
        ZStack(alignment: .topLeading) {
            Color(DesignTokens.CoopPalette.door)
            Rectangle().fill(.black.opacity(0.2)).frame(width: 2, height: 53).offset(x: 12)
            Rectangle().fill(.black.opacity(0.2)).frame(width: 2, height: 53).offset(x: 25)
            Circle().fill(Color(DesignTokens.CoopPalette.inside)).frame(width: 10, height: 10).offset(x: 14, y: 13)
        }
        .clipShape(archedOpening)
    }

    /// A straw, rotated around its own center like the CSS.
    private func straw(x: CGFloat, y: CGFloat, width: CGFloat, angle: Double) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color(DesignTokens.CoopPalette.straw))
            .frame(width: width, height: 3)
            .rotationEffect(.degrees(angle))
            .offset(x: x, y: y)
    }
}

/// `transform: perspective(220px) rotateY(angle)` with `transform-origin: 0 50%`.
private struct DoorSwing: GeometryEffect {
    var angle: Double

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        var perspective = CATransform3DIdentity
        perspective.m34 = -1 / 220
        let toOrigin = CATransform3DMakeTranslation(0, -size.height / 2, 0)
        let rotate = CATransform3DMakeRotation(angle * .pi / 180, 0, 1, 0)
        let back = CATransform3DMakeTranslation(0, size.height / 2, 0)
        let transform = CATransform3DConcat(CATransform3DConcat(CATransform3DConcat(toOrigin, rotate), perspective), back)
        return ProjectionTransform(transform)
    }
}
