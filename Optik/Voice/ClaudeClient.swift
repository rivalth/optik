import Foundation
import OptikCore

/// Claude Messages API over `URLSession`, streamed (`docs/02-mimari.md` 3.3).
/// The key is read from the Keychain for every request, so a new key works at once.
final class ClaudeClient: LLMClient {
    private let session: URLSession
    private let apiKey: @Sendable () -> String?

    init(session: URLSession = .shared, apiKey: @escaping @Sendable () -> String? = { KeychainStore.read(.anthropic) }) {
        self.session = session
        self.apiKey = apiKey
    }

    func stream(_ request: LLMRequest) -> AsyncThrowingStream<LLMEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let key = apiKey() else { throw LLMError.missingKey }
                    var urlRequest = URLRequest(url: ClaudeMessages.endpoint, timeoutInterval: 30)
                    urlRequest.httpMethod = "POST"
                    urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
                    urlRequest.setValue(key, forHTTPHeaderField: "x-api-key")
                    urlRequest.setValue(ClaudeMessages.apiVersion, forHTTPHeaderField: "anthropic-version")
                    urlRequest.httpBody = try ClaudeMessages.body(for: request)

                    let (bytes, response) = try await session.bytes(for: urlRequest)
                    guard let http = response as? HTTPURLResponse else { throw LLMError.malformedResponse }
                    guard http.statusCode == 200 else {
                        var body = Data()
                        for try await byte in bytes { body.append(byte); if body.count > 8_192 { break } }
                        throw LLMError.http(status: http.statusCode, type: ClaudeMessages.errorType(in: body))
                    }
                    var parser = ServerSentEventParser()
                    var decoder = ClaudeMessages.StreamDecoder()
                    // `lines` drops blank lines; every Claude event has a single data line,
                    // so a data line completes its event.
                    for try await line in bytes.lines {
                        _ = parser.feed(line: line)
                        guard line.hasPrefix("data:"), let event = parser.feed(line: "") else { continue }
                        if let decoded = try decoder.decode(event) {
                            continuation.yield(decoded)
                            if case .finished = decoded { break }
                        }
                    }
                    continuation.finish()
                } catch let error as URLError {
                    continuation.finish(throwing: error.code == .cancelled ? CancellationError() : LLMError.offline)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// A tiny authenticated request that leaves a warm connection in the session's pool.
    func warmUp() async {
        guard let key = apiKey() else { return }
        var request = URLRequest(url: ClaudeMessages.modelsEndpoint.appending(queryItems: [URLQueryItem(name: "limit", value: "1")]),
                                 timeoutInterval: 5)
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue(ClaudeMessages.apiVersion, forHTTPHeaderField: "anthropic-version")
        _ = try? await session.data(for: request)
    }
}
