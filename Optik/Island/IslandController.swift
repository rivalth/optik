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
    var onClick: () -> Void = {}

    var phase: IslandPhase { machine.phase }
}

/// Runs the notch island: the panel, the state machine and everything that reacts
/// to it (sounds, "Efendim?", Esc, the 8 s silence timeout, screens, full screen).
@MainActor
final class IslandController {
    static let shared = IslandController()

    let model = IslandModel()

    private var panel: IslandPanel?
    private var screen: IslandScreen?
    private let fullScreen = FullScreenMonitor()
    private let doubleCommand = DoubleCommandMonitor()
    private let speaker = GreetingSpeaker()
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
    /// A reply's time on screen, until replies are spoken by Optik's own voice.
    static let replyDuration: TimeInterval = 5.7
    /// `docs/03-karakter.md` 7: speech starts 60 ms after the sound effect ends.
    static let speechGap: TimeInterval = 0.06

    // MARK: Setup

    func start() {
        model.onClick = { [weak self] in self?.clicked() }

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

        speaker.onStart = { [weak self] in self?.logLatency("Efendim audible") }
        speaker.onFinish = { [weak self] in self?.send(.greeted) }
        speaker.prewarm()

        doubleCommand.onDoubleTap = { [weak self] timestamp in self?.summon(at: timestamp) }
        updateDoubleCommand()
        KeyboardShortcuts.onKeyDown(for: .summonOptik) { [weak self] in
            self?.summon(at: clock_gettime_nsec_np(CLOCK_UPTIME_RAW))
        }
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

    // MARK: Input

    /// `timestamp`: when the key event happened, ns since boot (`CLOCK_UPTIME_RAW`).
    func summon(at timestamp: UInt64 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) {
        summonedAt = timestamp
        send(.summon)
        logLatency("island opening")
    }

    func dismiss() { send(.dismiss) }

    func showReply(_ text: String) { send(.reply(text)) }

    func announce(_ announcement: Announcement) { send(.announce(announcement)) }

    private func clicked() {
        if model.phase.isOpen { dismiss() } else { summon() }
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
            speaker.stop()
            setEscapeEnabled(false)
        case .wake:
            setEscapeEnabled(true)
            speaker.stop()
            let effect = SoundEffect.uyan
            Task {
                await SoundEffectPlayer.shared.play(effect)
                self.logLatency("first sound")
            }
            // "Efendim?" right after the wake sound, never on top of it.
            let delay = effect.duration + Self.speechGap
            schedule(after: delay) { [weak self] in
                self?.speaker.speak(String(localized: "Efendim?"))
            }
        case .listening:
            Task { await SoundEffectPlayer.shared.play(.dinliyor) }
            // Nothing transcribes yet (stage 2), so the silence timeout always ends it.
            schedule(after: Self.silenceTimeout) { [weak self] in self?.send(.dismiss) }
        case .replying:
            Task { await SoundEffectPlayer.shared.play(.mutlu) }
            schedule(after: Self.replyDuration) { [weak self] in self?.send(.replyFinished) }
        case .announcing:
            setEscapeEnabled(true)
            Task { await SoundEffectPlayer.shared.play(.uyari) }
            schedule(after: Self.announcementDuration) { [weak self] in self?.send(.announcementFinished) }
        }
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
        guard let panel, let screen, !model.phase.isOpen else { return }
        panel.setFrame(IslandLayout.panelFrame(IslandPhase.idle.size, on: screen, withMargin: false), display: true)
        updateVisibility()
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
