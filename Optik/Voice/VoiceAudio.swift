import AVFoundation
import OptikCore
import os

/// The microphone and Optik's speech on one audio engine.
///
/// Both share an engine so the system's voice processing can cancel Optik's own
/// voice from the microphone (echo cancellation); without it Optik would hear itself
/// and interrupt its own replies. Runs only during a conversation: the microphone is
/// off at rest (`docs/02-mimari.md` 7).
///
/// All engine work happens on a private serial queue, never on the main thread.
final class VoiceAudio: @unchecked Sendable {
    /// 20 ms of 16 kHz mono audio, the unit the endpoint detector and Whisper use.
    static let captureFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    static let frameLength = 320

    typealias FrameHandler = @Sendable (_ samples: [Float], _ time: Double) -> Void

    private let queue = DispatchQueue(label: "optik.voice-audio", qos: .userInteractive)
    private let engine = AVAudioEngine()
    private let speechPlayer = AVAudioPlayerNode()
    private var converter: AVAudioConverter?
    private var pending: [Float] = []
    private var onFrame: FrameHandler?
    private var isConfigured = false
    private(set) var hasEchoCancellation = false
    /// Voice processing was switched off while idle and comes back with the next capture.
    private var releasedVoiceProcessing = false
    private var speechFormat: AVAudioFormat?
    /// Bumped by `stopSpeech`, so buffers scheduled before it never report completion.
    private var speechGeneration = 0
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Optik", category: "audio")

    private(set) var isCapturing = false

    // MARK: Engine

