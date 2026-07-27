import Foundation

/// Chuẩn giao tiếp cho các Server Extractor Plugin giải mã link video stream.
public protocol VideoExtractor: Sendable {
    /// Tên đại diện của Server (Hydrax, StreamTape, FileMoon, Google, Fembed, Default)
    var name: String { get }

    /// Kiểm tra URL có thuộc về Server này hay không
    func canHandle(url: String) -> Bool

    /// Bóc tách luồng phát video từ URL trang web / iframe
    func extract(url: String, referer: String) async throws -> StreamSource
}
