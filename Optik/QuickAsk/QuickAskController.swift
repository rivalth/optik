import AppKit
import KeyboardShortcuts
import Observation
import OptikCore
import os
import SwiftUI

extension KeyboardShortcuts.Name {
    /// Silent mode: a box under the notch to type to Optik where talking is not an
    /// option (a library, a crowd). ⌃⌥O by default (⌃⌥Space switches input sources).
    static let quietAsk = Self("quietAsk", initial: .init(.o, modifiers: [.control, .option]))
}

/// What the typing box shows.
@MainActor
@Observable
final class QuickAskModel {
    var text = ""
    /// The question being answered, and the answer as it streams in.
    var question = ""
    private(set) var reply = ""
    /// When each word of the reply starts to fade in, one after another.
    private(set) var wordStarts: [Date] = []
    /// False once the last word has settled, so the reply stops redrawing.
    private(set) var isAnimatingReply = false
    var isWaiting = false
    private(set) var isError = false
    /// The page the reply came from, and whether Optik is asking to open it.
    var link: URL?
    var isOfferingLink = false
    /// Drives the drop from the notch and the way back.
    var isShown = false
    /// Bumped each time the box opens, so the field takes focus again.
    var focusRequest = 0
    var onSubmit: () -> Void = {}
    var onClose: () -> Void = {}
    var onOpenLink: () -> Void = {}

    private var settle: Task<Void, Never>?

    /// Each word starts this long after the one before it.
    nonisolated static let wordDelay: TimeInterval = 0.07
    /// How long one word takes to settle.
    nonisolated static let wordDuration: TimeInterval = 0.42

    /// Thinking: the question is sent and nothing has come back yet.
    var isThinking: Bool { isWaiting && reply.isEmpty }

    var mood: Mood {
        if isError { return .alert }
        if isThinking { return .thoughtful }
        if !text.isEmpty { return .listening }
        if isOfferingLink || (!isWaiting && IslandStateMachine.isQuestion(reply)) { return .asking }
        if !reply.isEmpty { return .happy }
        return .waiting
    }

    func clearReply() {
        reply = ""
        wordStarts = []
        isError = false
        link = nil
        isOfferingLink = false
    }

    func appendReply(_ delta: String) {
        reply += delta
        let count = Self.words(in: reply).count
        let now = Date.now
        while wordStarts.count < count {
            let afterPrevious = wordStarts.last.map { $0.addingTimeInterval(Self.wordDelay) } ?? now
            wordStarts.append(max(now, afterPrevious))
        }
        animateUntilSettled()
    }

    func showError(_ message: String) {
        clearReply()
        isError = true
        appendReply(message)
    }

    private func animateUntilSettled() {
        isAnimatingReply = true
        settle?.cancel()
        let settlesAt = (wordStarts.last ?? .now).addingTimeInterval(Self.wordDuration)
        settle = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, settlesAt.timeIntervalSinceNow) + 0.05))
            guard !Task.isCancelled else { return }
            self?.isAnimatingReply = false
        }
    }

    /// The words of `text`, each with the spaces after it, so joined they give `text` back.
    nonisolated static func words(in text: String) -> [Substring] {
        var words: [Substring] = []
        var start = text.startIndex
        var inSpace = false
        for index in text.indices {
            let isSpace = text[index].isWhitespace
            if inSpace, !isSpace {
                words.append(text[start..<index])
                start = index
            }
            inSpace = isSpace
        }
        if start < text.endIndex { words.append(text[start...]) }
        return words
    }
}

/// Silent mode (`docs/01-urun.md`): the user types, Optik answers on screen, nothing
/// is spoken and the microphone stays off. Uses the same connection to Claude as the
/// voice conversation, so with Claude Code both share one memory.
@MainActor
final class QuickAskController {
    static let shared = QuickAskController()

    private let model = QuickAskModel()
    private var panel: QuickAskPanel?
    private var llm: (any LLMClient)?
    private var history = ConversationHistory()
    private var lastUse = Date.distantPast
    private var turn: Task<Void, Never>?
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Optik", category: "quiet")

    /// The typed conversation is forgotten after this long without use.
    static let historyLifetime: TimeInterval = 600

