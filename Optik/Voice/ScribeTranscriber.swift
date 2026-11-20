import Foundation
import OptikCore
import os

/// ElevenLabs Scribe v2 Realtime (`docs/02-mimari.md` 3.2). Only when the user picks
/// it: the sentence's audio is sent to ElevenLabs, never the wake word listening.
/// The whole sentence goes at once when the user stops talking, over the realtime
/// socket, which answers in about 0.3 s on an M2 (the upload endpoint is slower).
actor ScribeTranscriber {
    static let model = "scribe_v2_realtime"
    static let url = URL(string: "wss://api.elevenlabs.io/v1/speech-to-text/realtime")!
    /// The API takes at most 50 key terms of at most 20 characters.
    static let maxTerms = 50
    static let maxTermLength = 20
    /// Half a second of 16-bit 16 kHz audio per message (the API asks for 0.1–1 s).
    static let chunkBytes = 16_000
    static let timeout: Duration = .seconds(8)

    private let session: URLSession
    private let apiKey: @Sendable () -> String?
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Optik", category: "speech")

    init(session: URLSession = .shared, apiKey: @escaping @Sendable () -> String? = { KeychainStore.read(.elevenLabs) }) {
        self.session = session
        self.apiKey = apiKey
    }

    var hasKey: Bool { apiKey() != nil }

    /// A socket opened when Optik wakes, so the sentence does not wait for the
    /// connection (about half a second). The server closes an idle socket after
    /// 15 s; an older one is not used.
    private var waiting: (socket: URLSessionWebSocketTask, hints: [String], opened: ContinuousClock.Instant)?
    static let idleLimit: Duration = .seconds(12)

    /// Opens the socket for the coming sentence. Nothing is sent, nothing is billed.
    func warmUp(hints: [String]) {
        if let waiting, waiting.hints == hints, waiting.opened.duration(to: .now) < Self.idleLimit { return }
        waiting?.socket.cancel(with: .normalClosure, reason: nil)
        waiting = nil
        guard let socket = try? openSocket(hints: hints) else { return }
        waiting = (socket, hints, .now)
    }

    private func socket(hints: [String]) throws -> URLSessionWebSocketTask {
        defer { waiting = nil }
        if let waiting, waiting.hints == hints, waiting.opened.duration(to: .now) < Self.idleLimit,
           waiting.socket.state == .running {
            return waiting.socket
        }
        waiting?.socket.cancel(with: .normalClosure, reason: nil)
        return try openSocket(hints: hints)
    }

    private func openSocket(hints: [String]) throws -> URLSessionWebSocketTask {
        guard let key = apiKey() else { throw SpeechError.missingKey }
        var components = URLComponents(url: Self.url, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "model_id", value: Self.model),
            URLQueryItem(name: "language_code", value: "tr"),
            URLQueryItem(name: "audio_format", value: "pcm_16000"),
            URLQueryItem(name: "commit_strategy", value: "manual"),
        ] + Self.keyTerms(hints).map { URLQueryItem(name: "keyterms", value: $0) }
        var request = URLRequest(url: components.url!)
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        let socket = session.webSocketTask(with: request)
        socket.resume()
        return socket
    }

    /// `samples`: 16 kHz mono, -1...1.
    func transcribe(_ samples: [Float], hints: [String]) async throws -> String {
        let socket = try socket(hints: hints)
        defer { socket.cancel(with: .normalClosure, reason: nil) }

        let started = ContinuousClock.now
        return try await withThrowingTaskGroup(of: String?.self) { group in
            group.addTask {
                let audio = Self.pcm16(samples)
                var offset = audio.startIndex
                while offset < audio.endIndex {
                    let end = min(audio.endIndex, offset + Self.chunkBytes)
                    try await socket.send(.string(Self.chunkMessage(audio[offset..<end], commit: end == audio.endIndex)))
                    offset = end
                }
                return nil
            }
            group.addTask {
                while true {
                    let message = try await socket.receive()
                    guard case .string(let text) = message, let event = ScribeEvent(json: text) else { continue }
                    switch event {
                    case .committed(let text): return text
                    case .error(let type): throw ScribeError.server(type)
                    case .partial, .other: continue
                    }
                }
            }
            group.addTask {
                try await Task.sleep(for: Self.timeout)
                throw ScribeError.timedOut
            }
            while let result = try await group.next() {
                guard let text = result else { continue }
                group.cancelAll()
                log.info("scribe answered in \(started.duration(to: .now).components.seconds * 1000 + started.duration(to: .now).components.attoseconds / 1_000_000_000_000_000, privacy: .public) ms")
                return TranscriptFilter.clean(text)
            }
            throw ScribeError.timedOut
        }
    }

    /// Starts a sentence that is sent while the user is still talking.
    func startLive(hints: [String]) throws -> ScribeLiveSession {
        ScribeLiveSession(socket: try socket(hints: hints))
    }

    static func keyTerms(_ hints: [String]) -> [String] {
        Array(hints.filter { $0.count <= maxTermLength }.prefix(maxTerms))
    }

    static func pcm16(_ samples: [Float]) -> Data {
        var data = Data(capacity: samples.count * 2)
        for sample in samples {
            let value = Int16(max(-1, min(1, sample)) * Float(Int16.max))
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        return data
    }

    static func chunkMessage(_ audio: Data, commit: Bool) -> String {
        let body: [String: Any] = [
            "message_type": "input_audio_chunk", "audio_base_64": audio.base64EncodedString(),
            "commit": commit, "sample_rate": 16_000,
        ]
        let data = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}

enum ScribeError: Error, Equatable {
    case timedOut
    /// The server's error type ("auth_error", "quota_exceeded"…), never its text.
    case server(String)
}

/// What the realtime socket says.
enum ScribeEvent: Equatable {
    case partial(String)
    case committed(String)
    case error(String)
    case other

    init?(json: String) {
        guard let object = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any],
              let type = object["message_type"] as? String else { return nil }
        switch type {
        case "committed_transcript": self = .committed(object["text"] as? String ?? "")
        case "partial_transcript": self = .partial(object["text"] as? String ?? "")
        case "session_started", "committed_transcript_with_timestamps": self = .other
        default: self = object["error"] != nil ? .error(type) : .other
        }
    }
}

