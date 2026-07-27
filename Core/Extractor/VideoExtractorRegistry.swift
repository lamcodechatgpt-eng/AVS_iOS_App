import Foundation

/// Bộ quản lý và giải quyết Extractor phù hợp theo Server URL
public final class VideoExtractorRegistry: @unchecked Sendable {
    public static let shared = VideoExtractorRegistry()
    private var extractors: [VideoExtractor] = []
    private let lock = NSLock()

    private init() {
        registerDefaultExtractors()
    }

    /// Đăng ký thêm Server Extractor mới
    public func register(_ extractor: VideoExtractor) {
        lock.lock()
        defer { lock.unlock() }
        extractors.append(extractor)
    }

    /// Tìm Extractor phù hợp nhất cho URL
    public func resolveExtractor(for url: String) -> VideoExtractor? {
        lock.lock()
        defer { lock.unlock() }
        return extractors.first { $0.canHandle(url: url) }
    }

    /// Trả về tất cả các extractor đã đăng ký
    public func allExtractors() -> [VideoExtractor] {
        lock.lock()
        defer { lock.unlock() }
        return extractors
    }

    private func registerDefaultExtractors() {
        register(HydraxExtractor())
        register(StreamTapeExtractor())
        register(FileMoonExtractor())
        register(GoogleVideoExtractor())
        register(FembedExtractor())
        register(DefaultAVSExtractor())
    }
}
