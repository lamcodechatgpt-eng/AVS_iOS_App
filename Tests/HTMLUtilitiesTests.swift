import XCTest
@testable import AVS_iOS_App

final class HTMLUtilitiesTests: XCTestCase {
    func testPlainTextDecodesNamedAndNumericEntities() {
        let html = "<b>Frieren &amp; Fern</b>&nbsp;&#8212; Tập &#x31;"
        XCTAssertEqual(HTMLUtilities.plainText(fromHTML: html), "Frieren & Fern — Tập 1")
    }

    func testEntityDecodingHandlesNestedAmpersandDeterministically() {
        XCTAssertEqual(HTMLUtilities.decodeEntities("&amp;quot;Anime&amp;quot; &amp;#x31;"),
                       "\"Anime\" 1")
    }

    func testSearchPathComponentNormalizesVietnameseAndEscapesReservedCharacters() {
        XCTAssertEqual(SearchUtilities.pathComponent(from: "  Đảo Hải Tặc  "), "dao+hai+tac")
        XCTAssertEqual(SearchUtilities.pathComponent(from: "Fate/Zero #1?"), "fate%2Fzero+%231%3F")
        XCTAssertNil(SearchUtilities.pathComponent(from: " \n\t "))
    }
}
