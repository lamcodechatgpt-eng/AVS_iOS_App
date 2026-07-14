import XCTest
@testable import AVS_iOS_App

final class NetworkParsingTests: XCTestCase {
    func testHomeItemsKeepStableIdentityWithinEachSection() {
        let movie = Movie(title: "Anime", link: "https://example.test/phim/anime", thumbUrl: "", episodeStatus: "")
        XCTAssertEqual(HomeItem(movie: movie, progress: 0.2, namespace: "grid"),
                       HomeItem(movie: movie, progress: 0.8, namespace: "grid"))
        XCTAssertNotEqual(HomeItem(movie: movie, namespace: "hero"),
                          HomeItem(movie: movie, namespace: "grid"))
    }

    func testEpisodesAreSortedBySemanticEpisodeNumber() {
        let episodes = [
            Episode(title: "Tập 12", link: "https://example.test/anime-tap-12"),
            Episode(title: "Tập 2", link: "https://example.test/anime-tap-2"),
            Episode(title: "Tập 1", link: "https://example.test/anime-tap-1")
        ]

        XCTAssertEqual(NetworkManager.sortedEpisodes(episodes).map(\.title),
                       ["Tập 1", "Tập 2", "Tập 12"])
    }

    func testEpisodeSortingPreservesUnknownShortLists() {
        let episodes = [
            Episode(title: "OVA", link: "https://example.test/ova"),
            Episode(title: "Special", link: "https://example.test/special")
        ]
        XCTAssertEqual(NetworkManager.sortedEpisodes(episodes).map(\.title), ["OVA", "Special"])
    }

    func testEpisodeSortingDoesNotInterleavePartsWithRepeatedNumbers() {
        let episodes = [
            Episode(title: "Phần 1 - Tập 2", link: "https://example.test/part-1-tap-2"),
            Episode(title: "Phần 1 - Tập 1", link: "https://example.test/part-1-tap-1"),
            Episode(title: "Phần 2 - Tập 2", link: "https://example.test/part-2-tap-2"),
            Episode(title: "Phần 2 - Tập 1", link: "https://example.test/part-2-tap-1")
        ]
        XCTAssertEqual(NetworkManager.sortedEpisodes(episodes).map(\.title), episodes.map(\.title))
    }

    func testGenresAreParsedFromCurrentDomainMarkupAndDeduplicated() {
        let html = """
        <a href="/the-loai/hanh-dong/">Action</a>
        <a href='https://example.test/the-loai/truong-hoc/'>School &amp; Campus</a>
        <a href="/the-loai/hanh-dong/">Action duplicate</a>
        """
        let genres = NetworkManager.parseGenres(from: html)
        XCTAssertEqual(genres.map(\.slug), ["hanh-dong", "truong-hoc"])
        XCTAssertEqual(genres.map(\.name), ["Action", "School & Campus"])
    }

    func testMovieDetailsAcceptSingleQuotesCombinedClassesAndReorderedMetaAttributes() {
        let html = """
        <meta content='Fallback description' name='description'>
        <meta content='https://cdn.example/banner.jpg' property='og:image'>
        <script type='application/ld+json'>
        {"datePublished":"2015", "aggregateRating":{"ratingValue":"9.5"}}
        </script>
        <div class='Panel Description compact'><p>A story &amp; more.</p></div>
        <a class='genre' href='/the-loai/school/'><span>School</span></a>
        <a href="/the-loai/comedy/">Comedy</a>
        """

        let details = NetworkManager.parseDetails(from: html)
        XCTAssertEqual(details.description, "A story & more.")
        XCTAssertEqual(details.year, "2015")
        XCTAssertEqual(details.rating, "9.5")
        XCTAssertEqual(details.bannerUrl, "https://cdn.example/banner.jpg")
        XCTAssertEqual(details.genres, ["School", "Comedy"])
    }
}
