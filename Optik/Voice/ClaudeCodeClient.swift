import Foundation
import OptikCore
import os

/// Answers through Claude Code, with the user's Claude subscription, when there is
/// no API key.
///
/// Optik is sandboxed and cannot start programs; macOS runs the scripts in its
/// Application Scripts folder outside the sandbox (`scripts/optik-claude-code.sh`).
/// That script starts `claude -p` with every tool, setting and MCP server turned
/// off, so Claude Code can only answer in text.
///
/// Optik keeps one Claude Code conversation for good: the process stays open
/// between turns, and after a restart the same session is resumed, so Optik
/// remembers earlier talks. An idle process is let go and resumed at the next
/// summon, while "Efendim?" plays.
final class ClaudeCodeClient: LLMClient, @unchecked Sendable {
    static let scriptName = "optik-claude-code.sh"
    /// An unused process is let go after this long.
    static let idleLifetime: Duration = .seconds(600)
    /// No first event in this long means Claude Code is stuck.
    static let firstEventTimeout: Duration = .seconds(20)

    private let sessionKey: String
    private var sessionStartedKey: String { sessionKey + "Started" }

    private let lock = NSLock()
    private var session: ClaudeCodeSession?
    private var lastSetup: Setup?
    private var idleTimer: Task<Void, Never>?
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Optik", category: "llm")

    /// `sessionKey`: where the conversation's id is kept, in user defaults.
    init(sessionKey: String = "claudeCodeSession") {
        self.sessionKey = sessionKey
    }

    struct Setup: Equatable, Sendable {
        var model: String
        var system: String
    }

    static var scriptURL: URL? {
        guard let folder = try? FileManager.default.url(for: .applicationScriptsDirectory, in: .userDomainMask,
                                                         appropriateFor: nil, create: false)
        else { return nil }
        return folder.appending(path: scriptName)
    }

    static var isInstalled: Bool {
        guard let url = scriptURL else { return false }
        return FileManager.default.isExecutableFile(atPath: url.path)
    }

    /// Optik's one Claude Code conversation.
    private var sessionID: String {
        let defaults = UserDefaults.standard
        if let id = defaults.string(forKey: sessionKey) { return id }
        let id = UUID().uuidString.lowercased()
        defaults.set(id, forKey: sessionKey)
        defaults.set(false, forKey: sessionStartedKey)
        return id
    }

    // MARK: LLMClient

    func stream(_ request: LLMRequest) -> AsyncThrowingStream<LLMEvent, Error> {
        let setup = Setup(model: request.model, system: request.system)
        let message = Self.message(for: request)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let session = try self.session(for: setup)
                    let lines = try await session.ask(message, firstEventTimeout: Self.firstEventTimeout)
                    var decoder = ClaudeCodeEvents()
                    for try await line in lines {
                        guard let event = try decoder.decode(line) else { continue }
                        continuation.yield(event)
                        if case .finished = event {
                            UserDefaults.standard.set(true, forKey: self.sessionStartedKey)
                            break
                        }
                    }
                    guard decoder.finished else { throw LLMError.claudeCodeFailed }
                    self.scheduleIdleRelease()
                    continuation.finish()
                } catch is CancellationError {
                    self.scheduleIdleRelease()
                    continuation.finish(throwing: CancellationError())
                } catch {
                    self.log.error("Claude Code did not answer")
                    self.release()
                    continuation.finish(throwing: (error as? LLMError) ?? LLMError.claudeCodeFailed)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Opens the conversation ahead of the question, so it is ready when the user stops talking.
    func warmUp() async {
        guard Self.isInstalled, let setup = lock.withLock({ lastSetup }) ?? Self.bundledSetup() else { return }
        _ = try? session(for: setup)
        scheduleIdleRelease()
    }

    // MARK: Session

    private func session(for setup: Setup) throws -> ClaudeCodeSession {
        let (reusable, stale): (ClaudeCodeSession?, ClaudeCodeSession?) = lock.withLock {
            lastSetup = setup
            idleTimer?.cancel()
            if let session, session.setup == setup, session.isAlive { return (session, nil) }
            let stale = session
            session = nil
            return (nil, stale)
        }
        if let reusable { return reusable }
        stale?.close()
        let resume = UserDefaults.standard.bool(forKey: sessionStartedKey)
        let created = try ClaudeCodeSession(setup: setup, sessionID: sessionID, resume: resume)
        log.info("Claude Code \(resume ? "resumed" : "started", privacy: .public)")
        lock.withLock { session = created }
        return created
    }

    func release() {
        let old = lock.withLock { () -> ClaudeCodeSession? in
            defer { session = nil }
            return session
        }
        old?.close()
    }

    /// Lets the process go after a while without questions; the conversation is
    /// resumed from disk next time.
    private func scheduleIdleRelease() {
        let timer = Task { [weak self] in
            try? await Task.sleep(for: Self.idleLifetime)
            guard !Task.isCancelled else { return }
            self?.release()
        }
        lock.withLock {
            idleTimer?.cancel()
            idleTimer = timer
        }
    }

    /// The system prompt and model from the app bundle, for warming up before the
    /// first question.
    static func bundledSetup() -> Setup? {
        guard let promptURL = Bundle.main.url(forResource: "sistem-istemi", withExtension: "md"),
              let markdown = try? String(contentsOf: promptURL, encoding: .utf8),
              let system = SystemPrompt.extract(fromMarkdown: markdown),
              let modelsURL = Bundle.main.url(forResource: "modeller", withExtension: "json"),
              let data = try? Data(contentsOf: modelsURL),
              let models = try? LLMModels.decode(from: data)
        else { return nil }
        return Setup(model: models.voice, system: system)
    }


    /// One user message: the turn context, then the new words. Claude Code keeps
    /// the earlier turns itself.
    static func message(for request: LLMRequest) -> String {
        let text = request.messages.last?.text ?? ""
        return request.turnContext.isEmpty ? text : request.turnContext + "\n\n" + text
    }
}

/// One `claude -p` process started through the Application Scripts folder. It
/// answers one question at a time; a reply nobody waits for any more (the user
/// talked over it) is read to its end and dropped before the next question.
final class ClaudeCodeSession: @unchecked Sendable {
    let setup: ClaudeCodeClient.Setup
    private let input = Pipe()
    private let output = Pipe()
    private let lock = NSLock()
    private var closed = false
    private var exited = false
    private var busy = false
    private var consumer: AsyncThrowingStream<String, Error>.Continuation?
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    init(setup: ClaudeCodeClient.Setup, sessionID: String, resume: Bool) throws {
        guard let url = ClaudeCodeClient.scriptURL else { throw LLMError.claudeCodeFailed }
        self.setup = setup
        let task = try NSUserUnixTask(url: url)
        task.standardInput = input.fileHandleForReading
        task.standardOutput = output.fileHandleForWriting
        let output = self.output
        let tools = ComputerServer.shared.configPath ?? ""
        task.execute(withArguments: [setup.model, setup.system, resume ? "resume" : "new", sessionID, tools]) { [weak self] _ in
            self?.processExited()
            // Our copy of the write end, so reading sees the end of the output.
            try? output.fileHandleForWriting.close()
        }
        let handle = output.fileHandleForReading
        Task.detached { [weak self] in
            do {
                for try await line in handle.bytes.lines { self?.deliver(line) }
            } catch {}
            self?.processExited()
        }
    }

