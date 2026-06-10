import Foundation

struct Movie: Codable {
    var title: String
    var link: String
    var thumbUrl: String
    var episodeStatus: String
}

struct Episode: Codable {
    var title: String
    var link: String
    var episodeId: String?
}

/// Luồng phim cùng với URL Referer dùng để gọi server stream (m3u8 thường yêu cầu
/// header Referer khớp với origin iframe player, không có là server trả 403).
/// Khi `inlinePlaylist` có giá trị, đó là nội dung m3u8 đã được decode sẵn (từ
/// data URL của JWPlayer); PlayerController sẽ phục vụ qua custom URL scheme thay
/// vì fetch URL ở `url`.
struct Stream {
    let url: URL
    let referer: String
    let inlinePlaylist: Data?

    init(url: URL, referer: String, inlinePlaylist: Data? = nil) {
        self.url = url
        self.referer = referer
        self.inlinePlaylist = inlinePlaylist
    }
}
