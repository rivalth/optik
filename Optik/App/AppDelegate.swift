import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// `--show-character-preview` opens the preview window at launch (development aid).
    static let showPreviewArgument = "--show-character-preview"

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.arguments.contains(Self.showPreviewArgument) {
            CharacterPreviewWindowController.shared.show()
        }
    }
}
