import Foundation

/// Speech to text, on the device (`docs/02-mimari.md` 3.2). Behind a protocol so
/// tests use a fake.
public protocol Transcriber: Sendable {
    /// Loads the model if it is on disk. Cheap when it is already loaded.
    func prepare() async throws
    /// `samples`: 16 kHz mono, -1...1.
    func transcribe(_ samples: [Float]) async throws -> String
    /// Frees the model's memory.
    func unload() async
}

/// Text to Optik's voice (`docs/02-mimari.md` 3.4).
public protocol SpeechSynthesizer: Sendable {
    /// The audio format of the chunks `synthesize` returns.
    var format: PCMFormat { get }
    /// Streams audio for one sentence as it is generated.
    func synthesize(_ text: String) -> AsyncThrowingStream<Data, Error>
    func warmUp() async
}

public extension SpeechSynthesizer {
    func warmUp() async {}
}

/// Signed 16-bit little-endian mono PCM.
public struct PCMFormat: Equatable, Sendable {
    public var sampleRate: Double

    public init(sampleRate: Double) {
        self.sampleRate = sampleRate
    }
}

public enum SpeechError: Error, Equatable, Sendable {
    case missingKey
    case offline
    case http(status: Int)
}

/// The latencies measured in every voice turn (`docs/02-mimari.md` 6), in ms.
/// Stored in `conversation_log.latency_ms_json` once the database lands (stage 3).
public struct TurnLatency: Equatable, Sendable, Codable {
    public var wakeToIsland: Double?
    public var wakeToEfendim: Double?
    public var speechEndToTranscript: Double?
    public var transcriptToFirstToken: Double?
    public var firstTokenToFirstAudio: Double?
    public var total: Double?

    enum CodingKeys: String, CodingKey {
        case wakeToIsland = "wake_to_island"
        case wakeToEfendim = "wake_to_efendim"
        case speechEndToTranscript = "speech_end_to_transcript"
        case transcriptToFirstToken = "transcript_to_first_token"
        case firstTokenToFirstAudio = "first_token_to_first_audio"
        case total
    }

    public init() {}

    /// Speech end → Optik's first sound: the 1.5 s budget in `CLAUDE.md`.
    public var speechEndToFirstAudio: Double? {
        guard let a = speechEndToTranscript, let b = transcriptToFirstToken, let c = firstTokenToFirstAudio else { return nil }
        return a + b + c
    }

    public var json: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}
