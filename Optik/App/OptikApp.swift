import SwiftUI

/// Optik runs as a menu bar agent (`LSUIElement`): no Dock icon, no main window.
/// The notch island (stage 1) and the second-brain window (stage 3) come later.
@main
struct OptikApp: App {
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
