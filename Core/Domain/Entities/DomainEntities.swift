import Foundation

/// Thống kê và trạng thái tiến độ xem phim.
public struct PlaybackProgress: Codable, Equatable, Sendable {
    public let episodeURL: String
    public let positionSeconds: Double
    public let totalDurationSeconds: Double
    public let lastUpdated: Date

    public var percentage: Double {
        guard totalDurationSeconds > 0 else { return 0 }
        return min(max(positionSeconds / totalDurationSeconds, 0), 1.0)
    }

    public var isCompleted: Bool {
        percentage >= 0.90
    }

    public init(episodeURL: String, positionSeconds: Double, totalDurationSeconds: Double, lastUpdated: Date = Date()) {
        self.episodeURL = episodeURL
        self.positionSeconds = positionSeconds
        self.totalDurationSeconds = totalDurationSeconds
        self.lastUpdated = lastUpdated
    }
}

/// Nguồn phát video đa dạng server.
public struct VideoStreamSource: Sendable, Equatable {
    public let url: URL
    public let referer: String
    public let inlinePlaylist: Data?
    public let serverName: String

    public init(url: URL, referer: String, inlinePlaylist: Data? = nil, serverName: String = "Default") {
        self.url = url
        self.referer = referer
        self.inlinePlaylist = inlinePlaylist
        self.serverName = serverName
    }
}
