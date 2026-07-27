import Foundation

public struct FileMoonExtractor: VideoExtractor {
    public var name: String { "FileMoon" }

    public init() {}

    public func canHandle(url: String) -> Bool {
        url.lowercased().contains("filemoon")
    }

    public func extract(url: String, referer: String) async throws -> StreamSource {
        guard let validURL = URL(string: url) else {
            throw ExtractorError.invalidURL
        }
        return StreamSource(url: validURL, referer: referer.isEmpty ? "https://filemoon.sx/" : referer)
    }
}
