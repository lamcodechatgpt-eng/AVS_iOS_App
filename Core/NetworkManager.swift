import Foundation
import WebKit

class NetworkManager: NSObject, WKNavigationDelegate {
    static let shared = NetworkManager()
    
    // Dùng link rút gọn gốc để auto redirect về domain sống mới nhất (chống die tên miền)
    var baseUrl = "https://bit.ly/animevietsubtv"
    var resolvedDomain = "https://animevietsub.by" // Fallback
    
    private var webView: WKWebView!
    private var completionQueue: [(String) -> Void] = []
    private var currentLoadId: Int = 0
    
    override init() {
        super.init()
        DispatchQueue.main.async {
            let config = WKWebViewConfiguration()
            // Đặt ngoài màn hình để không bị iOS đình chỉ render (throttle JS của Cloudflare)
            self.webView = WKWebView(frame: CGRect(x: -3000, y: -3000, width: 375, height: 812), configuration: config)
            self.webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15"
            self.webView.navigationDelegate = self
            self.webView.isHidden = false
            self.webView.alpha = 1.0
        }
    }
    
    // Tải HTML thông qua WKWebView để tự động bypass Cloudflare/Bot-check
    func fetchHTML(url: String, completion: @escaping (String) -> Void) {
        DispatchQueue.main.async {
            // Phải add vào view hierarchy thì WKWebView mới chạy thực tế trên iOS
            if self.webView.superview == nil, let window = UIApplication.shared.windows.first {
                window.addSubview(self.webView) 
            }
            
            self.currentLoadId += 1
            let loadId = self.currentLoadId
            
            self.completionQueue.removeAll() // Hủy các request cũ đang bị kẹt
            self.completionQueue.append(completion)
            
            if let targetUrl = URL(string: url) {
                let req = URLRequest(url: targetUrl)
                self.webView.load(req)
                // Khởi động vòng lặp kiểm tra DOM ngay lập tức
                self.checkDOM(webView: self.webView, loadId: loadId, retries: 25) // Tăng thời gian chờ lên 25s cho mạng chậm
            }
        }
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let host = webView.url?.host {
            self.resolvedDomain = "https://" + host
        }
    }
    
    private func checkDOM(webView: WKWebView, loadId: Int, retries: Int) {
        // Nếu đã có request mới đè lên, hủy vòng lặp này
        if loadId != self.currentLoadId { return }
        
        if retries <= 0 {
            let queue = self.completionQueue
            self.completionQueue.removeAll()
            for completion in queue {
                completion("")
            }
            return
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if loadId != self.currentLoadId { return }
            
            webView.evaluateJavaScript("document.documentElement.outerHTML") { [weak self] result, _ in
                let html = (result as? String) ?? ""
                guard let self = self else { return }
                
                // Chờ tới khi trang chủ load xong AJAX (hiện TPostMv) hoặc trang chi tiết load tập phim (-tap-) hoặc iframe load xong (.m3u8)
                if html.contains("TPostMv") || html.contains("mli-eps") || html.contains("-tap-") || html.contains(".m3u8") {
                    let queue = self.completionQueue
                    self.completionQueue.removeAll()
                    for completion in queue {
                        completion(html)
                    }
                } else {
                    self.checkDOM(webView: webView, loadId: loadId, retries: retries - 1)
                }
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
                                            link: link.hasPrefix("http") ? link : NetworkManager.shared.resolvedDomain + link,
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
                                                link: link.hasPrefix("http") ? link : NetworkManager.shared.resolvedDomain + link,
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
