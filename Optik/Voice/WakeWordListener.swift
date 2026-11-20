@preconcurrency import AVFoundation
import OptikCore
import os

/// Listens for "Optik" on its own audio engine while the island is closed
/// (`docs/02-mimari.md` 3.1).
///
/// The room is watched with the same voice activity detection as the conversation,
/// which costs almost nothing. When someone starts talking, the first second goes
/// to the speech model that is already loaded for conversations, and Optik wakes
/// only if that speech starts with its name. A quiet room runs no model at all.
///
/// No voice processing here: the conversation's engine does that once Optik is
/// awake. All audio work happens on a private serial queue, never on the main thread.
final class WakeWordListener: WakeWordDetector, @unchecked Sendable {
    /// How much of an utterance is checked for the name: "Optik" takes about half a second.
    static let checkedDuration = 1.0
    /// Audio kept from before speech was detected, so the word's start is not cut.
    static let preRoll = 0.25

    private let transcriber: WhisperTranscriber
    /// A fast model of its own, used while the user picked the large one.
    private let fastTranscriber = WhisperTranscriber(model: { SpeechModel.forWakeWord })
    private let queue = DispatchQueue(label: "optik.wake-word", qos: .userInitiated)
    private var engine: AVAudioEngine?
    private var onEvent: (@Sendable (WakeWordEvent) -> Void)?
    private var generation = 0
    /// When the microphone last delivered audio, ns since boot. A new engine opened
    /// while the conversation's engine is still letting go of the microphone can
    /// run without ever receiving audio; the watchdog then builds it again.
    private var lastAudio: UInt64 = 0
    private var watchdog: DispatchSourceTimer?
    private static let silentMicrophoneTimeout: UInt64 = 1_500_000_000

    private var detector = EndpointDetector()
    private var pending: [Float] = []
    /// The last couple of seconds, for the pre-roll.
    private var history: [Float] = []
    private var historyStart = 0
    private var samplesSeen = 0
    /// Where the utterance being collected starts, in samples since `start`.
    private var utteranceStart: Int?
    private var isChecking = false
    /// The newest word that rose while a check ran; it is checked next.
    private var waitingStart: Int?
    /// Frame levels of the last 0.4 s, to notice a word starting after a gap.
    private var recentLevels = [Double](repeating: 0, count: 20)
    private var recentIndex = 0
    private var lastWindowStart = Int.min / 2
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Optik", category: "wake")

    init(transcriber: WhisperTranscriber) {
        self.transcriber = transcriber
    }

    func start(onEvent: @escaping @Sendable (WakeWordEvent) -> Void) {
        queue.async { self.startOnQueue(onEvent) }
        let fast = fastTranscriber
        let needsOwnModel = SpeechModel.forWakeWord != SpeechModel.selected
        Task.detached(priority: .utility) {
            if needsOwnModel { try? await fast.prepare() } else { await fast.unload() }
        }
    }

    /// The transcriber for wake checks: the shared one, unless the chosen model is
    /// too slow to check every sound with.
    private var checkTranscriber: WhisperTranscriber {
        SpeechModel.forWakeWord == SpeechModel.selected ? transcriber : fastTranscriber
    }

    func stop() {
        queue.async { self.stopOnQueue() }
    }

    private func startOnQueue(_ onEvent: @escaping @Sendable (WakeWordEvent) -> Void) {
        self.onEvent = onEvent
        guard engine == nil else { return }
        startEngine()
        startWatchdog()
    }

