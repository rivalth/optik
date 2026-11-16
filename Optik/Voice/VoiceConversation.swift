import AVFoundation
import Foundation
import OptikCore
import os

/// One conversation on the island: listen, transcribe, ask the model, speak.
///
/// `docs/02-mimari.md` 3: microphone → endpoint detection → Whisper (on device) →
/// Claude (streamed) → ElevenLabs (streamed, sentence by sentence). The island
/// controller owns the visuals; this class reports what to show through callbacks.
@MainActor
final class VoiceConversation {
    // MARK: Callbacks to the island

    /// The live transcript while the user talks.
    var onTranscript: (String) -> Void = { _ in }
    /// The reply text so far (streamed).
    var onReply: (String) -> Void = { _ in }
    /// The user interrupted a reply; show listening again.
    var onListenAgain: () -> Void = {}
    /// Close the island.
    var onFinish: () -> Void = {}
    /// The microphone turned on or off (green dot).
    var onMicrophoneChange: (Bool) -> Void = { _ in }

    // MARK: Services

    private let transcriber: WhisperTranscriber
    private let llm: any LLMClient
    private let synthesizer: ElevenLabsSynthesizer
    private let audio = VoiceAudio()
    private let systemSpeaker = SystemSpeaker()
    private lazy var recorder = UtteranceRecorder { [weak self] event, id in
        Task { @MainActor in self?.handle(event, utterance: id) }
    }

    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Optik", category: "latency")
    private let voiceLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Optik", category: "voice")

    // MARK: State

    private enum Stage: Equatable {
        case off
        /// "Efendim?" is playing.
        case greeting
        case listening
        /// Transcribing, asking, speaking.
        case responding
        /// The reply was spoken; listening for a follow-up until the silence timeout.
        case lingering
    }

    private var stage: Stage = .off {
        didSet { if stage != oldValue { stageSince = .now } }
    }
    private var stageSince = ContinuousClock.now
    private(set) var isActive = false
    private var trigger: TurnContext.Trigger = .shortcut
    private var history = ConversationHistory()
    private var latency = TurnLatency()
    private var summonedAt: UInt64 = 0
    private var speechEndedAt: Double?
    private var turnTask: Task<Void, Never>?
    private var partialTask: Task<Void, Never>?
    private var partialTimer: Task<Void, Never>?
    private var silenceTimer: Task<Void, Never>?
    private var greetingTask: Task<Void, Never>?
    private var bargeInCheck: Task<Void, Never>?
    private var systemPrompt: String?
    private var models: LLMModels?

    /// `docs/01-urun.md` 1.1: 8 s of silence closes the island.
    static let silenceTimeout: Duration = .seconds(8)
    static let partialInterval: Duration = .milliseconds(900)
    /// How long a turn waits for a loading model before Optik says it is getting ready.
    static let preparingNoticeDelay: Duration = .milliseconds(1500)
    /// Talking over a reply must last this long, clearly louder than the room.
    static let bargeInWait: Duration = .milliseconds(350)
    static let bargeInStrongSpeech = 0.25
    /// The start of a reply is not interrupted: the echo canceller is still settling.
    static let bargeInGrace: Duration = .milliseconds(600)

    private(set) var lastLatency: TurnLatency?

    init(transcriber: WhisperTranscriber, llm: any LLMClient, synthesizer: ElevenLabsSynthesizer) {
        self.transcriber = transcriber
        self.llm = llm
        self.synthesizer = synthesizer
        loadPromptFiles()
        systemSpeaker.prewarm()
    }

    private func loadPromptFiles() {
        if let url = Bundle.main.url(forResource: "sistem-istemi", withExtension: "md"),
           let markdown = try? String(contentsOf: url, encoding: .utf8) {
            systemPrompt = SystemPrompt.extract(fromMarkdown: markdown)
        }
        if let url = Bundle.main.url(forResource: "modeller", withExtension: "json"),
           let data = try? Data(contentsOf: url) {
            models = try? LLMModels.decode(from: data)
        }
    }

    // MARK: Lifecycle

