import Foundation

struct Movie: Codable, Hashable {
    var title: String
    var link: String
    var thumbUrl: String
    var episodeStatus: String
}

enum ContentIdentifier {
    static func make(from link: String) -> String {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        if let components = URLComponents(string: trimmed), !components.path.isEmpty {
            let path = components.path.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return path.isEmpty ? trimmed.lowercased() : path
        }
        return trimmed.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

extension Movie {
    var persistenceID: String { ContentIdentifier.make(from: link) }
}

struct Episode: Codable {
    var title: String
    var link: String
}

struct GenreOption: Codable, Hashable {
    let name: String
    let slug: String
}

extension Episode {
    var persistenceID: String { ContentIdentifier.make(from: link) }
}

/// Thông tin chi tiết phim hiện ở MovieInfoVC. Tách khỏi Movie (list) để
/// fetch lazy chỉ khi user mở phim cụ thể.
struct MovieDetails: Codable {
    var description: String
    var year: String
    var rating: String
    var bannerUrl: String
    var genres: [String]
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
