import AppKit
import OptikCore
import SwiftUI

/// Opens the character preview on demand. A plain AppKit window keeps it from
/// opening at launch, which a SwiftUI `Window` scene does on macOS 14.
@MainActor
final class CharacterPreviewWindowController {
    static let shared = CharacterPreviewWindowController()

    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: CharacterPreviewView())
            let window = NSWindow(contentViewController: hosting)
            window.title = String(localized: "Karakter önizlemesi")
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.backgroundColor = NSColor(DesignTokens.Palette.background)
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
