import Foundation

/// Disk cache đơn giản trên UserDefaults. Mỗi entry có timestamp;
/// nếu cũ hơn TTL → bỏ qua, fetch mới. Tốt cho list movie/episode (data nhẹ).
final class DiskCache {
    static let shared = DiskCache()
    private let defaults = UserDefaults.standard
    private init() {}

    private struct Entry: Codable {
        let savedAt: TimeInterval
        let payload: Data
    }

    func set<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        let entry = Entry(savedAt: Date().timeIntervalSince1970, payload: data)
        if let encoded = try? JSONEncoder().encode(entry) {
            defaults.set(encoded, forKey: "cache.\(key)")
        }
    }

    func get<T: Decodable>(_ key: String, ttl: TimeInterval, as type: T.Type) -> T? {
        guard let raw = defaults.data(forKey: "cache.\(key)") else { return nil }
        guard let entry = try? JSONDecoder().decode(Entry.self, from: raw) else { return nil }
        if Date().timeIntervalSince1970 - entry.savedAt > ttl { return nil }
        return try? JSONDecoder().decode(T.self, from: entry.payload)
    }

    func remove(_ key: String) {
        defaults.removeObject(forKey: "cache.\(key)")
    }
}
