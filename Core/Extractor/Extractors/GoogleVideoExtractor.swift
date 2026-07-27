import Foundation

public struct GoogleVideoExtractor: VideoExtractor {
    public var name: String { "GoogleVideo / GoogleApisCDN" }

    public init() {}

    public func canHandle(url: String) -> Bool {
        let lower = url.lowercased()
        return lower.contains("googleapiscdn") || lower.contains("googlevideo") || lower.contains("drive.google.com")
    }

    public func extract(url: String, referer: String) async throws -> StreamSource {
        guard let validURL = URL(string: url) else {
            throw ExtractorError.invalidURL
        }
        return StreamSource(url: validURL, referer: referer.isEmpty ? NetworkManager.shared.resolvedDomain : referer)
    }
}