    private func configureIfNeeded() {
        guard !isConfigured else { return }
        isConfigured = true
        engine.attach(speechPlayer)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24_000, channels: 1, interleaved: false)!
        engine.connect(speechPlayer, to: engine.mainMixerNode, format: format)
        speechFormat = format
        setVoiceProcessing(true)
    }

    /// Voice processing needs the output side at the microphone's sample rate: the
    /// built-in mic runs at 48 kHz while the speakers may run at 44.1 kHz, and the
    /// unit refuses to start when the two differ (error -10875).
    private func setVoiceProcessing(_ enabled: Bool) {
        do {
            try engine.inputNode.setVoiceProcessingEnabled(enabled)
        } catch {
            log.error("voice processing could not be switched")
            hasEchoCancellation = false
            return
        }
        hasEchoCancellation = enabled
        if enabled {
            // Automatic gain lifts the room between sentences until it sounds like
            // speech; the endpoint detector needs the room at its real level.
            engine.inputNode.isVoiceProcessingAGCEnabled = false
            // Keep music and calls at normal volume while Optik listens.
            engine.inputNode.voiceProcessingOtherAudioDuckingConfiguration =
                AVAudioVoiceProcessingOtherAudioDuckingConfiguration(enableAdvancedDucking: false, duckingLevel: .min)
            let inputRate = engine.inputNode.outputFormat(forBus: 0).sampleRate
            let outputChannels = max(1, engine.outputNode.outputFormat(forBus: 0).channelCount)
            engine.connect(engine.mainMixerNode, to: engine.outputNode,
                           format: AVAudioFormat(standardFormatWithSampleRate: inputRate, channels: outputChannels))
        } else {
            engine.connect(engine.mainMixerNode, to: engine.outputNode, format: nil)
        }
    }

    /// Starts the engine; without echo cancellation if voice processing will not start.
    private func startEngine() throws {
        configureIfNeeded()
        guard !engine.isRunning else { return }
        if releasedVoiceProcessing {
            releasedVoiceProcessing = false
            let hadTap = isCapturing || onFrame != nil
            if hadTap { engine.inputNode.removeTap(onBus: 0) }
            setVoiceProcessing(true)
            if hadTap { installTap() }
        }
        engine.prepare()
        do {
            try engine.start()
        } catch where hasEchoCancellation {
            log.error("voice processing did not start, continuing without echo cancellation")
            let hadTap = isCapturing || onFrame != nil
            if hadTap { engine.inputNode.removeTap(onBus: 0) }
            setVoiceProcessing(false)
            engine.prepare()
            try engine.start()
            if hadTap { installTap() }
        }
    }

    // MARK: Capture

    /// Starts the microphone. Frames arrive on the audio queue.
    func startCapture(onFrame: @escaping FrameHandler) async throws {
        try await perform {
            self.onFrame = onFrame
            guard !self.isCapturing else { return }
            self.pending.removeAll(keepingCapacity: true)
            try self.startEngine()
            self.installTap()
            guard self.converter != nil else {
                self.onFrame = nil
                throw VoiceAudioError.noMicrophone
            }
            self.isCapturing = true
        }
    }

    /// Taps the microphone in its current format (it changes with voice processing).
    private func installTap() {
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, let converter = AVAudioConverter(from: inputFormat, to: Self.captureFormat) else {
            converter = nil
            return
        }
        // With voice processing the first channel is the cleaned-up voice; the
        // others are raw microphones and must not be mixed back in.
        converter.downmix = false
        converter.channelMap = [0]
        self.converter = converter
        // Convert inside the tap: the engine reuses its buffer once the block returns.
        input.installTap(onBus: 0, bufferSize: 1_024, format: inputFormat) { [weak self] buffer, _ in
            guard let samples = Self.convert(buffer, with: converter) else { return }
            self?.queue.async { self?.deliver(samples) }
        }
    }

    func stopCapture() async {
        await perform {
            guard self.isCapturing else { return }
            self.engine.inputNode.removeTap(onBus: 0)
            self.isCapturing = false
            self.onFrame = nil
            self.pending.removeAll()
            self.stopEngineIfIdle()
        }
    }

    private static func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter) -> [Float]? {
        let ratio = captureFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: captureFormat, frameCapacity: capacity) else { return nil }
        var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let channel = output.floatChannelData?[0] else { return nil }
        return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
    }

    private func deliver(_ samples: [Float]) {
        guard let onFrame else { return }
        pending.append(contentsOf: samples)
        let now = Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) / 1e9
        while pending.count >= Self.frameLength {
            let frame = Array(pending.prefix(Self.frameLength))
            pending.removeFirst(Self.frameLength)
            onFrame(frame, now)
        }
    }

    // MARK: Speech

    /// Plays a WAV file (a fixed phrase) and returns when it ends or is stopped.
    /// Reading, converting and scheduling all happen on the audio queue.
    func play(file url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    try self.startEngine()
                    let file = try AVAudioFile(forReading: url)
                    guard let source = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
                        throw VoiceAudioError.unreadableFile
                    }
                    try file.read(into: source)
                    guard let format = self.speechFormat, let buffer = Self.resample(source, to: format) else {
                        throw VoiceAudioError.unreadableFile
                    }
                    self.speechPlayer.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in
                        continuation.resume()
                    }
                    if !self.speechPlayer.isPlaying { self.speechPlayer.play() }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// A stream of synthesized speech: chunks are scheduled as they arrive.
    final class SpeechStream: @unchecked Sendable {
        fileprivate weak var audio: VoiceAudio?
        fileprivate let generation: Int
        fileprivate let format: AVAudioFormat
        fileprivate var scheduled = 0
        fileprivate var played = 0
        fileprivate var finished = false
        fileprivate var completion: CheckedContinuation<Void, Never>?
        /// Called on the audio queue when the first chunk starts playing.
        fileprivate var onFirstAudio: (@Sendable () -> Void)?

        fileprivate init(audio: VoiceAudio, generation: Int, format: AVAudioFormat) {
            self.audio = audio
            self.generation = generation
            self.format = format
        }
    }

    /// Opens a stream for 16-bit PCM at `format`.
    func beginSpeech(format pcm: PCMFormat, onFirstAudio: @escaping @Sendable () -> Void) async throws -> SpeechStream {
        try await perform {
            try self.startEngine()
            let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: pcm.sampleRate, channels: 1, interleaved: false)!
            let stream = SpeechStream(audio: self, generation: self.speechGeneration, format: format)
            stream.onFirstAudio = onFirstAudio
            return stream
        }
    }

    func enqueue(_ data: Data, on stream: SpeechStream) {
        queue.async {
            guard stream.generation == self.speechGeneration, let target = self.speechFormat else { return }
            let count = data.count / 2
            guard count > 0, let source = AVAudioPCMBuffer(pcmFormat: stream.format, frameCapacity: AVAudioFrameCount(count)) else { return }
            source.frameLength = AVAudioFrameCount(count)
            let channel = source.floatChannelData![0]
            data.withUnsafeBytes { raw in
                let samples = raw.bindMemory(to: Int16.self)
                for index in 0..<count { channel[index] = Float(Int16(littleEndian: samples[index])) / 32_768 }
            }
            guard let buffer = Self.resample(source, to: target) else { return }
            stream.scheduled += 1
            let first = stream.scheduled == 1
            self.speechPlayer.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                self?.queue.async { self?.chunkPlayed(on: stream) }
            }
            if !self.speechPlayer.isPlaying { self.speechPlayer.play() }
            if first { stream.onFirstAudio?() }
        }
    }

    /// Waits until every chunk of the stream has played, or speech was stopped.
    func finish(_ stream: SpeechStream) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                guard stream.generation == self.speechGeneration, stream.played < stream.scheduled else {
                    continuation.resume(); return
                }
                stream.finished = true
                stream.completion = continuation
            }
        }
    }

    private func chunkPlayed(on stream: SpeechStream) {
        stream.played += 1
        if stream.finished, stream.played >= stream.scheduled, let completion = stream.completion {
            stream.completion = nil
            completion.resume()
        }
    }

    /// Silences Optik at once (barge-in, Esc). Pending waits return immediately.
    func stopSpeech() {
        queue.async {
            self.speechGeneration += 1
            self.speechPlayer.stop()
            self.stopEngineIfIdle()
        }
    }

    private func stopEngineIfIdle() {
        guard !isCapturing, !speechPlayer.isPlaying, engine.isRunning else { return }
        engine.stop()
        // Voice processing keeps the microphone to itself even with the engine
        // stopped, and the wake word listener would hear nothing.
        if hasEchoCancellation {
            setVoiceProcessing(false)
            releasedVoiceProcessing = true
        }
    }

    /// Releases the engine after a conversation, when nothing plays or listens.
    func idle() {
        queue.async { self.stopEngineIfIdle() }
    }

    // MARK: Helpers

    private func perform<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do { continuation.resume(returning: try work()) } catch { continuation.resume(throwing: error) }
            }
        }
    }

    private func perform(_ work: @escaping @Sendable () -> Void) async {
        await withCheckedContinuation { continuation in
            queue.async { work(); continuation.resume() }
        }
    }

    private static func resample(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        if buffer.format == format { return buffer }
        guard let converter = AVAudioConverter(from: buffer.format, to: format) else { return nil }
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed { status.pointee = .endOfStream; return nil }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil ? output : nil
    }
}

enum VoiceAudioError: Error {
    case noMicrophone
    case unreadableFile
}
