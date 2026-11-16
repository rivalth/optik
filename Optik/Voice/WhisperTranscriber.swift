import Foundation
import OptikCore
import os
// WhisperKit predates Swift 6 concurrency checking; the actor serializes all use.
@preconcurrency import WhisperKit

/// The speech recognition models the user can pick (`docs/02-mimari.md` 3.2: start
/// small, grow if accuracy is not enough).
enum SpeechModel: String, CaseIterable, Identifiable, Sendable {
    case base = "openai_whisper-base"
    case small = "openai_whisper-small"
    case turbo = "openai_whisper-large-v3-v20240930_turbo_632MB"

    var id: String { rawValue }

    static let `default` = SpeechModel.small

    var localizedName: String {
        switch self {
        case .base: String(localized: "Hızlı (yaklaşık 150 MB)")
        case .small: String(localized: "Dengeli (yaklaşık 500 MB)")
        case .turbo: String(localized: "En doğru (yaklaşık 650 MB)")
        }
    }

    /// Where the model runs. The Neural Engine compiles a model once before its
    /// first use; for the large model that compile can run for hours, so it runs
    /// on the GPU, which needs no compile.
    var computeOptions: ModelComputeOptions? {
        switch self {
        case .base, .small: nil
        case .turbo: ModelComputeOptions(audioEncoderCompute: .cpuAndGPU, textDecoderCompute: .cpuAndGPU)
        }
    }

    static var selected: SpeechModel {
        UserDefaults.standard.string(forKey: SettingsKey.speechModel).flatMap(SpeechModel.init) ?? .default
    }
}

/// Where models live: `~/Library/Application Support/Optik/Models` (in the container).
enum ModelStorage {
    static var base: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appending(path: "Optik/Models", directoryHint: .isDirectory)
    }

    /// The downloaded folder for a model, if it is complete enough to load.
    static func folder(for model: SpeechModel) -> URL? {
        let root = base.appending(path: "models/argmaxinc/whisperkit-coreml/\(model.rawValue)", directoryHint: .isDirectory)
        let encoder = root.appending(path: "AudioEncoder.mlmodelc")
        return FileManager.default.fileExists(atPath: encoder.path) ? root : nil
    }
}

