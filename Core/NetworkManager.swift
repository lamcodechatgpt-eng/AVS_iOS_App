import Foundation
import WebKit

class NetworkManager: NSObject, WKNavigationDelegate {
    static let shared = NetworkManager()
    
    // Link gốc bất tử (bit.ly) dùng để dự phòng khi domain chết
    let backupUrl = "https://bit.ly/animevietsubtv"

    // Domain hiện tại, tự động lưu vào máy để các lần mở app sau load cực nhanh không cần qua bit.ly.
    // Chỉ chấp nhận host khớp với một trong các mẫu AVS để tránh bị nhiễm bởi iframe player
    // (vd stream.googleapiscdn.com) trong didFinish.
    private static let defaultDomain = "https://animevietsub.by"
    private static func isAVSHost(_ host: String) -> Bool {
        let h = host.lowercased()
        return h.contains("animevietsub")
            || h.contains("avsub")
            || h.contains("vsub")
            || h.contains("animevsub")
    }

    var resolvedDomain: String {
        get {
            let stored = UserDefaults.standard.string(forKey: "AVS_ResolvedDomain") ?? Self.defaultDomain
            // Phòng vệ: nếu giá trị đã lưu trước đây bị ghi đè bằng host khác (vd
            // stream.googleapiscdn.com từ iframe player) thì trả về default thay vì
            // dùng giá trị hỏng. Đồng thời xoá luôn để các lần sau không sa lại.
            if let url = URL(string: stored), let host = url.host, Self.isAVSHost(host) {
                return stored
            }
            UserDefaults.standard.removeObject(forKey: "AVS_ResolvedDomain")
            return Self.defaultDomain
        }
        set {
            guard newValue.hasPrefix("http"),
                  let host = URL(string: newValue)?.host,
                  Self.isAVSHost(host) else {
                print("Bỏ qua domain không hợp lệ: \(newValue)")
                return
            }
            if UserDefaults.standard.string(forKey: "AVS_ResolvedDomain") != newValue {
                UserDefaults.standard.set(newValue, forKey: "AVS_ResolvedDomain")
                print("Đã cập nhật domain mới: \(newValue)")
            }
        }
    }
    
    private var webView: WKWebView!
    private var completionQueue: [(String) -> Void] = []
    private var currentLoadId: Int = 0
    
