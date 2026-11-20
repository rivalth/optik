import Foundation
import Network
import OptikCore
import os

/// Gives Claude Code Optik's computer tools: a Model Context Protocol endpoint on
/// 127.0.0.1, reachable only with a secret made fresh at every launch. The secret
/// and address are written to a file only the user can read, which the Claude Code
/// script passes to `claude --mcp-config`.
final class ComputerServer: @unchecked Sendable {
    static let shared = ComputerServer()

    private let queue = DispatchQueue(label: "io.github.rivalth.optik.computer-server")
    private var listener: NWListener?
    private let token: String = {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }()
    private var port: UInt16 = 0
    private let lock = NSLock()
    private let handler = MCPHandler(tools: ComputerControl.tools, runner: ComputerControl.shared)
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Optik", category: "computer")

    /// `claude --mcp-config` reads this. Written once the server listens.
    static var configURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Optik/claude-code-mcp.json")
    }

    /// The config file, when the server is up.
    var configPath: String? {
        lock.withLock { port } == 0 ? nil : Self.configURL.path
    }

    func start() {
        guard listener == nil, !ComputerControl.tools.isEmpty else { return }
        do {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
            parameters.acceptLocalOnly = true
            let listener = try NWListener(using: parameters)
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                if case .ready = state, let port = listener.port?.rawValue {
                    self.lock.withLock { self.port = port }
                    self.writeConfig(port: port)
                    self.log.info("computer tools on port \(port, privacy: .public)")
                } else if case .failed = state {
                    self.log.error("computer tools server failed")
                }
            }
            listener.newConnectionHandler = { [weak self] connection in self?.serve(connection) }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            log.error("computer tools server could not start")
        }
    }

    private func writeConfig(port: UInt16) {
        let config: [String: Any] = [
            "mcpServers": [
                MCPHandler.serverName: [
                    "type": "http",
                    "url": "http://127.0.0.1:\(port)/mcp",
                    "headers": ["Authorization": "Bearer \(token)"],
                ],
            ],
        ]
        let url = Self.configURL
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
            FileManager.default.createFile(atPath: url.path, contents: data, attributes: [.posixPermissions: 0o600])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            log.error("could not write the Claude Code tools config")
        }
    }

    // MARK: Connections

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let request = HTTPRequest.parse(buffer) {
                Task { await self.respond(to: request, on: connection) }
            } else if isComplete || error != nil || buffer.count > 4 << 20 {
                connection.cancel()
            } else {
                self.receive(on: connection, buffer: buffer)
            }
        }
    }

    private func respond(to request: HTTPRequest, on connection: NWConnection) async {
        let reply: Data
        let port = lock.withLock { self.port }
        if request.headers["authorization"] != "Bearer \(token)" {
            reply = HTTPRequest.response(status: 401, reason: "Unauthorized")
        } else if request.headers["host"] != "127.0.0.1:\(port)" {
            // A web page reaching localhost through a renamed host.
            reply = HTTPRequest.response(status: 403, reason: "Forbidden")
        } else if request.path != "/mcp" {
            reply = HTTPRequest.response(status: 404, reason: "Not Found")
        } else if request.method != "POST" {
            // No server-sent stream: every answer comes with its request.
            reply = HTTPRequest.response(status: 405, reason: "Method Not Allowed")
        } else if let body = await handler.handle(request.body) {
            reply = HTTPRequest.response(status: 200, reason: "OK", body: body)
        } else {
            reply = HTTPRequest.response(status: 202, reason: "Accepted")
        }
        connection.send(content: reply, completion: .contentProcessed { _ in connection.cancel() })
    }
}
