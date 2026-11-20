import AppKit
import ApplicationServices
import OptikCore
import os

/// Does what `LocalCommandParser` recognized, on this Mac, without Claude: opens and
/// quits apps, searches the web in the browser the user named, plays music in Spotify.
@MainActor
final class LocalActionRunner {
    static let shared = LocalActionRunner()

    /// The app the last command was about, so "Spotify'ı aç" then "Tarkan çal" or
    /// "Dia'yı aç" then "maç saati arat" work across sentences.
    private(set) var lastApp: String?
    private var lastAppAt = Date.distantPast
    private var installed: [String: URL] = [:]
    private var scannedAt = Date.distantPast
    private var browsers: Set<String> = []
    /// The YouTube channel opened last, for "son videosunu aç" in the next sentence.
    private var lastChannel: String?
    private let youTube = YouTubeFinder(loader: URLSessionPageLoader())
    private(set) var parser = LocalCommandParser(appNames: [])
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Optik", category: "actions")

    /// The app context is forgotten after this long.
    static let contextLifetime: TimeInterval = 600

    private init() {}

    /// Lists installed apps off the main thread. Cheap; called at launch and when a
    /// name is not found.
    func refreshApps() async {
        scannedAt = .now
        let found = await Task.detached(priority: .utility) { Self.findApps() }.value
        installed = found.apps
        browsers = found.browsers
        parser = LocalCommandParser(appNames: Array(found.apps.keys), browserNames: Array(found.browsers))
        log.info("\(found.apps.count, privacy: .public) apps, \(found.browsers.count, privacy: .public) browsers")
    }

    /// New apps show up within a minute: the list is scanned again when Optik is
    /// summoned and the last scan is older than that.
    func refreshIfStale() {
        guard Date.now.timeIntervalSince(scannedAt) > 60 else { return }
        Task { await refreshApps() }
    }

    var context: String? {
        Date.now.timeIntervalSince(lastAppAt) < Self.contextLifetime ? lastApp : nil
    }

    func parse(_ text: String) -> [CommandClause] {
        parser.parse(text, context: context)
    }

