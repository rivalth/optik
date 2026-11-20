import AppKit

/// Tells whether a full-screen app or a presentation covers a screen, so Optik
/// doesn't come out on its own there (`docs/01-urun.md` 1.1).
///
/// Reads only window bounds, layers and owners, which needs no permission.
/// Checks run on space and app changes, never on a timer.
@MainActor
final class FullScreenMonitor {
    var onChange: ((Bool) -> Void)?
    /// The screen to watch, in global AppKit coordinates.
    var screenFrame: CGRect = .zero {
        didSet { if screenFrame != oldValue { scheduleCheck() } }
    }

    private(set) var isActive = false
    private var observers: [NSObjectProtocol] = []
    private var pendingCheck: DispatchWorkItem?

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleCheck() }
            })
        }
        scheduleCheck()
    }

    func stop() {
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers.removeAll()
        pendingCheck?.cancel()
    }

    /// Spaces slide for about half a second; check once after they settle, and once
    /// right away for app switches within a space.
    private func scheduleCheck() {
        check()
        pendingCheck?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.check() }
        }
        pendingCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
    }

    private func check() {
        let active = Self.isCovered(screenFrame)
        guard active != isActive else { return }
        isActive = active
        onChange?(active)
    }

    /// True when another app's visible window covers the whole screen, menu bar area
    /// included: a full-screen app or a slideshow. Zoomed windows stop below the
    /// menu bar, so they don't count.
    static func isCovered(_ screenFrame: CGRect) -> Bool {
        guard screenFrame.width > 0,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return false }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let target = cgRect(fromAppKit: screenFrame)
        return windows.contains { info in
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  let layer = info[kCGWindowLayer as String] as? Int, Self.contentLayers.contains(layer),
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo) else { return false }
            return covers(bounds, target)
        }
    }

    /// App windows up to floating panels. From the Dock's layer up (the Dock, the menu
    /// bar, overlays, screen savers) are system windows that don't mean "full screen":
    /// the Dock keeps a window over the whole screen at times, which hid the island.
    nonisolated static let contentLayers = 0..<Int(CGWindowLevelForKey(.dockWindow))

    nonisolated static func covers(_ window: CGRect, _ screen: CGRect) -> Bool {
        window.minX <= screen.minX + 1 && window.minY <= screen.minY + 1
            && window.maxX >= screen.maxX - 1 && window.maxY >= screen.maxY - 1
    }

    /// Window bounds use a top-left origin at the primary screen's top edge.
    static func cgRect(fromAppKit rect: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? rect.maxY
        return CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}
