import XCTest
@testable import AVS_iOS_App

final class DiskCacheTests: XCTestCase {
    func testExpiredAndCorruptEntriesAreRemoved() {
        let suite = "AVS_iOS_AppTests.DiskCache"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        var currentTime: TimeInterval = 100
        let cache = DiskCache(defaults: defaults, now: { currentTime })

        cache.set(["value"], forKey: "expired")
        currentTime = 200
        let stale: (value: [String], age: TimeInterval)? = cache.getWithAge("expired", as: [String].self)
        XCTAssertEqual(stale?.value, ["value"])
        XCTAssertEqual(stale?.age, 100)
        XCTAssertNil(cache.get("expired", ttl: 10, as: [String].self))
        XCTAssertNil(defaults.data(forKey: "cache.expired"))

        defaults.set(Data("broken".utf8), forKey: "cache.corrupt")
        XCTAssertNil(cache.get("corrupt", ttl: 60, as: [String].self))
        XCTAssertNil(defaults.data(forKey: "cache.corrupt"))

        defaults.removePersistentDomain(forName: suite)
    }
}
