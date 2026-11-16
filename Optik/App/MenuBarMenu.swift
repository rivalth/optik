import AppKit
import SwiftUI

struct MenuBarMenu: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Ayarlar…") {
            // An agent app is never active on its own; bring it forward so the window shows on top.
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")

        Divider()

        Button("Optik'ten çık") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
