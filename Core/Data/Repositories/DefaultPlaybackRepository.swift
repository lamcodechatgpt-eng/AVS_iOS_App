import Foundation

/// Implementation của PlaybackRepositoryProtocol wrap xung quanh PlaybackStore
public final class DefaultPlaybackRepository: PlaybackRepositoryProtocol {
    private let store: PlaybackStore

    public init(store: PlaybackStore = .shared) {
        self.store = store
    }

    public func saveProgress(_ progress: PlaybackProgress) {
        store.savePosition(progress.positionSeconds, duration: progress.totalDurationSeconds, for: progress.episodeURL)
    }

    public func getProgress(for episodeURL: String) -> PlaybackProgress? {
        guard let pos = store.position(for: episodeURL) else { return nil }
        let duration = store.progress(for: episodeURL).map { pos / max($0, 0.001) } ?? (24 * 60)
        return PlaybackProgress(episodeURL: episodeURL, positionSeconds: pos, totalDurationSeconds: duration)
    }

    public func recordWatchHistory(movie: Movie, episodeIndex: Int, episodeTitle: String, episodeURL: String?) {
        store.recordWatch(movie: movie, episodeIndex: episodeIndex, episodeTitle: episodeTitle, episodeURL: episodeURL)
    }

    public func fetchHistory() -> [PlaybackStore.HistoryEntry] {
        store.history()
    }

    public func toggleFavorite(movie: Movie) -> Bool {
        store.toggleFavorite(movie)
    }

    public func isFavorite(movie: Movie) -> Bool {
        store.isFavorite(movie)
    }

    public func fetchFavorites() -> [Movie] {
        store.favorites()
    }
}
