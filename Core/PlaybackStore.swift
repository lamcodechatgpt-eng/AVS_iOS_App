import Foundation

/// Lưu vị trí phát (giây) per-episode + danh sách lịch sử + danh sách yêu thích.
/// Tất cả persist qua UserDefaults với JSON.
final class PlaybackStore {
    static let shared = PlaybackStore()
    private let defaults = UserDefaults.standard
    private let queue = DispatchQueue(label: "com.avs.playbackstore.sync")
    private init() {}

    // MARK: - Position per episode

    private let positionKey = "playback.positions"
    private let historyKey = "playback.history"
    private let favoritesKey = "playback.favorites"

    /// Lưu vị trí (giây) đang xem cho 1 episode URL.
    func savePosition(_ seconds: Double, for episodeUrl: String) {
        guard seconds > 5 else { return }
        var map = positionMap()
        map[episodeUrl] = seconds
        if let data = try? JSONEncoder().encode(map) {
            defaults.set(data, forKey: positionKey)
        }
    }

    /// Lấy vị trí đã lưu cho episode URL. Trả về nil nếu chưa có hoặc < 5s.
    func position(for episodeUrl: String) -> Double? {
        return positionMap()[episodeUrl]
    }

    func clearPosition(for episodeUrl: String) {
        var map = positionMap()
        map.removeValue(forKey: episodeUrl)
        if let data = try? JSONEncoder().encode(map) {
            defaults.set(data, forKey: positionKey)
        }
    }

    private func positionMap() -> [String: Double] {
        guard let data = defaults.data(forKey: positionKey),
              let map = try? JSONDecoder().decode([String: Double].self, from: data) else {
            return [:]
        }
        return map
    }

    // MARK: - History

    struct HistoryEntry: Codable {
        let movie: Movie
        let lastEpisodeIndex: Int
        let lastEpisodeTitle: String
        let lastWatchedAt: TimeInterval
    }

    /// Cập nhật lịch sử khi user mở 1 tập của 1 phim.
    func recordWatch(movie: Movie, episodeIndex: Int, episodeTitle: String) {
        var list = history()
        list.removeAll { $0.movie.link == movie.link }
        list.insert(HistoryEntry(movie: movie,
                                 lastEpisodeIndex: episodeIndex,
                                 lastEpisodeTitle: episodeTitle,
                                 lastWatchedAt: Date().timeIntervalSince1970),
                    at: 0)
        if list.count > 100 { list = Array(list.prefix(100)) }
        if let data = try? JSONEncoder().encode(list) {
            defaults.set(data, forKey: historyKey)
        }
    }

    func history() -> [HistoryEntry] {
        guard let data = defaults.data(forKey: historyKey),
              let list = try? JSONDecoder().decode([HistoryEntry].self, from: data) else { return [] }
        return list
    }

    func clearHistory() {
        defaults.removeObject(forKey: historyKey)
    }

    // MARK: - Favorites

    func favorites() -> [Movie] {
        guard let data = defaults.data(forKey: favoritesKey),
              let list = try? JSONDecoder().decode([Movie].self, from: data) else { return [] }
        return list
    }

    func isFavorite(_ movie: Movie) -> Bool {
        return favorites().contains { $0.link == movie.link }
    }

    @discardableResult
    func toggleFavorite(_ movie: Movie) -> Bool {
        var list = favorites()
        if let idx = list.firstIndex(where: { $0.link == movie.link }) {
            list.remove(at: idx)
            persistFavorites(list)
            return false
        } else {
            list.insert(movie, at: 0)
            persistFavorites(list)
            return true
        }
    }

    private func persistFavorites(_ list: [Movie]) {
        if let data = try? JSONEncoder().encode(list) {
            defaults.set(data, forKey: favoritesKey)
        }
    }
}
