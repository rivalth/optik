import AppKit
import SwiftUI

/// The borderless, transparent panel the island lives in (`docs/02-mimari.md` 2).
/// It never becomes key or active, so the app in front keeps focus and typing.
final class IslandPanel: NSPanel {
    init(rootView: some View) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        isFloatingPanel = true
        // Above the menu bar, like the system's own notch content.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        setAccessibilityRole(.popover)

        let host = NSHostingView(rootView: rootView)
        host.sizingOptions = []
        contentView = host
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
