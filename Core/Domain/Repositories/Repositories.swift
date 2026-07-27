import Foundation

/// Repository Protocol làm sạch tương tác với dữ liệu danh sách Phim & HTML
protocol AnimeRepositoryProtocol: AnyObject {
    func fetchHomeMovies() async throws -> [Movie]
    func fetchMovieDetails(for link: String) async throws -> MovieDetails
    func fetchEpisodes(for link: String) async throws -> [Episode]
    func searchAnime(query: String) async throws -> [Movie]
}

/// Repository Protocol tương tác dữ liệu tiến độ xem, lịch sử & phim yêu thích
protocol PlaybackRepositoryProtocol: AnyObject {
    func saveProgress(_ progress: PlaybackProgress)
    func getProgress(for episodeURL: String) -> PlaybackProgress?
    func recordWatchHistory(movie: Movie, episodeIndex: Int, episodeTitle: String, episodeURL: String?)
    func fetchHistory() -> [PlaybackStore.HistoryEntry]
    func toggleFavorite(movie: Movie) -> Bool
    func isFavorite(movie: Movie) -> Bool
    func fetchFavorites() -> [Movie]
}
