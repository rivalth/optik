import AppKit
import OptikCore

/// What the island needs to know about the screen it sits on. Built from `NSScreen`
/// in the app, by hand in tests.
struct IslandScreen: Equatable {
    /// The screen's frame in global AppKit coordinates (origin bottom left).
    var frame: CGRect
    /// The camera housing, in the same coordinates. Nil on screens without a notch.
    var notch: CGRect?
    var displayID: CGDirectDisplayID = 0
    var isBuiltIn = false

    var hasNotch: Bool { notch != nil }
}

enum IslandLayout {
    /// Room around the island for the spring's overshoot, so it never gets clipped.
    static let overshootMargin: CGFloat = 32
    /// Without a notch the island floats this far below the top edge as a pill.
    static let floatingInset: CGFloat = 6

    /// Reads the notch from the screen: the gap between the two menu bar areas beside
    /// the camera, as tall as the top safe area. No hard-coded sizes.
    @MainActor
    static func screen(for screen: NSScreen) -> IslandScreen {
        let frame = screen.frame
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        let isBuiltIn = displayID != 0 && CGDisplayIsBuiltin(displayID) != 0
        var notch: CGRect?
        let top = screen.safeAreaInsets.top
        if top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let width = frame.width - left.width - right.width
            if width > 0 {
                notch = CGRect(x: frame.minX + left.width, y: frame.maxY - top, width: width, height: top)
            }
        }
        return IslandScreen(frame: frame, notch: notch, displayID: displayID, isBuiltIn: isBuiltIn)
    }

    /// The island lives on the built-in screen. With the lid closed it moves to the
    /// screen with the menu bar and floats there as a pill (`docs/02-mimari.md` 2).
    static func preferredScreen(_ screens: [IslandScreen]) -> IslandScreen? {
        screens.first(where: \.isBuiltIn) ?? screens.first
    }

    /// The island's own rectangle for a size, centered on the notch (or the screen).
    static func islandFrame(_ size: DesignTokens.Island.Size, on screen: IslandScreen) -> CGRect {
        let width = max(size.width, minimumWidth(on: screen, for: size))
        let midX = screen.notch?.midX ?? screen.frame.midX
        let top = screen.hasNotch ? screen.frame.maxY : screen.frame.maxY - floatingInset
        return CGRect(x: (midX - width / 2).rounded(), y: top - size.height, width: width, height: size.height)
    }

    /// The panel: the island plus room for the overshoot while open. Closed, it is
    /// exactly the island, so it catches clicks only there.
    static func panelFrame(_ size: DesignTokens.Island.Size, on screen: IslandScreen, withMargin: Bool) -> CGRect {
        let island = islandFrame(size, on: screen)
        guard withMargin else { return island }
        let margin = overshootMargin
        return CGRect(x: island.minX - margin, y: island.minY - margin,
                      width: island.width + 2 * margin, height: island.height + margin)
    }

    /// Keep the coop and the right wing clear of the camera on unusually wide notches:
    /// at least 56 pt of wing on each side, as on the 312 pt design.
    private static func minimumWidth(on screen: IslandScreen, for size: DesignTokens.Island.Size) -> CGFloat {
        guard let notch = screen.notch else { return size.width }
        return notch.width + 2 * 56
    }
}
