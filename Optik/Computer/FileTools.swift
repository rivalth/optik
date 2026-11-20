import AppKit
import OptikCore

/// Files and folders for Claude, only inside the user's home folder: find them
/// with Spotlight, make folders, open, move, rename, and put things in the Trash
/// (never deleted outright).
enum FileTools {
    static let names: Set<String> = ["find_files", "create_folder", "open_path", "move_item", "trash_item"]

    static func handles(_ name: String) -> Bool { names.contains(name) }

    static func run(_ name: String, arguments: [String: Any]) -> ToolOutput {
        switch name {
        case "find_files":
            guard let query = arguments["query"] as? String, !query.isEmpty else { return ToolOutput("query gerekli.", isError: true) }
            return find(query, kind: arguments["kind"] as? String ?? "any", inside: arguments["inside"] as? String)
        case "create_folder":
            guard let url = homePath(arguments["path"]) else { return outsideHome }
            if FileManager.default.fileExists(atPath: url.path) { return ToolOutput("Zaten var: \(display(url))") }
            do {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                return ToolOutput("Klasör oluşturuldu: \(display(url))")
            } catch {
                return ToolOutput("Klasör oluşturulamadı: \(error.localizedDescription)", isError: true)
            }
        case "open_path":
            guard let url = homePath(arguments["path"]) else { return outsideHome }
            guard FileManager.default.fileExists(atPath: url.path) else { return ToolOutput("Böyle bir yol yok: \(display(url))", isError: true) }
            let reveal = arguments["reveal"] as? Bool ?? false
            DispatchQueue.main.async {
                if reveal {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } else {
                    NSWorkspace.shared.open(url)
                }
            }
            return ToolOutput((reveal ? "Finder'da gösterildi: " : "Açıldı: ") + display(url))
        case "move_item":
            guard let from = homePath(arguments["from"]), let to = homePath(arguments["to"]) else { return outsideHome }
            guard FileManager.default.fileExists(atPath: from.path) else { return ToolOutput("Böyle bir yol yok: \(display(from))", isError: true) }
            guard !FileManager.default.fileExists(atPath: to.path) else { return ToolOutput("Hedefte aynı adda bir şey var: \(display(to))", isError: true) }
            do {
                try FileManager.default.moveItem(at: from, to: to)
                return ToolOutput("Taşındı: \(display(from)) → \(display(to))")
            } catch {
                return ToolOutput("Taşınamadı: \(error.localizedDescription)", isError: true)
            }
        case "trash_item":
            guard let url = homePath(arguments["path"]) else { return outsideHome }
            guard url.standardizedFileURL != home else { return ToolOutput("Ev klasörü çöpe atılamaz.", isError: true) }
            do {
                var trashed: NSURL?
                try FileManager.default.trashItem(at: url, resultingItemURL: &trashed)
                return ToolOutput("Çöp Sepeti'ne taşındı: \(display(url)). Çöp Sepeti'nden geri alınabilir.")
            } catch {
                return ToolOutput("Çöpe atılamadı: \(error.localizedDescription)", isError: true)
            }
        default:
            return ToolOutput("Bilinmeyen araç: \(name)", isError: true)
        }
    }

    private static let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
    private static let outsideHome = ToolOutput("Yalnızca ev klasörünün içindeki yollarla çalışırım (~/...).", isError: true)

    /// "~/Desktop/Faturalar" or an absolute path, only inside the home folder.
    static func homePath(_ value: Any?) -> URL? {
        guard var text = (value as? String)?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        if text == "~" { text = home.path }
        if text.hasPrefix("~/") { text = home.path + text.dropFirst(1) }
        guard text.hasPrefix("/") else { return nil }
        let url = URL(fileURLWithPath: text).standardizedFileURL.resolvingSymlinksInPath()
        let base = home.resolvingSymlinksInPath().path
        guard url.path == base || url.path.hasPrefix(base + "/") else { return nil }
        return url
    }

    /// Names containing `query`, nearest first (level by level, at most six deep),
    /// for up to three seconds. Skips Library, hidden folders and build folders.
    private static func walk(_ folder: URL, for query: String) -> [URL] {
        let wanted = query.lowercased(with: Locale(identifier: "tr_TR"))
        let skipped: Set<String> = ["Library", "node_modules", ".build", "DerivedData", "Pods", "Applications"]
        let manager = FileManager.default
        let deadline = Date.now.addingTimeInterval(3)
        var found: [URL] = []
        var level = [folder]
        for _ in 0..<6 {
            var next: [URL] = []
            for directory in level {
                if Date.now > deadline || found.count >= 100 { return found }
                guard let entries = try? manager.contentsOfDirectory(
                    at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey], options: [.skipsHiddenFiles]
                ) else { continue }
                for url in entries {
                    if url.lastPathComponent.lowercased(with: Locale(identifier: "tr_TR")).contains(wanted) { found.append(url) }
                    let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
                    if values?.isDirectory == true, values?.isPackage != true, !skipped.contains(url.lastPathComponent) {
                        next.append(url)
                    }
                }
            }
            level = next
        }
        return found
    }

    private static func display(_ url: URL) -> String {
        url.path.hasPrefix(home.path) ? "~" + url.path.dropFirst(home.path.count) : url.path
    }

    private static func find(_ query: String, kind: String, inside: String?) -> ToolOutput {
        let folder = inside.map { homePath($0) } ?? home
        guard let folder else { return outsideHome }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = ["-onlyin", folder.path, "-name", query]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return ToolOutput("Spotlight çalışmadı.", isError: true) }
        let deadline = Date.now.addingTimeInterval(6)
        var data = Data()
        while process.isRunning, Date.now < deadline { data.append(pipe.fileHandleForReading.availableData) }
        if process.isRunning { process.terminate() }
        data.append(pipe.fileHandleForReading.readDataToEndOfFile())

        let library = home.appending(path: "Library").path
        var paths = String(decoding: data, as: UTF8.self).split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
        // Spotlight can be off for the home folder: then look through it directly.
        if paths.isEmpty { paths = walk(folder, for: query) }
        var found: [(url: URL, date: Date, isFolder: Bool)] = []
        for url in paths {
            guard !url.path.hasPrefix(library), !url.pathComponents.contains(where: { $0.hasPrefix(".") }),
                  let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey, .isPackageKey])
            else { continue }
            let isFolder = values.isDirectory == true && values.isPackage != true
            if kind == "folder", !isFolder { continue }
            if kind == "file", isFolder { continue }
            found.append((url, values.contentModificationDate ?? .distantPast, isFolder))
        }
        guard !found.isEmpty else { return ToolOutput("\"\(query)\" adında bir şey bulunamadı.") }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.timeZone = TurnContext.timeZone
        formatter.dateFormat = "d MMM yyyy HH.mm"
        let lines = found.sorted { $0.date > $1.date }.prefix(20).map {
            "\($0.isFolder ? "klasör" : "dosya") \(display($0.url)) (değişti: \(formatter.string(from: $0.date)))"
        }
        let more = found.count > 20 ? "\n(\(found.count - 20) sonuç daha var.)" : ""
        return ToolOutput(lines.joined(separator: "\n") + more)
    }
}
