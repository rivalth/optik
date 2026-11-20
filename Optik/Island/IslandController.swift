import AppKit
import KeyboardShortcuts
import Observation
import OptikCore
import os
import SwiftUI

extension KeyboardShortcuts.Name {
    /// An optional extra shortcut, recorded by the user in Settings. Empty by default:
    /// ⌘ ⌘ is the default way to summon Optik.
    static let summonOptik = Self("summonOptik")
}

/// What the island view draws. The controller owns it and the view only reads it.
@MainActor
@Observable
final class IslandModel {
    var machine = IslandStateMachine()
    var hasNotch = true
    /// The island's current width; on very wide notches it can exceed the design size.
    var width: CGFloat = DesignTokens.Island.idle.width
    /// The greeting Optik says, one of the "Efendim?" variants.
    var greeting = String(localized: "Efendim?")
    /// The microphone is on: the island shows a green dot (`CLAUDE.md`, privacy).
    var isMicrophoneOn = false
    /// A notice in the closed island's wings: volume, charging, a new song.
    var indicator: IslandIndicator?
    /// The camera housing's width, which the wings' content keeps clear of.
    var notchWidth: CGFloat = 0
    var onClick: () -> Void = {}

    var phase: IslandPhase { machine.phase }

    /// The island's size: the phase's, or the indicator's while one shows.
    var size: DesignTokens.Island.Size {
        if phase == .idle, let indicator { return IndicatorLayout.size(for: indicator) }
        return phase.size
    }
}

/// Runs the notch island: the panel, the state machine and everything that reacts
/// to it (sounds, "Efendim?", the voice conversation, Esc, screens, full screen).
@MainActor
final class IslandController {
    static let shared = IslandController()

    let model = IslandModel()

    private var panel: IslandPanel?
    private var screen: IslandScreen?
    private let fullScreen = FullScreenMonitor()
    private let doubleCommand = DoubleCommandMonitor()
    let indicators = IndicatorMonitor()
    private var indicatorHide: DispatchWorkItem?
    let transcriber = WhisperTranscriber()
    /// One connection to Claude for talking and typing, so both share Claude Code's memory.
    let llm = LLMRouter()
    private lazy var wakeWord: any WakeWordDetector = WakeWordListener(transcriber: transcriber)
    private lazy var conversation = VoiceConversation(
        transcriber: SentenceTranscriber(whisper: transcriber), llm: llm, synthesizer: ElevenLabsSynthesizer()
    )
    private var trigger: TurnContext.Trigger = .shortcut
    /// "Optik, …" in one breath: no "Efendim?", the wake word listener records the sentence.
    private var waitsForSentence = false
    private var escapeTask: Task<Void, Never>?
    private var phaseTimer: DispatchWorkItem?
    private var shrinkPanel: DispatchWorkItem?
    private var screenObserver: NSObjectProtocol?
    private var summonedAt: UInt64?

    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Optik", category: "latency")

    /// `docs/01-urun.md` 1.1: Esc or 8 s of silence closes the island.
    static let silenceTimeout: TimeInterval = 8
    /// How long an announcement stays when nobody reacts.
    static let announcementDuration: TimeInterval = 6
    /// A reply's time on screen when no conversation drives it (debug demo).
    static let replyDuration: TimeInterval = 5.7
    /// `docs/03-karakter.md` 7: speech starts 60 ms after the sound effect ends.
    static let speechGap: TimeInterval = 0.06

    // MARK: Setup

    func start() {
        model.onClick = { [weak self] in self?.clicked() }
        LocalActionRunner.shared.refreshIfStale()

        let panel = IslandPanel(rootView: IslandView(model: model))
        self.panel = panel

        fullScreen.onChange = { [weak self] active in self?.send(.fullScreenChanged(active)) }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        }
        screensChanged()
        fullScreen.start()