    /// The island opened. Starts the microphone and warms every connection while
    /// "Efendim?" plays, so nothing loads after the user stops talking.
    func begin(trigger: TurnContext.Trigger, summonedAt: UInt64) {
        self.trigger = trigger
        self.summonedAt = summonedAt
        latency = TurnLatency()
        isActive = true
        stage = .greeting
        speechEndedAt = nil
        recorder.resetDetector()

        let llm = self.llm, synthesizer = self.synthesizer, transcriber = self.transcriber
        Task.detached(priority: .userInitiated) {
            async let a: Void = llm.warmUp()
            async let b: Void = synthesizer.warmUp()
            async let c: Void? = try? transcriber.prepareSelectedModel()
            _ = await (a, b, c)
        }
        Task { await startMicrophone() }
    }

    /// Plays "Efendim?" (a fixed phrase), then calls `done`.
    func playGreeting(_ phrase: FixedPhrases.Phrase?, onStart: @escaping () -> Void, done: @escaping () -> Void) {
        greetingTask?.cancel()
        greetingTask = Task {
            if let phrase, let url = FixedPhrases.url(for: phrase.id) {
                onStart()
                try? await audio.play(file: url)
            } else {
                systemSpeaker.onStart = onStart
                await systemSpeaker.speak(phrase?.metin ?? String(localized: "Efendim?"))
            }
            guard !Task.isCancelled, stage == .greeting else { return }
            done()
        }
    }

    /// "Efendim?" finished: listening starts.
    func greeted() {
        guard stage == .greeting else { return }
        stage = .listening
        restartSilenceTimer()
    }

    /// The island closed (Esc, timeout, click). Stops everything and the microphone.
    func end() {
        guard isActive else { return }
        isActive = false
        stage = .off
        greetingTask?.cancel()
        turnTask?.cancel()
        bargeInCheck?.cancel()
        partialTask?.cancel()
        partialTimer?.cancel()
        silenceTimer?.cancel()
        systemSpeaker.stop()
        audio.stopSpeech()
        recorder.reset()
        Task {
            await audio.stopCapture()
            onMicrophoneChange(false)
        }
    }

    // MARK: Microphone

    private func startMicrophone() async {
        guard await Self.microphoneAllowed() else {
            await reply(withFallback: String(localized: "Mikrofon izni yok. Sistem Ayarları'nda Optik'e mikrofon izni verir misin?"))
            return
        }
        let recorder = self.recorder
        do {
            try await audio.startCapture { samples, time in recorder.process(samples, at: time) }
            guard isActive else { await audio.stopCapture(); return }
            onMicrophoneChange(true)
        } catch {
            voiceLog.error("microphone did not start")
            await reply(withFallback: String(localized: "Mikrofonu açamadım."))
        }
    }

    static func microphoneAllowed() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    // MARK: Endpoint events

    private func handle(_ event: EndpointDetector.Event, utterance: Int) {
        guard isActive else { return }
        voiceLog.info("\(String(describing: event), privacy: .public) in stage \(String(describing: self.stage), privacy: .public)")
        switch event {
        case .speechStarted:
            speechStarted()
        case .speechEnded(let time):
            speechEnded(at: time, utterance: utterance)
        }
    }

    private func speechStarted() {
        silenceTimer?.cancel()
        switch stage {
        case .greeting:
            // Talking over "Efendim?" is fine: stop it and listen.
            greetingTask?.cancel()
            audio.stopSpeech()
            systemSpeaker.stop()
            stage = .listening
            onTranscript("")
        case .responding, .lingering:
            // Barge-in. Without echo cancellation Optik would hear its own voice,
            // so it only works when the system's voice processing is on.
            guard audio.hasEchoCancellation, !systemSpeaker.isSpeaking else { return }
            confirmBargeIn()
        case .listening, .off:
            break
        }
        startPartialTranscripts()
    }

    /// Room noise and leftover echo also cross the start threshold, so a barge-in
    /// counts only when the user keeps talking clearly above the room.
    private func confirmBargeIn() {
        guard stageSince.duration(to: .now) >= Self.bargeInGrace else { return }
        let stageAtStart = stage
        bargeInCheck?.cancel()
        bargeInCheck = Task {
            try? await Task.sleep(for: Self.bargeInWait)
            guard !Task.isCancelled, stage == stageAtStart, recorder.isSpeaking else { return }
            let strong = recorder.strongSpeech
            voiceLog.info("barge-in check: \(strong, format: .fixed(precision: 2), privacy: .public) s strong speech")
            guard strong >= Self.bargeInStrongSpeech else { return }
            interrupt()
        }
    }

