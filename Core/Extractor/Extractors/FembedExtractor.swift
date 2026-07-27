import Foundation

public struct FembedExtractor: VideoExtractor {
    public var name: String { "Fembed" }

    public init() {}

    public func canHandle(url: String) -> Bool {
        let lower = url.lowercased()
        return lower.contains("fembed") || lower.contains("feurl") || lower.contains("vanikis")
    }

    public func extract(url: String, referer: String) async throws -> StreamSource {
        guard let validURL = URL(string: url) else {
            throw ExtractorError.invalidURL
        }
        return StreamSource(url: validURL, referer: referer.isEmpty ? "https://fembed.com/" : referer)
    }
}
