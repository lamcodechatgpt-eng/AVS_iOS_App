import Foundation

class Extractor {

    /// Bóc tách luồng phát thông qua VideoExtractorRegistry Plugin Architecture
    static func resolveStreamViaPlugin(url: String, referer: String) async throws -> StreamSource {
        guard let extractor = VideoExtractorRegistry.shared.resolveExtractor(for: url) else {
            throw ExtractorError.unsupportedServer
        }
        return try await extractor.extract(url: url, referer: referer)
    }

    /// Giải mã HTML entity quan trọng cho URL.
    private static func htmlDecode(_ s: String) -> String {
        HTMLUtilities.decodeEntities(s)
    }

    /// Trích một object JavaScript cân bằng ngoặc, có tính đến chuỗi và ký tự escape.
    static func javascriptObject(in source: String, after range: Range<String.Index>) -> String? {
        guard let open = source[range.upperBound...].firstIndex(of: "{") else { return nil }
        var depth = 0
        var quote: Character?
        var escaped = false

        for index in source.indices[open...] {
            let character = source[index]
            if let activeQuote = quote {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == activeQuote {
                    quote = nil
                }
                continue
            }

            if character == "\"" || character == "'" {
                quote = character
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 { return String(source[open...index]) }
            }
        }
        return nil
    }

