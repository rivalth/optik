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
            VoiceSettingsView()
                .tabItem {
                    Label("Ses", systemImage: "waveform")
                }
            IndicatorSettingsView()
                .tabItem {
                    Label("Göstergeler", systemImage: "rectangle.topthird.inset.filled")
                }
        }
        .frame(width: 480)
    }
}

private struct GeneralSettingsView: View {
    @AppStorage(SettingsKey.accentColor) private var accent = AccentChoice.default
    @AppStorage(SettingsKey.soundEffectsEnabled) private var soundEffectsEnabled = true
    @State private var canControlApps = AccessibilityControl.isTrusted

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
            Section {
                LabeledContent("Erişilebilirlik izni") {
                    if canControlApps {
                        Label("Verildi", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.secondary)
                    } else {
                        Button("İzin ver…") {
                            AccessibilityControl.requestTrust()
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
            } header: {
                Text("Uygulamaları kullanma")
            } footer: {
                Text("“Dia’yı aç, sonra maç saati arat” ya da “Spotify’da Tarkan çal” gibi komutları Optik Claude’a sormadan yapar. Uygulama açmak ve tarayıcıda aramak izinsiz çalışır; Spotify’da çal düğmesine basmak gibi tıklamalar için Erişilebilirlik izni gerekir.")
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Sürüm", value: version)
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
        .onChange(of: soundEffectsEnabled, initial: true) { _, enabled in
            Task { await SoundEffectPlayer.shared.setEnabled(enabled) }
        }
        // The permission is given in System Settings; notice it without a restart.
        .task {
            while !Task.isCancelled {
                canControlApps = AccessibilityControl.isTrusted
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

private struct SummonSettingsView: View {
    @AppStorage(SettingsKey.summonWithDoubleCommand) private var doubleCommand = true
    @State private var hasPermission = DoubleCommandMonitor.hasPermission
    @AppStorage(SettingsKey.summonWithWakeWord) private var wakeWord = false
    @AppStorage(SettingsKey.onlyMyVoice) private var onlyMyVoice = true
    @State private var hasVoiceProfile = SpeakerVerifier.hasProfile
    @State private var showsEnrollment = false

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
                Toggle("“Optik” diye seslenince çık", isOn: $wakeWord)
            } footer: {
                Text("Mikrofon sürekli açık kalır ve macOS turuncu noktayı gösterir. Ses cihazdan çıkmaz.")
                    .foregroundStyle(.secondary)
            }
            Section {
                LabeledContent {
                    Button(hasVoiceProfile ? "Yeniden tanıt…" : "Sesimi tanı…") { showsEnrollment = true }
                } label: {
                    Text("Sesim")
                    Text(hasVoiceProfile ? "Optik sesini tanıyor." : "Optik henüz sesini tanımıyor.")
                }
                if hasVoiceProfile {
                    Toggle("Yalnızca benim sesime tepki ver", isOn: $onlyMyVoice)
                    Button("Ses profilini sil", role: .destructive) {
                        Task {
                            await SpeakerVerifier.shared.removeProfile()
                            hasVoiceProfile = false
                        }
                    }
                }
            } footer: {
                Text("Kalabalıkta başkası “Optik” deyince açılmaz, başkalarının sözlerini senin sanmaz. Ses kaydı saklanmaz.")
                    .foregroundStyle(.secondary)
            }
            Section {
                KeyboardShortcuts.Recorder("Ek kısayol", name: .summonOptik)
            }
            Section {
                KeyboardShortcuts.Recorder("Yazarak sor", name: .quietAsk)
            } footer: {
                Text("Konuşamayacağın yerlerde: çentiğin altında bir kutu açılır, Optik yazıyla cevap verir ve mikrofon kapalı kalır.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
        .sheet(isPresented: $showsEnrollment, onDismiss: { hasVoiceProfile = SpeakerVerifier.hasProfile }) {
            VoiceEnrollmentView()
        }
        .onChange(of: wakeWord) {
            IslandController.shared.updateWakeWord()
        }
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
