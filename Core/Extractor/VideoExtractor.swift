import Foundation

public enum ExtractorError: Error, LocalizedError {
    case invalidURL
    case parseFailed(String)
    case unsupportedServer

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "URL không hợp lệ"
        case .parseFailed(let msg): return "Lỗi bóc tách luồng phát: \(msg)"
        case .unsupportedServer: return "Server xem phim chưa được hỗ trợ"
        }
    }
}

/// Chuẩn giao tiếp cho các Server Extractor Plugin giải mã link video stream.
public protocol VideoExtractor: Sendable {
    /// Tên đại diện của Server (Hydrax, StreamTape, FileMoon, Google, Fembed, Default)
    var name: String { get }

    /// Kiểm tra URL có thuộc về Server này hay không
    func canHandle(url: String) -> Bool

    /// Bóc tách luồng phát video từ URL trang web / iframe
    func extract(url: String, referer: String) async throws -> StreamSource
}
