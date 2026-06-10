import Foundation

class Extractor {

    /// Giải mã HTML entity quan trọng cho URL. JS hook chèn URL vào DOM bằng
    /// `innerText` nên browser tự encode `&` thành `&amp;` khi serialize ra
    /// outerHTML. Nếu không decode, AVPlayer gửi `&amp;` lên server → server
    /// thấy query param dính vào nhau, JWT không khớp, trả 403.
    private static func htmlDecode(_ s: String) -> String {
        return s
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#38;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#34;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }

    // 1. Lấy link iframe hoặc direct link từ trang xem-phim.html
    static func resolveStream(episodeUrl: String, completion: @escaping (Stream?) -> Void) {
        // Dùng fetchHTML của NetworkManager (WKWebView) để bypass Cloudflare 403
        NetworkManager.shared.fetchHTML(url: episodeUrl) { html in

            if html.isEmpty {
                Logger.shared.log("[Extractor] HTML rỗng - WKWebView không tải được trang tập phim")
                return completion(nil)
            }

            // Referer mặc định khi luồng trỏ thẳng từ AVS (không qua iframe).
            let defaultReferer = "\(NetworkManager.shared.resolvedDomain)/"

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
                    Logger.shared.log("[Extractor] PLAYER_DATA tìm thấy. playTech=\(playTech) link=\(link)")

                    if playTech == "iframe" || link.contains("googleapiscdn") || link.contains("/player/") {
                        return extractFromIframe(iframeUrl: link, completion: completion)
                    } else if link.lowercased().contains(".m3u8") || link.lowercased().contains(".mp4") {
                        guard let url = URL(string: link) else { return completion(nil) }
                        return completion(Stream(url: url, referer: defaultReferer))
                    } else {
                        return extractFromIframe(iframeUrl: link, completion: completion)
                    }
                } else {
                    Logger.shared.log("[Extractor] PLAYER_DATA tìm thấy nhưng không parse được JSON: \(jsonString.prefix(200))")
                }
            }

            // (b) Fallback: hook JS có thể đã chèn m3u8 trực tiếp vào DOM. Bắt luôn.
            let m3u8Pattern = "(?i)(https?://[^\"\'\\s<>]+?\\.m3u8[^\"\'\\s<>]*)"
            if let regex = try? NSRegularExpression(pattern: m3u8Pattern),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let range = Range(match.range(at: 1), in: html) {
                let raw = htmlDecode(String(html[range]).replacingOccurrences(of: "\\/", with: "/"))
                Logger.shared.log("[Extractor] Bắt được m3u8 trực tiếp trong HTML: \(raw)")
                guard let url = URL(string: raw) else { return completion(nil) }
                return completion(Stream(url: url, referer: defaultReferer))
            }

            // (c) Fallback: tìm link iframe player (stream.googleapiscdn.com/player/HASH) rồi mở để bóc m3u8.
            let iframePattern = "(?i)(https?://[a-z0-9.-]*(?:googleapiscdn|streamlare|hydrax|fembed|streamtape)\\.[a-z]+/[^\"\'\\s<>]+)"
            if let regex = try? NSRegularExpression(pattern: iframePattern),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let range = Range(match.range(at: 1), in: html) {
                let iframeUrl = htmlDecode(String(html[range]).replacingOccurrences(of: "\\/", with: "/"))
                Logger.shared.log("[Extractor] Tìm thấy link iframe player: \(iframeUrl)")
                return extractFromIframe(iframeUrl: iframeUrl, completion: completion)
            }

            Logger.shared.log("[Extractor] Không tìm thấy PLAYER_DATA hay link luồng trong HTML (\(html.count) ký tự).")
            // Trích vài ký tự quanh các từ khoá quen thuộc để dễ debug khi server đổi format.
            for keyword in ["PLAYER_DATA", "playTech", "data-id", "halim-btn", "googleapiscdn", "m3u8", "iframe"] {
                if let range = html.range(of: keyword) {
                    let start = html.index(range.lowerBound, offsetBy: -50, limitedBy: html.startIndex) ?? html.startIndex
                    let end = html.index(range.upperBound, offsetBy: 200, limitedBy: html.endIndex) ?? html.endIndex
                    Logger.shared.log("[Extractor]   '\(keyword)' xuất hiện: ...\(html[start..<end])...")
                }
            }
            completion(nil)
        }
    }

    // 2. Chui vào iframe bên thứ 3 để bóc link m3u8 cuối cùng.
    // Referer trả về là origin của iframe vì server stream check Referer dựa trên đó.
    private static func extractFromIframe(iframeUrl: String, completion: @escaping (Stream?) -> Void) {
        // Trỏ NetworkManager fetch iframe URL thông qua WKWebView để bypass Cloudflare Bot Detection trên CDN
        NetworkManager.shared.fetchHTML(url: iframeUrl, waitForIframe: true) { html in
            // Referer cần là origin (scheme + host), không phải full URL — server stream
            // thường so sánh prefix "https://stream.googleapiscdn.com/".
            let referer: String = {
                if let u = URL(string: iframeUrl), let host = u.host {
                    return "\(u.scheme ?? "https")://\(host)/"
                }
                return iframeUrl
            }()

            if html.isEmpty {
                Logger.shared.log("[Extractor] Iframe \(iframeUrl) trả về rỗng (CF challenge chưa giải xong?).")
                return completion(nil)
            }
            // Hết retry nhưng HTML có nội dung — fall through để regex tìm m3u8.
            // Nếu vẫn không match, branch fail sẽ dump diagnostic.
            // Tìm file m3u8 trong source của iframe (dùng regex lỏng lẻo hơn để bắt cả file: "...", src="...", source: '...')
            let pattern = "(?i)[\"'](https?://[^\"\'\\s]+?\\.m3u8[^\"\'\\s]*)[\"']"
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let range = Range(match.range(at: 1), in: html) {
                let rawUrl = htmlDecode(String(html[range]).replacingOccurrences(of: "\\/", with: "/"))
                Logger.shared.log("[Extractor] Bóc được m3u8 từ iframe: \(rawUrl)")
                Logger.shared.log("[Extractor] Referer cho stream: \(referer)")
                guard let url = URL(string: rawUrl) else { return completion(nil) }
                completion(Stream(url: url, referer: referer))
            } else {
                Logger.shared.log("[Extractor] Không tìm thấy m3u8 trong iframe: \(iframeUrl)")
                Logger.shared.log("[Extractor] iframe HTML dài \(html.count) ký tự. Quanh các từ khoá:")
                for keyword in [".m3u8", "file:", "source:", "sources", "jwplayer", "setup(", "<video", "src=\"http"] {
                    if let range = html.range(of: keyword) {
                        let start = html.index(range.lowerBound, offsetBy: -60, limitedBy: html.startIndex) ?? html.startIndex
                        let end = html.index(range.upperBound, offsetBy: 200, limitedBy: html.endIndex) ?? html.endIndex
                        var snippet = String(html[start..<end])
                        snippet = snippet.replacingOccurrences(of: "\n", with: " ")
                        Logger.shared.log("[Extractor]   '\(keyword)': ...\(snippet)...")
                    }
                }
                completion(nil)
            }
        }
    }
}
