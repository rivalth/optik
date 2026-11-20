import Foundation

/// A tool Claude can call: its name, what it is for and its input, as in the
/// Messages API (`input_schema`) and MCP (`inputSchema`).
public struct ToolDefinition: Sendable {
    public let name: String
    public let description: String
    /// The JSON schema, kept as JSON text so it passes through untouched.
    public let inputSchema: Data

    public init(name: String, description: String, inputSchema: Data) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }

    /// Reads a list like `llm/bilgisayar-araclari.json`.
    public static func decodeList(from data: Data) throws -> [ToolDefinition] {
        guard let list = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "not a list of tools"))
        }
        return try list.map { tool in
            guard let name = tool["name"] as? String, let description = tool["description"] as? String,
                  let schema = tool["input_schema"] else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "tool without name or schema"))
            }
            return ToolDefinition(name: name, description: description,
                                  inputSchema: try JSONSerialization.data(withJSONObject: schema))
        }
    }
}

public struct ToolOutput: Equatable, Sendable {
    public var text: String
    public var isError: Bool

    public init(_ text: String, isError: Bool = false) {
        self.text = text
        self.isError = isError
    }
}

/// Runs a tool with its input (a JSON object).
public protocol ToolRunner: Sendable {
    func run(_ name: String, input: Data) async -> ToolOutput
}

/// The Model Context Protocol over HTTP, the part Claude Code uses: it lists the
/// tools and calls them. One JSON-RPC message in, one out (nil for a notification).
public struct MCPHandler: Sendable {
    public static let serverName = "optik"
    let tools: [ToolDefinition]
    let runner: any ToolRunner

    public init(tools: [ToolDefinition], runner: any ToolRunner) {
        self.tools = tools
        self.runner = runner
    }

    public func handle(_ body: Data) async -> Data? {
        guard let message = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let method = message["method"] as? String else {
            return Self.error(id: nil, code: -32700, message: "parse error")
        }
        // Notifications ("notifications/initialized") have no id and no answer.
        guard let id = message["id"] else { return nil }
        let params = message["params"] as? [String: Any] ?? [:]
        switch method {
        case "initialize":
            let version = params["protocolVersion"] as? String ?? "2025-06-18"
            return Self.result(id: id, [
                "protocolVersion": version,
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": Self.serverName, "version": "1"],
            ])
        case "ping":
            return Self.result(id: id, [:])
        case "tools/list":
            let list: [[String: Any]] = tools.map { tool in
                [
                    "name": tool.name,
                    "description": tool.description,
                    "inputSchema": (try? JSONSerialization.jsonObject(with: tool.inputSchema)) ?? ["type": "object"],
                ]
            }
            return Self.result(id: id, ["tools": list])
        case "tools/call":
            guard let name = params["name"] as? String, tools.contains(where: { $0.name == name }) else {
                return Self.error(id: id, code: -32602, message: "unknown tool")
            }
            let arguments = params["arguments"] ?? [String: Any]()
            let input = (try? JSONSerialization.data(withJSONObject: arguments)) ?? Data("{}".utf8)
            let output = await runner.run(name, input: input)
            return Self.result(id: id, [
                "content": [["type": "text", "text": output.text]],
                "isError": output.isError,
            ])
        default:
            return Self.error(id: id, code: -32601, message: "method not found")
        }
    }

    private static func result(id: Any, _ result: [String: Any]) -> Data? {
        try? JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": id, "result": result])
    }

    private static func error(id: Any?, code: Int, message: String) -> Data? {
        try? JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": message],
        ])
    }
}

/// The parts of an HTTP/1.1 request the MCP endpoint needs.
public struct HTTPRequest: Equatable, Sendable {
    public var method: String
    public var path: String
    public var headers: [String: String]
    public var body: Data

    /// Parses a request once all of it has arrived; nil while more is expected.
    public static func parse(_ data: Data) -> HTTPRequest? {
        guard let end = data.firstRange(of: Data("\r\n\r\n".utf8)),
              let head = String(data: data[..<end.lowerBound], encoding: .utf8) else { return nil }
        var lines = head.components(separatedBy: "\r\n")
        let start = lines.removeFirst().split(separator: " ")
        guard start.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        let body = data[end.upperBound...]
        guard body.count >= length else { return nil }
        return HTTPRequest(method: String(start[0]), path: String(start[1]), headers: headers,
                           body: Data(body.prefix(length)))
    }

    public static func response(status: Int, reason: String, body: Data = Data(), type: String = "application/json") -> Data {
        var head = "HTTP/1.1 \(status) \(reason)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n"
        if !body.isEmpty { head += "Content-Type: \(type)\r\n" }
        return Data((head + "\r\n").utf8) + body
    }
}
