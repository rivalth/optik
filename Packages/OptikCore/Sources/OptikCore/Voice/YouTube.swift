import Foundation

/// What the user wants from YouTube.
public enum YouTubeTarget: Equatable, Sendable {
    /// The best result for a phrase: a channel ("cyberrulz") or a video
    /// ("tarkan kuzu kuzu"), whichever YouTube ranks first, skipping ads.
    case open(String)
    /// A channel's newest video. nil: the channel opened last.
    case latestVideo(String?)
    /// The results page.
    case search(String)
}

/// The first organic result on a YouTube page.
public enum YouTubeResult: Equatable, Sendable {
    case channel(id: String)
    case video(id: String)
}

/// Loads a web page as text. Behind a protocol so tests use a fake.
public protocol WebPageLoader: Sendable {
    func html(at url: URL) async throws -> String
}

/// Reads YouTube's pages without an API key: every page carries its content as
/// `var ytInitialData = {…};`, in the order it is shown.
public enum YouTubePage {
    public static let home = URL(string: "https://www.youtube.com")!

    public static func searchURL(_ query: String) -> URL {
        var components = URLComponents(string: "https://www.youtube.com/results")!
        components.queryItems = [URLQueryItem(name: "search_query", value: query)]
        return components.url!
    }

    public static func channelURL(_ id: String) -> URL {
        URL(string: "https://www.youtube.com/channel/\(id)")!
    }

    /// The channel's uploads, newest first.
    public static func videosURL(channel id: String) -> URL {
        URL(string: "https://www.youtube.com/channel/\(id)/videos")!
    }

    public static func watchURL(_ id: String) -> URL {
        URL(string: "https://www.youtube.com/watch?v=\(id)")!
    }

    /// The first channel or video in a search page's results. Ads, shelves
    /// ("Latest from …", Shorts) and "people also searched" are left out.
    public static func firstResult(inSearch html: String) -> YouTubeResult? {
        guard let data = initialData(in: html),
              let sections = value(data, ["contents", "twoColumnSearchResultsRenderer", "primaryContents",
                                          "sectionListRenderer", "contents"]) as? [Any] else { return nil }
        for section in sections {
            guard let items = value(section, ["itemSectionRenderer", "contents"]) as? [Any] else { continue }
            for item in items {
                if let result = result(of: item) { return result }
            }
        }
        return nil
    }

    /// The newest upload on a channel's videos page.
    public static func latestVideo(inChannelVideos html: String) -> String? {
        guard let data = initialData(in: html),
              let tabs = value(data, ["contents", "twoColumnBrowseResultsRenderer", "tabs"]) as? [Any] else { return nil }
        for tab in tabs {
            guard let renderer = value(tab, ["tabRenderer"]) as? [String: Any],
                  renderer["selected"] as? Bool == true,
                  let items = value(renderer, ["content", "richGridRenderer", "contents"]) as? [Any] else { continue }
            for item in items {
                guard let content = value(item, ["richItemRenderer", "content"]) else { continue }
                if case .video(let id) = result(of: content) { return id }
            }
        }
        return nil
    }

    /// A result item in the current layout (`lockupViewModel`) or the older one.
    private static func result(of item: Any) -> YouTubeResult? {
        if let lockup = value(item, ["lockupViewModel"]) as? [String: Any],
           let id = lockup["contentId"] as? String, let type = lockup["contentType"] as? String {
            if type.hasSuffix("_CHANNEL") { return .channel(id: id) }
            if type.hasSuffix("_VIDEO") { return .video(id: id) }
            return nil
        }
        if let id = value(item, ["videoRenderer", "videoId"]) as? String { return .video(id: id) }
        if let id = value(item, ["channelRenderer", "channelId"]) as? String { return .channel(id: id) }
        return nil
    }

    static func initialData(in html: String) -> Any? {
        guard let start = html.range(of: "ytInitialData = ")?.upperBound
            ?? html.range(of: "ytInitialData\"] = ")?.upperBound else { return nil }
        guard let end = html.range(of: ";</script>", range: start..<html.endIndex)?.lowerBound else { return nil }
        return try? JSONSerialization.jsonObject(with: Data(html[start..<end].utf8))
    }

    private static func value(_ object: Any, _ path: [String]) -> Any? {
        var current: Any? = object
        for key in path { current = (current as? [String: Any])?[key] }
        return current
    }
}

/// Finds what `YouTubeTarget` names, through YouTube's own pages.
public struct YouTubeFinder: Sendable {
    let loader: any WebPageLoader

    public init(loader: any WebPageLoader) {
        self.loader = loader
    }

    public func firstResult(for query: String) async -> YouTubeResult? {
        guard let html = try? await loader.html(at: YouTubePage.searchURL(query)) else { return nil }
        return YouTubePage.firstResult(inSearch: html)
    }

    /// The channel a phrase names: the first channel result, or the channel of
    /// the first video ("Tarkan'ın son videosu").
    public func channel(for query: String) async -> String? {
        guard let html = try? await loader.html(at: YouTubePage.searchURL(query)),
              let data = YouTubePage.initialData(in: html) else { return nil }
        if case .channel(let id) = YouTubePage.firstResult(inSearch: html) { return id }
        // A video first: its channel's id is the first "UC…" browse id on the page.
        let text = String(data: (try? JSONSerialization.data(withJSONObject: data)) ?? Data(), encoding: .utf8) ?? ""
        guard let match = text.firstMatch(of: /"browseId":"(UC[\w-]{22})"/) else { return nil }
        return String(match.1)
    }

    public func latestVideo(ofChannel id: String) async -> String? {
        guard let html = try? await loader.html(at: YouTubePage.videosURL(channel: id)) else { return nil }
        return YouTubePage.latestVideo(inChannelVideos: html)
    }
}
