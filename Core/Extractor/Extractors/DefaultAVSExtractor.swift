import Foundation

public struct DefaultAVSExtractor: VideoExtractor {
    public var name: String { "AnimeVietsub Standard Server" }

    public init() {}

    public func canHandle(url: String) -> Bool {
        true // Mặc định xử lý tất cả các URL nếu không có extractor nào khác bắt được
    }

    public func extract(url: String, referer: String) async throws -> StreamSource {
        guard let validURL = URL(string: url) else {
            throw ExtractorError.invalidURL
        }
        let ref = referer.isEmpty ? "\(NetworkManager.shared.resolvedDomain)/" : referer
        return StreamSource(url: validURL, referer: ref)
    }
}
