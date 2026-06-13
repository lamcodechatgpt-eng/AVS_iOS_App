import Foundation

class Extractor {

    /// Giải mã HTML entity quan trọng cho URL.
    private static func htmlDecode(_ s: String) -> String {
        var result = s
        let entities = [
            "&amp;": "&", "&#38;": "&",
            "&quot;": "\"", "&#34;": "\"",
            "&apos;": "'", "&#39;": "'",
            "&lt;": "<", "&gt;": ">",
            "&#x2F;": "/", "&#47;": "/",
            "&#x3A;": ":", "&#58;": ":",
            "&#x3D;": "=", "&#61;": "=",
            "&#x3F;": "?", "&#63;": "?",
            "&#x25;": "%", "&#37;": "%"
        ]
        for (entity, char) in entities {
            result = result.replacingOccurrences(of: entity, with: char)
        }
        return result
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

            // (a) Thử bóc object PLAYER_DATA.
            let playerDataPattern = "(?:window\\.)?PLAYER_DATA\\s*=\\s*(\\{[\\s\\S]*?\\})\\s*;"
            if let regex = try? NSRegularExpression(pattern: playerDataPattern),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let range = Range(match.range(at: 1), in: html) {

                var jsonString = String(html[range])
                // Cân bằng dấu ngoặc nhọn: regex lazy chỉ bắt được tới `}` đầu tiên,
                // nếu JSON lồng nhau thì thiếu. Ta mở rộng bằng cách đếm { }.
                let fullRange = match.range(at: 1)
                let remainderStart = fullRange.upperBound
                let remainder = html[html.index(html.startIndex, offsetBy: remainderStart)...]
                var depth = 1
                var extra = ""
                for ch in remainder {
                    if ch == "{" { depth += 1 }
                    else if ch == "}" { depth -= 1 }
                    extra.append(ch)
                    if depth == 0 { break }
                }
                jsonString.append(extra)
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

            // (i) ƯU TIÊN: lấy m3u8 từ data URL trên <video src="data:application/...mpegurl;base64,...">.
            // AVS dùng anti-bot avs-shield + avs-fingerprint, sau khi pass, JWPlayer chèn
            // m3u8 đã giải mã DIRECTLY vào video element. URL playlist.m3u8?token=JWT đối
            // với client không qua anti-bot luôn trả 403/429 — cờ này mới là luồng thật.
            if html.contains("videoData: present") || html.range(of: "data:application/vnd.apple.mpegurl", options: .caseInsensitive) != nil {
                NetworkManager.shared.fetchVideoSrc { videoSrc in
                    if let data = handleVideoSrcData(videoSrc) {
                        // Trả về Stream với inlinePlaylist — PlayerController sẽ serve
                        // qua custom URL scheme + Resource Loader để AVPlayer chắc chắn
                        // nhận diện HLS (file:// thường không trigger HLS path trong AVPlayer).
                        Logger.shared.log("[Extractor] Trả về Stream với inlinePlaylist (\(data.count) bytes)")
                        completion(Stream(url: M3U8ResourceLoader.makePlaceholderURL(), referer: referer, inlinePlaylist: data))
                    } else {
                        Logger.shared.log("[Extractor] Có dấu hiệu video data URL nhưng không lấy được src — fall back regex.")
                        regexExtractM3U8(html: html, iframeUrl: iframeUrl, referer: referer, completion: completion)
                    }
                }
                return
            }
            // Hết retry nhưng HTML có nội dung — fall through để regex tìm m3u8.
            // Nếu vẫn không match, branch fail sẽ dump diagnostic.
            regexExtractM3U8(html: html, iframeUrl: iframeUrl, referer: referer, completion: completion)
        }
    }

    /// Decode data URL m3u8 (base64) → trả về Data thô để PlayerController serve qua
    /// AVAssetResourceLoaderDelegate. Trả nil nếu src không phải data URL HLS hoặc
    /// decode thất bại.
    private static func handleVideoSrcData(_ src: String) -> Data? {
        guard src.lowercased().hasPrefix("data:") else { return nil }
        let lc = src.lowercased()
        let isHLS = lc.contains("application/vnd.apple.mpegurl")
            || lc.contains("application/x-mpegurl")
            || lc.contains("audio/mpegurl")
        guard isHLS else { return nil }
        guard let commaIdx = src.firstIndex(of: ","), let semiIdx = src.firstIndex(of: ";") else { return nil }
        let metaRange = src.index(after: semiIdx)..<commaIdx
        let isBase64 = src[metaRange].lowercased().contains("base64")
        let payload = String(src[src.index(after: commaIdx)...])
        let m3u8Data: Data?
        if isBase64 {
            m3u8Data = Data(base64Encoded: payload)
        } else {
            m3u8Data = payload.removingPercentEncoding?.data(using: .utf8)
        }
        guard let data = m3u8Data, !data.isEmpty else {
            Logger.shared.log("[Extractor] Decode data URL thất bại (\(payload.prefix(40))...)")
            return nil
        }
        if let text = String(data: data, encoding: .utf8) {
            let segmentLines = text.split(separator: "\n").filter { $0.hasPrefix("http") }
            Logger.shared.log("[Extractor] M3U8 decoded \(data.count) bytes, \(segmentLines.count) segments")
            Logger.shared.log("[Extractor] M3U8 đầu file: \(text.prefix(300))")
            if let firstSeg = segmentLines.first {
                Logger.shared.log("[Extractor] Segment đầu: \(firstSeg.prefix(180))")
            }
        } else {
            Logger.shared.log("[Extractor] CẢNH BÁO: m3u8 không decode UTF-8 được — base64 sai.")
        }
        return data
    }

    private static func regexExtractM3U8(html: String, iframeUrl: String, referer: String, completion: @escaping (Stream?) -> Void) {
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
