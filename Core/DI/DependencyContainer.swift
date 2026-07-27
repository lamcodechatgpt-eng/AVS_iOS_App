import Foundation

/// Protocol-oriented Dependency Injection Container cho ứng dụng.
/// Cho phép đăng ký và giải phóng dependencies dạng Singleton hoặc Transient
/// một cách an toàn và dễ kiểm thử (Mocking).
@MainActor
public final class DependencyContainer {
    public static let shared = DependencyContainer()

    private var factories: [String: () -> Any] = [:]
    private var singletons: [String: Any] = [:]

    private init() {}

    /// Đăng ký dịch vụ dạng Singleton
    public func registerSingleton<T>(_ serviceType: T.Type, instance: T) {
        let key = String(describing: serviceType)
        singletons[key] = instance
    }

    /// Đăng ký dịch vụ dạng Factory (khởi tạo mới mỗi lần resolve)
    public func registerFactory<T>(_ serviceType: T.Type, factory: @escaping () -> T) {
        let key = String(describing: serviceType)
        factories[key] = factory
    }

    /// Giải phóng instance của dịch vụ đã đăng ký
    public func resolve<T>(_ serviceType: T.Type) -> T {
        let key = String(describing: serviceType)
        if let instance = singletons[key] as? T {
            return instance
        }
        if let factory = factories[key]?, let instance = factory() as? T {
            return instance
        }
        fatalError("[DependencyContainer] Dịch vụ chưa được đăng ký: \(key)")
    }

    /// Đăng ký mặc định các Repository và Services cốt lõi của ứng dụng
    public func registerDefaults() {
        let playbackRepo = DefaultPlaybackRepository()
        registerSingleton(PlaybackRepositoryProtocol.self, instance: playbackRepo)

        let animeRepo = DefaultAnimeRepository()
        registerSingleton(AnimeRepositoryProtocol.self, instance: animeRepo)
    }

    /// Dọn dẹp tất cả các đăng ký (sử dụng trong Unit Test)
    public func reset() {
        singletons.removeAll()
        factories.removeAll()
    }
}
