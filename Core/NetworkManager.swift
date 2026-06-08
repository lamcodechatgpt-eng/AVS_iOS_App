import Foundation
import WebKit

class NetworkManager: NSObject, WKNavigationDelegate {
    static let shared = NetworkManager()
    var baseUrl = "https://animevietsub.id"
    
    private var webView: WKWebView!
    private var completionQueue: [(String) -> Void] = []
    
    override init() {
        super.init()
        DispatchQueue.main.async {
            let config = WKWebViewConfiguration()
            self.webView = WKWebView(frame: .zero, configuration: config)
            self.webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15"
            self.webView.navigationDelegate = self
        }
    }
    
    // Tải HTML thông qua WKWebView để tự động bypass Cloudflare/Bot-check
    func fetchHTML(url: String, completion: @escaping (String) -> Void) {
        DispatchQueue.main.async {
            self.completionQueue.append(completion)
            if let targetUrl = URL(string: url) {
                let req = URLRequest(url: targetUrl)
                self.webView.load(req)
            }
        }
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Đợi thêm 1s để JS render xong nếu có Cloudflare
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            webView.evaluateJavaScript("document.documentElement.outerHTML") { [weak self] result, _ in
                let html = (result as? String) ?? ""
                guard let self = self else { return }
                for completion in self.completionQueue {
                    completion(html)
                }
                self.completionQueue.removeAll()
            }
        }
    }
    
    func fetchHomeMovies(completion: @escaping ([Movie]) -> Void) {
        fetchHTML(url: baseUrl) { html in
            var movies: [Movie] = []
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
                            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression, range: nil)
                        let title = String(html[titleRange])
                        
                        movies.append(Movie(title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                            link: link.hasPrefix("http") ? link : NetworkManager.shared.baseUrl + link,
                                            thumbUrl: thumbUrl,
                                            episodeStatus: epsRaw.trimmingCharacters(in: .whitespacesAndNewlines)))
                    }
                }
            }
            completion(movies)
        }
    }
    
    func fetchEpisodes(movieUrl: String, completion: @escaping ([Episode]) -> Void) {
        fetchHTML(url: movieUrl) { html in
            var episodes: [Episode] = []
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
            
            var uniqueEps: [Episode] = []
            var seen = Set<String>()
            for ep in episodes {
                if !seen.contains(ep.link) {
                    seen.insert(ep.link)
                    uniqueEps.append(ep)
                }
            }
            completion(uniqueEps)
        }
    }
}
