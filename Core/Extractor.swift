import Foundation

class Extractor {

    // 1. Lấy link iframe hoặc direct link từ trang xem-phim.html
    static func resolveStream(episodeUrl: String, completion: @escaping (URL?) -> Void) {
        // Dùng fetchHTML của NetworkManager (WKWebView) để bypass Cloudflare 403
        NetworkManager.shared.fetchHTML(url: episodeUrl) { html in

            if html.isEmpty {
                print("[Extractor] HTML rỗng - WKWebView không tải được trang tập phim")
                return completion(nil)
            }

            // (a) Thử bóc object PLAYER_DATA. Trang dùng cả `window.PLAYER_DATA = {...}` lẫn
            //     `var PLAYER_DATA = {...}` tùy theme nên không bắt buộc tiền tố `window.`.
            let playerDataPattern = "(?:window\\.)?PLAYER_DATA\\s*=\\s*(\\{[\\s\\S]*?\\})\\s*;"
            if let regex = try? NSRegularExpression(pattern: playerDataPattern),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let range = Range(match.range(at: 1), in: html) {

                let jsonString = String(html[range])
                if let jsonData = jsonString.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                   let link = json["link"] as? String {

                    let playTech = (json["playTech"] as? String) ?? ""
                    print("[Extractor] PLAYER_DATA tìm thấy. playTech=\(playTech) link=\(link)")

                    if playTech == "iframe" || link.contains("googleapiscdn") || link.contains("/player/") {
                        return extractFromIframe(iframeUrl: link, completion: completion)
                    } else if link.lowercased().contains(".m3u8") || link.lowercased().contains(".mp4") {
                        return completion(URL(string: link))
                    } else {
                        return extractFromIframe(iframeUrl: link, completion: completion)
                    }
                } else {
                    print("[Extractor] PLAYER_DATA tìm thấy nhưng không parse được JSON: \(jsonString.prefix(200))")
                }
            }

            // (b) Fallback: hook JS có thể đã chèn m3u8 trực tiếp vào DOM. Bắt luôn.
            let m3u8Pattern = "(?i)(https?://[^\"\'\\s<>]+?\\.m3u8[^\"\'\\s<>]*)"
            if let regex = try? NSRegularExpression(pattern: m3u8Pattern),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let range = Range(match.range(at: 1), in: html) {
                let raw = String(html[range]).replacingOccurrences(of: "\\/", with: "/")
                print("[Extractor] Bắt được m3u8 trực tiếp trong HTML: \(raw)")
                return completion(URL(string: raw))
            }

            // (c) Fallback: tìm link iframe player (stream.googleapiscdn.com/player/HASH) rồi mở để bóc m3u8.
            let iframePattern = "(?i)(https?://[a-z0-9.-]*(?:googleapiscdn|streamlare|hydrax|fembed|streamtape)\\.[a-z]+/[^\"\'\\s<>]+)"
            if let regex = try? NSRegularExpression(pattern: iframePattern),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let range = Range(match.range(at: 1), in: html) {
                let iframeUrl = String(html[range]).replacingOccurrences(of: "\\/", with: "/")
                print("[Extractor] Tìm thấy link iframe player: \(iframeUrl)")
                return extractFromIframe(iframeUrl: iframeUrl, completion: completion)
            }

            print("[Extractor] Không tìm thấy PLAYER_DATA hay link luồng trong HTML (\(html.count) ký tự).")
            completion(nil)
        }
    }

    // 2. Chui vào iframe bên thứ 3 để bóc link m3u8 cuối cùng
    private static func extractFromIframe(iframeUrl: String, completion: @escaping (URL?) -> Void) {
        // Trỏ NetworkManager fetch iframe URL thông qua WKWebView để bypass Cloudflare Bot Detection trên CDN
        NetworkManager.shared.fetchHTML(url: iframeUrl, waitForIframe: true) { html in
            if html.isEmpty {
                print("[Extractor] Iframe \(iframeUrl) trả về rỗng (CF challenge chưa giải xong?).")
                return completion(nil)
            }
            // Tìm file m3u8 trong source của iframe (dùng regex lỏng lẻo hơn để bắt cả file: "...", src="...", source: '...')
            let pattern = "(?i)[\"'](https?://[^\"\'\\s]+?\\.m3u8[^\"\'\\s]*)[\"']"
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let range = Range(match.range(at: 1), in: html) {
                let rawUrl = String(html[range]).replacingOccurrences(of: "\\/", with: "/")
                print("[Extractor] Bóc được m3u8 từ iframe: \(rawUrl)")
                completion(URL(string: rawUrl))
            } else {
                print("[Extractor] Không tìm thấy m3u8 trong iframe: \(iframeUrl)")
                completion(nil)
            }
        }
    }
}
