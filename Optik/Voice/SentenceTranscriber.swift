import Foundation
import OptikCore
import os

/// Turns the user's sentence into text with the engine chosen in Settings
/// (`SpeechEngine`). Whisper stays loaded either way: it hears the wake word, writes
/// the live text while the user talks, and takes over when another engine fails
/// (no connection, no key, no credits).
actor SentenceTranscriber {
    let whisper: WhisperTranscriber
    private let scribe: ScribeTranscriber
    private let engine: @Sendable () -> SpeechEngine
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Optik", category: "speech")

    init(whisper: WhisperTranscriber, scribe: ScribeTranscriber = ScribeTranscriber(),
         engine: @escaping @Sendable () -> SpeechEngine = { SpeechEngine.selected }) {
        self.whisper = whisper
        self.scribe = scribe
        self.engine = engine
    }

    private var hints: [String] {
        SpeechHints.terms(userName: UserDefaults.standard.string(forKey: SettingsKey.userName))
    }

    /// Whether a turn will not wait for a model to load.
    var isLoaded: Bool {
        get async { engine() == .whisper ? await whisper.isLoaded : true }
    }

    func prepareSelectedModel() async throws {
        if engine() == .scribe { await scribe.warmUp(hints: hints) }
        if engine() == .dictation, #available(macOS 26, *), !(await AppleDictation.isInstalled()) {
            try? await AppleDictation.install()
        }
        try await whisper.prepareSelectedModel()
    }

    func downloadSelectedModel() async throws {
        try await whisper.downloadSelectedModel()
    }

    /// The finished sentence.
    func transcribe(_ samples: [Float]) async throws -> String {
        let engine = engine()
        do {
            switch engine {
            case .whisper:
                return try await whisper.transcribe(samples)
            case .scribe:
                return try await scribe.transcribe(samples, hints: hints)
            case .dictation:
                guard #available(macOS 26, *) else { return try await whisper.transcribe(samples) }
                return try await AppleDictation.transcribe(samples, hints: hints)
            }
        } catch {
            guard engine != .whisper, !Task.isCancelled else { throw error }
            log.error("\(engine.rawValue, privacy: .public) failed (\(String(describing: type(of: error)), privacy: .public)), using Whisper")
            return try await whisper.transcribe(samples)
        }
    }

    /// Opens a sentence that streams to Scribe while the user talks; nil for the
    /// engines on this Mac or without a key.
    func startLive() async -> ScribeLiveSession? {
        guard engine() == .scribe else { return nil }
        return try? await scribe.startLive(hints: hints)
    }

    /// The streamed sentence's text: the rest of the audio goes with the commit.
    /// When the stream broke, the whole sentence is sent again (then Whisper).
    func finish(_ live: ScribeLiveSession, samples: [Float]) async throws -> String {
        do {
            try await live.send(samples, commit: true)
            return try await live.text()
        } catch {
            await live.close()
            guard !Task.isCancelled else { throw error }
            log.error("live scribe failed (\(String(describing: type(of: error)), privacy: .public)), sending the sentence again")
            return try await transcribe(samples)
        }
    }

    /// The live text while the user is still talking, every 0.9 s. Never sent to
    /// the cloud: it would send the same audio again and again.
    func transcribePartial(_ samples: [Float]) async throws -> String {
        if engine() == .dictation, #available(macOS 26, *) {
            return try await AppleDictation.transcribe(samples, hints: hints)
        }
        guard await whisper.isLoaded else { return "" }
        return try await whisper.transcribe(samples)
    }
}