    /// Runs one action. Returns a short line for the screen ("Açıldı: Dia"), or an
    /// explanation when it could not be done.
    @discardableResult
    func run(_ action: LocalAction) async -> Outcome {
        log.info("action \(String(describing: action), privacy: .private)")
        switch action {
        case .openApp(let name):
            remember(name)
            guard let url = installed[name] else { return .failed(String(localized: "\(name) bulunamadı.")) }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            return .done(String(localized: "Açıldı: \(name)"))
        case .quitApp(let name):
            guard let url = installed[name], let bundleID = Bundle(url: url)?.bundleIdentifier else {
                return .failed(String(localized: "\(name) bulunamadı."))
            }
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).forEach { $0.terminate() }
            if lastApp == name { lastApp = nil }
            return .done(String(localized: "Kapatıldı: \(name)"))
        case .openBrowser:
            guard let browser = DefaultBrowser.applicationURL else { return .failed(String(localized: "Tarayıcı bulunamadı.")) }
            remember(DefaultBrowser.name)
            _ = try? await NSWorkspace.shared.openApplication(at: browser, configuration: NSWorkspace.OpenConfiguration())
            return .done(String(localized: "Açıldı: \(DefaultBrowser.name)"))
        case .search(let query, let browser):
            var components = URLComponents(string: "https://www.google.com/search")!
            components.queryItems = [URLQueryItem(name: "q", value: query)]
            guard let url = components.url else { return .failed(String(localized: "Arama yapılamadı.")) }
            await open(url, in: browser)
            return .done(String(localized: "Aranıyor: \(query)"))
        case .openSite(let url, let browser):
            await open(url, in: browser)
            return .done(String(localized: "Açıldı: \(url.host() ?? url.absoluteString)"))
        case .play(let query):
            remember(LocalCommandParser.spotify)
            return await SpotifyPlayer.play(query, appURL: installed[LocalCommandParser.spotify])
        case .media(let control):
            remember(LocalCommandParser.spotify)
            return await SpotifyPlayer.control(control)
        case .youtube(let target):
            remember(LocalCommandParser.youtube)
            return await runYouTube(target)
        }
    }

    enum Outcome: Equatable {
        case done(String)
        case failed(String)

        var text: String {
            switch self {
            case .done(let text), .failed(let text): text
            }
        }

        var succeeded: Bool {
            if case .done = self { return true }
            return false
        }
    }

    private func runYouTube(_ target: YouTubeTarget) async -> Outcome {
        switch target {
        case .search(let query):
            await open(YouTubePage.searchURL(query), in: nil)
            return .done(String(localized: "YouTube’da aranıyor: \(query)"))
        case .open(let query):
            switch await youTube.firstResult(for: query) {
            case .channel(let id):
                lastChannel = id
                await open(YouTubePage.channelURL(id), in: nil)
                return .done(String(localized: "YouTube’da açıldı: \(query)"))
            case .video(let id):
                await open(YouTubePage.watchURL(id), in: nil)
                return .done(String(localized: "YouTube’da açıldı: \(query)"))
            case nil:
                await open(YouTubePage.searchURL(query), in: nil)
                return .done(String(localized: "YouTube’da aranıyor: \(query)"))
            }
        case .latestVideo(let query):
            var channel = lastChannel
            if let query { channel = await youTube.channel(for: query) }
            guard let channel else {
                if let query {
                    await open(YouTubePage.searchURL(query), in: nil)
                    return .failed(String(localized: "Kanalı bulamadım, YouTube’da aramayı açtım."))
                }
                return .failed(String(localized: "Hangi kanalın videosunu açayım?"))
            }
            lastChannel = channel
            guard let video = await youTube.latestVideo(ofChannel: channel) else {
                await open(YouTubePage.videosURL(channel: channel), in: nil)
                return .done(String(localized: "Kanalın videolarını açtım."))
            }
            await open(YouTubePage.watchURL(video), in: nil)
            return .done(String(localized: "Son video açıldı"))
        }
    }

    private func remember(_ app: String) {
        lastApp = app
        lastAppAt = .now
        if browsers.contains(app) { lastBrowser = app }
    }

    /// The browser named last, so a YouTube page opens where the search did.
    private var lastBrowser: String?

    /// Opens a web page in the browser named, the browser last used, or the default.
    private func open(_ url: URL, in browser: String?) async {
        if let browser { remember(browser) }
        let name = browser ?? (Date.now.timeIntervalSince(lastAppAt) < Self.contextLifetime ? lastBrowser : nil)
        guard let app = name.flatMap({ installed[$0] }) ?? DefaultBrowser.applicationURL else {
            NSWorkspace.shared.open(url)
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try? await NSWorkspace.shared.open([url], withApplicationAt: app, configuration: configuration)
    }

    nonisolated private static func findApps() -> (apps: [String: URL], browsers: Set<String>) {
        let manager = FileManager.default
        let folders = ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
                       manager.homeDirectoryForCurrentUser.appending(path: "Applications").path]
        var apps: [String: URL] = [:]
        for folder in folders {
            guard let names = try? manager.contentsOfDirectory(atPath: folder) else { continue }
            for file in names where file.hasSuffix(".app") {
                let url = URL(fileURLWithPath: folder).appending(path: file)
                var name = manager.displayName(atPath: url.path)
                if name.hasSuffix(".app") { name.removeLast(4) }
                if apps[name] == nil { apps[name] = url }
            }
        }
        let browserURLs = NSWorkspace.shared.urlsForApplications(toOpen: URL(string: "https://example.com")!)
        let browserPaths = Set(browserURLs.map(\.standardizedFileURL.path))
        let browsers = Set(apps.filter { browserPaths.contains($0.value.standardizedFileURL.path) }.keys)
        return (apps, browsers)
    }
}
