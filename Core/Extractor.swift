import Foundation

class Extractor {
    
    // 1. Lấy link iframe hoặc direct link từ trang xem-phim.html
    static func resolveStream(episodeUrl: String, completion: @escaping (URL?) -> Void) {
        // Dùng fetchHTML của NetworkManager (WKWebView) để bypass Cloudflare 403
        NetworkManager.shared.fetchHTML(url: episodeUrl) { html in
            
            // Tìm object PLAYER_DATA chứa thông tin luồng
            let pattern = "window\\.PLAYER_DATA\\s*=\\s*(\\{.*?\\});"
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let range = Range(match.range(at: 1), in: html) else {
                return completion(nil)
            }
            
            let jsonString = String(html[range])
            guard let jsonData = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let link = json["link"] as? String,
                  let playTech = json["playTech"] as? String else {
                return completion(nil)
            }
            
            if playTech == "iframe" {
                // Nếu bị bọc qua iframe (googleapiscdn.com), phải chui vào iframe bóc m3u8
                extractFromIframe(iframeUrl: link, completion: completion)
            } else {
                // Nếu là direct mp4 hoặc m3u8
                completion(URL(string: link))
            }
        }
    }
    
    // 2. Chui vào iframe bên thứ 3 để bóc link m3u8 cuối cùng
    private static func extractFromIframe(iframeUrl: String, completion: @escaping (URL?) -> Void) {
        guard let url = URL(string: iframeUrl) else { return completion(nil) }
        var req = URLRequest(url: url)
        req.setValue(NetworkManager.shared.resolvedDomain, forHTTPHeaderField: "Referer")
        
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let html = String(data: data ?? Data(), encoding: .utf8) else { return completion(nil) }
            
            // Tìm file m3u8 trong source của iframe
            let pattern = "(?i)file\\s*:\\s*[\"'](https?://.*?\\.m3u8.*?)[\"']"
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let range = Range(match.range(at: 1), in: html) {
                completion(URL(string: String(html[range])))
            } else {
                print("Không tìm thấy m3u8 trong iframe: \(iframeUrl)")
                completion(nil)
            }
        }.resume()
    }
}
