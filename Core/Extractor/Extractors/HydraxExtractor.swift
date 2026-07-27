import Foundation

public struct HydraxExtractor: VideoExtractor {
    public var name: String { "Hydrax" }

    public init() {}

    public func canHandle(url: String) -> Bool {
        let lower = url.lowercased()
        return lower.contains("hydrax") || lower.contains("iamcdn") || lower.contains("whos.amung.us")
    }

    public func extract(url: String, referer: String) async throws -> StreamSource {
        guard let validURL = URL(string: url) else {
            throw ExtractorError.invalidURL
        }
        return StreamSource(url: validURL, referer: referer.isEmpty ? url : referer)
    }
}