    override init() {
        super.init()
        DispatchQueue.main.async {
            let config = WKWebViewConfiguration()
            let userController = WKUserContentController()
            
            // Script để hook XHR/Fetch, bắt link m3u8 khi player tải ẩn qua API và in ra DOM để checkDOM thấy được
            let jsHook = """
            (function() {
                var injectM3u8 = function(url) {
                    if (url && typeof url === 'string' && url.indexOf('.m3u8') !== -1 && document.body) {
                        var div = document.createElement('div');
                        div.innerText = 'file: "' + url + '"';
                        div.style.display = 'none';
                        document.body.appendChild(div);
                    }
                };

                var open = XMLHttpRequest.prototype.open;
                XMLHttpRequest.prototype.open = function(method, url) {
                    injectM3u8(url);
                    return open.apply(this, arguments);
                };
                
                var originalFetch = window.fetch;
                window.fetch = function() {
                    var url = arguments[0];
                    if (typeof url === 'object' && url.url) { url = url.url; }
                    injectM3u8(url);
                    return originalFetch.apply(this, arguments);
                };

                // Bắt link m3u8 gán trực tiếp vào thẻ video trên iOS
                var observer = new MutationObserver(function(mutations) {
                    mutations.forEach(function(mutation) {
                        var target = mutation.target;
                        if (target.tagName === 'VIDEO' || target.tagName === 'SOURCE') {
                            injectM3u8(target.src || target.getAttribute('src'));
                        }
                        if (mutation.addedNodes) {
                            mutation.addedNodes.forEach(function(n) {
                                if (n.tagName === 'VIDEO' || n.tagName === 'SOURCE') {
                                    injectM3u8(n.src || n.getAttribute('src'));
                                }
                            });
                        }
                    });
                });
                
                document.addEventListener("DOMContentLoaded", function() {
                    observer.observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ['src'] });
                });

                // Auto-click play trên trang xem-phim: AnimeVietsub chỉ fetch luồng .m3u8
                // SAU KHI user bấm nút "Xem phim" hoặc một tập. Headless WKWebView không
                // có ai bấm nên link không bao giờ được sinh ra. Tự bấm thay user.
                var autoPlayTries = 0;
                var autoPlay = function() {
                    autoPlayTries++;
                    if (autoPlayTries > 30) return; // ~15s
                    var path = window.location.pathname || '';
                    var looksLikeWatch = path.indexOf('xem-phim') !== -1
                        || path.indexOf('-tap-') !== -1
                        || path.indexOf('/tap-') !== -1
                        || (document.documentElement.outerHTML || '').indexOf('PLAYER_DATA') !== -1;
                    if (!looksLikeWatch) { setTimeout(autoPlay, 500); return; }

                    // Ưu tiên tập đang xem (halim-watching), kế đến mọi nút play/episode
                    var candidates = document.querySelectorAll(
                        '.halim-watching, a.halim-watching, .episode-active, .play-button, '
                        + '.video-play-button, .btn-play, #btn-watch, .watch-button, '
                        + '.halim-btn.halim-btn-2, .episode-link, .list-episode a, '
                        + '.halim-list-eps a'
                    );
                    var clicked = false;
                    for (var i = 0; i < candidates.length && !clicked; i++) {
                        try { candidates[i].click(); clicked = true; } catch (e) {}
                    }
                    var video = document.querySelector('video');
                    if (video) { try { video.play(); } catch (e) {} }
                    if (!clicked) setTimeout(autoPlay, 500);
                };
                // Chỉ khởi động auto-click khi đường dẫn rõ ràng là trang xem phim.
                // Không polling trên trang chủ / trang tìm kiếm / trang thông tin để
                // tránh tốn CPU và làm chậm checkDOM của các trang đó.
                var startAutoPlayIfWatch = function() {
                    var p = window.location.pathname || '';
                    if (p.indexOf('xem-phim') !== -1
                        || p.indexOf('-tap-') !== -1
                        || p.indexOf('/tap-') !== -1) {
                        setTimeout(autoPlay, 800);
                    }
                };
                document.addEventListener("DOMContentLoaded", startAutoPlayIfWatch);
                if (document.readyState !== 'loading') startAutoPlayIfWatch();
            })();
            """
            let script = WKUserScript(source: jsHook, injectionTime: .atDocumentStart, forMainFrameOnly: false)
            userController.addUserScript(script)
            config.userContentController = userController
            
            // Đặt ngoài màn hình để không bị iOS đình chỉ render (throttle JS của Cloudflare)
            self.webView = WKWebView(frame: CGRect(x: -3000, y: -3000, width: 375, height: 812), configuration: config)
            self.webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
            self.webView.navigationDelegate = self
            self.webView.isHidden = false
            self.webView.alpha = 1.0
        }
    }
    
