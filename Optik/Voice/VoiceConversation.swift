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

    private let transcriber: SentenceTranscriber
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
    /// The sentence streaming to Scribe, when Scribe is chosen.
    private var live: LiveSentence?
    private var isRunningLiveClauses = false
    private var partialTimer: Task<Void, Never>?
    private var silenceTimer: Task<Void, Never>?
    private var greetingTask: Task<Void, Never>?
    private var bargeInCheck: Task<Void, Never>?
    private var systemPrompt: String?
    /// The page of the last reply, while Optik asks whether to open it in the browser.
    private var offeredLink: URL?
    /// Commands already done while the user was still talking ("Dia'yı aç, sonra …").
    private var streamed = StreamedCommands()

    private struct StreamedCommands {
        var clauses = 0
        var outcomes: [LocalActionRunner.Outcome] = []
        /// A clause Optik can't do itself: the rest waits for the whole sentence.
        var isBlocked = false
        var isUserVerified: Bool?
    }
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

    init(transcriber: SentenceTranscriber, llm: any LLMClient, synthesizer: ElevenLabsSynthesizer) {
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
    ///
    /// `waitsForSentence`: the user said "Optik" and kept talking. The wake word
    /// listener records that sentence on its own microphone and hands it over with
    /// `hear(sentence:)`; the conversation's microphone starts only then, since two
    /// microphones at once would silence the listener's.
    func begin(trigger: TurnContext.Trigger, summonedAt: UInt64, waitsForSentence: Bool = false) {
        self.trigger = trigger
        self.summonedAt = summonedAt
        latency = TurnLatency()
        isActive = true
        stage = waitsForSentence ? .listening : .greeting
        speechEndedAt = nil
        offeredLink = nil
        streamed = StreamedCommands()
        LocalActionRunner.shared.refreshIfStale()
        recorder.resetDetector()

        let llm = self.llm, synthesizer = self.synthesizer, transcriber = self.transcriber
        let speaks = Self.speaksReplies
        Task.detached(priority: .userInitiated) {
            async let a: Void = llm.warmUp()
            async let b: Void = speaks ? synthesizer.warmUp() : ()
            async let c: Void? = try? transcriber.prepareSelectedModel()
            _ = await (a, b, c)
        }
        if waitsForSentence {
            // The listener sends the sentence within 15 s; never wait forever.
            silenceTimer?.cancel()
            silenceTimer = Task {
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled, isActive, stage == .listening else { return }
                onFinish()
            }
        } else {
            Task { await startMicrophone() }
        }
    }

    /// The sentence that started with "Optik", recorded by the wake word listener.
    func hear(sentence samples: [Float]) {
        guard isActive, stage == .listening else { return }
        silenceTimer?.cancel()
        let endedAt = Self.now
        speechEndedAt = endedAt
        stage = .responding
        // For talking over the reply and for a follow-up question.
        Task { await startMicrophone() }
        turnTask = Task { await respond(to: samples, endedAt: endedAt, startsWithName: true) }
    }

    /// Settings → Ses → "Sesli cevap ver". Off: nothing is spoken and no speech is
    /// synthesized, neither by ElevenLabs nor by the system voice.
    static var speaksReplies: Bool {
        UserDefaults.standard.object(forKey: SettingsKey.speakReplies) as? Bool ?? true
    }

    /// Plays "Efendim?" (a fixed phrase), then calls `done`.
    func playGreeting(_ phrase: FixedPhrases.Phrase?, onStart: @escaping () -> Void, done: @escaping () -> Void) {
        greetingTask?.cancel()
        guard Self.speaksReplies else {
            // Silent replies: "Efendim?" only on screen, listening starts at once.
            done()
            return
        }
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
        live?.cancel()
        live = nil
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
            speechStarted(utterance: utterance)
        case .speechEnded(let time):
            speechEnded(at: time, utterance: utterance)
        }
    }

    private func speechStarted(utterance: Int) {
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
        if stage == .listening { startLive(utterance: utterance) } else { startPartialTranscripts() }
    }

    // MARK: Streaming to Scribe

    /// With Scribe chosen, the sentence streams while the user talks and its text
    /// arrives about 0.2 s after they stop. Otherwise the live text comes from
    /// Whisper on this Mac.
    private func startLive(utterance: Int) {
        live?.cancel()
        live = nil
        guard SpeechEngine.selected == .scribe else { startPartialTranscripts(); return }
        let recorder = self.recorder
        live = LiveSentence(
            utterance: utterance, transcriber: transcriber, recorder: recorder,
            onPartial: { [weak self] text in self?.livePartial(text, utterance: utterance) },
            onUnavailable: { [weak self] in
                guard let self, self.live?.utterance == utterance else { return }
                self.live = nil
                self.startPartialTranscripts()
            }
        )
    }

    private func livePartial(_ text: String, utterance: Int) {
        guard stage == .listening, live?.utterance == utterance else { return }
        onTranscript(text)
        guard !isRunningLiveClauses else { return }
        isRunningLiveClauses = true
        let samples = recorder.snapshot().samples
        Task {
            await runFinishedClauses(of: text, samples: samples)
            isRunningLiveClauses = false
        }
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
        // The follow-up is already being spoken: stream it from its start.
        if recorder.isSpeaking { startLive(utterance: recorder.snapshot().id) }
    }

    private func speechEnded(at time: Double, utterance: Int) {
        partialTimer?.cancel()
        guard stage == .listening else { return }
        speechEndedAt = time
        let samples = recorder.snapshot()
        let live = self.live?.utterance == utterance ? self.live : nil
        if self.live !== live { self.live?.cancel() }
        self.live = nil
        guard samples.id == utterance, samples.samples.count > VoiceAudio.frameLength * 10 else {
            live?.cancel()
            restartSilenceTimer()
            return
        }
        stage = .responding
        let audioSamples = samples.samples
        // The commit goes now, while the voice check below runs.
        let transcriber = self.transcriber
        let streamed: Task<String, Error>? = live.map { live in
            Task {
                guard let session = await live.finish() else { return try await transcriber.transcribe(audioSamples) }
                return try await transcriber.finish(session, samples: audioSamples)
            }
        }
        turnTask = Task { await respond(to: audioSamples, endedAt: time, streamed: streamed) }
    }

    // MARK: Partial transcripts

    private func startPartialTranscripts() {
        partialTimer?.cancel()
        streamed = StreamedCommands()
        partialTimer = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.partialInterval)
                guard !Task.isCancelled, stage == .listening, recorder.isSpeaking, partialTask == nil else { continue }
                let snapshot = recorder.snapshot()
                let transcriber = self.transcriber
                partialTask = Task {
                    let text = try? await transcriber.transcribePartial(snapshot.samples)
                    partialTask = nil
                    guard let text, !text.isEmpty, stage == .listening, recorder.snapshot().id == snapshot.id else { return }
                    onTranscript(text)
                    await runFinishedClauses(of: text, samples: snapshot.samples)
                }
            }
        }
    }

    /// While the user talks: every clause that is finished ("Spotify'ı aç," while
    /// the song name is still coming) and that Optik can do itself is done now.
    private func runFinishedClauses(of partial: String, samples: [Float]) async {
        guard !streamed.isBlocked else { return }
        let finished = LocalCommandParser.finishedClauses(inPartial: WakePhrase.remainder(partial) ?? partial)
        guard finished.count > streamed.clauses else { return }
        // Someone else's "Spotify'ı kapat" in the room is not a command.
        if streamed.isUserVerified == nil {
            streamed.isUserVerified = await SpeakerVerifier.shared.isUser(
                samples, leniency: SpeakerVerifier.conversationLeniency, context: "command")
        }
        guard streamed.isUserVerified == true, stage == .listening else {
            streamed.isBlocked = true
            return
        }
        let runner = LocalActionRunner.shared
        for clause in finished[streamed.clauses...] {
            guard case .local(let action)? = runner.parse(clause).first else {
                streamed.isBlocked = true
                return
            }
            streamed.clauses += 1
            streamed.outcomes.append(await runner.run(action))
            onReply(streamed.outcomes.map(\.text).joined(separator: "\n"))
        }
    }

    /// Commands Optik does itself, before or instead of asking Claude. Returns false
    /// when the sentence starts with something for Claude.
    private func runLocalCommands(in text: String, transcriptReady: Double) async -> Bool {
        let runner = LocalActionRunner.shared
        let parts = LocalCommandParser.clauses(in: text)
        var clauses = runner.parse(text)
        var outcomes = streamed.outcomes
        // The clauses done while speaking come first in the whole sentence too.
        let done = min(streamed.clauses, clauses.count)
        clauses.removeFirst(done)
        streamed = StreamedCommands()

        var rest: [String] = []
        for (offset, clause) in clauses.enumerated() {
            guard case .local(let action) = clause else {
                rest = Array(parts.dropFirst(done + offset))
                break
            }
            outcomes.append(await runner.run(action))
            guard !Task.isCancelled else { return true }
        }
        guard !outcomes.isEmpty else { return false }

        let summary = outcomes.map(\.text).joined(separator: "\n")
        if !rest.isEmpty {
            // Claude hears what was already done, then the rest of the sentence.
            onReply(summary)
            await ask("(Optik az önce yaptı: \(outcomes.map(\.text).joined(separator: "; ")).) " + rest.joined(separator: ", "),
                      transcriptReady: transcriptReady)
            return true
        }
        stage = .responding
        onReply(summary)
        let failure = outcomes.first { !$0.succeeded }
        let speech = SpeechQueue(conversation: self, effect: false)
        speech.say(failure?.text ?? String(localized: "Tamam."), firstToken: Self.now)
        await speech.finish()
        guard !Task.isCancelled else { speech.cancel(); return true }
        history.append(user: text, assistant: summary)
        finishTurn()
        return true
    }

    // MARK: A turn

    private func respond(to samples: [Float], endedAt: Double, startsWithName: Bool = false,
                         streamed: Task<String, Error>? = nil) async {
        defer { if Task.isCancelled { streamed?.cancel() } }
        // A partial transcript may still be running; the final one waits behind it.
        if let partialTask { partialTask.cancel(); _ = await partialTask.value }

        // In a crowd, a sentence from someone else is not the user's question.
        if !startsWithName,
           !(await SpeakerVerifier.shared.isUser(samples, leniency: SpeakerVerifier.conversationLeniency, context: "sentence")) {
            streamed?.cancel()
            guard !Task.isCancelled else { return }
            stage = .listening
            onTranscript("")
            restartSilenceTimer()
            return
        }
        guard !Task.isCancelled else { return }

        // The model may still be loading (the first time after a download it is
        // compiled for this Mac). Say so instead of going quiet.
        let notice: Task<Void, Never>? = await transcriber.isLoaded ? nil : Task {
            try? await Task.sleep(for: Self.preparingNoticeDelay)
            guard !Task.isCancelled else { return }
            await say(String(localized: "Bir saniye, hazırlanıyorum."))
        }
        var text: String
        do {
            if let streamed { text = try await streamed.value } else { text = try await transcriber.transcribe(samples) }
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

        if startsWithName {
            // "Optik, bugün hava nasıl" → "bugün hava nasıl". The name alone (the
            // rest was lost in noise) gets the usual "Efendim?".
            text = WakePhrase.remainder(text) ?? text
            if text.isEmpty {
                stage = .listening
                await say(String(localized: "Efendim?"))
                restartSilenceTimer()
                return
            }
        }
        guard !text.isEmpty, !Self.isNoise(text) else {
            stage = .listening
            restartSilenceTimer()
            return
        }
        onTranscript(text)

        // "Sayfayı Dia’da açayım mı?" answered with a plain yes or no.
        if let link = offeredLink {
            offeredLink = nil
            switch YesNoAnswer(text) {
            case .yes:
                DefaultBrowser.open(link)
                await reply(withFallback: String(localized: "Açtım."))
                return
            case .no:
                await reply(withFallback: String(localized: "Peki."))
                return
            case nil:
                break
            }
        }

        if LocalCommand(text) == .stop {
            onFinish()
            return
        }
        if await runLocalCommands(in: text, transcriptReady: transcriptReady) { return }
        await ask(text, transcriptReady: transcriptReady)
    }

    /// Whisper's habit of hearing "Altyazı M.K." or "İzlediğiniz için teşekkürler" in silence.
    private static func isNoise(_ text: String) -> Bool {
        let lowered = text.lowercased(with: Locale(identifier: "tr_TR"))
        return lowered.hasPrefix("altyazı") || lowered.contains("izlediğiniz için")
            || lowered.trimmingCharacters(in: .punctuationCharacters.union(.whitespaces)).isEmpty
    }

    private func ask(_ userText: String, transcriptReady: Double) async {
        guard KeychainStore.has(.anthropic) || ClaudeCodeClient.isInstalled else {
            await echo(userText, transcriptReady: transcriptReady)
            return
        }
        guard let systemPrompt, let models else {
            await reply(withFallback: String(localized: "İstem dosyası eksik, Optik kurulumunu kontrol et."))
            return
        }
        let context = TurnContext(userName: UserDefaults.standard.string(forKey: SettingsKey.userName),
                                  now: .now, trigger: trigger,
                                  computerControl: LLMRouter.canUseComputer)
        let request = LLMRequest(model: models.voice, system: systemPrompt, turnContext: context.text,
                                 messages: history.request(adding: userText))

        var replyText = ""
        var source: URL?
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
                case .source(let url):
                    if source == nil { source = url }
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
        if let source {
            // Asked after the reply, so it is never cut by the spoken length limit.
            let offer = DefaultBrowser.offer
            replyText += "\n" + offer
            onReply(replyText)
            let question = SpeechQueue(conversation: self, effect: false)
            question.say(offer, firstToken: Self.now)
            await question.finish()
            guard !Task.isCancelled else { question.cancel(); return }
            offeredLink = source
        }
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
        case .claudeCodeFailed: String(localized: "Claude Code yanıt vermedi. Terminalde claude ile giriş yaptığını kontrol eder misin?")
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
        /// Spoken replies are off: sentences are dropped, nothing is synthesized.
        private let isMuted = !VoiceConversation.speaksReplies

        init(conversation: VoiceConversation, effect: Bool = true) {
            self.conversation = conversation
            useSystemVoice = !conversation.synthesizer.hasKey
            playedEffect = !effect
            measures = effect
        }

        func say(_ sentence: String, firstToken: Double) {
            guard !cancelled, !isMuted else { return }
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
