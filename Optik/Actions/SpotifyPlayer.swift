import AppKit
import ApplicationServices
import OptikCore

/// Spotify without its Web API: Apple Events for play, pause and skipping, and for
/// a song by name its own search page, where Optik presses the best matching play
/// button through Accessibility (Spotify's scripting cannot search).
@MainActor
enum SpotifyPlayer {
    static let bundleID = "com.spotify.client"

    static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    static func control(_ control: MediaControl) async -> LocalActionRunner.Outcome {
        guard isRunning else { return .failed(String(localized: "Spotify açık değil.")) }
        let command = switch control {
        case .play: "play"
        case .pause: "pause"
        case .next: "next track"
        case .previous: "previous track"
        }
        guard await AppleScriptRunner.run("tell application id \"\(bundleID)\" to \(command)") != nil else {
            return .failed(String(localized: "Spotify’a ulaşamadım. Otomasyon iznini Sistem Ayarları’ndan verebilirsin."))
        }
        return switch control {
        case .play: .done(String(localized: "Çalıyor"))
        case .pause: .done(String(localized: "Durduruldu"))
        case .next: .done(String(localized: "Sonraki şarkı"))
        case .previous: .done(String(localized: "Önceki şarkı"))
        }
    }

    /// Spotify draws its window with Chromium, which shows the page to Accessibility
    /// only when started with this flag.
    static let accessibilityArgument = "--force-renderer-accessibility"

    /// Starts Spotify with its page visible to Accessibility.
    private static func launch(_ appURL: URL) async {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = [accessibilityArgument]
        configuration.activates = true
        _ = try? await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
        for _ in 0..<40 where !isRunning { try? await Task.sleep(for: .milliseconds(200)) }
        // The window needs a moment after the process starts.
        try? await Task.sleep(for: .seconds(2.5))
    }

    /// Quits Spotify and starts it again with the flag. Once per Spotify session,
    /// when it was started without it.
    private static func relaunch(_ appURL: URL) async {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).forEach { $0.terminate() }
        for _ in 0..<40 where isRunning { try? await Task.sleep(for: .milliseconds(200)) }
        await launch(appURL)
    }

    /// Opens Spotify's search for `query` and plays the result that matches it best.
    static func play(_ query: String, appURL: URL?) async -> LocalActionRunner.Outcome {
        guard let appURL else { return .failed(String(localized: "Spotify bulunamadı.")) }
        if !isRunning { await launch(appURL) }
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let search = URL(string: "spotify:search:\(encoded)") else {
            return .failed(String(localized: "Arama yapılamadı."))
        }
        NSWorkspace.shared.open(search)
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.activate()

        guard AccessibilityControl.isTrusted else {
            AccessibilityControl.requestTrust()
            return .failed(String(localized: "Spotify’da aramayı açtım. İlk sonuca tıklayabilmem için Optik’e Erişilebilirlik izni ver."))
        }
        let before = await nowPlaying()
        var relaunched = false
        // Results load a moment after the page opens; look a few times.
        for attempt in 0..<10 {
            try? await Task.sleep(for: .milliseconds(attempt == 0 ? 1200 : 500))
            guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.processIdentifier else {
                return .failed(String(localized: "Spotify açık değil."))
            }
            let result = await Task.detached(priority: .userInitiated) {
                AccessibilityControl.pressPlayButton(inApp: pid, matching: query)
            }.value
            if result == .pageHidden, !relaunched {
                // Started without the flag (by the user, or before Optik): start it again.
                relaunched = true
                await relaunch(appURL)
                NSWorkspace.shared.open(search)
                continue
            }
            guard result == .pressed else { continue }
            try? await Task.sleep(for: .milliseconds(700))
            if let playing = await nowPlaying(), playing != before {
                return .done(String(localized: "Çalıyor: \(playing)"))
            }
            return .done(String(localized: "Çalıyor: \(query)"))
        }
        return .failed(String(localized: "Spotify’da aramayı açtım ama çalacak sonucu bulamadım."))
    }

    /// "Kuzu Kuzu – Tarkan" while playing, nil otherwise.
    static func nowPlaying() async -> String? {
        let script = """
        tell application id "\(bundleID)"
            if player state is playing then return (name of current track) & " – " & (artist of current track)
        end tell
        return ""
        """
        guard let result = await AppleScriptRunner.run(script), !result.isEmpty else { return nil }
        return result
    }
}

/// Runs AppleScript off the main thread, one script at a time.
enum AppleScriptRunner {
    private static let queue = DispatchQueue(label: "io.github.rivalth.optik.applescript")

    /// The result as text, or nil when the script failed (no permission, app gone).
    static func run(_ source: String) async -> String? {
        await withCheckedContinuation { continuation in
            queue.async {
                var error: NSDictionary?
                let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
                continuation.resume(returning: error == nil ? (result?.stringValue ?? "") : nil)
            }
        }
    }
}