    func start(llm: any LLMClient) {
        self.llm = llm
        model.onSubmit = { [weak self] in self?.submit() }
        model.onClose = { [weak self] in self?.close() }
        model.onOpenLink = { [weak self] in self?.openLink() }
        KeyboardShortcuts.onKeyDown(for: .quietAsk) { [weak self] in self?.toggle() }
    }

    func toggle() {
        if panel?.isVisible == true { close() } else { open() }
    }

    func open() {
        if Date.now.timeIntervalSince(lastUse) > Self.historyLifetime {
            history.clear()
            model.question = ""
            model.clearReply()
        }
        let panel = self.panel ?? QuickAskPanel(model: model)
        self.panel = panel
        panel.show()
        LocalActionRunner.shared.refreshIfStale()
        Task.detached(priority: .userInitiated) { [llm] in await llm?.warmUp() }
    }

    func close() {
        panel?.dismiss()
    }

    private func openLink() {
        guard let link = model.link else { return }
        model.isOfferingLink = false
        DefaultBrowser.open(link)
        close()
    }

    private func submit() {
        let question = model.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !model.isWaiting else { return }
        // "Sayfayı Dia’da açayım mı?" answered with a plain yes or no.
        if model.isOfferingLink, let answer = YesNoAnswer(question) {
            model.text = ""
            if answer == .yes { openLink() } else { model.isOfferingLink = false }
            return
        }
        model.text = ""
        model.question = question
        model.clearReply()
        lastUse = .now
        if LocalCommand(question) == .stop { close(); return }
        turn?.cancel()
        turn = Task {
            if await runLocalCommands(question) { return }
            await ask(question)
        }
    }

    /// "Dia'yı aç, sonra maç saati arat": what Optik can do itself is done here,
    /// the rest goes to Claude with a note of what was done. False when the
    /// sentence starts with something for Claude.
    private func runLocalCommands(_ question: String) async -> Bool {
        let runner = LocalActionRunner.shared
        let parts = LocalCommandParser.clauses(in: question)
        var outcomes: [LocalActionRunner.Outcome] = []
        var rest: [String] = []
        for (index, clause) in runner.parse(question).enumerated() {
            guard case .local(let action) = clause else {
                rest = Array(parts.dropFirst(index))
                break
            }
            outcomes.append(await runner.run(action))
            guard !Task.isCancelled else { return true }
        }
        guard !outcomes.isEmpty else { return false }
        let summary = outcomes.map(\.text).joined(separator: "\n")
        if outcomes.contains(where: { !$0.succeeded }) {
            model.showError(summary)
        } else {
            model.appendReply(summary)
        }
        guard !rest.isEmpty else {
            history.append(user: question, assistant: summary)
            return true
        }
        model.appendReply("\n")
        await ask("(Optik az önce yaptı: \(outcomes.map(\.text).joined(separator: "; ")).) " + rest.joined(separator: ", "),
                  shownAs: question)
        return true
    }

    private func ask(_ question: String, shownAs typed: String? = nil) async {
        guard let llm, KeychainStore.has(.anthropic) || ClaudeCodeClient.isInstalled else {
            model.showError(String(localized: "Yazarak sormak için Claude API anahtarı ya da Claude Code gerekli."))
            return
        }
        guard let setup = ClaudeCodeClient.bundledSetup() else {
            model.showError(String(localized: "İstem dosyası eksik, Optik kurulumunu kontrol et."))
            return
        }
        let context = TurnContext(userName: UserDefaults.standard.string(forKey: SettingsKey.userName),
                                  now: .now, trigger: .typed,
                                  computerControl: LLMRouter.canUseComputer)
        let request = LLMRequest(model: setup.model, system: setup.system, turnContext: context.text,
                                 messages: history.request(adding: question))
        model.isWaiting = true
        defer { model.isWaiting = false }
        do {
            for try await event in llm.stream(request) {
                guard !Task.isCancelled else { return }
                switch event {
                case .text(let delta): model.appendReply(delta)
                case .source(let url): if model.link == nil { model.link = url }
                case .finished: break
                }
            }
            var said = model.reply
            if model.link != nil {
                model.isOfferingLink = true
                said += "\n" + DefaultBrowser.offer
            }
            history.append(user: typed ?? question, assistant: said)
            lastUse = .now
        } catch is CancellationError {
            return
        } catch {
            log.error("typed question failed")
            model.showError(String(localized: "Claude'dan yanıt alamadım. Bir daha dener misin?"))
        }
    }
}

