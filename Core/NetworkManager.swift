import Foundation

class NetworkManager {
    static let shared = NetworkManager()
    // Tên miền thay đổi liên tục, set var để có thể update từ UserDefaults hoặc API config từ xa
    var baseUrl = "https://animevietsub.by"
    
    // 1. Cào dữ liệu trang chủ (Lấy danh sách phim mới)
    func fetchHomeMovies(completion: @escaping ([Movie]) -> Void) {
        guard let url = URL(string: baseUrl) else { return completion([]) }
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let html = String(data: data ?? Data(), encoding: .utf8) else { return completion([]) }
            var movies: [Movie] = []
            
            // Regex bóc tách href, thumbnail, eps, title từ class TPostMv / TPost
            let pattern = "<article id=\"post-[\\s\\S]*?<a href=\"([^\"]+)\"[\\s\\S]*?<img[\\s\\S]*?src=\"([^\"]+)\"[\\s\\S]*?<span class=\"mli-eps\">(.*?)</span>[\\s\\S]*?<h2 class=\"Title\">([^<]+)</h2>"
            
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
                for match in matches {
                    if let linkRange = Range(match.range(at: 1), in: html),
                       let imgRange = Range(match.range(at: 2), in: html),
                       let epsRange = Range(match.range(at: 3), in: html),
                       let titleRange = Range(match.range(at: 4), in: html) {
                        
                        let link = String(html[linkRange])
                        let thumbUrl = String(html[imgRange])
                        let epsRaw = String(html[epsRange])
                            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression, range: nil) // Xóa html tags trong mli-eps (TẬP<i>1</i> -> TẬP 1)
                        let title = String(html[titleRange])
                        
                        movies.append(Movie(title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                            link: link.hasPrefix("http") ? link : NetworkManager.shared.baseUrl + link,
                                            thumbUrl: thumbUrl,
                                            episodeStatus: epsRaw.trimmingCharacters(in: .whitespacesAndNewlines)))
                    }
                }
            }
            DispatchQueue.main.async { completion(movies) }
        }.resume()
    }
    
    // 2. Cào danh sách tập phim trong trang chi tiết phim
    func fetchEpisodes(movieUrl: String, completion: @escaping ([Episode]) -> Void) {
        guard let url = URL(string: movieUrl) else { return completion([]) }
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let html = String(data: data ?? Data(), encoding: .utf8) else { return completion([]) }
            var episodes: [Episode] = []
            
            // Tìm block chứa danh sách tập (ul class="list-episode" hoặc tương tự)
            // Phân tích thẻ a href chứa link xem phim
            let pattern = "<a[^>]+href=\"([^\"]+-tap-[^\"]+\\.html)\"[^>]*>(.*?)</a>"
            
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
                for match in matches {
                    if let linkRange = Range(match.range(at: 1), in: html),
                       let titleRange = Range(match.range(at: 2), in: html) {
                        
                        let link = String(html[linkRange])
                        let title = String(html[titleRange]).replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression, range: nil)
                        
                        episodes.append(Episode(title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                                link: link.hasPrefix("http") ? link : NetworkManager.shared.baseUrl + link,
                                                episodeId: nil))
                    }
                }
            }
            // Lọc trùng lặp nếu có
            var uniqueEps: [Episode] = []
            var seen = Set<String>()
            for ep in episodes {
                if !seen.contains(ep.link) {
                    seen.insert(ep.link)
                    uniqueEps.append(ep)
                }
            }
            
            DispatchQueue.main.async { completion(uniqueEps) }
        }.resume()
    }
}