    var isAlive: Bool { lock.withLock { !exited && !closed } }

    /// Sends a question once the previous reply is over; returns the reply's JSON lines.
    func ask(_ text: String, firstEventTimeout: Duration) async throws -> AsyncThrowingStream<String, Error> {
        await waitUntilIdle()
        try Task.checkCancellation()
        guard isAlive else { throw LLMError.claudeCodeFailed }
        let (stream, continuation) = AsyncThrowingStream<String, Error>.makeStream()
        lock.withLock {
            busy = true
            heardSinceAsk = false
            consumer = continuation
        }
        continuation.onTermination = { [weak self] _ in
            self?.lock.withLock { self?.consumer = nil }
        }
        let message: [String: Any] = ["type": "user", "message": ["role": "user", "content": text]]
        var data = try JSONSerialization.data(withJSONObject: message)
        data.append(0x0A)
        do {
            try input.fileHandleForWriting.write(contentsOf: data)
        } catch {
            close()
            throw LLMError.claudeCodeFailed
        }
        Task { [weak self] in
            try? await Task.sleep(for: firstEventTimeout)
            self?.timeOutIfSilent(continuation)
        }
        return stream
    }

    private var heardSinceAsk = false

    private func deliver(_ line: String) {
        let isResult = line.contains(#""type":"result""#) && Self.type(of: line) == "result"
        let (consumer, waiters): (AsyncThrowingStream<String, Error>.Continuation?, [CheckedContinuation<Void, Never>]) = lock.withLock {
            heardSinceAsk = true
            let current = self.consumer
            guard isResult else { return (current, []) }
            busy = false
            self.consumer = nil
            defer { idleWaiters = [] }
            return (current, idleWaiters)
        }
        consumer?.yield(line)
        if isResult { consumer?.finish() }
        for waiter in waiters { waiter.resume() }
    }

    private static func type(of line: String) -> String? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object["type"] as? String
    }

    private func timeOutIfSilent(_ continuation: AsyncThrowingStream<String, Error>.Continuation) {
        let silent = lock.withLock { () -> Bool in
            defer { heardSinceAsk = false }
            return !heardSinceAsk && busy
        }
        guard silent else { return }
        continuation.finish(throwing: LLMError.claudeCodeFailed)
        close()
    }

    private func waitUntilIdle() async {
        await withCheckedContinuation { (waiter: CheckedContinuation<Void, Never>) in
            let ready = lock.withLock { () -> Bool in
                if !busy || exited || closed { return true }
                idleWaiters.append(waiter)
                return false
            }
            if ready { waiter.resume() }
        }
    }

    private func processExited() {
        let (consumer, waiters) = lock.withLock { () -> (AsyncThrowingStream<String, Error>.Continuation?, [CheckedContinuation<Void, Never>]) in
            exited = true
            busy = false
            defer { self.consumer = nil; idleWaiters = [] }
            return (self.consumer, idleWaiters)
        }
        consumer?.finish(throwing: LLMError.claudeCodeFailed)
        for waiter in waiters { waiter.resume() }
    }

    /// Closing the input ends Claude Code once it has nothing left to do; the
    /// conversation stays on disk.
    func close() {
        let wasOpen = lock.withLock { () -> Bool in
            defer { closed = true }
            return !closed
        }
        if wasOpen { try? input.fileHandleForWriting.close() }
    }

    deinit { close() }
}
