import XCTest
@testable import AVS_iOS_App

final class ExtractorTests: XCTestCase {
    func testBalancedPlayerDataSupportsNestedObjectsAndEscapedQuotes() throws {
        let html = #"window.PLAYER_DATA = {"link":"/player/a","meta":{"label":"a } \"quote\""},"playTech":"iframe"}; tail"#
        let assignment = try XCTUnwrap(html.range(of: "window.PLAYER_DATA ="))
        let object = try XCTUnwrap(Extractor.javascriptObject(in: html, after: assignment))

        XCTAssertEqual(Extractor.playerDataField("link", in: object), "/player/a")
        XCTAssertEqual(Extractor.playerDataField("playTech", in: object), "iframe")
        XCTAssertTrue(object.hasSuffix("}"))
        XCTAssertFalse(object.contains("tail"))
    }

    func testPlayerDataFieldSupportsJavaScriptSingleQuotes() {
        let object = #"{ link: '//cdn.example/video.m3u8', playTech: 'direct' }"#
        XCTAssertEqual(Extractor.playerDataField("link", in: object), "//cdn.example/video.m3u8")
        XCTAssertEqual(Extractor.playerDataField("playTech", in: object), "direct")
    }

    func testResolvedURLSupportsCommonForms() {
        let base = "https://animevietsub.pl/xem-phim/tap-1.html"
        XCTAssertEqual(Extractor.resolvedURL("//cdn.example/a.m3u8", relativeTo: base)?.absoluteString,
                       "https://cdn.example/a.m3u8")
        XCTAssertEqual(Extractor.resolvedURL("/player/abc", relativeTo: base)?.absoluteString,
                       "https://animevietsub.pl/player/abc")
        XCTAssertEqual(Extractor.resolvedURL("../stream/a.mp4", relativeTo: base)?.absoluteString,
                       "https://animevietsub.pl/stream/a.mp4")
        XCTAssertEqual(Extractor.resolvedURL("https://cdn.example/a.m3u8?x=1&amp;y=2", relativeTo: base)?.absoluteString,
                       "https://cdn.example/a.m3u8?x=1&y=2")
    }

    func testInlinePlaylistRewritesSegmentsVariantsAndKeys() throws {
        let playlist = """
        #EXTM3U
        #EXT-X-KEY:METHOD=AES-128,URI="keys/key.bin"
        #EXT-X-MEDIA:TYPE=SUBTITLES,URI="/subs/vi.m3u8"
        variant/720.m3u8
        ../segments/001.ts
        """
        let result = Extractor.rewritingPlaylist(try XCTUnwrap(playlist.data(using: .utf8)),
                                                 relativeTo: "https://cdn.example/player/index.html")
        let output = try XCTUnwrap(String(data: result, encoding: .utf8))

        XCTAssertTrue(output.contains(#"URI="https://cdn.example/player/keys/key.bin""#))
        XCTAssertTrue(output.contains(#"URI="https://cdn.example/subs/vi.m3u8""#))
        XCTAssertTrue(output.contains("https://cdn.example/player/variant/720.m3u8"))
        XCTAssertTrue(output.contains("https://cdn.example/segments/001.ts"))
    }
}
