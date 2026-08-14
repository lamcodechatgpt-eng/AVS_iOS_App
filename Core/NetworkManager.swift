import Foundation
import UIKit
import WebKit

class NetworkManager: NSObject, WKNavigationDelegate {
    static let shared = NetworkManager()
    
    private static let defaultDomain = "https://animevietsub.meme"
    private static let domainProbeDateKey = "AVS_LastDomainProbe"
    private static let domainProbeSuccessKey = "AVS_LastDomainProbeSucceeded"
    private static let domainCandidates = [
        "https://animevietsub.meme",
        "https://animevietsub.mom",
        "https://animevietsub.baby",
        "https://animevietsub.vip",
        "https://animevietsub.io",
        "https://animevietsub.site"
    ]

    private var domainProbeInFlight = false
    private var domainProbeCompletions: [(String) -> Void] = []

    var resolvedDomain: String {
        get {
            let stored = UserDefaults.standard.string(forKey: "AVS_ResolvedDomain")
            return stored == "https://animevietsub.pl" ? Self.defaultDomain : (stored ?? Self.defaultDomain)
        }
        set {
            let candidate = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: candidate),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  let host = url.host, !host.isEmpty else {
                Logger.shared.log("Bỏ qua domain không hợp lệ: \(newValue)")
                return
            }
            var components = URLComponents()
            components.scheme = scheme
            components.host = host
            components.port = url.port
            guard let cleaned = components.url?.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) else {
                Logger.shared.log("Bỏ qua domain không thể chuẩn hoá: \(newValue)")
                return
            }
            if UserDefaults.standard.string(forKey: "AVS_ResolvedDomain") != cleaned {
                UserDefaults.standard.set(cleaned, forKey: "AVS_ResolvedDomain")
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.domainProbeDateKey)
                UserDefaults.standard.set(true, forKey: Self.domainProbeSuccessKey)
                DiskCache.shared.removeAll()
                Logger.shared.log("Đã cập nhật domain mới: \(cleaned)")
            }
        }
    }
    
    /// Ép URL về đúng resolvedDomain hiện tại, dù link gốc chứa domain cũ.
    /// Probe known aliases and keep the first one serving a real listing page.
    /// The timestamp avoids probing every candidate on every app launch.
    func autoDetectDomain(force: Bool = false, completion: @escaping (String) -> Void) {
        let start = {
            let now = Date().timeIntervalSince1970
            let lastProbe = UserDefaults.standard.double(forKey: Self.domainProbeDateKey)
            let lastProbeSucceeded = UserDefaults.standard.bool(forKey: Self.domainProbeSuccessKey)
            let validCacheWindow = lastProbeSucceeded ? 6 * 60 * 60 : 10 * 60
            if !force, lastProbe > 0, now - lastProbe < validCacheWindow {
                completion(self.resolvedDomain)
                return
            }

            self.domainProbeCompletions.append(completion)
            guard !self.domainProbeInFlight else { return }
            self.domainProbeInFlight = true
            UserDefaults.standard.set(now, forKey: Self.domainProbeDateKey)

            let group = DispatchGroup()
            let lock = NSLock()
            var selectedDomain: String?
            for candidate in Self.domainCandidates {
                guard let url = URL(string: candidate) else { continue }
                group.enter()
                var request = URLRequest(url: url)
                request.timeoutInterval = 5
                request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
                request.setValue("vi-VN,vi;q=0.9,en;q=0.7", forHTTPHeaderField: "Accept-Language")
                request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1",
                                 forHTTPHeaderField: "User-Agent")
                URLSession.shared.dataTask(with: request) { data, response, error in
                    defer { group.leave() }
                    guard error == nil,
                          let http = response as? HTTPURLResponse,
                          let html = data.flatMap({ String(data: $0, encoding: .utf8) }),
                          Self.isUsableListingHTML(html, statusCode: http.statusCode),
                          let finalURL = http.url,
                          let scheme = finalURL.scheme,
                          let host = finalURL.host else { return }
                    var components = URLComponents()
                    components.scheme = scheme
                    components.host = host
                    components.port = finalURL.port
                    guard let detected = components.url?.absoluteString else { return }
                    lock.lock()
                    if selectedDomain == nil { selectedDomain = detected }
                    lock.unlock()
                }.resume()
            }
            group.notify(queue: .main) {
                lock.lock()
                let detected = selectedDomain
                lock.unlock()
                if let detected = detected, detected != self.resolvedDomain {
                    self.resolvedDomain = detected
                    Logger.shared.log("[Domain] Auto-selected \(detected)")
                }
                UserDefaults.standard.set(detected != nil, forKey: Self.domainProbeSuccessKey)
                let result = self.resolvedDomain
                let completions = self.domainProbeCompletions
                self.domainProbeCompletions.removeAll()
                self.domainProbeInFlight = false
                completions.forEach { $0(result) }
            }
        }
        if Thread.isMainThread { start() } else { DispatchQueue.main.async(execute: start) }
    }

    func normalizeURL(_ urlString: String) -> String {
        var raw = urlString.replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, let currentBase = URL(string: resolvedDomain) else { return urlString }
        if raw.hasPrefix("//") { raw = "\(currentBase.scheme ?? "https"):\(raw)" }

        if let url = URL(string: raw),
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            guard url.host?.lowercased() != currentBase.host?.lowercased() else {
                return url.absoluteString
            }
            var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            comps?.scheme = currentBase.scheme
            comps?.host = currentBase.host
            comps?.port = currentBase.port
            return comps?.url?.absoluteString ?? raw
        }

        guard let base = URL(string: resolvedDomain + "/") else { return raw }
        return URL(string: raw, relativeTo: base)?.absoluteURL.absoluteString ?? raw
    }
    
    private var webView: WKWebView!
    private struct HTMLRequest {
        let url: String
        let waitForIframe: Bool
        let isCancelled: () -> Bool
        let completion: (String) -> Void
    }

    private var htmlRequestQueue: [HTMLRequest] = []
    private var activeHTMLCompletion: ((String) -> Void)?
    private var activeHTMLCancellation: (() -> Bool)?
    private var isLoadingHTML = false
    private var currentLoadId: Int = 0
    private var lastCapturedVideoSrc = ""
    private var activeNavigation: WKNavigation?
    
    override init() {
        super.init()
        if UserDefaults.standard.string(forKey: "AVS_ResolvedDomain") == "https://animevietsub.pl" {
            UserDefaults.standard.set(Self.defaultDomain, forKey: "AVS_ResolvedDomain")
            DiskCache.shared.removeAll()
        }
        let setupWebView = {
            let config = WKWebViewConfiguration()
            let userController = WKUserContentController()
            
            // Script để hook XHR/Fetch, bắt link m3u8 khi player tải ẩn qua API và in ra DOM để checkDOM thấy được
            let jsHook = """
            (function() {
                // Regex dùng chung cho cả URL lẫn body text
                var M3U8_RE = /https?:\\/\\/[^\\s"'<>\\\\]+?\\.(m3u8|mp4)[^\\s"'<>\\\\]*/gi;
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
                    var lower = clean.toLowerCase();
                    if (lower.indexOf('.m3u8') === -1 && lower.indexOf('.mp4') === -1) return;
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

                    // Đã có URL media thật trong DOM → dừng (đã xong việc).
                    if (/[\"\\']https?:\\/\\/[^\"\\'\\s]+?\\.(m3u8|mp4)/i.test(topHTML)) return;

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
        if Thread.isMainThread {
            setupWebView()
        } else {
            DispatchQueue.main.async(execute: setupWebView)
        }
    }
    
    // Tải HTML thông qua WKWebView để tự động bypass Cloudflare/Bot-check
    func fetchHTML(url: String,
                   waitForIframe: Bool = false,
                   isCancelled: @escaping () -> Bool = { false },
                   completion: @escaping (String) -> Void) {
        let enqueue = {
            // Purge obsolete queued work even while another navigation is active.
            // This gives cancelled callers an immediate terminal callback instead
            // of making them wait for the shared WebView to become idle.
            let cancelledRequests = self.htmlRequestQueue.filter { $0.isCancelled() }
            self.htmlRequestQueue.removeAll { $0.isCancelled() }
            cancelledRequests.forEach { $0.completion("") }
            guard !isCancelled() else {
                completion("")
                return
            }

            let request = HTMLRequest(url: url,
                                      waitForIframe: waitForIframe,
                                      isCancelled: isCancelled,
                                      completion: completion)
            let path = URL(string: url)?.path.lowercased() ?? ""
            let isPlaybackRequest = waitForIframe
                || path.contains("xem-phim")
                || path.contains("-tap-")
                || path.contains("/tap-")
                || path.contains("/player/")
            if isPlaybackRequest {
                self.htmlRequestQueue.insert(request, at: 0)
            } else {
                self.htmlRequestQueue.append(request)
            }
            self.startNextHTMLRequestIfNeeded()
        }
        if Thread.isMainThread {
            enqueue()
        } else {
            DispatchQueue.main.async(execute: enqueue)
        }
    }

    /// WKWebView chỉ điều hướng được một trang tại một thời điểm. Xử lý tuần tự để
    /// refresh nền, tìm kiếm và mở phim không hủy callback của nhau.
    private func startNextHTMLRequestIfNeeded() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !isLoadingHTML else { return }

        // A player can enqueue another episode while an older one is waiting.
        // Complete cancelled entries immediately instead of loading pages whose
        // result can no longer be displayed.
        while let cancelledIndex = htmlRequestQueue.firstIndex(where: { $0.isCancelled() }) {
            let cancelled = htmlRequestQueue.remove(at: cancelledIndex)
            cancelled.completion("")
        }
        guard !htmlRequestQueue.isEmpty else { return }

        let request = htmlRequestQueue.removeFirst()
        isLoadingHTML = true
        activeHTMLCompletion = request.completion
        activeHTMLCancellation = request.isCancelled
        lastCapturedVideoSrc = ""
        currentLoadId += 1
        let loadId = currentLoadId

        guard let targetURL = URL(string: request.url),
              let scheme = targetURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            Logger.shared.log("[WebView] URL không hợp lệ: \(request.url)")
            finishHTMLRequest(loadId: loadId, html: "")
            return
        }

        // Phải add vào view hierarchy thì WKWebView mới chạy thực tế trên iOS.
        if webView.superview == nil,
           let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
           let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first {
            window.addSubview(webView)
        }

        var urlRequest = URLRequest(url: targetURL)
        urlRequest.setValue(resolvedDomain + "/", forHTTPHeaderField: "Referer")
        activeNavigation = webView.load(urlRequest)

        let path = targetURL.path.lowercased()
        let isWatchLike = request.waitForIframe
            || path.contains("xem-phim")
            || path.contains("-tap-")
            || path.contains("/tap-")
        let retries = request.waitForIframe ? 16 : (isWatchLike ? 10 : 6)
        checkDOM(webView: webView,
                 loadId: loadId,
                 retries: retries,
                 waitForIframe: request.waitForIframe)
    }

    private func finishHTMLRequest(loadId: Int, html: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard loadId == currentLoadId, isLoadingHTML else { return }
        let completion = activeHTMLCompletion
        activeHTMLCompletion = nil
        activeHTMLCancellation = nil
        activeNavigation = nil
        isLoadingHTML = false
        completion?(html)
        startNextHTMLRequestIfNeeded()
    }
    
    /// Lấy giá trị src của <video> hiện tại trong WKWebView. Dùng khi iframe player
    /// đã render và JWPlayer gắn data URL HLS lên <video> (không in ra outerHTML
    /// theo cách regex thông thường bắt được). Trả về chuỗi rỗng nếu không có.
    func fetchVideoSrc(completion: @escaping (String) -> Void) {
        let fetch = {
            if !self.lastCapturedVideoSrc.isEmpty {
                let captured = self.lastCapturedVideoSrc
                self.lastCapturedVideoSrc = ""
                completion(captured)
                return
            }
            let js = "(function(){var v=document.querySelector('video');return v?(v.src||v.getAttribute('src')||''):''})()"
            self.webView.evaluateJavaScript(js) { result, _ in
                completion((result as? String) ?? "")
            }
        }
        if Thread.isMainThread {
            fetch()
        } else {
            DispatchQueue.main.async(execute: fetch)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Logger.shared.log("[WebView] didFinish: \(webView.url?.absoluteString ?? "nil")")
        syncCookiesToURLSession()
    }

    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        handleNavigationFailure(navigation: navigation, error: error)
    }

    func webView(_ webView: WKWebView,
                 didFail navigation: WKNavigation!,
                 withError error: Error) {
        handleNavigationFailure(navigation: navigation, error: error)
    }

    private func handleNavigationFailure(navigation: WKNavigation?, error: Error) {
        guard navigation === activeNavigation else { return }
        let nsError = error as NSError
        guard nsError.code != NSURLErrorCancelled else { return }
        Logger.shared.log("[WebView] Điều hướng lỗi: \(nsError.localizedDescription) (\(nsError.code))")
        if isLoadingHTML { finishHTMLRequest(loadId: currentLoadId, html: "") }
    }

    private func syncCookiesToURLSession() {
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            for c in cookies {
                HTTPCookieStorage.shared.setCookie(c)
            }
        }
    }

    static func isUsableListingHTML(_ html: String, statusCode: Int) -> Bool {
        guard statusCode == 200 else { return false }
        let lower = html.lowercased()
        let isChallenge = lower.contains("cf-chl-")
            || lower.contains("just a moment")
            || lower.contains("checking your browser")
        let hasListingContent = lower.contains("/phim/")
            || lower.contains("tpost")
            || lower.contains("ml-item")
        return !isChallenge && hasListingContent
    }

    /// Fast path for list pages. Reuses WKWebView cookies but avoids the DOM polling
    /// cost when Cloudflare already trusts the current session. A challenge/403 is
    /// reported as nil so callers can transparently fall back to `fetchHTML`.
    private func fetchDirectListingHTML(url: URL, completion: @escaping (String?) -> Void) {
        let startedAt = Date()
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            let host = url.host?.lowercased() ?? ""
            let matchingCookies = cookies.filter { cookie in
                let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
                let hostMatches = host == domain || host.hasSuffix(".\(domain)")
                let pathMatches = url.path.isEmpty || url.path.hasPrefix(cookie.path)
                let securityMatches = !cookie.isSecure || url.scheme?.lowercased() == "https"
                return hostMatches && pathMatches && securityMatches
            }

            var request = URLRequest(url: url)
            request.timeoutInterval = 4
            request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
                             forHTTPHeaderField: "Accept")
            request.setValue("vi-VN,vi;q=0.9,en;q=0.7", forHTTPHeaderField: "Accept-Language")
            var origin = URLComponents()
            origin.scheme = url.scheme
            origin.host = url.host
            origin.port = url.port
            request.setValue((origin.url?.absoluteString ?? self.resolvedDomain) + "/",
                             forHTTPHeaderField: "Referer")
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1",
                             forHTTPHeaderField: "User-Agent")
            for (name, value) in HTTPCookie.requestHeaderFields(with: matchingCookies) {
                request.setValue(value, forHTTPHeaderField: name)
            }

            URLSession.shared.dataTask(with: request) { data, response, error in
                let html = data.flatMap { String(data: $0, encoding: .utf8) }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                let accepted = error == nil
                    && html.map { Self.isUsableListingHTML($0, statusCode: status) } == true
                let elapsed = Int(Date().timeIntervalSince(startedAt) * 1_000)
                Logger.shared.log("[DirectHTML] \(url.path.isEmpty ? "/" : url.path) HTTP \(status), accepted=\(accepted), \(elapsed)ms")
                DispatchQueue.main.async { completion(accepted ? html : nil) }
            }.resume()
        }
    }

    private func fetchListingHTML(url: String, completion: @escaping (String) -> Void) {
        let execute = { [weak self] in
            guard let self = self, let target = URL(string: url) else { completion(""); return }
            self.fetchDirectListingHTML(url: target) { [weak self] directHTML in
                guard let self = self else { completion(""); return }
                if let directHTML = directHTML {
                    completion(directHTML)
                } else {
                    self.fetchHTML(url: url, completion: completion)
                }
            }
        }
        if Thread.isMainThread {
            execute()
        } else {
            DispatchQueue.main.async(execute: execute)
        }
    }

    static func combineHomeMovies(home: [Movie], page1: [Movie], page2: [Movie]) -> [Movie] {
        var seen = Set<String>()
        return (home + page1 + page2).filter { seen.insert($0.link).inserted }
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
        guard let encoded = SearchUtilities.formComponent(from: trimmed) else {
            completion([])
            return
        }
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
    static func parseSuggestions(html: String) -> [Movie] {
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

            let poster = firstMatch(in: inner, pattern: "background-image:\\s*url\\(\\s*['\"]?([^'\"\\)]+)['\"]?\\s*\\)")
            let link = firstMatch(in: inner, pattern: "<a(?=[^>]*class\\s*=\\s*['\"][^'\"]*\\bthumb\\b)[^>]*href\\s*=\\s*['\"]([^'\"]+)['\"]")
                ?? firstMatch(in: inner, pattern: "<a(?=[^>]*class\\s*=\\s*['\"][^'\"]*\\bss-title\\b)[^>]*href\\s*=\\s*['\"]([^'\"]+)['\"]")
                ?? firstMatch(in: inner, pattern: "href\\s*=\\s*['\"]([^'\"]*?/phim/[^'\"]+)['\"]")
            let title = firstMatch(in: inner, pattern: "<a(?=[^>]*class\\s*=\\s*['\"][^'\"]*\\bss-title\\b)[^>]*>([\\s\\S]*?)</a>")
            let status = firstMatch(in: inner, pattern: "<p[^>]*>([\\s\\S]*?)</p>")

            guard let link = link, let title = title, !seen.contains(link) else { continue }
            seen.insert(link)
            result.append(Movie(
                title: HTMLUtilities.plainText(fromHTML: title),
                link: NetworkManager.shared.normalizeURL(link),
                thumbUrl: poster.map(absoluteAssetURL) ?? "",
                episodeStatus: HTMLUtilities.plainText(fromHTML: status ?? "")
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

    private static func absoluteAssetURL(_ raw: String) -> String {
        let decoded = raw.replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if decoded.hasPrefix("//") {
            let scheme = URL(string: NetworkManager.shared.resolvedDomain)?.scheme ?? "https"
            return "\(scheme):\(decoded)"
        }
        if let url = URL(string: decoded), url.scheme != nil { return url.absoluteString }
        guard let base = URL(string: NetworkManager.shared.resolvedDomain + "/") else { return decoded }
        return URL(string: decoded, relativeTo: base)?.absoluteURL.absoluteString ?? decoded
    }

    /// Returns true only when an episode link belongs to the movie currently
    /// being parsed. Comment sections often contain links to episodes from
    /// other titles; accepting every `/tap-*` anchor mixes those episodes into
    /// the current series.
    static func episodeLinkBelongsToMovie(_ episodeLink: String, movieURL: String) -> Bool {
        func meaningfulTokens(_ value: String) -> Set<String> {
            let path = URL(string: value)?.path.lowercased() ?? value.lowercased()
            let ignored: Set<String> = ["phim", "xem", "xem-phim", "tap", "episode", "ep", "anime"]
            return Set(path
                .split { !$0.isLetter && !$0.isNumber }
                .map(String.init)
                .filter { $0.count >= 3 && !ignored.contains($0) && $0.range(of: "^\\d+$", options: .regularExpression) == nil })
        }

        let movieTokens = meaningfulTokens(movieURL)
        let episodeTokens = meaningfulTokens(episodeLink)
        guard !movieTokens.isEmpty, !episodeTokens.isEmpty else { return true }
        return !movieTokens.isDisjoint(with: episodeTokens)
    }

    private static func isEpisodeTitle(_ title: String, link: String) -> Bool {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let episodeMarker = "(?i)(?:tập|tap|episode|ep)\\s*[-._:# ]*\\d+(?:[.,]\\d+)?"
        if normalized.range(of: episodeMarker, options: .regularExpression) != nil {
            return true
        }
        // Some templates render only "05" in the label. Allow that narrow
        // form only when the URL itself is an episode URL and the label is
        // short; arbitrary comment text containing a number stays rejected.
        let episodeLink = link.range(of: "(?i)(?:[-_/](?:tap|episode|ep)[-_\\d])", options: .regularExpression) != nil
        return episodeLink && normalized.range(of: "^\\d{1,4}$", options: .regularExpression) != nil
    }

    static func sortedEpisodes(_ episodes: [Episode]) -> [Episode] {
        func number(in episode: Episode) -> Double? {
            let source = episode.title + " " + episode.link
            let pattern = "(?i)(?:tập|tap|episode|ep)[\\s._/-]*(\\d+(?:[.,]\\d+)?)"
            guard let value = firstMatch(in: source, pattern: pattern)?.replacingOccurrences(of: ",", with: ".") else {
                return nil
            }
            return Double(value)
        }

        let numbered = episodes.enumerated().compactMap { index, episode -> (Int, Episode, Double)? in
            guard let value = number(in: episode) else { return nil }
            return (index, episode, value)
        }
        guard numbered.count >= 2, numbered.count * 5 >= episodes.count * 4 else { return episodes }
        // Repeated episode numbers usually mean the page contains multiple seasons
        // or parts. Sorting only by episode number would interleave those groups.
        guard Set(numbered.map { $0.2 }).count == numbered.count else { return episodes }
        let values = Dictionary(uniqueKeysWithValues: numbered.map { ($0.0, $0.2) })
        return episodes.enumerated().sorted { lhs, rhs in
            switch (values[lhs.offset], values[rhs.offset]) {
            case let (left?, right?):
                return left == right ? lhs.offset < rhs.offset : left < right
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return lhs.offset < rhs.offset
            }
        }.map(\.element)
    }

    func fetchGenres(completion: @escaping ([GenreOption]) -> Void) {
        if let cached: [GenreOption] = DiskCache.shared.get("genres", ttl: 86_400, as: [GenreOption].self),
           !cached.isEmpty {
            completion(cached)
            return
        }
        let requestedDomain = resolvedDomain
        fetchHTML(url: requestedDomain) { html in
            guard self.resolvedDomain == requestedDomain else {
                completion([])
                return
            }
            let genres = Self.parseGenres(from: html)
            if !genres.isEmpty { DiskCache.shared.set(genres, forKey: "genres") }
            completion(genres)
        }
    }

    static func parseGenres(from html: String) -> [GenreOption] {
        let pattern = "(?i)<a[^>]+href=[\"'][^\"']*/the-loai/([^/\"']+)/?[\"'][^>]*>([\\s\\S]*?)</a>"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        var seen = Set<String>()
        return regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap { match in
            guard let slugRange = Range(match.range(at: 1), in: html),
                  let nameRange = Range(match.range(at: 2), in: html) else { return nil }
            let slug = String(html[slugRange]).lowercased()
            let name = HTMLUtilities.plainText(fromHTML: String(html[nameRange]))
            guard !slug.isEmpty, !name.isEmpty, name.count <= 40, seen.insert(slug).inserted else { return nil }
            return GenreOption(name: name, slug: slug)
        }
    }
    
    private func checkDOM(webView: WKWebView, loadId: Int, retries: Int, waitForIframe: Bool) {
        // Nếu đã có request mới đè lên, hủy vòng lặp này
        guard loadId == self.currentLoadId, isLoadingHTML else { return }
        if activeHTMLCancellation?() == true {
            Logger.shared.log("[WebView] Hủy request HTML đã lỗi thời")
            webView.stopLoading()
            finishHTMLRequest(loadId: loadId, html: "")
            return
        }
        
        if retries <= 0 {
            // Hết retry. Lấy HTML hiện tại (không phải rỗng) + diagnostic để Extractor
            // có thể log snippet quanh các keyword, biết tại sao JWPlayer không khởi động.
            let captureJS = "(function(){var v=document.querySelector('video');return {html:document.documentElement.outerHTML,videoSrc:v?(v.src||v.getAttribute('src')||''):''};})()"
            webView.evaluateJavaScript(captureJS) { [weak self] pageResult, _ in
                let page = pageResult as? [String: Any]
                let html = (page?["html"] as? String) ?? ""
                guard let self = self else { return }
                guard loadId == self.currentLoadId, self.isLoadingHTML else { return }
                self.lastCapturedVideoSrc = (page?["videoSrc"] as? String) ?? ""
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
                    self.finishHTMLRequest(loadId: loadId, html: html)
                }
            }
            return
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard loadId == self.currentLoadId, self.isLoadingHTML else { return }
            
            let jsCheck = """
            (function() {
                if (\(waitForIframe ? "true" : "false")) {
                    var oh = document.documentElement.outerHTML;
                    // Stricter: phải có URL m3u8 thực sự trong dấu nháy hoặc dạng file:"..."
                    // chứ không chỉ là chuỗi con ".m3u8" (jwplayer init code có chữ này sẵn
                    // nên indexOf trả về true ngay lập tức trước khi luồng thực sự được fetch).
                    if (/[\"\\']https?:\\/\\/[^\"\\'\\s]+?\\.(m3u8|mp4)/i.test(oh)) return true;
                    if (/file\\s*:\\s*[\"\\']https?:\\/\\/[^\"\\'\\s]+?\\.(m3u8|mp4)/i.test(oh)) return true;
                    // <video src="..m3u8/mp4..."> hoặc data URL HLS đã inject vào video element
                    if (document.querySelector('video[src*=".m3u8"], source[src*=".m3u8"], video[src*=".mp4"], source[src*=".mp4"]')) return true;
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
                        || html.indexOf('.mp4') !== -1
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

                return isHome || isInfo || html.indexOf('.m3u8') !== -1 || html.indexOf('.mp4') !== -1;
            })();
            """
            
            webView.evaluateJavaScript(jsCheck) { [weak self] result, _ in
                let isReady = (result as? Bool) ?? false
                guard let self = self else { return }
                
                if isReady {
                    let captureJS = "(function(){var v=document.querySelector('video');return {html:document.documentElement.outerHTML,videoSrc:v?(v.src||v.getAttribute('src')||''):''};})()"
                    webView.evaluateJavaScript(captureJS) { pageResult, _ in
                        guard loadId == self.currentLoadId, self.isLoadingHTML else { return }
                        let page = pageResult as? [String: Any]
                        let html = (page?["html"] as? String) ?? ""
                        self.lastCapturedVideoSrc = (page?["videoSrc"] as? String) ?? ""
                        self.finishHTMLRequest(loadId: loadId, html: html)
                    }
                } else {
                    self.checkDOM(webView: webView, loadId: loadId, retries: retries - 1, waitForIframe: waitForIframe)
                }
            }
        }
    }
    
    func fetchHomeMovies(completion: @escaping ([Movie]) -> Void) {
        autoDetectDomain { [weak self] _ in
            guard let self = self else { completion([]); return }
            self.fetchHomeMoviesUsingCurrentDomain(completion: completion, allowDomainRecovery: true)
        }
    }

    private func fetchHomeMoviesUsingCurrentDomain(completion: @escaping ([Movie]) -> Void,
                                                   allowDomainRecovery: Bool) {
        var deliveredMovies: [Movie]?
        if let cached: (value: [Movie], age: TimeInterval) = DiskCache.shared.getWithAge("home", as: [Movie].self),
           !cached.value.isEmpty {
            if cached.age <= 1_800 {
                Logger.shared.log("[fetchHomeMovies] CACHE HIT (\(cached.value.count) phim, \(Int(cached.age))s)")
                completion(cached.value)
                return
            }
            if cached.age <= 7 * 86_400 {
                Logger.shared.log("[fetchHomeMovies] STALE CACHE (\(cached.value.count) phim, \(Int(cached.age))s) — hiển thị trong lúc refresh")
                deliveredMovies = cached.value
                completion(cached.value)
            } else {
                DiskCache.shared.remove("home")
            }
        }
        let requestedDomain = resolvedDomain
        fetchHomePlusLatest(domain: requestedDomain, onInitial: { movies in
            if deliveredMovies != movies {
                deliveredMovies = movies
                completion(movies)
            }
        }) { movies in
            if movies.isEmpty, allowDomainRecovery {
                Logger.shared.log("[Domain] Trang chủ rỗng, thử dò lại domain")
                self.autoDetectDomain(force: true) { [weak self] _ in
                    self?.fetchHomeMoviesUsingCurrentDomain(completion: completion,
                                                            allowDomainRecovery: false)
                }
                return
            }
            if !movies.isEmpty, self.resolvedDomain == requestedDomain {
                DiskCache.shared.set(movies, forKey: "home")
            }
            if !movies.isEmpty, deliveredMovies != movies {
                deliveredMovies = movies
                completion(movies)
            } else if deliveredMovies == nil {
                completion([])
            }
        }
    }

    func fetchMoviesPage(_ page: Int, completion: @escaping ([Movie]) -> Void) {
        fetchListingHTML(url: "\(resolvedDomain)/phim-moi/page/\(page)/") { html in
            self.parseMovies(html: html, completion: completion)
        }
    }

    private func fetchHomePlusLatest(domain: String,
                                     onInitial: @escaping ([Movie]) -> Void,
                                     completion: @escaping ([Movie]) -> Void) {
        let startedAt = Date()
        fetchListingHTML(url: domain) { [weak self] html in
            let genres = Self.parseGenres(from: html)
            if !genres.isEmpty, self?.resolvedDomain == domain {
                DiskCache.shared.set(genres, forKey: "genres")
            }
            self?.parseMovies(html: html) { movies in
                guard let self = self else { completion(movies); return }
                if !movies.isEmpty { onInitial(movies) }

                var pages: [Int: [Movie]] = [:]
                var remaining = 2
                func finish(page: Int, movies pageMovies: [Movie]) {
                    pages[page] = pageMovies
                    remaining -= 1
                    guard remaining == 0 else { return }

                    let combined = Self.combineHomeMovies(home: movies,
                                                          page1: pages[1] ?? [],
                                                          page2: pages[2] ?? [])
                    let elapsed = Int(Date().timeIntervalSince(startedAt) * 1_000)
                    Logger.shared.log("[Home] progressive home=\(movies.count), page1=\(pages[1]?.count ?? 0), page2=\(pages[2]?.count ?? 0) → \(combined.count) phim, \(elapsed)ms")
                    completion(combined)
                }

                for page in 1...2 {
                    self.fetchListingHTML(url: "\(domain)/phim-moi/page/\(page)/") { pageHTML in
                        self.parseMovies(html: pageHTML) { finish(page: page, movies: $0) }
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
            let trimmedTitle = HTMLUtilities.plainText(fromHTML: title)
            // Bỏ qua match rác (link điều hướng, anchor trống)
            if trimmedTitle.isEmpty || trimmedTitle.count > 200 || thumb.isEmpty { continue }
            seen.insert(link)
            result.append(Movie(
                title: trimmedTitle,
                link: normalizeURL(link),
                thumbUrl: Self.absoluteAssetURL(thumb),
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
                title: HTMLUtilities.plainText(fromHTML: title),
                link: normalizeURL(link),
                thumbUrl: Self.absoluteAssetURL(thumbUrl),
                episodeStatus: HTMLUtilities.plainText(fromHTML: eps)
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

    static func parseDetails(from html: String) -> MovieDetails {
        func rawMatch(_ pattern: String, group: Int = 1) -> String? {
            guard let regex = try? NSRegularExpression(pattern: pattern,
                                                       options: [.caseInsensitive, .dotMatchesLineSeparators]),
                  let result = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  result.numberOfRanges > group,
                  let range = Range(result.range(at: group), in: html) else { return nil }
            return String(html[range])
        }

        func match(_ pattern: String, group: Int = 1) -> String {
            rawMatch(pattern, group: group)
                .map { HTMLUtilities.plainText(fromHTML: $0) } ?? ""
        }

        func attribute(_ name: String, in tag: String) -> String? {
            let escapedName = NSRegularExpression.escapedPattern(for: name)
            let pattern = "(?i)\\b\(escapedName)\\s*=\\s*([\\\"'])(.*?)\\1"
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let result = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
                  let range = Range(result.range(at: 2), in: tag) else { return nil }
            return HTMLUtilities.decodeEntities(String(tag[range]))
        }

        func metaContent(attribute key: String, value: String) -> String? {
            guard let regex = try? NSRegularExpression(pattern: "(?i)<meta\\b[^>]*>") else { return nil }
            for result in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
                guard let range = Range(result.range, in: html) else { continue }
                let tag = String(html[range])
                if attribute(key, in: tag)?.caseInsensitiveCompare(value) == .orderedSame,
                   let content = attribute("content", in: tag), !content.isEmpty {
                    return content
                }
            }
            return nil
        }

        var description = match("class\\s*=\\s*[\"'][^\"']*\\bDescription\\b[^\"']*[\"'][^>]*>[\\s\\S]*?<p[^>]*>([\\s\\S]+?)</p>")
        if description.isEmpty {
            description = metaContent(attribute: "name", value: "description")
                .map(HTMLUtilities.plainText) ?? ""
        }
        var year = match("class\\s*=\\s*[\"'][^\"']*\\bDate\\b[^\"']*[\"'][^>]*>([^<]+)")
        if year.isEmpty {
            year = match("\"datePublished\"\\s*:\\s*\"?((?:19|20)\\d{2})")
        }
        if year.isEmpty {
            year = match("\\b(19|20)\\d{2}\\b", group: 0)
        }
        var rating = match("class\\s*=\\s*[\"'][^\"']*\\bpost-ratings?\\b[^\"']*[\"'][^>]*>([^<]+)")
        if rating.isEmpty {
            rating = match("\"ratingValue\"\\s*:\\s*\"?([0-9.]+)")
        }
        var banner = ""
        if let imageTag = rawMatch("class\\s*=\\s*[\"'][^\"']*\\bTPostBg\\b[^\"']*[\"'][^>]*>[\\s\\S]{0,4000}?(<img\\b[^>]*>)") {
            banner = attribute("data-src", in: imageTag)
                ?? attribute("src", in: imageTag)
                ?? ""
        }
        if banner.isEmpty {
            banner = metaContent(attribute: "property", value: "og:image") ?? ""
        }

        var genres: [String] = []
        if let r = try? NSRegularExpression(pattern: "<a[^>]+href\\s*=\\s*[\"'][^\"']*?/the-loai/[^\"']+[\"'][^>]*>([\\s\\S]*?)</a>", options: .caseInsensitive) {
            let ms = r.matches(in: html, range: NSRange(html.startIndex..., in: html))
            var seen = Set<String>()
            for m in ms {
                if let g = Range(m.range(at: 1), in: html) {
                    let name = HTMLUtilities.plainText(fromHTML: String(html[g]))
                    if !name.isEmpty && !seen.contains(name) && name.count < 30 {
                        seen.insert(name)
                        genres.append(name)
                    }
                }
            }
        }

        return MovieDetails(description: description,
                            year: year,
                            rating: rating,
                            bannerUrl: banner.isEmpty ? "" : absoluteAssetURL(banner),
                            genres: genres)
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
                    let title = HTMLUtilities.plainText(fromHTML: String(html[titleRange]))
                    
                    let lowerTitle = title.lowercased()
                    let lowerLink = link.lowercased()
                    if lowerTitle.contains("đăng nhập") || lowerTitle.contains("login") || lowerLink.contains("login") || lowerTitle.contains("đăng ký") {
                        continue
                    }
                    
                    let isEpisodeTitle = lowerTitle.contains("tập")
                        || lowerTitle.contains("episode")
                        || (title.rangeOfCharacter(from: .decimalDigits) != nil && title.count < 30)
                    guard isEpisodeTitle else { continue }
                    
                    guard Self.episodeLinkBelongsToMovie(link, movieURL: normalizedUrl),
                          Self.isEpisodeTitle(title, link: link) else { continue }

                    let fullLink = NetworkManager.shared.normalizeURL(link)
                    if !episodes.contains(where: { ContentIdentifier.make(from: $0.link) == ContentIdentifier.make(from: fullLink) }) {
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
            uniqueEps = Self.sortedEpisodes(uniqueEps)
            
            if uniqueEps.count <= 4 && !isRecursive && !uniqueEps.isEmpty {
                self.fetchEpisodes(movieUrl: uniqueEps[0].link, isRecursive: true) { innerEps in
                    var merged = uniqueEps
                    var seenInner = Set(merged.map { $0.link })
                    for ep in innerEps where seenInner.insert(ep.link).inserted {
                        merged.append(ep)
                    }
                    merged = Self.sortedEpisodes(merged)
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
