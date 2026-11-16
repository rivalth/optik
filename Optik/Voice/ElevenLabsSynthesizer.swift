import Foundation
import OptikCore

/// Optik's voice through ElevenLabs, streamed as raw PCM (`docs/02-mimari.md` 3.4).
/// 24 kHz PCM is available on every plan, the free one included.
final class ElevenLabsSynthesizer: SpeechSynthesizer {
    /// Jessica, ElevenLabs premade voice (`llm/ses-kimligi.md`).
    static let defaultVoiceID = "cgSgspJ2msm6clMCkdW9"
    static let liveModel = "eleven_v4_turbo"

    let format = PCMFormat(sampleRate: 24_000)

    private let session: URLSession
    private let apiKey: @Sendable () -> String?
    private let voiceID: @Sendable () -> String

    init(session: URLSession = .shared,
         apiKey: @escaping @Sendable () -> String? = { KeychainStore.read(.elevenLabs) },
         voiceID: @escaping @Sendable () -> String = { ElevenLabsSynthesizer.defaultVoiceID }) {
        self.session = session
        self.apiKey = apiKey
        self.voiceID = voiceID
    }

    var hasKey: Bool { apiKey() != nil }

    func synthesize(_ text: String) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let key = apiKey() else { throw SpeechError.missingKey }
                    var components = URLComponents(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceID())/stream")!
                    components.queryItems = [URLQueryItem(name: "output_format", value: "pcm_24000")]
                    var request = URLRequest(url: components.url!, timeoutInterval: 20)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "content-type")
                    request.setValue(key, forHTTPHeaderField: "xi-api-key")
                    request.httpBody = try JSONSerialization.data(withJSONObject: [
                        "text": text, "model_id": Self.liveModel, "language_code": "tr",
                    ])
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                        throw SpeechError.http(status: (response as? HTTPURLResponse)?.statusCode ?? 0)
                    }
                    // ~50 ms chunks; an even byte count keeps 16-bit samples whole.
                    var chunk = Data()
                    chunk.reserveCapacity(2_400)
                    for try await byte in bytes {
                        chunk.append(byte)
                        if chunk.count >= 2_400 {
                            continuation.yield(chunk)
                            chunk = Data()
                            chunk.reserveCapacity(2_400)
                        }
                    }
                    if chunk.count > 1 { continuation.yield(chunk.prefix(chunk.count & ~1)) }
                    continuation.finish()
                } catch let error as URLError {
                    continuation.finish(throwing: error.code == .cancelled ? CancellationError() : SpeechError.offline)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func warmUp() async {
        guard let key = apiKey() else { return }
        var request = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/models")!, timeoutInterval: 5)
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        _ = try? await session.data(for: request)
    }
}
