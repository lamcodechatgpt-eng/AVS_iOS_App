import Foundation

/// Implementation của PlaybackRepositoryProtocol wrap xung quanh PlaybackStore
final class DefaultPlaybackRepository: PlaybackRepositoryProtocol {
    private let store: PlaybackStore

    init(store: PlaybackStore = .shared) {
        self.store = store
    }

    func saveProgress(_ progress: PlaybackProgress) {
        store.savePosition(progress.positionSeconds, duration: progress.totalDurationSeconds, for: progress.episodeURL)
    }

    func getProgress(for episodeURL: String) -> PlaybackProgress? {
        guard let pos = store.position(for: episodeURL) else { return nil }
        let duration = store.progress(for: episodeURL).map { pos / max($0, 0.001) } ?? (24 * 60)
        return PlaybackProgress(episodeURL: episodeURL, positionSeconds: pos, totalDurationSeconds: duration)
    }

    func recordWatchHistory(movie: Movie, episodeIndex: Int, episodeTitle: String, episodeURL: String?) {
        store.recordWatch(movie: movie, episodeIndex: episodeIndex, episodeTitle: episodeTitle, episodeURL: episodeURL)
    }

    func fetchHistory() -> [PlaybackStore.HistoryEntry] {
        store.history()
    }

    func toggleFavorite(movie: Movie) -> Bool {
        store.toggleFavorite(movie)
    }

    func isFavorite(movie: Movie) -> Bool {
        store.isFavorite(movie)
    }

    func fetchFavorites() -> [Movie] {
        store.favorites()
    }
}
