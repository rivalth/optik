import OptikCore
import SwiftUI

/// SwiftUI wrapper around `OptikCharacterView`.
///
/// Changing `mood` plays the shape transition and the tap bounce, like the demo.
/// Tapping Optik bounces and calls `onTap`.
struct OptikView: NSViewRepresentable {
    var mood: Mood
    var scale: CGFloat = 1
    var accent: RGBA = DesignTokens.Palette.accent
    var onTap: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeNSView(context: Context) -> OptikCharacterView {
        let view = OptikCharacterView(frame: .zero)
        view.scale = scale
        view.accentColor = accent
        view.reduceMotion = reduceMotion
        view.setMood(mood, animated: false)
        view.onTap = onTap
        return view
    }

    func updateNSView(_ view: OptikCharacterView, context: Context) {
        view.scale = scale
        view.accentColor = accent
        view.reduceMotion = reduceMotion
        view.onTap = onTap
        if view.mood != mood {
            view.setMood(mood, animated: true)
            view.bounce()
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: OptikCharacterView, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }
}
