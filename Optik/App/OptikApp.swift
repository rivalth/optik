import SwiftUI

/// Optik runs as a menu bar agent (`LSUIElement`): no Dock icon, no main window.
/// It lives in the notch island (`IslandController`); the second-brain window comes in stage 3.
@main
struct OptikApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Once, before anything reads a setting: the move out of the sandbox
        // container is a rename on the same disk, so it costs no time here.
        if !AppDelegate.isRunningTests { ContainerMigration.runIfNeeded() }
        // Decode sound effects off the main thread so the first one plays instantly.
        Task.detached(priority: .utility) {
            await SoundEffectPlayer.shared.preload()
            let enabled = UserDefaults.standard.object(forKey: SettingsKey.soundEffectsEnabled) as? Bool ?? true
            await SoundEffectPlayer.shared.setEnabled(enabled)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarMenu()
        } label: {
            Image(.menuBarIcon)
                .accessibilityLabel(Text("Optik"))
        }

        Settings {
            SettingsView()
        }
    }
}
