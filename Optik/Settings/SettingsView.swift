import KeyboardShortcuts
import OptikCore
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("Genel", systemImage: "gearshape")
                }
            SummonSettingsView()
                .tabItem {
                    Label("Çağırma", systemImage: "keyboard")
                }
        }
        .frame(width: 440)
    }
}

private struct GeneralSettingsView: View {
    @AppStorage(SettingsKey.accentColor) private var accent = AccentChoice.default
    @AppStorage(SettingsKey.soundEffectsEnabled) private var soundEffectsEnabled = true

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        Form {
            Picker("Vurgu rengi", selection: $accent) {
                ForEach(AccentChoice.allCases) { choice in
                    Label {
                        Text(choice.localizedName)
                    } icon: {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(Color(choice.color))
                    }
                    .tag(choice)
                }
            }
            Toggle("Ses efektleri", isOn: $soundEffectsEnabled)
            LabeledContent("Sürüm", value: version)
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
        .onChange(of: soundEffectsEnabled, initial: true) { _, enabled in
            Task { await SoundEffectPlayer.shared.setEnabled(enabled) }
        }
    }
}

private struct SummonSettingsView: View {
    @AppStorage(SettingsKey.summonWithDoubleCommand) private var doubleCommand = true
    @State private var hasPermission = DoubleCommandMonitor.hasPermission

    var body: some View {
        Form {
            Section {
                Toggle("⌘ ⌘ ile çağır", isOn: $doubleCommand)
                if doubleCommand && !hasPermission {
                    LabeledContent {
                        Button("İzin ver…") {
                            DoubleCommandMonitor.requestPermission()
                            NSWorkspace.shared.open(DoubleCommandMonitor.settingsURL)
                        }
                    } label: {
                        Text("Girdi İzleme izni gerekli")
                        Text("Optik yalnızca ⌘ tuşunu izler, başka hiçbir tuşu okumaz.")
                    }
                }
            } footer: {
                Text("Command tuşuna art arda iki kez bas.")
                    .foregroundStyle(.secondary)
            }
            Section {
                KeyboardShortcuts.Recorder("Ek kısayol", name: .summonOptik)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
        .onChange(of: doubleCommand) {
            IslandController.shared.updateDoubleCommand()
            hasPermission = DoubleCommandMonitor.hasPermission
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasPermission = DoubleCommandMonitor.hasPermission
        }
    }
}

#Preview {
    SettingsView()
}