    // Tải HTML thông qua WKWebView để tự động bypass Cloudflare/Bot-check
    func fetchHTML(url: String, waitForIframe: Bool = false, completion: @escaping (String) -> Void) {
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
                var req = URLRequest(url: targetUrl)
                req.setValue(self.resolvedDomain + "/", forHTTPHeaderField: "Referer")
                self.webView.load(req)
                // Trang xem phim cần ~40s vì còn phải chờ JS auto-click → AJAX trả luồng.
                // Trang chủ/tìm kiếm/thông tin chỉ cần render HTML tĩnh nên 15s là đủ;
                // hết thì rơi xuống fallback (bit.ly) ngay thay vì để user chờ mãi.
                let path = targetUrl.path
                let isWatchLike = waitForIframe
                    || path.contains("xem-phim")
                    || path.contains("-tap-")
                    || path.contains("/tap-")
                let retries = isWatchLike ? 40 : 10
                self.checkDOM(webView: self.webView, loadId: loadId, retries: retries, waitForIframe: waitForIframe)
            }
        }
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Setter của resolvedDomain đã tự lọc theo isAVSHost, ở đây chỉ cần log để debug.
        if let url = webView.url {
            print("[WebView] didFinish: \(url.absoluteString)")
            if let host = url.host {
                self.resolvedDomain = "https://" + host
            }
        }
    }
    
    private func checkDOM(webView: WKWebView, loadId: Int, retries: Int, waitForIframe: Bool) {
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
            
            let jsCheck = """
            (function() {
                if (\(waitForIframe ? "true" : "false")) {
                    return document.documentElement.outerHTML.indexOf('.m3u8') !== -1;
                }
                var html = document.documentElement.outerHTML;
                var path = window.location.pathname;
                
                var isWatchPage = path.indexOf('xem-phim.html') !== -1 || path.indexOf('-tap-') !== -1 || path.indexOf('/tap-') !== -1 || html.indexOf('PLAYER_DATA') !== -1;

                if (isWatchPage) {
                    // Phải chờ tới khi script PLAYER_DATA hoặc link iframe/m3u8 thực sự xuất hiện
                    // trong source, không thể chỉ dựa vào danh sách tập (vì danh sách hiển thị
                    // ngay nhưng PLAYER_DATA mới là dữ liệu để bóc luồng phim).
                    return html.indexOf('PLAYER_DATA') !== -1
                        || html.indexOf('.m3u8') !== -1
                        || html.indexOf('googleapiscdn') !== -1
                        || html.indexOf('streamlare') !== -1
                        || html.indexOf('hydrax') !== -1;
                }
                
                // Home/list được coi là sẵn sàng khi có ít nhất một số thẻ phim đã render.
                // Chấp nhận nhiều tên class vì site đổi theme theo từng đợt; nếu không khớp
                // selector nào thì kiểm tra số link /phim/ trong DOM như fallback cuối.
                var cardCount = document.querySelectorAll(
                    '.TPost, .TPostMv, .mli-eps, article, .ml-item, .halim-item, .movies-list .item'
                ).length;
                var phimLinkCount = document.querySelectorAll('a[href*="/phim/"]').length;
                var hasMovieCards = cardCount > 0 || phimLinkCount >= 6;

                var isListLike = path === '/' || path === ''
                    || path.indexOf('/phim') === 0
                    || path.indexOf('/tim-kiem') === 0
                    || path.indexOf('/the-loai') === 0
                    || html.indexOf('TPostMv') !== -1
                    || html.indexOf('MovieList') !== -1;
                var isHome = isListLike && hasMovieCards;

                var isInfo = html.indexOf('MovieInfo') !== -1 || html.indexOf('MvTbCn') !== -1;

                return isHome || isInfo || html.indexOf('.m3u8') !== -1;
            })();
            """
            
            webView.evaluateJavaScript(jsCheck) { [weak self] result, _ in
                let isReady = (result as? Bool) ?? false
                guard let self = self else { return }
                
                if isReady {
                    webView.evaluateJavaScript("document.documentElement.outerHTML") { htmlResult, _ in
                        let html = (htmlResult as? String) ?? ""
                        let queue = self.completionQueue
                        self.completionQueue.removeAll()
                        for completion in queue {
                            completion(html)
                        }
                    }
                } else {
                    self.checkDOM(webView: webView, loadId: loadId, retries: retries - 1, waitForIframe: waitForIframe)
                }
            }
        }
    }
    
    // Danh sách domain AVS quen thuộc, thử lần lượt nếu domain đã lưu fail.
    // bit.ly là phương án cuối vì chậm và đôi khi rate-limit.
    private let knownDomains = [
        "https://animevietsub.by",
        "https://animevietsub.cx",
        "https://animevietsub.lol",
        "https://animevietsub.show"
    ]

    func fetchHomeMovies(completion: @escaping ([Movie]) -> Void) {
        tryHomeFromDomains([resolvedDomain] + knownDomains.filter { $0 != resolvedDomain }, completion: completion)
    }

    private func tryHomeFromDomains(_ domains: [String], completion: @escaping ([Movie]) -> Void) {
        guard let first = domains.first else {
            // Cạn danh sách → fallback cuối qua bit.ly
            print("[fetchHomeMovies] Tất cả domain known đều fail, thử bit.ly")
            fetchHTML(url: backupUrl) { html in
                self.parseMovies(html: html, completion: completion)
            }
            return
        }
        print("[fetchHomeMovies] Thử domain: \(first)")
        fetchHTML(url: first) { html in
            self.parseMovies(html: html) { movies in
                if movies.isEmpty {
                    self.tryHomeFromDomains(Array(domains.dropFirst()), completion: completion)
                } else {
                    completion(movies)
                }
            }
        }
    }

    func parseMovies(html: String, completion: @escaping ([Movie]) -> Void) {
        var movies: [Movie] = appendMovies(from: html, pattern: parseMoviesPrimaryPattern)
        if movies.isEmpty {
            // Site đôi khi thay tên class hoặc bỏ <span class="mli-eps">. Pattern dự phòng
            // chỉ yêu cầu cấu trúc tối thiểu: <article ... href ... img src ... Title >.
            // epsRange là rỗng nên ta nhận diện ở appendMovies.
            movies = appendMovies(from: html, pattern: parseMoviesFallbackPattern)
        }
        print("[parseMovies] tìm thấy \(movies.count) phim (html=\(html.count) ký tự)")
        completion(movies)
    }

    private var parseMoviesPrimaryPattern: String {
        return "<article id=\"post-[\\s\\S]*?<a href=\"([^\"]+)\"[\\s\\S]*?<img[\\s\\S]*?src=\"([^\"]+)\"[\\s\\S]*?<span class=\"mli-eps\">(.*?)</span>[\\s\\S]*?<h2 class=\"Title\">([^<]+)</h2>"
    }

    private var parseMoviesFallbackPattern: String {
        // Match cả <article> lẫn <div class="TPostMv"> / <li class="TPostMv"> ...
        // Không bắt buộc có mli-eps; nếu không có sẽ để trống.
        return "<(?:article|div|li)[^>]*?(?:TPost|post-)[\\s\\S]*?<a[^>]*?href=\"([^\"]+)\"[\\s\\S]*?<img[\\s\\S]*?(?:data-src|src)=\"([^\"]+)\"[\\s\\S]*?<h[1-3][^>]*?(?:Title|TPostTitle|entry-title)[^>]*>([^<]+)</h[1-3]>"
    }

    private func appendMovies(from html: String, pattern: String) -> [Movie] {
        var result: [Movie] = []
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return result }
        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        for match in matches {
            guard let linkRange = Range(match.range(at: 1), in: html),
                  let imgRange = Range(match.range(at: 2), in: html) else { continue }
            let link = String(html[linkRange])
            let thumbUrl = String(html[imgRange])

            var title = ""
            var eps = ""
            if match.numberOfRanges >= 5,
               let epsRange = Range(match.range(at: 3), in: html),
               let titleRange = Range(match.range(at: 4), in: html) {
                eps = String(html[epsRange])
                    .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression, range: nil)
                title = String(html[titleRange])
            } else if match.numberOfRanges >= 4,
                      let titleRange = Range(match.range(at: 3), in: html) {
                title = String(html[titleRange])
            }

            result.append(Movie(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                link: link.hasPrefix("http") ? link : NetworkManager.shared.resolvedDomain + link,
                thumbUrl: thumbUrl,
                episodeStatus: eps.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        }
        return result
    }
    
    func fetchEpisodes(movieUrl: String, isRecursive: Bool = false, completion: @escaping ([Episode]) -> Void) {
        fetchHTML(url: movieUrl) { html in
            var episodes: [Episode] = []
            // Regex bắt tất cả các link chứa "tap-" hoặc có chữ "Tập" bên trong
            let pattern = "(?i)<a[^>]*?href=[\"']([^\"']*?tap-[^\"']*?\\.html)[\"'][^>]*>(.*?)</a>"
            
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
                for match in matches {
                    if let linkRange = Range(match.range(at: 1), in: html),
                       let titleRange = Range(match.range(at: 2), in: html) {
                        
                        let link = String(html[linkRange])
                        let title = String(html[titleRange]).replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression, range: nil).trimmingCharacters(in: .whitespacesAndNewlines)
                        
                        let lowerTitle = title.lowercased()
                        let lowerLink = link.lowercased()
                        if lowerTitle.contains("đăng nhập") || lowerTitle.contains("login") || lowerLink.contains("login") || lowerTitle.contains("đăng ký") {
                            continue
                        }
                        
                        episodes.append(Episode(title: title,
                                                link: link.hasPrefix("http") ? link : NetworkManager.shared.resolvedDomain + link,
                                                episodeId: nil))
                    }
                }
            }
            
            var uniqueEps: [Episode] = []
            var seen = Set<String>()
            // Đảo ngược danh sách vì tập 1 thường nằm cuối trong HTML (để hiển thị theo thứ tự cũ -> mới)
            for ep in episodes.reversed() {
                if !seen.contains(ep.link) {
                    seen.insert(ep.link)
                    uniqueEps.insert(ep, at: 0) // Giữ thứ tự đúng
                }
            }
            
            // Nếu tìm thấy <= 4 tập và chưa đệ quy, có thể ta đang ở trang thông tin (chỉ hiện tập mới cập nhật).
            // Ta sẽ vào thẳng link tập đầu tiên tìm được để quét toàn bộ danh sách tập.
            if uniqueEps.count <= 4 && !isRecursive && !uniqueEps.isEmpty {
                self.fetchEpisodes(movieUrl: uniqueEps[0].link, isRecursive: true, completion: completion)
            } else {
                completion(uniqueEps)
            }
        }
    }
}