/// Pressing buttons in other apps (System Settings → Privacy & Security → Accessibility).
enum AccessibilityControl {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that leads to the Accessibility list.
    static func requestTrust() {
        // The value of kAXTrustedCheckOptionPrompt, which Swift 6 sees as shared mutable state.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Words that start a play button's label, in Spotify's languages.
    private static let playWords = ["play", "çal", "oynat"]

    enum PressResult: Equatable, Sendable {
        case pressed
        case notFound
        /// The app shows no page content to Accessibility (Chromium without the flag).
        case pageHidden
    }

    /// Presses the play button that fits `query` best on a search page:
    /// 1. the top result's green button, when its card holds every word of the
    ///    query: Spotify ranks it first by popularity, and song rows name only the
    ///    title, so two songs called "Kuzu Kuzu" look the same there;
    /// 2. otherwise a result row whose title shares the most words with the query
    ///    and has the fewest others;
    /// 3. otherwise the top result anyway (an artist, a playlist).
    /// The library on the left and the player bar at the bottom are left out.
    nonisolated static func pressPlayButton(inApp pid: pid_t, matching query: String) -> PressResult {
        let app = AXUIElementCreateApplication(pid)
        // Electron apps expose their page when asked; Chromium apps need a flag.
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        let tokens = Set(words(query))
        guard !tokens.isEmpty else { return .notFound }

        var best: (element: AXUIElement, score: Int)?
        var topBare: (element: AXUIElement, y: CGFloat)?
        var window = CGRect.null
        var queue: [AXUIElement] = [app]
        var visited = 0
        while !queue.isEmpty, visited < 25_000 {
            let element = queue.removeFirst()
            visited += 1
            let role = role(of: element)
            if role == kAXWindowRole as String, let frame = frame(of: element), frame.width * frame.height > window.width * window.height || window.isNull {
                window = frame
            }
            if role == kAXButtonRole as String, let label = label(of: element),
               let frame = frame(of: element), !window.isNull,
               // The library list fills the left quarter, the player bar the bottom.
               frame.minX > window.minX + window.width * 0.22, frame.minY < window.maxY - 120 {
                let labelWords = words(label)
                if let first = labelWords.first, playWords.contains(first) {
                    let title = Set(labelWords.dropFirst())
                    if title.isEmpty {
                        if frame.minY < (topBare?.y ?? .infinity) { topBare = (element, frame.minY) }
                    } else {
                        let shared = tokens.intersection(title).count
                        let score = shared * 10 - title.subtracting(tokens).count
                        if shared > 0, score > (best?.score ?? .min) { best = (element, score) }
                    }
                }
            }
            queue.append(contentsOf: children(of: element))
        }
        if visited < 600 { return .pageHidden }
        let target: AXUIElement?
        if let top = topBare?.element, tokens.isSubset(of: cardWords(around: top)) {
            target = top
        } else {
            target = best?.element ?? topBare?.element
        }
        guard let target else { return .notFound }
        return AXUIElementPerformAction(target, kAXPressAction as CFString) == .success ? .pressed : .notFound
    }

    /// The words of the card a button sits on ("Kuzu Kuzu", "Song • Tarkan"): the
    /// text under its nearest ancestors, up to the first one that has some.
    private static func cardWords(around element: AXUIElement) -> Set<String> {
        var current = element
        for _ in 0..<4 {
            guard let parent = attribute(kAXParentAttribute, of: current) else { break }
            current = parent as! AXUIElement
            var found = Set<String>()
            var queue = [current]
            var visited = 0
            while !queue.isEmpty, visited < 200 {
                let node = queue.removeFirst()
                visited += 1
                if role(of: node) != kAXButtonRole as String {
                    for name in [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute] {
                        if let text = attribute(name, of: node) as? String { found.formUnion(words(text)) }
                    }
                }
                queue.append(contentsOf: children(of: node))
            }
            if !found.isEmpty { return found }
        }
        return []
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        guard let position = attribute(kAXPositionAttribute, of: element),
              let size = attribute(kAXSizeAttribute, of: element) else { return nil }
        var point = CGPoint.zero, extent = CGSize.zero
        AXValueGetValue(position as! AXValue, .cgPoint, &point)
        AXValueGetValue(size as! AXValue, .cgSize, &extent)
        return CGRect(origin: point, size: extent)
    }

    private static func words(_ text: String) -> [String] {
        text.lowercased(with: Locale(identifier: "tr_TR"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private static func role(of element: AXUIElement) -> String? {
        attribute(kAXRoleAttribute, of: element) as? String
    }

    private static func label(of element: AXUIElement) -> String? {
        for name in [kAXDescriptionAttribute, kAXTitleAttribute] {
            if let text = attribute(name, of: element) as? String, !text.isEmpty { return text }
        }
        return nil
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        (attribute(kAXChildrenAttribute, of: element) as? [AXUIElement]) ?? []
    }

    private static func attribute(_ name: String, of element: AXUIElement) -> AnyObject? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}
