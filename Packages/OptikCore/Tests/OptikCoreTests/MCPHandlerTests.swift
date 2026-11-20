import Foundation
import OptikCore
import Testing

struct MCPHandlerTests {
    struct Echo: ToolRunner {
        func run(_ name: String, input: Data) async -> ToolOutput {
            ToolOutput("\(name) \(String(decoding: input, as: UTF8.self))")
        }
    }

    let handler = MCPHandler(
        tools: [ToolDefinition(name: "click", description: "Tıklar.", inputSchema: Data(#"{"type":"object"}"#.utf8))],
        runner: Echo()
    )

    private func call(_ json: String) async -> [String: Any]? {
        guard let data = await handler.handle(Data(json.utf8)) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    @Test func initializesListsAndCalls() async throws {
        let start = try #require(await call(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}"#))
        let info = try #require(start["result"] as? [String: Any])
        #expect(info["protocolVersion"] as? String == "2025-06-18")

        #expect(await call(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#) == nil)

        let list = try #require(await call(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#))
        let tools = try #require((list["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        #expect(tools.first?["name"] as? String == "click")
        #expect(tools.first?["inputSchema"] as? [String: String] == ["type": "object"])

        let result = try #require(await call(#"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"click","arguments":{"id":4}}}"#))
        let content = try #require((result["result"] as? [String: Any])?["content"] as? [[String: Any]])
        #expect(content.first?["text"] as? String == #"click {"id":4}"#)

        let unknown = try #require(await call(#"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"rm"}}"#))
        #expect(unknown["error"] != nil)
    }

    @Test func readsAnHTTPRequestOnceItIsAllThere() {
        let raw = "POST /mcp HTTP/1.1\r\nHost: 127.0.0.1:5\r\nContent-Length: 4\r\n\r\n{\"a\""
        #expect(HTTPRequest.parse(Data(raw.utf8).dropLast(1)) == nil)
        let request = HTTPRequest.parse(Data(raw.utf8))
        #expect(request?.method == "POST")
        #expect(request?.headers["host"] == "127.0.0.1:5")
        #expect(request?.body == Data("{\"a\"".utf8))
    }

    @Test func bundledComputerToolsDecode() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "llm/bilgisayar-araclari.json")
        let tools = try ToolDefinition.decodeList(from: Data(contentsOf: url))
        #expect(tools.map(\.name).contains("look_at_screen"))
        #expect(Set(tools.map(\.name)).count == tools.count)
    }
}