/// One sentence streamed to Scribe as it is spoken: audio goes out every quarter
/// second, partial text comes back, and the final text arrives about 0.2 s after
/// the last piece. The socket closes when the sentence is done or dropped.
actor ScribeLiveSession {
    private let socket: URLSessionWebSocketTask
    private var final: CheckedContinuation<String, Error>?
    private var result: Result<String, Error>?
    private var receiver: Task<Void, Never>?
    private let partialFeed: AsyncStream<String>.Continuation
    /// Scribe's text so far; each one replaces the last.
    nonisolated let partials: AsyncStream<String>
    private var sentSamples = 0
    private var isCommitted = false

    init(socket: URLSessionWebSocketTask) {
        self.socket = socket
        (partials, partialFeed) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    private func startReceiving() {
        guard receiver == nil else { return }
        receiver = Task { [socket] in
            do {
                while !Task.isCancelled {
                    let message = try await socket.receive()
                    guard case .string(let text) = message, let event = ScribeEvent(json: text) else { continue }
                    switch event {
                    case .partial(let text): self.partialFeed.yield(text)
                    case .committed(let text): self.finish(with: .success(TranscriptFilter.clean(text))); return
                    case .error(let type): self.finish(with: .failure(ScribeError.server(type))); return
                    case .other: continue
                    }
                }
            } catch {
                self.finish(with: .failure(error))
            }
        }
    }

    private func finish(with result: Result<String, Error>) {
        guard self.result == nil else { return }
        self.result = result
        partialFeed.finish()
        final?.resume(with: result)
        final = nil
    }

    /// Sends what was recorded since the last call. `utterance`: everything so far.
    func send(_ utterance: [Float], commit: Bool) async throws {
        startReceiving()
        guard !isCommitted, result == nil else { return }
        var start = sentSamples
        // The last piece carries the commit, so it must hold some audio.
        if commit, start >= utterance.count { start = max(0, utterance.count - 1_600) }
        guard start < utterance.count else { return }
        let audio = ScribeTranscriber.pcm16(Array(utterance[start...]))
        var offset = audio.startIndex
        while offset < audio.endIndex {
            let end = min(audio.endIndex, offset + ScribeTranscriber.chunkBytes)
            let last = end == audio.endIndex
            try await socket.send(.string(ScribeTranscriber.chunkMessage(audio[offset..<end], commit: commit && last)))
            offset = end
        }
        sentSamples = utterance.count
        if commit { isCommitted = true }
    }

    /// The final text, after `send(_:commit: true)`.
    func text() async throws -> String {
        defer { close() }
        if let result { return try result.get() }
        let timeout = Task { [weak self] in
            try? await Task.sleep(for: ScribeTranscriber.timeout)
            await self?.finish(with: .failure(ScribeError.timedOut))
        }
        defer { timeout.cancel() }
        return try await withCheckedThrowingContinuation { final = $0 }
    }

    /// The sentence was not one (noise, someone else): drop it.
    func close() {
        receiver?.cancel()
        socket.cancel(with: .normalClosure, reason: nil)
        finish(with: .failure(CancellationError()))
    }
}
