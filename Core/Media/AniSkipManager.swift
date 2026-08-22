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
            config.timeoutIntervalForRequest = 10
            config.timeoutIntervalForResource = 15
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
        
        // 2. Resolve MAL ID
        resolveMalId(for: names) { [weak self] malId in
            guard let self = self, let malId = malId else {
                completion(nil)
                return
            }
            
            // 3. Fetch AniSkip
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
        if names.isEmpty {
            completion(nil)
            return
        }
        
        let firstTitle = names[0]
        let cacheKey = "\(malIdCachePrefix)\(firstTitle.hashValue)"
        
        if let data = DiskCache.shared.data(for: cacheKey),
           let id = try? JSONDecoder().decode(Int.self, from: data) {
            completion(id)
            return
        }
        
        searchAniList(title: firstTitle) { [weak self] id in
            guard let self = self else { return }
            if let id = id {
                if let data = try? JSONEncoder().encode(id) {
                    DiskCache.shared.set(data, for: cacheKey)
                }
                completion(id)
            } else {
                self.searchJikan(title: firstTitle) { id2 in
                    if let id2 = id2 {
                        if let data = try? JSONEncoder().encode(id2) {
                            DiskCache.shared.set(data, for: cacheKey)
                        }
                    }
                    completion(id2)
                }
            }
        }
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
        t = t.replacingOccurrences(of: "xem phim", with: "")
             .replacingOccurrences(of: "phim", with: "")
             .replacingOccurrences(of: "vietsub", with: "")
             .replacingOccurrences(of: "fhd", with: "")
             .replacingOccurrences(of: "hd", with: "")
             .trimmingCharacters(in: .whitespacesAndNewlines)
             
        t = t.replacingOccurrences(of: "^(?:tập|ep|episode)[\\s\\-_]*\\d+", with: "", options: .regularExpression)
             .replacingOccurrences(of: "(?:tập|ep|episode)[\\s\\-_]*\\d+.*$", with: "", options: .regularExpression)
             .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove text in parentheses but keep it as alternative
        var names = [String]()
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
            names.append(t)
        }
        
        return names.filter { $0.count > 2 }
    }
}