    private func startEngine() {
        resetStream()
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0,
              let converter = AVAudioConverter(from: inputFormat, to: VoiceAudio.captureFormat)
        else { log.error("no microphone for the wake word"); return }
        converter.channelMap = [0]
        generation += 1
        let generation = self.generation
        // 100 ms buffers: fewer wake-ups than the conversation's 20 ms frames.
        let bufferSize = AVAudioFrameCount(inputFormat.sampleRate / 10)
        input.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
            guard let self, let samples = Self.convert(buffer, with: converter, from: inputFormat) else { return }
            self.queue.async { self.push(samples, generation: generation) }
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            log.error("wake word listener could not start")
            return
        }
        self.engine = engine
        lastAudio = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        log.info("listening for the wake word")
    }

    private func stopEngine() {
        generation += 1
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
        resetStream()
    }

    private func stopOnQueue() {
        watchdog?.cancel()
        watchdog = nil
        onEvent = nil
        guard engine != nil else { return }
        stopEngine()
        log.info("wake word listener stopped")
    }

    private func startWatchdog() {
        watchdog?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(200))
        timer.setEventHandler { [weak self] in
            guard let self, self.onEvent != nil else { return }
            let silentFor = clock_gettime_nsec_np(CLOCK_UPTIME_RAW) &- self.lastAudio
            guard self.engine == nil || silentFor > Self.silentMicrophoneTimeout else { return }
            self.log.info("no audio from the microphone, starting the wake word listener again")
            self.stopEngine()
            self.startEngine()
        }
        timer.resume()
        watchdog = timer
    }

    private func resetStream() {
        detector = EndpointDetector()
        pending.removeAll(keepingCapacity: true)
        history.removeAll(keepingCapacity: true)
        historyStart = 0
        samplesSeen = 0
        utteranceStart = nil
        waitingStart = nil
        sentenceStart = nil
        lastLoud = 0
        recentLevels = [Double](repeating: 0, count: recentLevels.count)
        lastWindowStart = Int.min / 2
    }

    /// A rise this many dB over the quietest of the last 0.4 s starts a new word.
    static let riseOverGap = 12.0
    /// Windows inside one long stretch of talk start at least this far apart.
    static let windowSpacing = 0.5
    /// A rising word must also be this many dB above the room's loud end.
    static let overBackground = 4.0
    /// A sentence after the name ends after this long without speech.
    static let sentenceEndSilence = 0.8
    /// A sentence after the name is cut off after this long.
    static let longestSentence = 15.0

    /// Where the sentence that started with the name begins, while it is recorded.
    private var sentenceStart: Int?
    /// The last frame clearly louder than the room, in samples since `start`.
    private var lastLoud = 0

    // MARK: Audio

    private func push(_ samples: [Float], generation: Int) {
        pushOnQueue(samples, generation: generation)
    }

    private func pushOnQueue(_ samples: [Float], generation: Int) {
        guard generation == self.generation else { return }
        lastAudio = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        pending.append(contentsOf: samples)
        let frame = VoiceAudio.frameLength
        var offset = 0
        while pending.count - offset >= frame {
            let samples = pending[offset..<(offset + frame)]
            offset += frame
            remember(samples)
            samplesSeen += frame
            let time = Double(samplesSeen) / 16_000
            let level = EndpointDetector.level(of: samples)
            let gap = recentLevels.min() ?? level
            recentLevels[recentIndex] = level
            recentIndex = (recentIndex + 1) % recentLevels.count
            let event = detector.process(level: level, at: time)
            if level >= max(detector.noiseFloor + 8, detector.background + 3), level > -55 {
                lastLoud = samplesSeen
            }
            if let start = sentenceStart {
                // "Optik, bugün hava nasıl": record until the user stops.
                if samplesSeen - lastLoud >= Int(Self.sentenceEndSilence * 16_000)
                    || samplesSeen - start >= Int(Self.longestSentence * 16_000) {
                    finishSentence(from: start)
                    return
                }
                continue
            }
            if case .speechStarted(let at) = event, utteranceStart == nil {
                utteranceStart = max(historyStart, Int((at - Self.preRoll) * 16_000))
                lastWindowStart = samplesSeen
            } else if utteranceStart == nil,
                      samplesSeen - lastWindowStart >= Int(Self.windowSpacing * 16_000),
                      level >= gap + Self.riseOverGap,
                      level >= detector.background + Self.overBackground,
                      level >= -50 {
                // "Optik" is short and broken by its p and t, so it may never count as
                // speech; and in a room that keeps talking the name comes in the
                // middle. Check every word that rises out of a short gap above the room.
                utteranceStart = max(historyStart, samplesSeen - Int(Self.preRoll * 16_000))
                lastWindowStart = samplesSeen
            }
            if let start = utteranceStart, samplesSeen - start >= Int((Self.checkedDuration + Self.preRoll) * 16_000) {
                utteranceStart = nil
                check(from: start)
            }
            if case .speechEnded = event, let start = utteranceStart {
                utteranceStart = nil
                check(from: start)
            }
        }
        pending.removeFirst(offset)
    }

    private func remember(_ samples: ArraySlice<Float>) {
        history.append(contentsOf: samples)
        let limit = 32_000
        if history.count > 2 * limit {
            // Never drop the sentence being recorded.
            let keepFrom = sentenceStart.map { $0 - historyStart } ?? Int.max
            let drop = min(history.count - limit, keepFrom)
            guard drop > 0 else { return }
            history.removeFirst(drop)
            historyStart += drop
        }
    }

    /// Sends the start of an utterance to the speech model and wakes on the name.
    private func check(from start: Int) {
        guard start >= historyStart else { return }
        guard !isChecking else { waitingStart = start; return }
        let samples = Array(history[(start - historyStart)...])
        let transcriber = checkTranscriber
        let generation = self.generation
        isChecking = true
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            guard await transcriber.isLoaded else {
                // Its model was let go (memory pressure) or just chosen: load it for the next word.
                Task.detached(priority: .utility) { try? await transcriber.prepare() }
                self.queue.async { self.isChecking = false }
                return
            }
            let started = ContinuousClock.now
            let text = (try? await transcriber.transcribe(samples)) ?? ""
            let saidName = WakePhrase.startsWithName(text)
            // Someone else saying "Optik" does not wake it, once it knows the user's voice.
            let heard = saidName ? await SpeakerVerifier.shared.isUser(samples, context: "wake word") : false
            let elapsed = started.duration(to: .now).components
            let ms = elapsed.seconds * 1000 + elapsed.attoseconds / 1_000_000_000_000_000
            self.queue.async {
                self.isChecking = false
                self.log.info("checked \(samples.count * 1000 / 16_000, privacy: .public) ms of speech in \(ms, privacy: .public) ms: \(heard ? "name" : "not the name", privacy: .public)")
                guard heard, generation == self.generation else {
                    if let next = self.waitingStart, generation == self.generation {
                        self.waitingStart = nil
                        self.check(from: next)
                    }
                    return
                }
                let heardAt = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
                let onEvent = self.onEvent
                if let rest = WakePhrase.remainder(text), !rest.isEmpty, self.engine != nil {
                    // The user keeps talking: record the sentence here, on the same
                    // microphone, so no word is lost switching to the conversation's.
                    self.sentenceStart = start
                    self.utteranceStart = nil
                    self.waitingStart = nil
                    self.log.info("name with a sentence, recording it")
                    onEvent?(.calledWithSentence(at: heardAt))
                } else {
                    self.stopOnQueue()
                    onEvent?(.called(at: heardAt))
                }
            }
        }
    }

    private func finishSentence(from start: Int) {
        let samples = start >= historyStart ? Array(history[(start - historyStart)...]) : history
        let onEvent = self.onEvent
        log.info("sentence after the name: \(samples.count * 1000 / 16_000, privacy: .public) ms")
        stopOnQueue()
        onEvent?(.sentence(samples))
    }

    static func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter,
                                from format: AVAudioFormat) -> [Float]? {
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * 16_000 / format.sampleRate) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: VoiceAudio.captureFormat, frameCapacity: capacity) else { return nil }
        nonisolated(unsafe) var given = false
        nonisolated(unsafe) let input = buffer
        converter.convert(to: output, error: nil) { _, status in
            if given { status.pointee = .noDataNow; return nil }
            given = true
            status.pointee = .haveData
            return input
        }
        guard let channel = output.floatChannelData?[0], output.frameLength > 0 else { return nil }
        return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
    }
}
