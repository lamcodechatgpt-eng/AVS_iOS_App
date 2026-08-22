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