/// WhisperKit on the device (`docs/02-mimari.md` 3.2). The model is prepared as soon
/// as it is downloaded or chosen, and stays loaded: once compiled it takes little
/// memory, and loading it again would cost the next turn. It leaves memory only
/// when the system runs low.
actor WhisperTranscriber: Transcriber {
    enum State: Equatable, Sendable {
        case notDownloaded
        case downloading(Double)
        /// Downloaded and loading. The first load after a download compiles the
        /// model for this Mac and can take close to a minute.
        case preparing
        case ready
        case failed
    }

    private var whisper: WhisperKit?
    private var loadedModel: SpeechModel?
    private var loading: Task<WhisperKit, Error>?
    private var loadingModel: SpeechModel?
    private var download: Task<URL, Error>?
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Optik", category: "speech")
    private let memoryPressure = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .global(qos: .utility))

    /// Download progress and readiness, for Settings and the island.
    private(set) var state: State = .notDownloaded
    private var stateObservers: [UUID: @Sendable (State) -> Void] = [:]

    init() {
        memoryPressure.setEventHandler { [weak self] in
            Task { await self?.unload() }
        }
        memoryPressure.activate()
    }

    func observe(_ observer: @escaping @Sendable (State) -> Void) -> UUID {
        let id = UUID()
        stateObservers[id] = observer
        observer(currentState())
        return id
    }

    func removeObserver(_ id: UUID) { stateObservers[id] = nil }

    func currentState() -> State {
        switch state {
        case .downloading, .preparing: return state
        default: break
        }
        if ModelStorage.folder(for: SpeechModel.selected) == nil { return state == .failed ? .failed : .notDownloaded }
        return .ready
    }

    /// Whether the selected model is loaded and a turn will not wait for it.
    var isLoaded: Bool { whisper != nil && loadedModel == SpeechModel.selected }

    private func publish(_ newState: State) {
        state = newState
        for observer in stateObservers.values { observer(newState) }
    }

    // MARK: Download

    /// Downloads the selected model from Hugging Face, then prepares it. Only text
    /// crosses the network later; this is the one time a large file comes in.
    func downloadSelectedModel() async throws {
        let model = SpeechModel.selected
        if ModelStorage.folder(for: model) != nil { try await prepareSelectedModel(); return }
        if let download { _ = try await download.value; return }
        publish(.downloading(0))
        let task = Task { () throws -> URL in
            try FileManager.default.createDirectory(at: ModelStorage.base, withIntermediateDirectories: true)
            return try await WhisperKit.download(variant: model.rawValue, downloadBase: ModelStorage.base) { progress in
                let fraction = progress.fractionCompleted
                Task { await self.publishProgress(fraction) }
            }
        }
        download = task
        defer { download = nil }
        do {
            _ = try await task.value
        } catch {
            log.error("model download failed")
            publish(.failed)
            throw error
        }
        try await prepareSelectedModel()
    }

    private func publishProgress(_ fraction: Double) {
        guard case .downloading = state else { return }
        publish(.downloading(fraction))
    }

    /// Loads the selected model now, so the next turn does not wait. Called at launch,
    /// after a download and when the user picks another model.
    func prepareSelectedModel() async throws {
        guard ModelStorage.folder(for: SpeechModel.selected) != nil else {
            publish(.notDownloaded)
            return
        }
        if !isLoaded { publish(.preparing) }
        do {
            _ = try await loadedWhisper()
            publish(.ready)
        } catch {
            log.error("model could not be loaded")
            publish(.failed)
            throw error
        }
    }

    // MARK: Transcriber

    func prepare() async throws {
        _ = try await loadedWhisper()
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        let whisper = try await loadedWhisper()
        let options = DecodingOptions(
            task: .transcribe, language: "tr", temperature: 0, temperatureFallbackCount: 1,
            usePrefillPrompt: true, detectLanguage: false, skipSpecialTokens: true, withoutTimestamps: true,
            suppressBlank: true
        )
        let started = ContinuousClock.now
        let results = try await whisper.transcribe(audioArray: samples, decodeOptions: options)
        log.info("transcribed \(samples.count / 16_000, privacy: .public) s of audio in \(Self.milliseconds(since: started), privacy: .public) ms")
        return results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func unload() async {
        loading?.cancel()
        loading = nil
        loadingModel = nil
        await whisper?.unloadModels()
        whisper = nil
        loadedModel = nil
    }

    private func loadedWhisper() async throws -> WhisperKit {
        let model = SpeechModel.selected
        if let whisper, loadedModel == model { return whisper }
        // A load already under way: wait for it instead of starting a second one.
        if let loading, loadingModel == model { return try await loading.value }
        if loadedModel != nil || loading != nil { await unload() }
        guard let folder = ModelStorage.folder(for: model) else { throw TranscriberError.modelMissing }
        let task = Task { () throws -> WhisperKit in
            let config = WhisperKitConfig(
                model: model.rawValue, downloadBase: ModelStorage.base, modelFolder: folder.path,
                tokenizerFolder: ModelStorage.base, computeOptions: model.computeOptions, verbose: false, logLevel: .error,
                prewarm: false, load: true, download: false
            )
            return try await WhisperKit(config)
        }
        loading = task
        loadingModel = model
        defer { if loadingModel == model { loading = nil; loadingModel = nil } }
        let started = ContinuousClock.now
        log.info("loading \(model.rawValue, privacy: .public)")
        let whisper = try await task.value
        log.info("model loaded in \(Self.milliseconds(since: started), privacy: .public) ms")
        self.whisper = whisper
        loadedModel = model
        return whisper
    }

    private static func milliseconds(since start: ContinuousClock.Instant) -> Int64 {
        let elapsed = start.duration(to: .now).components
        return elapsed.seconds * 1000 + elapsed.attoseconds / 1_000_000_000_000_000
    }
}

enum TranscriberError: Error {
    case modelMissing
}