        conversation.onTranscript = { [weak self] text in self?.send(.transcript(text)) }
        conversation.onReply = { [weak self] text in self?.send(.reply(text)) }
        conversation.onListenAgain = { [weak self] in self?.send(.listen) }
        conversation.onFinish = { [weak self] in self?.send(.dismiss) }
        conversation.onMicrophoneChange = { [weak self] on in self?.model.isMicrophoneOn = on }

        indicators.onIndicator = { [weak self] indicator in self?.show(indicator) }
        indicators.refresh()

        doubleCommand.onDoubleTap = { [weak self] timestamp in self?.summon(at: timestamp) }
        updateDoubleCommand()
        updateWakeWord()
        QuickAskController.shared.start(llm: llm)
        KeyboardShortcuts.onKeyDown(for: .summonOptik) { [weak self] in
            self?.summon(at: clock_gettime_nsec_np(CLOCK_UPTIME_RAW))
        }

        // Warm the speech model from disk once, so the first summon does not pay
        // Core ML's specialization; it leaves memory again after 90 s.
        let transcriber = self.transcriber
        Task.detached(priority: .utility) { try? await transcriber.prepareSelectedModel() }
    }

    /// Starts or stops the ⌘ ⌘ watcher to match the setting and the permission.
    func updateDoubleCommand() {
        let enabled = UserDefaults.standard.object(forKey: SettingsKey.summonWithDoubleCommand) as? Bool ?? true
        guard enabled else { doubleCommand.stop(); return }
        if !doubleCommand.start(), !DoubleCommandMonitor.hasPermission {
            DoubleCommandMonitor.requestPermission()
        }
    }

    var isDoubleCommandRunning: Bool { doubleCommand.isRunning }

    static var isWakeWordEnabled: Bool {
        UserDefaults.standard.bool(forKey: SettingsKey.summonWithWakeWord)
    }

    /// The wake word stays off while the user records voice samples in Settings.
    private var wakeWordPaused = false

    func pauseWakeWord(_ paused: Bool) {
        wakeWordPaused = paused
        updateWakeWord()
    }

    /// Listens for "Optik" while the island is closed, if the user turned it on.
    /// The conversation has its own microphone, so this one stops while Optik is awake.
    func updateWakeWord() {
        guard Self.isWakeWordEnabled, !wakeWordPaused, !model.phase.isOpen else { wakeWord.stop(); return }
        let verifier = SpeakerVerifier.shared
        Task.detached(priority: .utility) { await verifier.prepare() }
        wakeWord.start { [weak self] event in
            Task { @MainActor in self?.wakeWordHeard(event) }
        }
    }

    private func wakeWordHeard(_ event: WakeWordEvent) {
        switch event {
        case .called(let heardAt):
            summon(at: heardAt, trigger: .wakeWord)
        case .calledWithSentence(let heardAt):
            summon(at: heardAt, trigger: .wakeWord, waitsForSentence: true)
        case .sentence(let samples):
            waitsForSentence = false
            conversation.hear(sentence: samples)
            // The island closed while the sentence was recorded: listen again.
            if !model.phase.isOpen { updateWakeWord() }
        }
    }

    // MARK: Input

    /// `timestamp`: when the key event happened, ns since boot (`CLOCK_UPTIME_RAW`).
    func summon(at timestamp: UInt64 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW),
                trigger: TurnContext.Trigger = .shortcut, waitsForSentence: Bool = false) {
        summonedAt = timestamp
        self.trigger = trigger
        self.waitsForSentence = waitsForSentence
        lastLatencies = [:]
        send(.summon)
        logLatency("island opening")
    }

    func dismiss() { send(.dismiss) }

    func showReply(_ text: String) { send(.reply(text)) }

    func announce(_ announcement: Announcement) { send(.announce(announcement)) }

    private func clicked() {
        if model.phase.isOpen { dismiss() } else { summon(trigger: .click) }
    }

    // MARK: State

    private func send(_ event: IslandStateMachine.Event) {
        let before = model.machine
        guard model.machine.handle(event) else { return }
        let after = model.machine
        if before.phase != after.phase || before.currentAnnouncement != after.currentAnnouncement {
            enter(after.phase)
        }
        updatePanel(from: before.phase, to: after.phase)
    }

    /// Side effects of entering a phase. Every phase cancels the previous one's timer.
    private func enter(_ phase: IslandPhase) {
        phaseTimer?.cancel()
        switch phase {
        case .idle:
            conversation.end()
            setEscapeEnabled(false)
            if waitsForSentence {
                // Closed while the listener was still recording the sentence.
                waitsForSentence = false
                wakeWord.stop()
            }
            updateWakeWord()
        case .wake:
            setEscapeEnabled(true)
            // The listener keeps its microphone while it records a one-breath sentence.
            if !waitsForSentence { wakeWord.stop() }
            conversation.end()
            conversation.begin(trigger: trigger, summonedAt: summonedAt ?? clock_gettime_nsec_np(CLOCK_UPTIME_RAW),
                               waitsForSentence: waitsForSentence)
            let effect = SoundEffect.uyan
            Task {
                await SoundEffectPlayer.shared.play(effect)
                self.logLatency("first sound")
            }
            if waitsForSentence {
                // No "Efendim?": the user is already talking. Show listening.
                schedule(after: effect.duration) { [weak self] in self?.send(.greeted) }
                break
            }
            // "Efendim?" right after the wake sound, never on top of it.
            let phrase = FixedPhrases.variant("efendim")
            model.greeting = phrase?.metin ?? String(localized: "Efendim?")
            let delay = effect.duration + Self.speechGap
            schedule(after: delay) { [weak self] in self?.greet(phrase) }
        case .listening:
            if conversation.isActive {
                // The conversation listens and closes the island after 8 s of silence.
                conversation.greeted()
            } else {
                schedule(after: Self.silenceTimeout) { [weak self] in self?.send(.dismiss) }
            }
        case .replying:
            // A spoken reply ends when the conversation says so; the demo reply on a timer.
            if !conversation.isActive {
                Task { await SoundEffectPlayer.shared.play(.mutlu) }
                schedule(after: Self.replyDuration) { [weak self] in self?.send(.replyFinished) }
            }
        case .announcing:
            setEscapeEnabled(true)
            Task { await SoundEffectPlayer.shared.play(.uyari) }
            schedule(after: Self.announcementDuration) { [weak self] in self?.send(.announcementFinished) }
        }
    }

    private func greet(_ phrase: FixedPhrases.Phrase?) {
        conversation.playGreeting(
            phrase,
            onStart: { [weak self] in
                guard let self else { return }
                self.logLatency("Efendim audible")
                self.conversation.recordIslandLatency(wakeToIsland: self.lastLatencies["island opening"],
                                                      wakeToEfendim: self.lastLatencies["Efendim audible"])
            },
            done: { [weak self] in self?.send(.greeted) }
        )
    }

    private func schedule(after seconds: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        let work = DispatchWorkItem { MainActor.assumeIsolated { action() } }
        phaseTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    /// Esc closes the island only while it is open, so it never steals Esc otherwise.
    private func setEscapeEnabled(_ enabled: Bool) {
        if enabled {
            guard escapeTask == nil else { return }
            let escape = KeyboardShortcuts.Shortcut(.escape)
            escapeTask = Task { [weak self] in
                for await event in KeyboardShortcuts.events(for: escape) where event == .keyDown {
                    self?.dismiss()
                }
            }
        } else {
            escapeTask?.cancel()
            escapeTask = nil
        }
    }

    // MARK: Panel

    private func updatePanel(from previous: IslandPhase, to phase: IslandPhase) {
        guard let panel, let screen else { return }
        shrinkPanel?.cancel()
        if phase.isOpen {
            // Optik coming out takes the island over from any notice.
            indicatorHide?.cancel()
            model.indicator = nil
        }
        model.width = IslandLayout.islandFrame(phase.size, on: screen).width
        if phase.isOpen {
            // Grow first, then let the island spring into the room.
            panel.setFrame(IslandLayout.panelFrame(phase.size, on: screen, withMargin: true), display: false)
        } else if previous.isOpen {
            // Shrink the panel back once the closing spring has settled.
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated { self?.fitPanelToIdle() }
            }
            shrinkPanel = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
        }
        updateVisibility()
    }

    private func fitPanelToIdle() {
        shrinkPanel = nil
        guard let panel, let screen, !model.phase.isOpen, model.indicator == nil else { return }
        panel.setFrame(IslandLayout.panelFrame(IslandPhase.idle.size, on: screen, withMargin: false), display: true)
        updateVisibility()
    }

    // MARK: Indicators

    /// Shows a notice in the closed island's wings for a moment. A new notice of the
    /// same kind (the volume key held down) updates it and restarts its time.
    func show(_ indicator: IslandIndicator) {
        guard model.phase == .idle, model.machine.isVisible, let panel, let screen else { return }
        log.info("indicator \(indicator.kind.rawValue, privacy: .public)")
        shrinkPanel?.cancel()
        shrinkPanel = nil
        let size = IndicatorLayout.size(for: indicator)
        panel.setFrame(IslandLayout.panelFrame(size, on: screen, withMargin: true), display: false)
        model.width = IslandLayout.islandFrame(size, on: screen).width
        model.indicator = indicator
        indicatorHide?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.hideIndicator() }
        }
        indicatorHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + indicator.kind.duration, execute: work)
    }

    private func hideIndicator() {
        guard model.indicator != nil, let screen else { return }
        model.indicator = nil
        guard !model.phase.isOpen else { return }
        model.width = IslandLayout.islandFrame(IslandPhase.idle.size, on: screen).width
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.fitPanelToIdle() }
        }
        shrinkPanel = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    /// Over a full-screen app the closed island hides, but only after it finished closing.
    private func updateVisibility() {
        guard let panel else { return }
        if model.machine.isVisible {
            if !panel.isVisible { panel.orderFrontRegardless() }
        } else if panel.isVisible, shrinkPanel == nil {
            panel.orderOut(nil)
        }
    }

    /// Displays came or went, or the lid closed: move to the right screen.
    private func screensChanged() {
        let screens = NSScreen.screens.map(IslandLayout.screen(for:))
        guard let target = IslandLayout.preferredScreen(screens) else { return }
        screen = target
        model.hasNotch = target.hasNotch
        model.notchWidth = target.notch?.width ?? 0
        fullScreen.screenFrame = target.frame
        let phase = model.phase
        model.width = IslandLayout.islandFrame(phase.size, on: target).width
        panel?.setFrame(IslandLayout.panelFrame(phase.size, on: target, withMargin: phase.isOpen), display: true)
        updateVisibility()
    }

    // MARK: Development

    #if DEBUG
    /// The design's demo: summon, listen, a sample reply, back to the coop.
    func playDemo() {
        summon()
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.9) { [weak self] in
            MainActor.assumeIsolated {
                self?.showReply(String(localized: "13.00’te Yeliz ile kahve, Moda’da. 16.30’da da proje grubu toplantın var."))
            }
        }
    }

    /// A sample reminder after a delay, to try it over a full-screen app.
    func announceSample(after seconds: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            MainActor.assumeIsolated {
                self?.announce(Announcement(text: String(localized: "20.00’de alt ağ planı ödevinin teslimi var.")))
            }
        }
    }
    #endif

    // MARK: Latency

    /// Logs the time since the summoning key event. Budgets (`CLAUDE.md`): the island
    /// starts opening within 100 ms, the first sound (the wake effect) within 250 ms.
    /// "Efendim?" follows the effect, 60 ms after it ends.
    private func logLatency(_ step: String) {
        guard let start = summonedAt else { return }
        let now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        let ms = Double(now &- start) / 1_000_000
        log.info("\(step, privacy: .public): \(ms, format: .fixed(precision: 1), privacy: .public) ms")
        lastLatencies[step] = ms
    }

    /// The latest measurements, for the debug menu and tests.
    private(set) var lastLatencies: [String: Double] = [:]
}
