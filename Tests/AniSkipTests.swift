import XCTest
@testable import AVS_iOS_App

final class AniSkipTests: XCTestCase {

    func testExtractEpisodeNumberFromStandardFormats() {
        XCTAssertEqual(AniSkipManager.extractEpisodeNumber(from: "Tập 1"), 1)
        XCTAssertEqual(AniSkipManager.extractEpisodeNumber(from: "Tập 05"), 5)
        XCTAssertEqual(AniSkipManager.extractEpisodeNumber(from: "Tập 120 (FHD)"), 120)
        XCTAssertEqual(AniSkipManager.extractEpisodeNumber(from: "Episode 24"), 24)
        XCTAssertEqual(AniSkipManager.extractEpisodeNumber(from: "Ep 03"), 3)
        XCTAssertEqual(AniSkipManager.extractEpisodeNumber(from: "ep-10"), 10)
        XCTAssertEqual(AniSkipManager.extractEpisodeNumber(from: "12"), 12)
    }

    func testCleanTitleRemovesTagsAndExtractsAlternativeNames() {
        let title = "Xem Phim Solo Leveling (Tôi Thăng Cấp Một Mình) FHD Vietsub"
        let names = AniSkipManager.cleanTitle(title)
        
        XCTAssertTrue(names.contains { $0.contains("solo leveling") })
        XCTAssertTrue(names.contains { $0.contains("tôi thăng cấp một mình") })
    }

    func testCleanTitleRemovesLeadingAndTrailingEpisodeMarkers() {
        let title = "Phim Kimetsu no Yaiba Tập 12 Vietsub"
        let names = AniSkipManager.cleanTitle(title)
        
        XCTAssertTrue(names.contains("kimetsu no yaiba"))
    }

    func testExtractSlugFromURL() {
        let url1 = "https://animevietsub.meme/phim/jujutsu-kaisen-season-2-a4812/"
        XCTAssertEqual(AniSkipManager.extractSlugFromURL(url1), "jujutsu kaisen season 2")

        let url2 = "https://animevietsub.mom/phim/kimetsu-no-yaiba-hashira-geiko-hen-a5214/xem-phim.html"
        XCTAssertEqual(AniSkipManager.extractSlugFromURL(url2), "kimetsu no yaiba hashira geiko hen")
    }

    func testCleanTitleWithVietnameseOnlyAndURLFallback() {
        let title = "Thanh Gươm Diệt Quỷ: Đại Trụ Huấn Luyện"
        let url = "https://animevietsub.meme/phim/kimetsu-no-yaiba-hashira-geiko-hen-a5214/"
        let names = AniSkipManager.cleanTitle(title, url: url)

        XCTAssertTrue(names.contains("kimetsu no yaiba hashira geiko hen"))
        // ASCII / Romaji title should be prioritized first for accurate AniList/MAL matching
        XCTAssertEqual(names.first, "kimetsu no yaiba hashira geiko hen")
    }

    func testCleanTitleSeasonVariations() {
        let title = "Jujutsu Kaisen Phần 2 (Chú Thuật Hồi Chiến Mùa 2)"
        let names = AniSkipManager.cleanTitle(title)

        XCTAssertTrue(names.contains("jujutsu kaisen Season 2"))
        XCTAssertTrue(names.contains("jujutsu kaisen 2"))
    }

    func testAniSkipResultSerialization() throws {
        let intro = SkipInterval(start: 90.0, end: 180.0, episodeLength: 1440.0)
        let outro = SkipInterval(start: 1300.0, end: 1420.0, episodeLength: 1440.0)
        let result = AniSkipResult(intro: intro, outro: outro, isEstimated: false)

        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(AniSkipResult.self, from: data)

        XCTAssertEqual(decoded, result)
        XCTAssertEqual(decoded.intro?.start, 90.0)
        XCTAssertEqual(decoded.outro?.end, 1420.0)
        XCTAssertFalse(decoded.isEstimated)
    }
}
