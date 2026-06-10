import UIKit
import AVKit

class PlayerController: UIViewController {
    var episodeUrl: String! // Truyền link tập phim từ UI vào đây
    var episodes: [Episode] = []        // Toàn bộ danh sách tập của phim hiện tại
    var currentIndex: Int = 0           // Vị trí tập đang phát trong `episodes`
    var movie: Movie?                   // Phim đang xem (để ghi lịch sử / favorite)

    private var periodicTimeToken: Any?
    private var resumeStatusObservation: NSKeyValueObservation?

    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let statusLabel = UILabel()
    private let logTextView = UITextView()
    private let copyButton = UIButton(type: .system)
    private let retryButton = UIButton(type: .system)

    // Overlay điều khiển
    private let skipBackwardButton = UIButton(type: .system)
    private let skipForwardButton = UIButton(type: .system)
    private let skipIntroButton = UIButton(type: .system)
    private let episodePickerButton = UIButton(type: .system)
    private let nextEpisodeButton = UIButton(type: .system)
    private let speedButton = UIButton(type: .system)
    private weak var currentPlayer: AVPlayer?
    private weak var currentPlayerVC: AVPlayerViewController?

    private var statusObservation: NSKeyValueObservation?
    private var errorObserver: NSObjectProtocol?
    private var stallObserver: NSObjectProtocol?
    private var accessLogObserver: NSObjectProtocol?
    private var errorLogObserver: NSObjectProtocol?
    private var endObserver: NSObjectProtocol?
    private var diagTimer: Timer?
    private var m3u8Loader: M3U8ResourceLoader?
    private weak var currentPlayerItem: AVPlayerItem?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        setupLoadingUI()
        setupOverlayControls()
        startResolve()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Lưu vị trí cuối cùng. KHÔNG pause vì PiP cần tiếp tục chạy.
        if let player = currentPlayer, !episodeUrl.isEmpty {
            let secs = CMTimeGetSeconds(player.currentTime())
            if secs.isFinite { PlaybackStore.shared.savePosition(secs, for: episodeUrl) }
        }
        if let token = periodicTimeToken {
            currentPlayer?.removeTimeObserver(token)
            periodicTimeToken = nil
        }
    }

    deinit {
        phaseTimer?.invalidate()
        diagTimer?.invalidate()
        statusObservation?.invalidate()
        if let o = errorObserver { NotificationCenter.default.removeObserver(o) }
        if let o = stallObserver { NotificationCenter.default.removeObserver(o) }
        if let o = accessLogObserver { NotificationCenter.default.removeObserver(o) }
        if let o = errorLogObserver { NotificationCenter.default.removeObserver(o) }
        if let o = endObserver { NotificationCenter.default.removeObserver(o) }
    }

    private var resolveStartTime: Date?
    private var phaseTimer: Timer?

    private func startResolve() {
        activityIndicator.startAnimating()
        statusLabel.text = "Đang tải trang xem phim..."
        statusLabel.isHidden = false
        logTextView.isHidden = true
        copyButton.isHidden = true
        retryButton.isHidden = true

        // Update text mỗi 4s để user biết app vẫn đang chạy.
        resolveStartTime = Date()
        phaseTimer?.invalidate()
        phaseTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            guard let self = self, let start = self.resolveStartTime else { return }
            let elapsed = Int(Date().timeIntervalSince(start))
            switch elapsed {
            case 0..<6: self.statusLabel.text = "Đang tải trang xem phim... (\(elapsed)s)"
            case 6..<14: self.statusLabel.text = "Đang vào iframe player... (\(elapsed)s)"
            case 14..<26: self.statusLabel.text = "Đang chờ player fetch luồng m3u8... (\(elapsed)s)"
            default: self.statusLabel.text = "Sắp hết giờ — sẽ hiển thị log nếu không bóc được (\(elapsed)s)"
            }
        }

        Extractor.resolveStream(episodeUrl: episodeUrl) { [weak self] stream in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.phaseTimer?.invalidate()
                self.phaseTimer = nil
                self.activityIndicator.stopAnimating()

                guard let stream = stream else {
                    self.showFailure()
                    Logger.shared.log("[PlayerController] resolveStream trả về nil cho \(self.episodeUrl ?? "")")
                    return
                }

                Logger.shared.log("[PlayerController] Tạo AVPlayer với m3u8=\(stream.url.absoluteString) referer=\(stream.referer)")
                self.statusLabel.text = "Đang khởi động player..."
                // KHÔNG preflight: server stream rate-limit theo URL (HTTP 429 nếu hit 2 lần
                // trong vài giây). JWPlayer trong iframe đã fetch lúc capture URL — preflight
                // HEAD sẽ là request thứ 2, đẩy AVPlayer xuống request thứ 3 → 429.
                self.attachPlayer(for: stream)
            }
        }
    }

    /// Giữ lại để debug khi cần: gửi HEAD thử URL với header để xem server trả status nào.
    /// Không gọi mặc định vì sẽ làm tăng rate-limit counter và khiến AVPlayer dính 429.
    private func preflightAndAttach(stream: Stream) {
        var req = URLRequest(url: stream.url)
        req.httpMethod = "HEAD"
        req.timeoutInterval = 5
        req.setValue(stream.referer, forHTTPHeaderField: "Referer")
        req.setValue(String(stream.referer.dropLast()), forHTTPHeaderField: "Origin")
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")

        // Session riêng để timeout chặt, không dùng URLSession.shared (60s default).
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 8
        let session = URLSession(configuration: config)

        session.dataTask(with: req) { _, resp, err in
            DispatchQueue.main.async {
                if let err = err {
                    Logger.shared.log("[Preflight] LỖI mạng: \(err.localizedDescription)")
                } else if let http = resp as? HTTPURLResponse {
                    Logger.shared.log("[Preflight] HTTP \(http.statusCode) cho \(stream.url.host ?? "?")")
                    if http.statusCode == 403 || http.statusCode == 401 {
                        Logger.shared.log("[Preflight] Server từ chối — Referer/cookie/expiry sai. Header gửi: Referer=\(stream.referer)")
                    } else if http.statusCode == 404 {
                        Logger.shared.log("[Preflight] 404 — link m3u8 đã hết hạn hoặc URL sai.")
                    }
                }
                self.activityIndicator.stopAnimating()
                self.attachPlayer(for: stream)
            }
        }.resume()
    }

    private func attachPlayer(for stream: Stream) {
        let asset: AVURLAsset
        if let playlistData = stream.inlinePlaylist {
            // Phục vụ m3u8 từ memory qua AVAssetResourceLoaderDelegate. AVPlayer
            // sẽ thấy custom scheme "avshls://" → gọi delegate, delegate trả nội dung
            // playlist với Content-Type "application/vnd.apple.mpegurl" rõ ràng nên
            // chắc chắn được parse như HLS. Segments trong playlist là HTTPS tuyệt đối
            // → AVPlayer fetch trực tiếp.
            asset = AVURLAsset(url: M3U8ResourceLoader.makePlaceholderURL(), options: nil)
            let loader = M3U8ResourceLoader(payload: playlistData)
            m3u8Loader = loader
            asset.resourceLoader.setDelegate(loader, queue: .main)
            Logger.shared.log("[PlayerController] Dùng ResourceLoader (\(playlistData.count) bytes m3u8 inline)")
        } else if stream.url.isFileURL {
            asset = AVURLAsset(url: stream.url, options: nil)
            Logger.shared.log("[PlayerController] Local file URL — không gắn HTTP headers")
        } else {
            let headers: [String: String] = [
                "Referer": stream.referer,
                "Origin": String(stream.referer.dropLast()),
                "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
            ]
            asset = AVURLAsset(url: stream.url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        }
        let item = AVPlayerItem(asset: asset)
        currentPlayerItem = item

        // Quan sát status để log lỗi cụ thể khi AVPlayer từ chối stream.
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                switch item.status {
                case .readyToPlay:
                    Logger.shared.log("[PlayerController] AVPlayerItem readyToPlay")
                case .failed:
                    let err = item.error as NSError?
                    Logger.shared.log("[PlayerController] AVPlayerItem failed: code=\(err?.code ?? -1) domain=\(err?.domain ?? "?") msg=\(err?.localizedDescription ?? "?")")
                    if let underlying = err?.userInfo[NSUnderlyingErrorKey] as? NSError {
                        Logger.shared.log("[PlayerController]   underlying: code=\(underlying.code) domain=\(underlying.domain) msg=\(underlying.localizedDescription)")
                    }
                    self?.showFailure()
                case .unknown:
                    Logger.shared.log("[PlayerController] AVPlayerItem status=unknown")
                @unknown default:
                    break
                }
            }
        }

        errorObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { note in
            let err = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? NSError
            Logger.shared.log("[PlayerController] FailedToPlayToEndTime: \(err?.localizedDescription ?? "?")")
        }

        stallObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: item,
            queue: .main
        ) { _ in
            Logger.shared.log("[PlayerController] Playback stalled")
        }

        // Access log: mỗi segment HTTP fetch sẽ thêm 1 entry. Đếm để biết AVPlayer
        // có thực sự pull video data hay chỉ ngồi yên.
        accessLogObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.newAccessLogEntryNotification,
            object: item,
            queue: .main
        ) { _ in
            guard let log = item.accessLog(), let last = log.events.last else { return }
            Logger.shared.log("[AccessLog] URI=\(last.uri ?? "?") served=\(last.numberOfBytesTransferred) bytes mediaRequests=\(last.numberOfMediaRequests) avgBitrate=\(Int(last.indicatedBitrate))")
        }

        // Error log: mỗi segment thất bại sẽ có 1 entry với mã lỗi cụ thể (HTTP code,
        // network error). Đây là chìa khoá biết Google Photos có chặn / segment có
        // phải định dạng lạ không.
        errorLogObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.newErrorLogEntryNotification,
            object: item,
            queue: .main
        ) { _ in
            guard let log = item.errorLog(), let last = log.events.last else { return }
            Logger.shared.log("[ErrorLog] URI=\(last.uri ?? "?") status=\(last.errorStatusCode) domain=\(last.errorDomain) comment=\(last.errorComment ?? "?")")
        }

        // Auto-next: khi item phát hết, nhảy sang tập tiếp theo (nếu còn).
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.playNextEpisodeIfAvailable()
        }

        // Dump state mỗi 2s trong 12s đầu — không cần KVO trên mỗi property riêng.
        let startedAt = Date()
        diagTimer?.invalidate()
        diagTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self, weak item] timer in
            guard let item = item else { timer.invalidate(); return }
            let elapsed = Date().timeIntervalSince(startedAt)
            if elapsed > 12 { timer.invalidate(); self?.diagTimer = nil; return }
            let size = item.presentationSize
            let dur = CMTimeGetSeconds(item.duration)
            let loaded = item.loadedTimeRanges.first.map { CMTimeRangeGetEnd($0.timeRangeValue) }
            let loadedSec = loaded.map { CMTimeGetSeconds($0) } ?? 0
            Logger.shared.log("[Diag \(Int(elapsed))s] size=\(Int(size.width))x\(Int(size.height)) duration=\(dur.isFinite ? String(format: "%.1f", dur) : "n/a") buffered=\(String(format: "%.1f", loadedSec))s bufferEmpty=\(item.isPlaybackBufferEmpty) likelyKeepUp=\(item.isPlaybackLikelyToKeepUp)")
        }

        let player = AVPlayer(playerItem: item)
        let playerVC = AVPlayerViewController()
        playerVC.player = player
        playerVC.allowsPictureInPicturePlayback = true
        if #available(iOS 14.2, *) {
            playerVC.canStartPictureInPictureAutomaticallyFromInline = true
        }
        currentPlayer = player
        currentPlayerVC = playerVC

        addChild(playerVC)
        playerVC.view.frame = view.bounds
        playerVC.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(playerVC.view)
        playerVC.didMove(toParent: self)

        statusLabel.isHidden = true
        logTextView.isHidden = true
        copyButton.isHidden = true
        retryButton.isHidden = true

        // Đem overlay buttons lên trên player view và bật hiển thị.
        showOverlayControls(true)

        // Seek-to-resume khi user quay lại tập đang xem dở.
        // Quan sát readyToPlay rồi seek (không seek trước khi item ready).
        let savedPosition = PlaybackStore.shared.position(for: episodeUrl)
        if let pos = savedPosition, pos > 30 {
            let token = item.observe(\.status, options: [.new]) { [weak item, weak self] obs, _ in
                guard obs.status == .readyToPlay, let item = item else { return }
                let duration = CMTimeGetSeconds(item.duration)
                // Đừng seek nếu gần cuối (< 30s) — coi như đã xem xong
                guard duration.isFinite && duration > 0 && pos < duration - 30 else { return }
                item.seek(to: CMTime(seconds: pos, preferredTimescale: 600)) { _ in
                    Logger.shared.log("[Resume] Tua tới \(Int(pos))s (đã lưu trước đó)")
                }
                self?.resumeStatusObservation = nil
            }
            resumeStatusObservation = token
        }

        // Lưu vị trí mỗi 5s.
        let interval = CMTime(seconds: 5, preferredTimescale: 600)
        periodicTimeToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            let secs = CMTimeGetSeconds(time)
            if secs.isFinite {
                PlaybackStore.shared.savePosition(secs, for: self.episodeUrl)
            }
        }

        // Ghi lịch sử (movie + episode index + title)
        if let movie = movie, currentIndex < episodes.count {
            PlaybackStore.shared.recordWatch(movie: movie,
                                             episodeIndex: currentIndex,
                                             episodeTitle: episodes[currentIndex].title)
        }

        player.play()
    }

    private func showFailure() {
        // Gỡ AVPlayerViewController nếu đang attach — nếu không, view nó sẽ che hết
        // logs và user chỉ nhìn thấy logo gạch chéo.
        for child in children {
            child.willMove(toParent: nil)
            child.view.removeFromSuperview()
            child.removeFromParent()
        }

        statusLabel.text = "Không phát được phim.\nLog gần nhất ở dưới — bấm Copy để gửi dev."
        statusLabel.isHidden = false
        logTextView.text = Logger.shared.snapshot()
        logTextView.isHidden = false
        copyButton.isHidden = false
        retryButton.isHidden = false
        view.bringSubviewToFront(statusLabel)
        view.bringSubviewToFront(logTextView)
        view.bringSubviewToFront(copyButton)
        view.bringSubviewToFront(retryButton)
        DispatchQueue.main.async {
            let bottom = NSRange(location: max(0, self.logTextView.text.utf16.count - 1), length: 1)
            self.logTextView.scrollRangeToVisible(bottom)
        }
    }

    private func setupLoadingUI() {
        activityIndicator.color = .white
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(activityIndicator)

        statusLabel.text = "Đang tải luồng phim..."
        statusLabel.textColor = .white
        statusLabel.font = .systemFont(ofSize: 15)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        logTextView.backgroundColor = UIColor(white: 0.1, alpha: 1.0)
        logTextView.textColor = .white
        logTextView.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        logTextView.isEditable = false
        logTextView.isHidden = true
        logTextView.translatesAutoresizingMaskIntoConstraints = false
        logTextView.layer.cornerRadius = 6
        view.addSubview(logTextView)

        copyButton.setTitle("Copy log", for: .normal)
        copyButton.setTitleColor(.white, for: .normal)
        copyButton.backgroundColor = .systemBlue
        copyButton.layer.cornerRadius = 6
        copyButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        copyButton.isHidden = true
        copyButton.addTarget(self, action: #selector(copyLogs), for: .touchUpInside)
        view.addSubview(copyButton)

        retryButton.setTitle("Thử lại", for: .normal)
        retryButton.setTitleColor(.white, for: .normal)
        retryButton.backgroundColor = .systemGray
        retryButton.layer.cornerRadius = 6
        retryButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        retryButton.translatesAutoresizingMaskIntoConstraints = false
        retryButton.isHidden = true
        retryButton.addTarget(self, action: #selector(retry), for: .touchUpInside)
        view.addSubview(retryButton)

        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 40),

            statusLabel.topAnchor.constraint(equalTo: activityIndicator.bottomAnchor, constant: 16),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            logTextView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 12),
            logTextView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            logTextView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            logTextView.bottomAnchor.constraint(equalTo: copyButton.topAnchor, constant: -12),

            copyButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            copyButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),

            retryButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            retryButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12)
        ])

        activityIndicator.startAnimating()
    }

    @objc private func copyLogs() {
        UIPasteboard.general.string = logTextView.text
        let original = copyButton.title(for: .normal)
        copyButton.setTitle("Đã copy", for: .normal)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.copyButton.setTitle(original, for: .normal)
        }
    }

    @objc private func retry() {
        // Gỡ player cũ + observer
        diagTimer?.invalidate(); diagTimer = nil
        m3u8Loader = nil
        statusObservation?.invalidate()
        statusObservation = nil
        if let o = errorObserver { NotificationCenter.default.removeObserver(o); errorObserver = nil }
        if let o = stallObserver { NotificationCenter.default.removeObserver(o); stallObserver = nil }
        if let o = accessLogObserver { NotificationCenter.default.removeObserver(o); accessLogObserver = nil }
        if let o = errorLogObserver { NotificationCenter.default.removeObserver(o); errorLogObserver = nil }
        if let o = endObserver { NotificationCenter.default.removeObserver(o); endObserver = nil }
        for child in children {
            child.willMove(toParent: nil)
            child.view.removeFromSuperview()
            child.removeFromParent()
        }
        Logger.shared.clear()
        startResolve()
    }

    // MARK: - Overlay controls (skip / next / episode picker)

    private func setupOverlayControls() {
        // Cụm nút giữa: -10s, +10s, +90s (skip intro).
        let buttons: [(UIButton, String, Selector)] = [
            (skipBackwardButton, "⟲ 10", #selector(skipBackward)),
            (skipForwardButton, "10 ⟳", #selector(skipForward)),
            (skipIntroButton, "+1:30", #selector(skipIntro))
        ]
        for (btn, title, sel) in buttons {
            configureOverlayButton(btn, title: title, action: sel)
        }
        configureOverlayButton(episodePickerButton, title: "📺", action: #selector(showEpisodePicker))
        configureOverlayButton(nextEpisodeButton, title: "Tập sau ▶", action: #selector(skipToNextEpisode))
        configureOverlayButton(speedButton, title: "1x", action: #selector(showSpeedPicker))

        let centerStack = UIStackView(arrangedSubviews: [skipBackwardButton, skipIntroButton, skipForwardButton])
        centerStack.axis = .horizontal
        centerStack.spacing = 12
        centerStack.distribution = .fillEqually
        centerStack.translatesAutoresizingMaskIntoConstraints = false
        centerStack.isHidden = true
        view.addSubview(centerStack)

        let topStack = UIStackView(arrangedSubviews: [speedButton, episodePickerButton, nextEpisodeButton])
        topStack.axis = .horizontal
        topStack.spacing = 8
        topStack.translatesAutoresizingMaskIntoConstraints = false
        topStack.isHidden = true
        view.addSubview(topStack)

        NSLayoutConstraint.activate([
            centerStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            centerStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -80),
            topStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            topStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12)
        ])

        overlayStacks = [centerStack, topStack]
    }

    private var overlayStacks: [UIStackView] = []

    private func configureOverlayButton(_ btn: UIButton, title: String, action: Selector) {
        btn.setTitle(title, for: .normal)
        btn.setTitleColor(.white, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        btn.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        btn.layer.cornerRadius = 8
        btn.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        btn.addTarget(self, action: action, for: .touchUpInside)
    }

    private func showOverlayControls(_ show: Bool) {
        overlayStacks.forEach { $0.isHidden = !show }
        overlayStacks.forEach { view.bringSubviewToFront($0) }
        // Ẩn nút "Tập sau" nếu đã ở tập cuối.
        nextEpisodeButton.isHidden = !(show && currentIndex + 1 < episodes.count)
        episodePickerButton.isHidden = !(show && episodes.count > 1)
    }

    @objc private func skipBackward() { seek(by: -10) }
    @objc private func skipForward()  { seek(by:  10) }
    @objc private func skipIntro()    { seek(by:  90) }

    private func seek(by seconds: Double) {
        guard let player = currentPlayer else { return }
        let current = CMTimeGetSeconds(player.currentTime())
        guard current.isFinite else { return }
        let target = max(0, current + seconds)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
    }

    @objc private func skipToNextEpisode() {
        playNextEpisodeIfAvailable()
    }

    @objc private func showSpeedPicker() {
        let speeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
        let sheet = UIAlertController(title: "Tốc độ phát", message: nil, preferredStyle: .actionSheet)
        for s in speeds {
            let label = s == 1.0 ? "1x (thường)" : "\(s)x"
            sheet.addAction(UIAlertAction(title: label, style: .default) { [weak self] _ in
                self?.currentPlayer?.rate = s
                self?.speedButton.setTitle("\(s)x", for: .normal)
            })
        }
        sheet.addAction(UIAlertAction(title: "Đóng", style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = speedButton
            pop.sourceRect = speedButton.bounds
        }
        present(sheet, animated: true)
    }

    private func playNextEpisodeIfAvailable() {
        let next = currentIndex + 1
        guard next < episodes.count else {
            Logger.shared.log("[PlayerController] Đã hết phim — không còn tập tiếp theo.")
            return
        }
        Logger.shared.log("[PlayerController] Auto-next → tập \(next + 1)/\(episodes.count)")
        currentIndex = next
        episodeUrl = episodes[next].link
        retry()
    }

    @objc private func showEpisodePicker() {
        guard !episodes.isEmpty else { return }
        let alert = UIAlertController(title: "Chọn tập", message: nil, preferredStyle: .actionSheet)
        for (idx, ep) in episodes.enumerated() {
            let title = idx == currentIndex ? "▶ \(ep.title)" : ep.title
            alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                guard let self = self, idx != self.currentIndex else { return }
                self.currentIndex = idx
                self.episodeUrl = ep.link
                self.retry()
            })
        }
        alert.addAction(UIAlertAction(title: "Đóng", style: .cancel))
        if let pop = alert.popoverPresentationController {
            pop.sourceView = episodePickerButton
            pop.sourceRect = episodePickerButton.bounds
        }
        present(alert, animated: true)
    }
}
