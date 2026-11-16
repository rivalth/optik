import OptikCore
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("Genel", systemImage: "gearshape")
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

#Preview {
    SettingsView()
}
