import Foundation

/// Lưu vị trí phát (giây) per-episode + danh sách lịch sử + danh sách yêu thích.
/// Tất cả persist qua UserDefaults với JSON.
final class PlaybackStore {
    static let shared = PlaybackStore()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Position per episode

    private let positionKey = "playback.positions"
    private let durationKey = "playback.durations"
    private let historyKey = "playback.history"
    private let favoritesKey = "playback.favorites"

    /// Lưu vị trí (giây) đang xem cho 1 episode URL.
    func savePosition(_ seconds: Double, duration: Double? = nil, for episodeUrl: String) {
        guard seconds.isFinite, seconds > 5, !episodeUrl.isEmpty else { return }
        let storageKey = ContentIdentifier.make(from: episodeUrl)
        var map = positionMap()
        map = map.filter { ContentIdentifier.make(from: $0.key) != storageKey }
        map[storageKey] = seconds
        if let data = try? JSONEncoder().encode(map) {
            defaults.set(data, forKey: positionKey)
        }
        if let duration = duration, duration.isFinite, duration > 0 {
            var durations = durationMap()
            durations = durations.filter { ContentIdentifier.make(from: $0.key) != storageKey }
            durations[storageKey] = duration
            if let data = try? JSONEncoder().encode(durations) {
                defaults.set(data, forKey: durationKey)
            }
        }
    }

    /// Lấy vị trí đã lưu cho episode URL. Trả về nil nếu chưa có hoặc < 5s.
    func position(for episodeUrl: String) -> Double? {
        let key = ContentIdentifier.make(from: episodeUrl)
        return positionMap().first(where: { ContentIdentifier.make(from: $0.key) == key })?.value
    }

    func clearPosition(for episodeUrl: String) {
        let key = ContentIdentifier.make(from: episodeUrl)
        var map = positionMap()
        map = map.filter { ContentIdentifier.make(from: $0.key) != key }
        if let data = try? JSONEncoder().encode(map) {
            defaults.set(data, forKey: positionKey)
        }
        var durations = durationMap()
        durations = durations.filter { ContentIdentifier.make(from: $0.key) != key }
        if let data = try? JSONEncoder().encode(durations) {
            defaults.set(data, forKey: durationKey)
        }
    }

    /// Tiến độ chuẩn hoá 0...1. Với dữ liệu cũ chưa có duration, dùng 24 phút làm fallback.
    func progress(for episodeUrl: String) -> Double? {
        guard let position = position(for: episodeUrl) else { return nil }
        let key = ContentIdentifier.make(from: episodeUrl)
        let duration = durationMap().first(where: { ContentIdentifier.make(from: $0.key) == key })?.value ?? 24 * 60
        guard duration > 0 else { return nil }
        return min(max(position / duration, 0), 1)
    }

    private func positionMap() -> [String: Double] {
        guard let data = defaults.data(forKey: positionKey),
              let map = try? JSONDecoder().decode([String: Double].self, from: data) else {
            return [:]
        }
        return map
    }

    private func durationMap() -> [String: Double] {
        guard let data = defaults.data(forKey: durationKey),
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
        let lastEpisodeURL: String?
        let isCompleted: Bool?
        let lastWatchedAt: TimeInterval
    }

    /// Cập nhật lịch sử khi user mở 1 tập của 1 phim.
    func recordWatch(movie: Movie, episodeIndex: Int, episodeTitle: String, episodeURL: String? = nil) {
        var list = history()
        list.removeAll { $0.movie.persistenceID == movie.persistenceID }
        list.insert(HistoryEntry(movie: movie,
                                 lastEpisodeIndex: episodeIndex,
                                 lastEpisodeTitle: episodeTitle,
                                 lastEpisodeURL: episodeURL,
                                 isCompleted: false,
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
        defaults.removeObject(forKey: positionKey)
        defaults.removeObject(forKey: durationKey)
    }

    func markCompleted(movie: Movie) {
        var list = history()
        guard let index = list.firstIndex(where: { $0.movie.persistenceID == movie.persistenceID }) else { return }
        let entry = list.remove(at: index)
        list.insert(HistoryEntry(movie: entry.movie,
                                 lastEpisodeIndex: entry.lastEpisodeIndex,
                                 lastEpisodeTitle: entry.lastEpisodeTitle,
                                 lastEpisodeURL: entry.lastEpisodeURL,
                                 isCompleted: true,
                                 lastWatchedAt: Date().timeIntervalSince1970),
                    at: 0)
        if let data = try? JSONEncoder().encode(list) {
            defaults.set(data, forKey: historyKey)
        }
    }

    // MARK: - Favorites

    func favorites() -> [Movie] {
        guard let data = defaults.data(forKey: favoritesKey),
              let list = try? JSONDecoder().decode([Movie].self, from: data) else { return [] }
        return list
    }

    func isFavorite(_ movie: Movie) -> Bool {
        return favorites().contains { $0.persistenceID == movie.persistenceID }
    }

    @discardableResult
    func toggleFavorite(_ movie: Movie) -> Bool {
        var list = favorites()
        if let idx = list.firstIndex(where: { $0.persistenceID == movie.persistenceID }) {
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
