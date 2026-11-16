import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// `--show-character-preview` opens the preview window at launch (development aid).
    static let showPreviewArgument = "--show-character-preview"

    /// Unit tests run inside the app; they get no island, event tap or permission prompt.
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningTests else { return }
        IslandController.shared.start()
        if ProcessInfo.processInfo.arguments.contains(Self.showPreviewArgument) {
            CharacterPreviewWindowController.shared.show()
        }
    }

    /// Coming back from System Settings may have granted Input Monitoring.
    @MainActor
    func applicationDidBecomeActive(_ notification: Notification) {
        guard !Self.isRunningTests else { return }
        IslandController.shared.updateDoubleCommand()
    }
}
