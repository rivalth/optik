import Foundation

/// The sentence being streamed to Scribe while the user talks: a quarter second
/// at a time from the recorder, with Scribe's partial text shown as it comes.
@MainActor
final class LiveSentence {
    let utterance: Int
    private var session: ScribeLiveSession?
    private var feeder: Task<Void, Never>?
    private var listener: Task<Void, Never>?

    static let interval: Duration = .milliseconds(250)

    /// `onPartial` runs on the main actor; `onUnavailable` when there is no stream
    /// (no key), so the caller writes the live text another way.
    init(utterance: Int, transcriber: SentenceTranscriber, recorder: UtteranceRecorder,
         onPartial: @escaping @MainActor (String) -> Void, onUnavailable: @escaping @MainActor () -> Void) {
        self.utterance = utterance
        feeder = Task { [weak self] in
            guard let session = await transcriber.startLive() else {
                if !Task.isCancelled { onUnavailable() }
                return
            }
            guard let self, !Task.isCancelled else { await session.close(); return }
            self.session = session
            self.listener = Task {
                for await text in session.partials where !text.isEmpty { onPartial(text) }
            }
            while !Task.isCancelled {
                let snapshot = recorder.snapshot()
                guard snapshot.id == utterance else { break }
                try? await session.send(snapshot.samples, commit: false)
                try? await Task.sleep(for: Self.interval)
            }
        }
    }

    /// Stops feeding and hands over the session for the commit; nil when the stream
    /// never opened.
    func finish() async -> ScribeLiveSession? {
        feeder?.cancel()
        await feeder?.value
        listener?.cancel()
        return session
    }

    /// Not a sentence after all.
    func cancel() {
        feeder?.cancel()
        listener?.cancel()
        let session = self.session
        Task { await session?.close() }
    }
}
