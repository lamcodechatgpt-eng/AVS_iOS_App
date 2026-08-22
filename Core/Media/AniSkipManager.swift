import Foundation

public struct AniSkipResult: Codable, Equatable {
    public let intro: SkipInterval?
    public let outro: SkipInterval?
    public let isEstimated: Bool

    public init(intro: SkipInterval?, outro: SkipInterval?, isEstimated: Bool) {
        self.intro = intro
        self.outro = outro
        self.isEstimated = isEstimated
    }
}

public struct SkipInterval: Codable, Equatable {
    public let start: Double
    public let end: Double
    public let episodeLength: Double?

    public init(start: Double, end: Double, episodeLength: Double? = nil) {
        self.start = start
        self.end = end
        self.episodeLength = episodeLength
    }
}

// MARK: - API Responses
private struct AniListResponse: Decodable {
    let data: AniListData?
}
private struct AniListData: Decodable {
    let Media: AniListMedia?
}
private struct AniListMedia: Decodable {
    let idMal: Int?
}

private struct JikanResponse: Decodable {
    let data: [JikanAnime]?
}
private struct JikanAnime: Decodable {
    let mal_id: Int?
}

private struct AniSkipAPIResponse: Decodable {
    let found: Bool
    let results: [AniSkipItem]?
}
private struct AniSkipItem: Decodable {
    let skip_type: String
    let interval: AniSkipInterval?
    let start_time: Double?
    let end_time: Double?
    let episode_length: Double?
}
private struct AniSkipInterval: Decodable {
    let start_time: Double
    let end_time: Double
}

public class AniSkipManager {
    public static let shared = AniSkipManager()
    
    private let session: URLSession
    private let cacheKeyPrefix = "aniskip_"
    private let malIdCachePrefix = "malid_"
    
