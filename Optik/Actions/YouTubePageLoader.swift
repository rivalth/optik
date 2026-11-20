import Foundation
import OptikCore

/// Loads YouTube pages the way a browser would, so they carry their results.
struct URLSessionPageLoader: WebPageLoader {
    func html(at url: URL) async throws -> String {
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("tr-TR,tr;q=0.9", forHTTPHeaderField: "Accept-Language")
        // Skips the cookie consent page shown in some countries.
        request.setValue("SOCS=CAI", forHTTPHeaderField: "Cookie")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return String(decoding: data, as: UTF8.self)
    }
}
