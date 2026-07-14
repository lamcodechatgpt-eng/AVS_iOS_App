import XCTest
@testable import AVS_iOS_App

final class PlaybackStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: PlaybackStore!
    private let suiteName = "AVS_iOS_AppTests.PlaybackStore"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        store = PlaybackStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        store = nil
        defaults = nil
        super.tearDown()
    }

    func testProgressUsesStoredDurationAndClearRemovesIt() throws {
        store.savePosition(300, duration: 1200, for: "episode-1")
        XCTAssertEqual(store.position(for: "episode-1"), 300)
        XCTAssertEqual(try XCTUnwrap(store.progress(for: "episode-1")), 0.25, accuracy: 0.0001)

        store.clearPosition(for: "episode-1")
        XCTAssertNil(store.position(for: "episode-1"))
        XCTAssertNil(store.progress(for: "episode-1"))
    }

    func testHistoryStoresEpisodeURLAndKeepsMostRecentMovieOnce() throws {
        let movie = Movie(title: "Anime", link: "/phim/anime", thumbUrl: "", episodeStatus: "")
        store.recordWatch(movie: movie, episodeIndex: 0, episodeTitle: "Tập 1", episodeURL: "/tap-1")
        store.recordWatch(movie: movie, episodeIndex: 1, episodeTitle: "Tập 2", episodeURL: "/tap-2")

        let history = store.history()
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.lastEpisodeIndex, 1)
        XCTAssertEqual(history.first?.lastEpisodeURL, "/tap-2")
    }

    func testHistoryRemainsCompatibleWithEntriesSavedByOlderVersions() throws {
        struct LegacyHistoryEntry: Codable {
            let movie: Movie
            let lastEpisodeIndex: Int
            let lastEpisodeTitle: String
            let lastWatchedAt: TimeInterval
        }
        let movie = Movie(title: "Cũ", link: "/phim/cu", thumbUrl: "", episodeStatus: "")
        let legacy = LegacyHistoryEntry(movie: movie,
                                        lastEpisodeIndex: 3,
                                        lastEpisodeTitle: "Tập 4",
                                        lastWatchedAt: 123)
        defaults.set(try JSONEncoder().encode([legacy]), forKey: "playback.history")

        let history = store.history()
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.lastEpisodeIndex, 3)
        XCTAssertNil(history.first?.lastEpisodeURL)
        XCTAssertNil(history.first?.isCompleted)
    }

    func testFavoritesAndHistorySurviveDomainChanges() {
        let oldMovie = Movie(title: "Anime", link: "https://old.example/phim/anime.html", thumbUrl: "", episodeStatus: "")
        let newMovie = Movie(title: "Anime", link: "https://new.example/phim/anime.html", thumbUrl: "", episodeStatus: "")

        XCTAssertTrue(store.toggleFavorite(oldMovie))
        XCTAssertTrue(store.isFavorite(newMovie))
        XCTAssertFalse(store.toggleFavorite(newMovie))
        XCTAssertTrue(store.favorites().isEmpty)

        store.recordWatch(movie: oldMovie, episodeIndex: 0, episodeTitle: "Tập 1")
        store.recordWatch(movie: newMovie, episodeIndex: 1, episodeTitle: "Tập 2")
        XCTAssertEqual(store.history().count, 1)
        XCTAssertEqual(store.history().first?.lastEpisodeIndex, 1)
    }

    func testProgressSurvivesEpisodeDomainChanges() throws {
        store.savePosition(120,
                           duration: 600,
                           for: "https://old.example/xem-phim/anime-tap-1.html")
        let newURL = "https://new.example/xem-phim/anime-tap-1.html"
        XCTAssertEqual(store.position(for: newURL), 120)
        XCTAssertEqual(try XCTUnwrap(store.progress(for: newURL)), 0.2, accuracy: 0.0001)

        store.clearPosition(for: newURL)
        XCTAssertNil(store.position(for: "https://old.example/xem-phim/anime-tap-1.html"))
    }

    func testCompletedMovieLeavesHistoryButIsMarkedNotToResume() {
        let movie = Movie(title: "Anime", link: "/phim/anime", thumbUrl: "", episodeStatus: "")
        store.recordWatch(movie: movie, episodeIndex: 11, episodeTitle: "Tập 12", episodeURL: "/tap-12")
        store.markCompleted(movie: movie)

        XCTAssertEqual(store.history().count, 1)
        XCTAssertEqual(store.history().first?.isCompleted, true)
    }
}
