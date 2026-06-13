import Foundation
import WebKit

class NetworkManager: NSObject, WKNavigationDelegate {
    static let shared = NetworkManager()
    
    private static let defaultDomain = "https://animevietsub.pl"

    var resolvedDomain: String {
        get {
            UserDefaults.standard.string(forKey: "AVS_ResolvedDomain") ?? Self.defaultDomain
        }
        set {
            let cleaned = newValue.hasSuffix("/") ? String(newValue.dropLast()) : newValue
            guard cleaned.hasPrefix("http") else {
                Logger.shared.log("Bỏ qua domain không hợp lệ: \(newValue)")
                return
            }
            if UserDefaults.standard.string(forKey: "AVS_ResolvedDomain") != cleaned {
                UserDefaults.standard.set(cleaned, forKey: "AVS_ResolvedDomain")
                Logger.shared.log("Đã cập nhật domain mới: \(cleaned)")
            }
        }
    }
    
    /// Ép URL về đúng resolvedDomain hiện tại, dù link gốc chứa domain cũ.
    func normalizeURL(_ urlString: String) -> String {
        guard !urlString.hasPrefix("http") else {
            guard let url = URL(string: urlString),
                  let currentBase = URL(string: resolvedDomain),
                  url.host?.lowercased() != currentBase.host?.lowercased() else {
                return urlString
            }
            var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            comps?.scheme = currentBase.scheme
            comps?.host = currentBase.host
            comps?.port = currentBase.port
            return comps?.url?.absoluteString ?? urlString
        }
        let base = resolvedDomain.hasSuffix("/") ? String(resolvedDomain.dropLast()) : resolvedDomain
        let path = urlString.hasPrefix("/") ? urlString : "/" + urlString
        return base + path
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
                // Regex dùng chung cho cả URL lẫn body text
                var M3U8_RE = /https?:\\/\\/[^\\s"'<>\\\\]+?\\.m3u8[^\\s"'<>\\\\]*/gi;
                var IFRAME_HOSTS_RE = /https?:\\/\\/[^\\s"'<>\\\\]*?(googleapiscdn|streamlare|hydrax|fembed|streamtape|filemoon)[^\\s"'<>\\\\]+/gi;

                var injectInBody = function(text) {
                    if (!document.body) return;
                    var div = document.createElement('div');
                    div.innerText = text;
                    div.style.display = 'none';
                    document.body.appendChild(div);
                };

                var injectM3u8Marker = function(url) {
                    if (!url || typeof url !== 'string') return;
                    var clean = url.replace(/\\\\\\//g, '/');
                    if (clean.indexOf('.m3u8') === -1) return;
                    injectInBody('file: "' + clean + '"');
                    try {
                        if (window.top && window.top !== window) {
                            window.top.postMessage({ avsM3u8: clean }, '*');
                        }
                    } catch (e) {}
                };

                var injectIframeMarker = function(url) {
                    if (!url || typeof url !== 'string') return;
                    var clean = url.replace(/\\\\\\//g, '/');
                    injectInBody('iframe: "' + clean + '"');
                    try {
                        if (window.top && window.top !== window) {
                            window.top.postMessage({ avsIframe: clean }, '*');
                        }
                    } catch (e) {}
                };

                // Quét response body: m3u8 trực tiếp HOẶC link iframe player (host quen).
                // AVS ajax/player trả về {link: "https://stream.googleapiscdn.com/player/HASH",
                // playTech: "iframe"} — request URL không có gì đặc biệt, chỉ response mới có.
                var scanText = function(text) {
                    if (typeof text !== 'string' || text.length === 0) return;
                    var m, count;
                    count = 0;
                    M3U8_RE.lastIndex = 0;
                    while ((m = M3U8_RE.exec(text)) !== null && count++ < 8) {
                        injectM3u8Marker(m[0]);
                    }
                    count = 0;
                    IFRAME_HOSTS_RE.lastIndex = 0;
                    while ((m = IFRAME_HOSTS_RE.exec(text)) !== null && count++ < 8) {
                        injectIframeMarker(m[0]);
                    }
                };

                // Tương thích ngược với phần code cũ gọi injectMarker(url) cho m3u8
                var injectMarker = injectM3u8Marker;

                // Hook XHR: cả request URL lẫn response text khi xong
                var open = XMLHttpRequest.prototype.open;
                XMLHttpRequest.prototype.open = function(method, url) {
                    injectMarker(url);
                    try {
                        this.addEventListener('load', function() {
                            try { scanText(this.responseText || ''); } catch (e) {}
                        });
                    } catch (e) {}
                    return open.apply(this, arguments);
                };

                // Hook fetch: URL + clone response để đọc text mà không ảnh hưởng caller
                var originalFetch = window.fetch;
                window.fetch = function() {
                    var url = arguments[0];
                    if (typeof url === 'object' && url && url.url) { url = url.url; }
                    injectMarker(url);
                    var p = originalFetch.apply(this, arguments);
                    try {
                        return p.then(function(resp) {
                            try {
                                resp.clone().text().then(function(t) { scanText(t); }).catch(function(){});
                            } catch (e) {}
                            return resp;
                        });
                    } catch (e) {
                        return p;
                    }
                };

                // Lắng nghe message từ iframe con (cross-origin) gửi lên: m3u8 hoặc iframe URL
                if (!window.__avsTopHooked && window.top === window) {
                    window.__avsTopHooked = true;
                    window.addEventListener('message', function(e) {
                        if (!e || !e.data || typeof e.data !== 'object') return;
                        if (e.data.avsM3u8) injectM3u8Marker(e.data.avsM3u8);
                        if (e.data.avsIframe) injectIframeMarker(e.data.avsIframe);
                    });
                }

                // Bắt link m3u8 gán trực tiếp vào thẻ video / source trên iOS,
                // BAO GỒM cả data URL chứa m3u8 đã giải mã sẵn (JWPlayer của AVS
                // gắn vào src dạng "data:application/vnd.apple.mpegurl;base64,...").
                var injectVideoDataMarker = function(src) {
                    if (!src || typeof src !== 'string') return;
                    var lc = src.toLowerCase();
                    if (lc.indexOf('data:application/vnd.apple.mpegurl') === 0
                        || lc.indexOf('data:application/x-mpegurl') === 0
                        || lc.indexOf('data:audio/mpegurl') === 0) {
                        // KHÔNG inject toàn bộ data URL (có thể vài MB) vào innerText —
                        // chỉ đánh dấu sự tồn tại + post message để top frame biết và
                        // Extractor có thể querySelector('video').src lấy giá trị thật.
                        injectInBody('videoData: present');
                        try {
                            if (window.top && window.top !== window) {
                                window.top.postMessage({ avsVideoData: true }, '*');
                            }
                        } catch (e) {}
                    } else {
                        injectM3u8Marker(src);
                    }
                };

                var observer = new MutationObserver(function(mutations) {
                    mutations.forEach(function(mutation) {
                        var target = mutation.target;
                        if (target.tagName === 'VIDEO' || target.tagName === 'SOURCE') {
                            injectVideoDataMarker(target.src || target.getAttribute('src'));
                        }
                        if (mutation.addedNodes) {
                            mutation.addedNodes.forEach(function(n) {
                                if (n.tagName === 'VIDEO' || n.tagName === 'SOURCE') {
                                    injectVideoDataMarker(n.src || n.getAttribute('src'));
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
                    if (autoPlayTries > 60) return; // ~30s
                    var path = window.location.pathname || '';
                    var host = window.location.host || '';
                    var topHTML = document.documentElement.outerHTML || '';

                    var isIframePlayer = path.indexOf('/player/') !== -1
                        || host.indexOf('googleapiscdn') !== -1
                        || host.indexOf('streamlare') !== -1;
                    var isAVSWatch = path.indexOf('xem-phim') !== -1
                        || path.indexOf('-tap-') !== -1
                        || path.indexOf('/tap-') !== -1;

                    if (!isIframePlayer && !isAVSWatch) { setTimeout(autoPlay, 500); return; }

                    // Đã có m3u8 URL thật trong DOM → dừng (đã xong việc).
                    if (/[\"\\']https?:\\/\\/[^\"\\'\\s]+?\\.m3u8/i.test(topHTML)) return;

                    // Trên trang AVS: PLAYER_DATA đã được render server-side. Extractor
                    // sẽ bóc từ HTML, KHÔNG CẦN click bất cứ gì. Click vào episode link
                    // (anchor tag) sẽ điều hướng trang, gây reload → JWPlayer iframe
                    // fetch m3u8 nhiều lần → server rate-limit (HTTP 429).
                    if (isAVSWatch) {
                        if (topHTML.indexOf('PLAYER_DATA') !== -1) return;
                        // Chưa có PLAYER_DATA: thử bấm chỉ nút Xem phim (button hoặc div,
                        // KHÔNG anchor) để trigger AJAX. Tuyệt đối không click anchor.
                        var safe = document.querySelectorAll(
                            'button#btn-film-watch, button.btn-film-watch, '
                            + 'button.play-button, button.video-play-button, '
                            + 'button.btn-play, button#btn-watch, button.watch-button, '
                            + 'div.play-button, div.video-play-button, div.btn-play'
                        );
                        for (var i = 0; i < safe.length && i < 4; i++) {
                            try { safe[i].click(); } catch (e) {}
                        }
                        setTimeout(autoPlay, 500);
                        return;
                    }

                    // Trên iframe player: click overlay JWPlayer / gọi API play().
                    // Cũng tránh anchor để không bị điều hướng.
                    if (isIframePlayer) {
                        var jw = document.querySelectorAll(
                            '.jw-icon-display, .jw-display-icon-container, '
                            + '.jw-icon-playback, #player, .jwplayer'
                        );
                        for (var j = 0; j < jw.length && j < 5; j++) {
                            try { jw[j].click(); } catch (e) {}
                        }
                        var video = document.querySelector('video');
                        if (video) { try { video.play(); } catch (e) {} }
                        try {
                            if (typeof jwplayer === 'function') {
                                var jp = jwplayer();
                                if (jp && typeof jp.play === 'function') jp.play(true);
                            }
                        } catch (e) {}
                        setTimeout(autoPlay, 500);
                        return;
                    }
                };
                // Khởi động auto-click trên cả trang xem AVS lẫn iframe player của bên thứ 3.
                // Trang chủ/search/info bỏ qua để khỏi tốn CPU.
                var startAutoPlayIfWatch = function() {
                    var p = window.location.pathname || '';
                    var h = window.location.host || '';
                    if (p.indexOf('xem-phim') !== -1
                        || p.indexOf('-tap-') !== -1
                        || p.indexOf('/tap-') !== -1
                        || p.indexOf('/player/') !== -1
                        || h.indexOf('googleapiscdn') !== -1
                        || h.indexOf('streamlare') !== -1) {
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

            // Trả về chuỗi rỗng cho các request cũ để tránh bị treo (hang) UI
            for oldCompletion in self.completionQueue {
                oldCompletion("")
            }
            self.completionQueue.removeAll()
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
                // Giảm số lần retry + poll nhanh hơn để load nhanh
                let retries: Int
                if waitForIframe {
                    retries = 16
                } else if isWatchLike {
                    retries = 10
                } else {
                    retries = 6
                }
                self.checkDOM(webView: self.webView, loadId: loadId, retries: retries, waitForIframe: waitForIframe)
            }
        }
    }
    
    /// Lấy giá trị src của <video> hiện tại trong WKWebView. Dùng khi iframe player
    /// đã render và JWPlayer gắn data URL HLS lên <video> (không in ra outerHTML
    /// theo cách regex thông thường bắt được). Trả về chuỗi rỗng nếu không có.
    func fetchVideoSrc(completion: @escaping (String) -> Void) {
        DispatchQueue.main.async {
            let js = "(function(){var v=document.querySelector('video');return v?(v.src||v.getAttribute('src')||''):''})()"
            self.webView.evaluateJavaScript(js) { result, _ in
                completion((result as? String) ?? "")
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Logger.shared.log("[WebView] didFinish: \(webView.url?.absoluteString ?? "nil")")
        syncCookiesToURLSession()
    }

    private func syncCookiesToURLSession() {
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            for c in cookies {
                HTTPCookieStorage.shared.setCookie(c)
            }
        }
    }

    /// Live search suggestion qua AJAX endpoint `/ajax/suggest`.
    /// Trả tối đa 5-6 phim trong < 500ms (URLSession trực tiếp, không qua WebView).
    func fetchSearchSuggestions(keyword: String, completion: @escaping ([Movie]) -> Void) {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { completion([]); return }
        guard let url = URL(string: "\(resolvedDomain)/ajax/suggest") else { completion([]); return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 6
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        req.setValue("\(resolvedDomain)/", forHTTPHeaderField: "Referer")
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1",
                     forHTTPHeaderField: "User-Agent")

        // Form encoding: dấu cách = '+', còn lại percent-encode. AVS dùng form key
        // `ajaxSearch=1&keysearch=<từ khoá>`.
        let encoded = trimmed
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)?
            .replacingOccurrences(of: "%20", with: "+") ?? trimmed
        let body = "ajaxSearch=1&keysearch=\(encoded)"
        req.httpBody = body.data(using: .utf8)

        URLSession.shared.dataTask(with: req) { data, resp, err in
            if let err = err {
                Logger.shared.log("[Suggest] LỖI: \(err.localizedDescription)")
                DispatchQueue.main.async { completion([]) }
                return
            }
            if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
                Logger.shared.log("[Suggest] HTTP \(http.statusCode) cho '\(trimmed)'")
            }
            let html = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let movies = Self.parseSuggestions(html: html)
            Logger.shared.log("[Suggest] '\(trimmed)' → \(movies.count) gợi ý")
            DispatchQueue.main.async { completion(movies) }
        }.resume()
    }

    /// Parse 1 trong <li> của response AJAX suggest:
    /// <li>
    ///   <a style="background-image: url('POSTER')" href="LINK"></a>
    ///   <div class="ss-info">
    ///     <a class="ss-title" href="...">TITLE</a>
    ///     <p>EPISODE STATUS</p>
    ///   </div>
    /// </li>
    private static func parseSuggestions(html: String) -> [Movie] {
        var result: [Movie] = []
        var seen = Set<String>()
        let liPattern = "<li[^>]*>([\\s\\S]*?)</li>"
        guard let liRegex = try? NSRegularExpression(pattern: liPattern, options: .caseInsensitive) else { return [] }
        let lis = liRegex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        for m in lis {
            guard let r = Range(m.range(at: 1), in: html) else { continue }
            let inner = String(html[r])
            // Skip footer "Enter để tìm kiếm"
            if inner.contains("suggest-all") || inner.contains("ss-bottom") { continue }

            let poster = firstMatch(in: inner, pattern: "background-image:\\s*url\\(['\"]?([^'\"\\)]+)['\"]?\\)")
            let link = firstMatch(in: inner, pattern: "<a[^>]+href=\"([^\"]+)\"[^>]*class=\"thumb\"")
                ?? firstMatch(in: inner, pattern: "<a[^>]+class=\"thumb\"[^>]*href=\"([^\"]+)\"")
                ?? firstMatch(in: inner, pattern: "<a[^>]+class=\"ss-title\"[^>]*href=\"([^\"]+)\"")
                ?? firstMatch(in: inner, pattern: "href=\"([^\"]*?/phim/[^\"]+)\"")
            let title = firstMatch(in: inner, pattern: "<a[^>]+class=\"ss-title\"[^>]*>([^<]+)</a>")
            let status = firstMatch(in: inner, pattern: "<p>([^<]+)</p>")

            guard let link = link, let title = title, !seen.contains(link) else { continue }
            seen.insert(link)
            result.append(Movie(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                link: link,
                thumbUrl: poster ?? "",
                episodeStatus: (status ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        }
        return result
    }

    private static func firstMatch(in html: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return nil }
        guard let m = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let r = Range(m.range(at: 1), in: html) else { return nil }
        return String(html[r])
    }
    
    private func checkDOM(webView: WKWebView, loadId: Int, retries: Int, waitForIframe: Bool) {
        // Nếu đã có request mới đè lên, hủy vòng lặp này
        if loadId != self.currentLoadId { return }
        
        if retries <= 0 {
            // Hết retry. Lấy HTML hiện tại (không phải rỗng) + diagnostic để Extractor
            // có thể log snippet quanh các keyword, biết tại sao JWPlayer không khởi động.
            webView.evaluateJavaScript("document.documentElement.outerHTML") { [weak self] htmlResult, _ in
                let html = (htmlResult as? String) ?? ""
                guard let self = self else { return }
                Logger.shared.log("[checkDOM] Hết retry. HTML hiện tại dài \(html.count) ký tự.")
                let diagJS = """
                JSON.stringify({
                    path: window.location.pathname,
                    host: window.location.host,
                    title: document.title,
                    bodyLen: (document.body && document.body.innerHTML || '').length,
                    scripts: [].slice.call(document.scripts).map(function(s){return s.src||'(inline)'}).slice(0, 30),
                    videoCount: document.querySelectorAll('video').length,
                    videoSrc: (document.querySelector('video')||{}).src || '',
                    sourceCount: document.querySelectorAll('source').length,
                    sourceSrc: (document.querySelector('source')||{}).src || '',
                    iframeCount: document.querySelectorAll('iframe').length,
                    iframeSrc: (document.querySelector('iframe')||{}).src || '',
                    hasJwplayer: typeof jwplayer === 'function',
                    hasJwInstance: (typeof jwplayer === 'function') ? !!jwplayer('player') : false,
                    buttonsClicked: (document.querySelectorAll('button, .jw-icon-display, .play-button, .video-play-button').length),
                    challengeText: (document.body && document.body.innerText || '').slice(0, 200)
                })
                """
                webView.evaluateJavaScript(diagJS) { diagResult, _ in
                    if let s = diagResult as? String {
                        Logger.shared.log("[checkDOM] Diagnostic: \(s)")
                    }
                    let queue = self.completionQueue
                    self.completionQueue.removeAll()
                    for completion in queue {
                        completion(html)
                    }
                }
            }
            return
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if loadId != self.currentLoadId { return }
            
            let jsCheck = """
            (function() {
                if (\(waitForIframe ? "true" : "false")) {
                    var oh = document.documentElement.outerHTML;
                    // Stricter: phải có URL m3u8 thực sự trong dấu nháy hoặc dạng file:"..."
                    // chứ không chỉ là chuỗi con ".m3u8" (jwplayer init code có chữ này sẵn
                    // nên indexOf trả về true ngay lập tức trước khi luồng thực sự được fetch).
                    if (/[\"\\']https?:\\/\\/[^\"\\'\\s]+?\\.m3u8/i.test(oh)) return true;
                    if (/file\\s*:\\s*[\"\\']https?:\\/\\/[^\"\\'\\s]+?\\.m3u8/i.test(oh)) return true;
                    // <video src="..m3u8..."> hoặc data URL HLS đã inject vào video element
                    if (document.querySelector('video[src*=".m3u8"], source[src*=".m3u8"]')) return true;
                    // Data URL HLS đã chèn vào video src (JWPlayer của AVS làm trò này sau khi
                    // anti-bot avs-shield.min.js / avs-fingerprint.min.js verify xong).
                    var v = document.querySelector('video');
                    if (v && v.src && /^data:(application\\/vnd\\.apple\\.mpegurl|application\\/x-mpegurl|audio\\/mpegurl)/i.test(v.src)) return true;
                    if (oh.indexOf('videoData: present') !== -1) return true;
                    return false;
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

                var isHome = hasMovieCards;

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
    
    func fetchHomeMovies(completion: @escaping ([Movie]) -> Void) {
        if let cached: [Movie] = DiskCache.shared.get("home", ttl: 1800, as: [Movie].self), !cached.isEmpty {
            Logger.shared.log("[fetchHomeMovies] CACHE HIT (\(cached.count) phim) — trả ngay + refresh nền")
            completion(cached)
            fetchHomePlusLatest { fresh in
                if !fresh.isEmpty { DiskCache.shared.set(fresh, forKey: "home") }
            }
            return
        }
        fetchHomePlusLatest { movies in
            if !movies.isEmpty { DiskCache.shared.set(movies, forKey: "home") }
            completion(movies)
        }
    }

    func fetchMoviesPage(_ page: Int, completion: @escaping ([Movie]) -> Void) {
        fetchHTML(url: "\(resolvedDomain)/phim-moi/page/\(page)/") { html in
            self.parseMovies(html: html, completion: completion)
        }
    }

    private func fetchHomePlusLatest(completion: @escaping ([Movie]) -> Void) {
        var homeMovies: [Movie] = []
        var page1Movies: [Movie] = []
        var page2Movies: [Movie] = []

        fetchHTML(url: resolvedDomain) { [weak self] html in
            self?.parseMovies(html: html) { movies in
                homeMovies = movies
                guard let self = self else { return }
                
                self.fetchHTML(url: "\(self.resolvedDomain)/phim-moi/page/1/") { html1 in
                    self.parseMovies(html: html1) { m1 in
                        page1Movies = m1
                        
                        self.fetchHTML(url: "\(self.resolvedDomain)/phim-moi/page/2/") { html2 in
                            self.parseMovies(html: html2) { m2 in
                                page2Movies = m2
                                
                                var seen = Set<String>()
                                var combined: [Movie] = []
                                for m in homeMovies + page1Movies + page2Movies where seen.insert(m.link).inserted {
                                    combined.append(m)
                                }
                                Logger.shared.log("[Home] home=\(homeMovies.count) + page1=\(page1Movies.count) + page2=\(page2Movies.count) → \(combined.count) phim sau dedupe")
                                completion(combined)
                            }
                        }
                    }
                }
            }
        }
    }

    func parseMovies(html: String, completion: @escaping ([Movie]) -> Void) {
        var movies: [Movie] = appendMovies(from: html, pattern: parseMoviesPrimaryPattern)
        var matchedPattern = "primary"
        if movies.isEmpty {
            movies = appendMovies(from: html, pattern: parseMoviesFallbackPattern)
            matchedPattern = "fallback"
        }
        if movies.isEmpty {
            movies = appendMoviesLoose(from: html)
            matchedPattern = "loose"
        }
        // Dedupe theo link — home AVS đôi khi chèn phim vào nhiều block (Hot, Mới cập nhật...)
        // dẫn tới trùng. Giữ thứ tự xuất hiện đầu tiên.
        var seen = Set<String>()
        movies = movies.filter { seen.insert($0.link).inserted }
        Logger.shared.log("[parseMovies] \(matchedPattern) → \(movies.count) phim (sau dedupe), html=\(html.count) ký tự")
        completion(movies)
    }

    /// Pattern lỏng nhất: tìm mọi `<a href="...phim/...">` và lấy `<img>` + text trong cùng anchor.
    /// Dùng cho trang search / genre / sort khi không khớp template chính.
    private func appendMoviesLoose(from html: String) -> [Movie] {
        var result: [Movie] = []
        var seen = Set<String>()
        let pattern = "(?i)<a[^>]*?href=\"([^\"]*?/phim/[^\"]+?)\"[^>]*>([\\s\\S]{0,2000}?)</a>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        for m in matches {
            guard let linkRange = Range(m.range(at: 1), in: html),
                  let inner = Range(m.range(at: 2), in: html) else { continue }
            let link = String(html[linkRange])
            if seen.contains(link) { continue }
            let innerHtml = String(html[inner])

            // Image src
            var thumb = ""
            if let imgRegex = try? NSRegularExpression(pattern: "(?i)<img[^>]*?(?:data-src|data-original|src)=\"([^\"]+)\"") {
                if let imgMatch = imgRegex.firstMatch(in: innerHtml, range: NSRange(innerHtml.startIndex..., in: innerHtml)),
                   let r = Range(imgMatch.range(at: 1), in: innerHtml) {
                    thumb = String(innerHtml[r])
                }
            }
            // Title: prefer <h*> content, else <img alt>, else stripped text
            var title = ""
            if let hRegex = try? NSRegularExpression(pattern: "(?i)<h[1-6][^>]*>([^<]+)</h[1-6]>") {
                if let hMatch = hRegex.firstMatch(in: innerHtml, range: NSRange(innerHtml.startIndex..., in: innerHtml)),
                   let r = Range(hMatch.range(at: 1), in: innerHtml) {
                    title = String(innerHtml[r])
                }
            }
            if title.isEmpty,
               let altRegex = try? NSRegularExpression(pattern: "(?i)<img[^>]*?alt=\"([^\"]+)\""),
               let altMatch = altRegex.firstMatch(in: innerHtml, range: NSRange(innerHtml.startIndex..., in: innerHtml)),
               let r = Range(altMatch.range(at: 1), in: innerHtml) {
                title = String(innerHtml[r])
            }
            if title.isEmpty {
                title = innerHtml
                    .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression, range: nil)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            // Bỏ qua match rác (link điều hướng, anchor trống)
            if trimmedTitle.isEmpty || trimmedTitle.count > 200 || thumb.isEmpty { continue }
            seen.insert(link)
            result.append(Movie(
                title: trimmedTitle,
                link: link.hasPrefix("http") ? link : NetworkManager.shared.resolvedDomain + link,
                thumbUrl: thumb,
                episodeStatus: ""
            ))
        }
        return result
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
    
    // MARK: - Movie details (info page)

    /// Fetch trang info phim → parse description, year, rating, banner, genres.
    /// Cache 24h vì info ít đổi.
    func fetchMovieDetails(movieUrl: String, completion: @escaping (MovieDetails?) -> Void) {
        let normalizedUrl = normalizeURL(movieUrl)
        let key = "details." + (normalizedUrl.data(using: .utf8)?.base64EncodedString() ?? normalizedUrl)
        if let cached: MovieDetails = DiskCache.shared.get(key, ttl: 86400, as: MovieDetails.self) {
            completion(cached)
            return
        }
        fetchHTML(url: normalizedUrl) { html in
            let details = Self.parseDetails(from: html)
            if !details.description.isEmpty || !details.genres.isEmpty {
                DiskCache.shared.set(details, forKey: key)
            }
            completion(details)
        }
    }

    private static func parseDetails(from html: String) -> MovieDetails {
        func match(_ pattern: String, group: Int = 1) -> String {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return "" }
            let r = NSRange(html.startIndex..., in: html)
            guard let m = regex.firstMatch(in: html, range: r),
                  let range = Range(m.range(at: group), in: html) else { return "" }
            return String(html[range])
                .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression, range: nil)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var description = match("class=\"Description\">\\s*<p>(.+?)</p>")
        if description.isEmpty {
            description = match("<meta name=\"description\" content=\"([^\"]+)\"")
        }
        var year = match("class=\"Date\"[^>]*>([^<]+)")
        if year.isEmpty {
            year = match("\\b(19|20)\\d{2}\\b", group: 0)
        }
        var rating = match("class=\"post-ratings?\"[^>]*>([^<]+)")
        if rating.isEmpty {
            rating = match("\"ratingValue\"\\s*:\\s*\"?([0-9.]+)")
        }
        var banner = ""
        if let r = try? NSRegularExpression(pattern: "class=\"TPostBg[\\s\\S]*?<img[^>]+src=\"([^\"]+)\"", options: .caseInsensitive) {
            if let m = r.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let g = Range(m.range(at: 1), in: html) {
                banner = String(html[g])
            }
        }
        if banner.isEmpty {
            if let r = try? NSRegularExpression(pattern: "<meta property=\"og:image\" content=\"([^\"]+)\"", options: .caseInsensitive) {
                if let m = r.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                   let g = Range(m.range(at: 1), in: html) {
                    banner = String(html[g])
                }
            }
        }

        var genres: [String] = []
        if let r = try? NSRegularExpression(pattern: "<a[^>]+href=\"[^\"]*?/the-loai/[^\"]+\"[^>]*>([^<]+)</a>", options: .caseInsensitive) {
            let ms = r.matches(in: html, range: NSRange(html.startIndex..., in: html))
            var seen = Set<String>()
            for m in ms {
                if let g = Range(m.range(at: 1), in: html) {
                    let name = String(html[g]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty && !seen.contains(name) && name.count < 30 {
                        seen.insert(name)
                        genres.append(name)
                    }
                }
            }
        }

        return MovieDetails(description: description, year: year, rating: rating, bannerUrl: banner, genres: genres)
    }

    func fetchEpisodes(movieUrl: String, isRecursive: Bool = false, completion: @escaping ([Episode]) -> Void) {
        let normalizedUrl = normalizeURL(movieUrl)
        let cacheKey = "episodes." + (normalizedUrl.data(using: .utf8)?.base64EncodedString() ?? normalizedUrl)
        if !isRecursive, let cached: [Episode] = DiskCache.shared.get(cacheKey, ttl: 3600, as: [Episode].self), !cached.isEmpty {
            Logger.shared.log("[fetchEpisodes] CACHE HIT \(cached.count) tập")
            completion(cached)
            return
        }
        fetchHTML(url: normalizedUrl) { html in
            var episodes: [Episode] = []
            
            let patterns = [
                "(?i)<a[^>]*?href=[\"']([^\"']*?tap-[^\"']*?(?:\\.html)?)[\"'][^>]*>(.*?)</a>",
                "(?i)<a[^>]*?href=[\"']([^\"']*?(?:/episode|/xem-phim|/tap)[^\"']*?(?:\\.html)?)[\"'][^>]*>(.*?)</a>"
            ]
            for pattern in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
                let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
                for match in matches {
                    guard let linkRange = Range(match.range(at: 1), in: html),
                          let titleRange = Range(match.range(at: 2), in: html) else { continue }
                    
                    let link = String(html[linkRange])
                    let title = String(html[titleRange]).replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression, range: nil).trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    let lowerTitle = title.lowercased()
                    let lowerLink = link.lowercased()
                    if lowerTitle.contains("đăng nhập") || lowerTitle.contains("login") || lowerLink.contains("login") || lowerTitle.contains("đăng ký") {
                        continue
                    }
                    
                    let isEpisodeTitle = lowerTitle.contains("tập")
                        || lowerTitle.contains("episode")
                        || (title.rangeOfCharacter(from: .decimalDigits) != nil && title.count < 30)
                    guard isEpisodeTitle else { continue }
                    
                    let fullLink = NetworkManager.shared.normalizeURL(link)
                    if !episodes.contains(where: { $0.link == fullLink }) {
                        episodes.append(Episode(title: title, link: fullLink))
                    }
                }
                if !episodes.isEmpty { break }
            }
            
            var uniqueEps: [Episode] = []
            var seen = Set<String>()
            for ep in episodes.reversed() {
                if !seen.contains(ep.link) {
                    seen.insert(ep.link)
                    uniqueEps.insert(ep, at: 0)
                }
            }
            
            if uniqueEps.count <= 4 && !isRecursive && !uniqueEps.isEmpty {
                self.fetchEpisodes(movieUrl: uniqueEps[0].link, isRecursive: true) { innerEps in
                    var merged = uniqueEps
                    var seenInner = Set(merged.map { $0.link })
                    for ep in innerEps where seenInner.insert(ep.link).inserted {
                        merged.append(ep)
                    }
                    if !merged.isEmpty { DiskCache.shared.set(merged, forKey: cacheKey) }
                    completion(merged)
                }
            } else {
                if !uniqueEps.isEmpty { DiskCache.shared.set(uniqueEps, forKey: cacheKey) }
                completion(uniqueEps)
            }
        }
    }
}