    private func interrupt() {
        turnTask?.cancel()
        audio.stopSpeech()
        stage = .listening
        onListenAgain()
    }

    private func speechEnded(at time: Double, utterance: Int) {
        partialTimer?.cancel()
        guard stage == .listening else { return }
        speechEndedAt = time
        let samples = recorder.snapshot()
        guard samples.id == utterance, samples.samples.count > VoiceAudio.frameLength * 10 else {
            restartSilenceTimer()
            return
        }
        stage = .responding
        let audioSamples = samples.samples
        turnTask = Task { await respond(to: audioSamples, endedAt: time) }
    }

    // MARK: Partial transcripts

    private func startPartialTranscripts() {
        partialTimer?.cancel()
        partialTimer = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.partialInterval)
                guard !Task.isCancelled, stage == .listening, recorder.isSpeaking, partialTask == nil else { continue }
                let snapshot = recorder.snapshot()
                let transcriber = self.transcriber
                partialTask = Task {
                    let text = try? await transcriber.transcribe(snapshot.samples)
                    partialTask = nil
                    guard let text, !text.isEmpty, stage == .listening, recorder.snapshot().id == snapshot.id else { return }
                    onTranscript(text)
                }
            }
        }
    }

    // MARK: A turn

    private func respond(to samples: [Float], endedAt: Double) async {
        // A partial transcript may still be running; the final one waits behind it.
        if let partialTask { partialTask.cancel(); _ = await partialTask.value }

        // The model may still be loading (the first time after a download it is
        // compiled for this Mac). Say so instead of going quiet.
        let notice: Task<Void, Never>? = await transcriber.isLoaded ? nil : Task {
            try? await Task.sleep(for: Self.preparingNoticeDelay)
            guard !Task.isCancelled else { return }
            await say(String(localized: "Bir saniye, hazırlanıyorum."))
        }
        let text: String
        do {
            text = try await transcriber.transcribe(samples)
            notice?.cancel()
            await notice?.value
        } catch TranscriberError.modelMissing {
            notice?.cancel()
            await modelMissing()
            return
        } catch {
            notice?.cancel()
            guard !Task.isCancelled else { return }
            voiceLog.error("transcription failed")
            await reply(withFallback: String(localized: "Seni duyamadım, bir daha söyler misin?"))
            return
        }
        guard !Task.isCancelled else { return }
        let transcriptReady = Self.now
        latency.speechEndToTranscript = (transcriptReady - endedAt) * 1000
        voiceLog.info("transcript \(text.count, privacy: .public) chars in \(self.latency.speechEndToTranscript ?? 0, format: .fixed(precision: 0), privacy: .public) ms")
        #if DEBUG
        voiceLog.debug("transcript: \(text, privacy: .public)")
        #endif

        guard !text.isEmpty, !Self.isNoise(text) else {
            stage = .listening
            restartSilenceTimer()
            return
        }
        onTranscript(text)

        if LocalCommand(text) == .stop {
            onFinish()
            return
        }
        await ask(text, transcriptReady: transcriptReady)
    }

    /// Whisper's habit of hearing "Altyazı M.K." or "İzlediğiniz için teşekkürler" in silence.
    private static func isNoise(_ text: String) -> Bool {
        let lowered = text.lowercased(with: Locale(identifier: "tr_TR"))
        return lowered.hasPrefix("altyazı") || lowered.contains("izlediğiniz için")
            || lowered.trimmingCharacters(in: .punctuationCharacters.union(.whitespaces)).isEmpty
    }

    private func ask(_ userText: String, transcriptReady: Double) async {
        guard KeychainStore.has(.anthropic) else {
            await echo(userText, transcriptReady: transcriptReady)
            return
        }
        guard let systemPrompt, let models else {
            await reply(withFallback: String(localized: "İstem dosyası eksik, Optik kurulumunu kontrol et."))
            return
        }
        let context = TurnContext(userName: UserDefaults.standard.string(forKey: SettingsKey.userName),
                                  now: .now, trigger: trigger)
        let request = LLMRequest(model: models.voice, system: systemPrompt, turnContext: context.text,
                                 messages: history.request(adding: userText))

        var replyText = ""
        var chunker = SentenceChunker()
        var limiter = SpokenReplyLimiter()
        var firstToken: Double?
        let speech = SpeechQueue(conversation: self)

        do {
            for try await event in llm.stream(request) {
                guard !Task.isCancelled else { break }
                switch event {
                case .text(let delta):
                    if firstToken == nil {
                        firstToken = Self.now
                        latency.transcriptToFirstToken = (firstToken! - transcriptReady) * 1000
                    }
                    replyText += delta
                    onReply(replyText)
                    for sentence in chunker.append(delta) where limiter.shouldSpeak(sentence) {
                        speech.say(sentence, firstToken: firstToken!)
                    }
                case .finished(let stopReason, let usage):
                    if let rest = chunker.finish(), limiter.shouldSpeak(rest) {
                        speech.say(rest, firstToken: firstToken ?? Self.now)
                    }
                    voiceLog.info("""
                        reply \(stopReason ?? "-", privacy: .public) in=\(usage.inputTokens, privacy: .public) \
                        out=\(usage.outputTokens, privacy: .public) cache_read=\(usage.cacheReadInputTokens, privacy: .public) \
                        cache_write=\(usage.cacheCreationInputTokens, privacy: .public)
                        """)
                    if stopReason == "refusal", replyText.isEmpty {
                        replyText = String(localized: "Bunda yardımcı olamam.")
                        onReply(replyText)
                        speech.say(replyText, firstToken: firstToken ?? Self.now)
                    }
                }
            }
        } catch is CancellationError {
            speech.cancel()
            return
        } catch let error as LLMError {
            speech.cancel()
            guard !Task.isCancelled else { return }
            await reply(withFallback: Self.message(for: error))
            return
        } catch {
            speech.cancel()
            guard !Task.isCancelled else { return }
            await reply(withFallback: String(localized: "Bir şeyler ters gitti, bir daha dener misin?"))
            return
        }
        guard !Task.isCancelled else { speech.cancel(); return }

        await speech.finish()
        guard !Task.isCancelled else { return }
        history.append(user: userText, assistant: replyText)
        finishTurn()
    }

    /// Without a Claude key Optik repeats what it heard, so microphone, speech
    /// recognition, voice and latency can be tried end to end.
    private func echo(_ userText: String, transcriptReady: Double) async {
        let text = String(localized: "Şunu duydum: \(userText)")
        latency.transcriptToFirstToken = 0
        onReply(text)
        let speech = SpeechQueue(conversation: self)
        speech.say(text, firstToken: transcriptReady)
        await speech.finish()
        guard !Task.isCancelled else { speech.cancel(); return }
        finishTurn()
    }

    private static func message(for error: LLMError) -> String {
        switch error {
        case .missingKey: String(localized: "Claude API anahtarı yok. Ayarlar'daki Ses bölümünden ekler misin?")
        case .offline: String(localized: "İnternete bağlanamadım. Biraz sonra tekrar dener misin?")
        case .http(let status, _) where status == 401: String(localized: "Claude API anahtarı geçersiz görünüyor. Ayarlar'dan kontrol eder misin?")
        case .http(let status, _) where status == 429 || status == 529: String(localized: "Claude şu an çok yoğun. Biraz sonra tekrar dener misin?")
        case .http, .malformedResponse: String(localized: "Claude'dan yanıt alamadım. Bir daha dener misin?")
        }
    }

    /// Shows and speaks a short note without ending the turn.
    private func say(_ text: String) async {
        guard isActive else { return }
        onReply(text)
        let speech = SpeechQueue(conversation: self, effect: false)
        speech.say(text, firstToken: Self.now)
        await speech.finish()
    }

    /// Shows and speaks a message (errors, missing setup) in Optik's voice, or the
    /// system voice when there is no ElevenLabs key or no network.
    private func reply(withFallback text: String) async {
        guard isActive else { return }
        stage = .responding
        onReply(text)
        let speech = SpeechQueue(conversation: self, effect: false)
        speech.say(text, firstToken: Self.now)
        await speech.finish()
        guard isActive, !Task.isCancelled else { speech.cancel(); return }
        finishTurn()
    }

    private func modelMissing() async {
        let transcriber = self.transcriber
        Task.detached { try? await transcriber.downloadSelectedModel() }
        await reply(withFallback: String(localized: "Konuşmayı tanıma modelini indiriyorum. Bitince seni duyabileceğim, ilerlemeyi Ayarlar'da görebilirsin."))
    }

    /// The reply was spoken: keep listening for a follow-up until the silence timeout.
    private func finishTurn() {
        latency.total = Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW) &- summonedAt) / 1e6
        log.info("turn \(self.latency.json, privacy: .public)")
        if let budget = latency.speechEndToFirstAudio {
            log.info("speech end to first audio: \(budget, format: .fixed(precision: 0), privacy: .public) ms")
        }
        lastLatency = latency
        latency = TurnLatency()
        stage = .lingering
        restartSilenceTimer()
    }

    private func restartSilenceTimer() {
        silenceTimer?.cancel()
        silenceTimer = Task {
            try? await Task.sleep(for: Self.silenceTimeout)
            guard !Task.isCancelled, isActive, !recorder.isSpeaking else { return }
            onFinish()
        }
    }

    // MARK: Latency from the island

    func recordIslandLatency(wakeToIsland: Double?, wakeToEfendim: Double?) {
        if let wakeToIsland { latency.wakeToIsland = wakeToIsland }
        if let wakeToEfendim { latency.wakeToEfendim = wakeToEfendim }
    }

    fileprivate func firstAudioPlayed(firstToken: Double) {
        guard latency.firstTokenToFirstAudio == nil else { return }
        latency.firstTokenToFirstAudio = (Self.now - firstToken) * 1000
    }

    static var now: Double { Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) / 1e9 }

    // MARK: Speech queue

    /// Speaks sentences in order: each is synthesized while the previous one plays.
    /// Falls back to the system voice if ElevenLabs is unavailable.
    @MainActor
    private final class SpeechQueue {
        private weak var conversation: VoiceConversation?
        private var sentences: [String] = []
        private var worker: Task<Void, Never>?
        private var stream: VoiceAudio.SpeechStream?
        private var useSystemVoice: Bool
        private var cancelled = false
        private var playedEffect: Bool
        /// Only real replies count toward the turn's latency.
        private let measures: Bool

        /// `effect`: the happy sound before the voice, for real replies, not errors.
        init(conversation: VoiceConversation, effect: Bool = true) {
            self.conversation = conversation
            useSystemVoice = !conversation.synthesizer.hasKey
            playedEffect = !effect
            measures = effect
        }

        func say(_ sentence: String, firstToken: Double) {
            guard !cancelled else { return }
            sentences.append(SpeechText.normalized(sentence))
            guard worker == nil else { return }
            worker = Task { await run(firstToken: firstToken) }
        }

        private func run(firstToken: Double) async {
            guard let conversation else { return }
            while !sentences.isEmpty, !cancelled {
                let sentence = sentences.removeFirst()
                if useSystemVoice {
                    await conversation.systemSpeaker.speak(sentence)
                    continue
                }
                do {
                    if stream == nil {
                        if !playedEffect, let url = Bundle.main.url(forResource: SoundEffect.mutlu.rawValue, withExtension: "wav") {
                            // The effect first, the voice right after it on the same player.
                            playedEffect = true
                            Task { try? await conversation.audio.play(file: url) }
                        }
                        let measures = self.measures
                        stream = try await conversation.audio.beginSpeech(format: conversation.synthesizer.format) { [weak conversation] in
                            guard measures else { return }
                            Task { @MainActor in conversation?.firstAudioPlayed(firstToken: firstToken) }
                        }
                    }
                    guard let stream else { continue }
                    for try await chunk in conversation.synthesizer.synthesize(sentence) {
                        guard !cancelled else { return }
                        conversation.audio.enqueue(chunk, on: stream)
                    }
                } catch {
                    guard !cancelled else { return }
                    conversation.voiceLog.error("speech synthesis failed, using the system voice")
                    useSystemVoice = true
                    if let stream { await conversation.audio.finish(stream) }
                    await conversation.systemSpeaker.speak(sentence)
                }
            }
            worker = nil
        }

        /// Waits until everything queued has been spoken.
        func finish() async {
            while let worker {
                await worker.value
                if self.worker == worker { self.worker = nil }
            }
            if let stream, let conversation, !cancelled { await conversation.audio.finish(stream) }
        }

        func cancel() {
            cancelled = true
            worker?.cancel()
            conversation?.audio.stopSpeech()
            conversation?.systemSpeaker.stop()
        }
    }
}
