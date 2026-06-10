import Foundation

struct Movie {
    var title: String
    var link: String
    var thumbUrl: String
    var episodeStatus: String
}

struct Episode {
    var title: String
    var link: String
    var episodeId: String?
}

/// Luồng phim cùng với URL Referer dùng để gọi server stream (m3u8 thường yêu cầu
/// header Referer khớp với origin iframe player, không có là server trả 403).
struct Stream {
    let url: URL
    let referer: String
}
