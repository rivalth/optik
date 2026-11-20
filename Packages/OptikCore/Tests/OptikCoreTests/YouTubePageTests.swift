import Foundation
import OptikCore
import Testing

struct YouTubePageTests {
    private func page(_ data: String) -> String {
        "<html><script>var ytInitialData = \(data);</script></html>"
    }

    private let search = """
    {"contents":{"twoColumnSearchResultsRenderer":{"primaryContents":{"sectionListRenderer":{"contents":[
      {"itemSectionRenderer":{"contents":[
        {"adSlotRenderer":{"videoId":"AD"}},
        {"shelfRenderer":{"content":{"videoId":"SHELF"}}},
        {"lockupViewModel":{"contentId":"UCaaaaaaaaaaaaaaaaaaaaaa","contentType":"LOCKUP_CONTENT_TYPE_CHANNEL"}},
        {"lockupViewModel":{"contentId":"v1","contentType":"LOCKUP_CONTENT_TYPE_VIDEO"}}
      ]}}
    ]}}}}}
    """

    @Test func firstOrganicResult() {
        #expect(YouTubePage.firstResult(inSearch: page(search)) == .channel(id: "UCaaaaaaaaaaaaaaaaaaaaaa"))
        let older = """
        {"contents":{"twoColumnSearchResultsRenderer":{"primaryContents":{"sectionListRenderer":{"contents":[
          {"itemSectionRenderer":{"contents":[{"videoRenderer":{"videoId":"old"}}]}}]}}}}}
        """
        #expect(YouTubePage.firstResult(inSearch: page(older)) == .video(id: "old"))
        #expect(YouTubePage.firstResult(inSearch: "<html></html>") == nil)
    }

    @Test func newestUploadOfAChannel() {
        let videos = """
        {"contents":{"twoColumnBrowseResultsRenderer":{"tabs":[
          {"tabRenderer":{"selected":false,"content":{"richGridRenderer":{"contents":[
            {"richItemRenderer":{"content":{"lockupViewModel":{"contentId":"home","contentType":"LOCKUP_CONTENT_TYPE_VIDEO"}}}}]}}}},
          {"tabRenderer":{"selected":true,"content":{"richGridRenderer":{"contents":[
            {"richItemRenderer":{"content":{"lockupViewModel":{"contentId":"newest","contentType":"LOCKUP_CONTENT_TYPE_VIDEO"}}}},
            {"richItemRenderer":{"content":{"lockupViewModel":{"contentId":"older","contentType":"LOCKUP_CONTENT_TYPE_VIDEO"}}}}]}}}}
        ]}}}
        """
        #expect(YouTubePage.latestVideo(inChannelVideos: page(videos)) == "newest")
    }

    @Test func finderGoesFromAPhraseToAVideo() async {
        struct Loader: WebPageLoader {
            let pages: [String: String]
            func html(at url: URL) async throws -> String {
                guard let page = pages[url.path()] else { throw URLError(.fileDoesNotExist) }
                return page
            }
        }
        let videos = """
        {"contents":{"twoColumnBrowseResultsRenderer":{"tabs":[{"tabRenderer":{"selected":true,"content":{"richGridRenderer":{"contents":[
          {"richItemRenderer":{"content":{"lockupViewModel":{"contentId":"newest","contentType":"LOCKUP_CONTENT_TYPE_VIDEO"}}}}]}}}}]}}}
        """
        let finder = YouTubeFinder(loader: Loader(pages: [
            "/results": page(search),
            "/channel/UCaaaaaaaaaaaaaaaaaaaaaa/videos": page(videos),
        ]))
        let channel = await finder.channel(for: "ada")
        #expect(channel == "UCaaaaaaaaaaaaaaaaaaaaaa")
        let newest = await finder.latestVideo(ofChannel: "UCaaaaaaaaaaaaaaaaaaaaaa")
        #expect(newest == "newest")
    }
}
