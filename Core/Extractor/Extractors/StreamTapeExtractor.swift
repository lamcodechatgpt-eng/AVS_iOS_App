import Foundation

public struct StreamTapeExtractor: VideoExtractor {
    public var name: String { "StreamTape" }

    public init() {}

    public func canHandle(url: String) -> Bool {
        url.lowercased().contains("streamtape")
    }

    public func extract(url: String, referer: String) async throws -> StreamSource {
        guard let validURL = URL(string: url) else {
            throw ExtractorError.invalidURL
        }
        return StreamSource(url: validURL, referer: referer.isEmpty ? "https://streamtape.com/" : referer)
    }
}
