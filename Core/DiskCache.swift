import Foundation

/// Disk cache đơn giản trên UserDefaults. Mỗi entry có timestamp;
/// nếu cũ hơn TTL → bỏ qua, fetch mới. Tốt cho list movie/episode (data nhẹ).
final class DiskCache {
    static let shared = DiskCache()
    private let defaults: UserDefaults
    private let now: () -> TimeInterval

    init(defaults: UserDefaults = .standard,
         now: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 }) {
        self.defaults = defaults
        self.now = now
    }

    private struct Entry: Codable {
        let savedAt: TimeInterval
        let payload: Data
    }

    func set<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        let entry = Entry(savedAt: now(), payload: data)
        if let encoded = try? JSONEncoder().encode(entry) {
            defaults.set(encoded, forKey: "cache.\(key)")
        }
    }

    func get<T: Decodable>(_ key: String, ttl: TimeInterval, as type: T.Type) -> T? {
        guard let raw = defaults.data(forKey: "cache.\(key)") else { return nil }
        guard let entry = try? JSONDecoder().decode(Entry.self, from: raw) else {
            remove(key)
            return nil
        }
        let age = now() - entry.savedAt
        if age < 0 || age > max(0, ttl) {
            remove(key)
            return nil
        }
        guard let value = try? JSONDecoder().decode(T.self, from: entry.payload) else {
            remove(key)
            return nil
        }
        return value
    }

    func remove(_ key: String) {
        defaults.removeObject(forKey: "cache.\(key)")
    }

    func removeAll() {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("cache.") {
            defaults.removeObject(forKey: key)
        }
    }
}
