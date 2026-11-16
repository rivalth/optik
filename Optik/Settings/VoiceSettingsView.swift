import AVFoundation
import SwiftUI

/// Keys, the speech model and the microphone (`docs/02-mimari.md` 7: keys are entered
/// in Settings and live only in the Keychain).
struct VoiceSettingsView: View {
    @AppStorage(SettingsKey.userName) private var userName = ""
    @AppStorage(SettingsKey.speechModel) private var speechModel = SpeechModel.default.rawValue
    @State private var microphone = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var modelState: WhisperTranscriber.State = .notDownloaded
    @State private var observer: UUID?

    private var transcriber: WhisperTranscriber { IslandController.shared.transcriber }

    var body: some View {
        Form {
            Section {
                TextField("Adın", text: $userName, prompt: Text("Optik sana nasıl seslensin?"))
            }
            Section {
                APIKeyField(title: "Claude API anahtarı", key: .anthropic, prompt: "sk-ant-…")
                APIKeyField(title: "ElevenLabs API anahtarı", key: .elevenLabs, prompt: "sk_…")
            } header: {
                Text("Anahtarlar")
            } footer: {
                Text("Anahtarlar yalnızca bu Mac'in Anahtar Zinciri'nde durur. ElevenLabs anahtarı yoksa Optik sistemin Türkçe sesiyle konuşur.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Picker("Model", selection: $speechModel) {
                    ForEach(SpeechModel.allCases) { model in
                        Text(model.localizedName).tag(model.rawValue)
                    }
                }
                LabeledContent("Durum") { modelStatus }
            } header: {
                Text("Konuşmayı tanıma")
            } footer: {
                Text("Konuşman bu Mac'te yazıya çevrilir, ses dışarı çıkmaz. Model bir kez indirilir.")
                    .foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Mikrofon") { microphoneStatus }
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
        .task {
            let id = await transcriber.observe { state in
                Task { @MainActor in modelState = state }
            }
            observer = id
        }
        .onDisappear {
            if let observer { Task { await transcriber.removeObserver(observer) } }
        }
        .onChange(of: speechModel) {
            let transcriber = self.transcriber
            Task.detached { try? await transcriber.prepareSelectedModel() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            microphone = AVCaptureDevice.authorizationStatus(for: .audio)
        }
    }

    @ViewBuilder
    private var modelStatus: some View {
        switch modelState {
        case .ready:
            Text("Hazır").foregroundStyle(.secondary)
        case .preparing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Hazırlanıyor…").foregroundStyle(.secondary)
            }
            .help(Text("İlk seferde model bu Mac için derlenir, bir dakika kadar sürebilir."))
        case .downloading(let fraction):
            ProgressView(value: fraction).frame(width: 140)
        case .notDownloaded, .failed:
            HStack {
                if modelState == .failed { Text("İndirilemedi").foregroundStyle(.secondary) }
                Button("İndir") {
                    let transcriber = self.transcriber
                    Task.detached { try? await transcriber.downloadSelectedModel() }
                }
            }
        }
    }

    @ViewBuilder
    private var microphoneStatus: some View {
        switch microphone {
        case .authorized:
            Text("İzin verildi").foregroundStyle(.secondary)
        case .notDetermined:
            Button("İzin ver…") {
                Task {
                    _ = await AVCaptureDevice.requestAccess(for: .audio)
                    microphone = AVCaptureDevice.authorizationStatus(for: .audio)
                }
            }
        default:
            Button("Sistem Ayarları'nı aç…") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
            }
        }
    }
}

/// A secure field that saves to the Keychain and never shows the stored key.
private struct APIKeyField: View {
    let title: LocalizedStringKey
    let key: APIKey
    let prompt: String

    @State private var draft = ""
    @State private var isSaved = false

    var body: some View {
        LabeledContent(title) {
            HStack {
                if isSaved && draft.isEmpty {
                    Text("Kayıtlı").foregroundStyle(.secondary)
                    Button("Sil", role: .destructive) {
                        KeychainStore.write("", for: key)
                        isSaved = false
                    }
                } else {
                    SecureField(text: $draft, prompt: Text(verbatim: prompt)) { EmptyView() }
                        .frame(width: 180)
                        .onSubmit(save)
                    Button("Kaydet", action: save).disabled(draft.isEmpty)
                }
            }
        }
        .onAppear { isSaved = KeychainStore.has(key) }
    }

    private func save() {
        guard !draft.isEmpty else { return }
        isSaved = KeychainStore.write(draft, for: key)
        draft = ""
    }
}
