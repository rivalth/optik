import AppKit
import OptikCore
import SwiftUI

struct MenuBarMenu: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Optik'i çağır") {
            IslandController.shared.summon()
        }

        Button("Karakter önizlemesi") {
            CharacterPreviewWindowController.shared.show()
        }

        #if DEBUG
        Menu("Geliştirici") {
            Button("Adacık akışını oynat") {
                IslandController.shared.playDemo()
            }
            Button("Örnek haber (5 sn sonra)") {
                IslandController.shared.announceSample(after: 5)
            }
        }
        #endif

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