    private static func firstMatch(in text: String, pattern: String, group: Int = 1) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: group), in: text) else { return nil }
        return String(text[range])
    }

    static func playerDataField(_ field: String, in object: String) -> String? {
        let name = NSRegularExpression.escapedPattern(for: field)
        return firstMatch(in: object,
                          pattern: "(?i)(?:[\\\"']?\(name)[\\\"']?)\\s*:\\s*[\\\"']([^\\\"']+)[\\\"']")
    }

    /// Hỗ trợ URL tuyệt đối, protocol-relative (`//host/...`) và relative (`/player/...`).
    static func resolvedURL(_ raw: String, relativeTo base: String) -> URL? {
        let decoded = htmlDecode(raw.replacingOccurrences(of: "\\/", with: "/"))
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines
                .union(CharacterSet(charactersIn: "\"'")))
        if decoded.hasPrefix("//") {
            return URL(string: "\(URL(string: base)?.scheme ?? "https"):\(decoded)")
        }
        if let absolute = URL(string: decoded), absolute.scheme != nil { return absolute }
        guard let baseURL = URL(string: base) else { return nil }
        return URL(string: decoded, relativeTo: baseURL)?.absoluteURL
    }

    // 1. Lấy link iframe hoặc direct link từ trang xem-phim.html
    static func resolveStream(episodeUrl: String,
                              isCancelled: @escaping () -> Bool = { false },
                              completion: @escaping (Stream?) -> Void) {
        // Dùng fetchHTML của NetworkManager (WKWebView) để bypass Cloudflare 403
        NetworkManager.shared.fetchHTML(url: episodeUrl, isCancelled: isCancelled) { html in
            guard !isCancelled() else { return completion(nil) }

            if html.isEmpty {
                Logger.shared.log("[Extractor] HTML rỗng - WKWebView không tải được trang tập phim")
                return completion(nil)
            }

            // Referer mặc định khi luồng trỏ thẳng từ AVS (không qua iframe).
            let defaultReferer = "\(NetworkManager.shared.resolvedDomain)/"

            // (a) Thử bóc object PLAYER_DATA.
            let playerDataPattern = "(?:window\\.)?PLAYER_DATA\\s*="
            if let regex = try? NSRegularExpression(pattern: playerDataPattern),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let assignmentRange = Range(match.range, in: html),
               let object = javascriptObject(in: html, after: assignmentRange) {

                let json = object.data(using: .utf8)
                    .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                let possibleKeys = ["link", "file", "source", "src", "url", "streamUrl", "stream", "backup"]
                var foundLink: String? = nil
                for k in possibleKeys {
                    if let val = (json?[k] as? String) ?? playerDataField(k, in: object), !val.isEmpty {
                        foundLink = val
                        break
                    }
                }
                if let link = foundLink {
                    let playTech = ((json?["playTech"] as? String)
                        ?? playerDataField("playTech", in: object)
                        ?? "").lowercased()
                    Logger.shared.log("[Extractor] PLAYER_DATA tìm thấy. playTech=\(playTech) link=\(link)")

                    if playTech == "iframe" || link.contains("googleapiscdn") || link.contains("/player/") || link.contains("/embed/") {
                        guard let url = resolvedURL(link, relativeTo: episodeUrl) else { return completion(nil) }
                        return extractFromIframe(iframeUrl: url.absoluteString, isCancelled: isCancelled, completion: completion)
                    } else if link.lowercased().contains(".m3u8") || link.lowercased().contains(".mp4") {
                        guard let url = resolvedURL(link, relativeTo: episodeUrl) else { return completion(nil) }
                        return completion(Stream(url: url, referer: defaultReferer))
                    } else {
                        guard let url = resolvedURL(link, relativeTo: episodeUrl) else { return completion(nil) }
                        return extractFromIframe(iframeUrl: url.absoluteString, isCancelled: isCancelled, completion: completion)
                    }
                } else {
                    Logger.shared.log("[Extractor] PLAYER_DATA tìm thấy nhưng không có field link: \(object.prefix(200))")
                }
            }

            // (b) Fallback: hook JS có thể đã chèn m3u8 trực tiếp vào DOM. Bắt luôn.
            let m3u8Pattern = "(?i)((?:https?:)?//[^\"\'\\s<>]+?\\.(?:m3u8|mp4)[^\"\'\\s<>]*)"
            if let regex = try? NSRegularExpression(pattern: m3u8Pattern),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let range = Range(match.range(at: 1), in: html) {
                let raw = htmlDecode(String(html[range]).replacingOccurrences(of: "\\/", with: "/"))
                Logger.shared.log("[Extractor] Bắt được luồng trực tiếp trong HTML: \(raw)")
                guard let url = resolvedURL(raw, relativeTo: episodeUrl) else { return completion(nil) }
                return completion(Stream(url: url, referer: defaultReferer))
            }

            // (c) Fallback: hỗ trợ iframe bất kỳ, kể cả URL relative/protocol-relative.
            let iframePattern = "(?i)<iframe[^>]+src\\s*=\\s*[\"']([^\"']+)[\"']"
            if let regex = try? NSRegularExpression(pattern: iframePattern) {
                let candidates = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
                    .compactMap { match -> URL? in
                        guard let range = Range(match.range(at: 1), in: html) else { return nil }
                        return resolvedURL(String(html[range]), relativeTo: episodeUrl)
                    }
                let playerHints = ["player", "stream", "embed", "video", "hydrax", "fembed"]
                guard let iframeURL = candidates.first(where: { url in
                    playerHints.contains { url.absoluteString.lowercased().contains($0) }
                }) ?? candidates.first else {
                    Logger.shared.log("[Extractor] Có thẻ iframe nhưng URL không hợp lệ.")
                    return completion(nil)
                }
                Logger.shared.log("[Extractor] Tìm thấy link iframe player: \(iframeURL.absoluteString)")
                return extractFromIframe(iframeUrl: iframeURL.absoluteString, isCancelled: isCancelled, completion: completion)
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
    private static func extractFromIframe(iframeUrl: String,
                                          isCancelled: @escaping () -> Bool,
                                          completion: @escaping (Stream?) -> Void) {
        // Referer cần là origin (scheme + host), không phải full URL — server stream
        // thường so sánh prefix "https://stream.googleapiscdn.com/".
        let referer: String = {
            if let u = URL(string: iframeUrl), let host = u.host {
                return "\(u.scheme ?? "https")://\(host)/"
            }
            return iframeUrl
        }()

        // Kiểm tra nếu iframeUrl đã chứa sẵn stream m3u8/mp4 trong query parameters (vd: player.phimapi.com/player/?url=https://...m3u8)
        if let comps = URLComponents(string: iframeUrl), let items = comps.queryItems {
            for item in items where item.name == "url" || item.name == "link" || item.name == "file" || item.name == "source" {
                if let val = item.value, (val.lowercased().contains(".m3u8") || val.lowercased().contains(".mp4")),
                   let direct = URL(string: val) {
                    Logger.shared.log("[Extractor] Trích xuất trực tiếp m3u8 từ query param của iframe: \(val)")
                    return completion(Stream(url: direct, referer: referer))
                }
            }
        }

        // Trỏ NetworkManager fetch iframe URL thông qua WKWebView để bypass Cloudflare Bot Detection trên CDN
        NetworkManager.shared.fetchHTML(url: iframeUrl,
                                        waitForIframe: true,
                                        isCancelled: isCancelled) { html in
            guard !isCancelled() else { return completion(nil) }

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
                    guard !isCancelled() else { return completion(nil) }
                    if let data = handleVideoSrcData(videoSrc, baseURL: iframeUrl) {
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
    private static func handleVideoSrcData(_ src: String, baseURL: String) -> Data? {
        guard src.lowercased().hasPrefix("data:") else { return nil }
        let lc = src.lowercased()
        let isHLS = lc.contains("application/vnd.apple.mpegurl")
            || lc.contains("application/x-mpegurl")
            || lc.contains("audio/mpegurl")
        guard isHLS else { return nil }
        guard let commaIdx = src.firstIndex(of: ",") else { return nil }
        let metadata = src[..<commaIdx].lowercased()
        let isBase64 = metadata.contains(";base64")
        let payload = String(src[src.index(after: commaIdx)...])
        let m3u8Data: Data?
        if isBase64 {
            let decodedPayload = payload.removingPercentEncoding ?? payload
            m3u8Data = Data(base64Encoded: decodedPayload, options: .ignoreUnknownCharacters)
        } else {
            m3u8Data = payload.removingPercentEncoding?.data(using: .utf8)
        }
        guard let decodedData = m3u8Data, !decodedData.isEmpty else {
            Logger.shared.log("[Extractor] Decode data URL thất bại (\(payload.prefix(40))...)")
            return nil
        }
        let data = rewritingPlaylist(decodedData, relativeTo: baseURL)
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

    /// AVPlayer sẽ resolve URI tương đối theo custom scheme `avshls://`, vì vậy cần
    /// đổi segment, variant, subtitle và key URI thành HTTPS trước khi serve playlist.
    static func rewritingPlaylist(_ data: Data, relativeTo baseURL: String) -> Data {
        guard let text = String(data: data, encoding: .utf8) else { return data }
        let uriRegex = try? NSRegularExpression(pattern: "URI=\\\"([^\\\"]+)\\\"")
        let normalizedText = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalizedText.components(separatedBy: "\n").map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return line }

            if !trimmed.hasPrefix("#") {
                return resolvedURL(trimmed, relativeTo: baseURL)?.absoluteString ?? line
            }

            guard let regex = uriRegex else { return line }
            let mutable = NSMutableString(string: line)
            let matches = regex.matches(in: line, range: NSRange(location: 0, length: mutable.length))
            for match in matches.reversed() {
                guard let swiftRange = Range(match.range(at: 1), in: line),
                      let absolute = resolvedURL(String(line[swiftRange]), relativeTo: baseURL)?.absoluteString else { continue }
                mutable.replaceCharacters(in: match.range(at: 1), with: absolute)
            }
            return mutable as String
        }
        return lines.joined(separator: "\n").data(using: .utf8) ?? data
    }

    private static func regexExtractM3U8(html: String, iframeUrl: String, referer: String, completion: @escaping (Stream?) -> Void) {
        // Nhận HLS/MP4 tuyệt đối, protocol-relative và relative trong file/src/source.
        let pattern = "(?i)[\"']([^\"\'\\s]+?\\.(?:m3u8|mp4)[^\"\'\\s]*)[\"']"
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html) {
            let rawUrl = htmlDecode(String(html[range]).replacingOccurrences(of: "\\/", with: "/"))
            Logger.shared.log("[Extractor] Bóc được luồng từ iframe: \(rawUrl)")
            Logger.shared.log("[Extractor] Referer cho stream: \(referer)")
            guard let url = resolvedURL(rawUrl, relativeTo: iframeUrl) else { return completion(nil) }
            completion(Stream(url: url, referer: referer))
        } else {
            Logger.shared.log("[Extractor] Không tìm thấy HLS/MP4 trong iframe: \(iframeUrl)")
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