    public init(session: URLSession? = nil) {
        if let session = session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 8
            config.timeoutIntervalForResource = 12
            self.session = URLSession(configuration: config)
        }
    }
    
    public func resolveTimestamps(movieTitle: String, movieUrl: String, episodeText: String, completion: @escaping (AniSkipResult?) -> Void) {
        let epNumber = Self.extractEpisodeNumber(from: episodeText) ?? 1
        let names = Self.cleanTitle(movieTitle, url: movieUrl)
        
        // 1. Kiểm tra cache skip times
        let cacheKey = "\(cacheKeyPrefix)\(movieUrl.hashValue)_\(epNumber)"
        if let cachedData = DiskCache.shared.data(for: cacheKey),
           let cachedResult = try? JSONDecoder().decode(AniSkipResult.self, from: cachedData) {
            completion(cachedResult)
            return
        }
        
        // 2. Resolve MAL ID qua danh sách tên gợi ý
        resolveMalId(for: names) { [weak self] malId in
            guard let self = self, let malId = malId else {
                completion(nil)
                return
            }
            
            // 3. Fetch AniSkip với MAL ID đã tìm được
            self.fetchAniSkip(malId: malId, episode: epNumber) { [weak self] result in
                guard let self = self else { return }
                
                if let result = result {
                    if let data = try? JSONEncoder().encode(result) {
                        DiskCache.shared.set(data, for: cacheKey)
                    }
                    completion(result)
                } else {
                    // Fallback estimation từ các tập lân cận
                    self.fetchAlternativeEpisodeTimes(malId: malId, currentEp: epNumber) { fallback in
                        if let fb = fallback {
                            if let data = try? JSONEncoder().encode(fb) {
                                DiskCache.shared.set(data, for: cacheKey)
                            }
                        }
                        completion(fallback)
                    }
                }
            }
        }
    }
    
    private func resolveMalId(for names: [String], completion: @escaping (Int?) -> Void) {
        guard !names.isEmpty else {
            completion(nil)
            return
        }
        
        // 1. Kiểm tra cache cho từng tên trước
        for name in names {
            let cacheKey = "\(malIdCachePrefix)\(name.hashValue)"
            if let data = DiskCache.shared.data(for: cacheKey),
               let id = try? JSONDecoder().decode(Int.self, from: data) {
                completion(id)
                return
            }
        }
        
        // 2. Thử lần lượt các tên ứng viên cho đến khi tìm thấy ID
        func searchCandidate(at index: Int) {
            guard index < names.count else {
                completion(nil)
                return
            }
            let currentTitle = names[index]
            let cacheKey = "\(malIdCachePrefix)\(currentTitle.hashValue)"
            
            searchAniList(title: currentTitle) { [weak self] id in
                guard let self = self else { return }
                if let id = id {
                    if let data = try? JSONEncoder().encode(id) {
                        DiskCache.shared.set(data, for: cacheKey)
                    }
                    completion(id)
                } else {
                    self.searchJikan(title: currentTitle) { [weak self] id2 in
                        guard let self = self else { return }
                        if let id2 = id2 {
                            if let data = try? JSONEncoder().encode(id2) {
                                DiskCache.shared.set(data, for: cacheKey)
                            }
                            completion(id2)
                        } else {
                            searchCandidate(at: index + 1)
                        }
                    }
                }
            }
        }
        
        searchCandidate(at: 0)
    }
    
    // MARK: - Networking
    private func searchAniList(title: String, completion: @escaping (Int?) -> Void) {
        guard let url = URL(string: "https://graphql.anilist.co") else {
            completion(nil)
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let query = """
        query ($search: String) {
            Media (search: $search, type: ANIME) {
                idMal
            }
        }
        """
        let body: [String: Any] = ["query": query, "variables": ["search": title]]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
        
        session.dataTask(with: req) { data, _, _ in
            guard let data = data,
                  let resp = try? JSONDecoder().decode(AniListResponse.self, from: data),
                  let malId = resp.data?.Media?.idMal else {
                completion(nil)
                return
            }
            completion(malId)
        }.resume()
    }
    
    private func searchJikan(title: String, completion: @escaping (Int?) -> Void) {
        let safeTitle = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlStr = "https://api.jikan.moe/v4/anime?q=\(safeTitle)&limit=1&sfw=false"
        guard let url = URL(string: urlStr) else {
            completion(nil)
            return
        }
        session.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let resp = try? JSONDecoder().decode(JikanResponse.self, from: data),
                  let malId = resp.data?.first?.mal_id else {
                completion(nil)
                return
            }
            completion(malId)
        }.resume()
    }
    
    private func fetchAniSkip(malId: Int, episode: Int, completion: @escaping (AniSkipResult?) -> Void) {
        let urlStr = "https://api.aniskip.com/v1/skip-times/\(malId)/\(episode)?types[]=op&types[]=ed"
        guard let url = URL(string: urlStr) else {
            completion(nil)
            return
        }
        session.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let resp = try? JSONDecoder().decode(AniSkipAPIResponse.self, from: data),
                  resp.found, let results = resp.results else {
                completion(nil)
                return
            }
            
            var intro: SkipInterval?
            var outro: SkipInterval?
            
            for item in results {
                let start = item.interval?.start_time ?? item.start_time
                let end = item.interval?.end_time ?? item.end_time
                let length = item.episode_length
                
                guard let s = start, let e = end else { continue }
                
                if item.skip_type == "op" {
                    intro = SkipInterval(start: s, end: e, episodeLength: length)
                } else if item.skip_type == "ed" {
                    outro = SkipInterval(start: s, end: e, episodeLength: length)
                }
            }
            
            if intro == nil && outro == nil {
                completion(nil)
            } else {
                completion(AniSkipResult(intro: intro, outro: outro, isEstimated: false))
            }
        }.resume()
    }
    
    private func fetchAlternativeEpisodeTimes(malId: Int, currentEp: Int, completion: @escaping (AniSkipResult?) -> Void) {
        var candidates = [Int]()
        if currentEp > 1 { candidates.append(currentEp - 1) }
        if currentEp != 1 { candidates.append(1) }
        for i in 2...5 {
            if currentEp != i && !candidates.contains(i) {
                candidates.append(i)
            }
        }
        
        func tryNext(_ index: Int) {
            guard index < candidates.count else {
                completion(nil)
                return
            }
            fetchAniSkip(malId: malId, episode: candidates[index]) { result in
                if var res = result {
                    res = AniSkipResult(intro: res.intro, outro: res.outro, isEstimated: true)
                    completion(res)
                } else {
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
                        tryNext(index + 1)
                    }
                }
            }
        }
        tryNext(0)
    }
    
    // MARK: - Helpers
    public static func extractEpisodeNumber(from text: String) -> Int? {
        let lower = text.lowercased()
        let regexes = [
            "(?:tập|ep|episode)[\\s\\-_]*(\\d{1,4})",
            "[-_/](\\d{1,3})(?:[-_/.]|$)",
            "^\\s*(\\d{1,4})\\s*$"
        ]
        
        for p in regexes {
            if let regex = try? NSRegularExpression(pattern: p, options: []),
               let match = regex.firstMatch(in: lower, options: [], range: NSRange(location: 0, length: lower.utf16.count)),
               let r = Range(match.range(at: 1), in: lower),
               let num = Int(lower[r]) {
                return num
            }
        }
        return nil
    }
    
    public static func cleanTitle(_ title: String, url: String = "") -> [String] {
        var t = title.lowercased()
        let tagsToRemove = [
            "xem phim", "phim", "vietsub", "thuyết minh", "thuyet minh",
            "fhd", "hd", "lồng tiếng", "long tieng", "trọn bộ", "tron bo",
            "bản đẹp", "ban dep", "raw", "uncut", "bluray"
        ]
        for tag in tagsToRemove {
            t = t.replacingOccurrences(of: tag, with: "")
        }
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
             
        t = t.replacingOccurrences(of: "^(?:tập|ep|episode)[\\s\\-_]*\\d+", with: "", options: .regularExpression)
             .replacingOccurrences(of: "(?:tập|ep|episode)[\\s\\-_]*\\d+.*$", with: "", options: .regularExpression)
             .trimmingCharacters(in: .whitespacesAndNewlines)
        
        var names = [String]()
        // Remove text in parentheses but keep it as alternative
        if let start = t.firstIndex(of: "("), let end = t.firstIndex(of: ")"), start < end {
            let inside = String(t[t.index(after: start)..<end])
            let outside = String(t[..<start]) + String(t[t.index(after: end)...])
            let cleanOutside = outside.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanOutside.isEmpty {
                names.append(cleanOutside)
            }
            let alts = inside.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            names.append(contentsOf: alts)
        } else {
            if !t.isEmpty {
                names.append(t)
            }
        }
        
        // Generate season/part variations (Phần 2 -> Season 2, etc.)
        var seasonVariants = [String]()
        for name in names {
            let s1 = name.replacingOccurrences(of: "(?i)(?:phần|mùa)\\s*(\\d+)", with: "Season $1", options: .regularExpression)
            if s1 != name {
                seasonVariants.append(s1.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            let s2 = name.replacingOccurrences(of: "(?i)(?:phần|mùa)\\s*(\\d+)", with: "$1", options: .regularExpression)
            if s2 != name {
                seasonVariants.append(s2.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        names.append(contentsOf: seasonVariants)
        
        // Extract romaji/English name from URL slug if available
        if !url.isEmpty {
            if let slug = extractSlugFromURL(url), !slug.isEmpty {
                names.append(slug)
            }
        }
        
        // Deduplicate and filter
        var seen = Set<String>()
        var cleanedList = [String]()
        for n in names {
            let trimmed = n.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                           .trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count >= 2 && !seen.contains(trimmed.lowercased()) {
                seen.insert(trimmed.lowercased())
                cleanedList.append(trimmed)
            }
        }
        
        // Sort so that ASCII / English / Romaji titles come first (higher match rate on AniList & MAL)
        return cleanedList.sorted { a, b in
            let aIsAscii = a.unicodeScalars.allSatisfy { $0.value <= 127 }
            let bIsAscii = b.unicodeScalars.allSatisfy { $0.value <= 127 }
            if aIsAscii != bIsAscii {
                return aIsAscii && !bIsAscii
            }
            return a.count < b.count
        }
    }
    
    public static func extractSlugFromURL(_ urlString: String) -> String? {
        guard let url = URL(string: urlString) else { return nil }
        let segments = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        for seg in segments {
            var s = seg.replacingOccurrences(of: ".html", with: "")
            if s.hasPrefix("phim-") {
                s = String(s.dropFirst(5))
            }
            // Remove trailing ID like -a5123 or -12345
            s = s.replacingOccurrences(of: "-[a-z]?\\d+$", with: "", options: .regularExpression)
            let ignored: Set<String> = ["phim", "xem-phim", "tap", "episode", "the-loai"]
            if !ignored.contains(s) && s.count >= 3 {
                return s.replacingOccurrences(of: "-", with: " ")
            }
        }
        return nil
    }
}
