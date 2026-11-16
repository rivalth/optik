/// Parses a server-sent events stream line by line (`text/event-stream`).
public struct ServerSentEventParser: Sendable {
    public struct Event: Equatable, Sendable {
        public var name: String
        public var data: String

        public init(name: String, data: String) {
            self.name = name
            self.data = data
        }
    }

    private var name = ""
    private var dataLines: [String] = []

    public init() {}

    /// Feeds one line without its line ending. Returns an event when a blank line ends one.
    public mutating func feed(line: String) -> Event? {
        if line.isEmpty {
            defer { name = ""; dataLines = [] }
            guard !dataLines.isEmpty else { return nil }
            return Event(name: name.isEmpty ? "message" : name, data: dataLines.joined(separator: "\n"))
        }
        if line.hasPrefix(":") { return nil }
        let field: Substring
        var value: Substring
        if let colon = line.firstIndex(of: ":") {
            field = line[..<colon]
            value = line[line.index(after: colon)...]
            if value.hasPrefix(" ") { value = value.dropFirst() }
        } else {
            field = Substring(line)
            value = ""
        }
        switch field {
        case "event": name = String(value)
        case "data": dataLines.append(String(value))
        default: break
        }
        return nil
    }
}
