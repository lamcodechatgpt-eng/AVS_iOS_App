import UIKit
import AVKit

class PlayerController: UIViewController {
    var episodeUrl: String?
    var episodes: [Episode] = []
    var currentIndex: Int = 0
    var movie: Movie?

    private var periodicTimeToken: Any?
    private var resumeStatusObservation: NSKeyValueObservation?

    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let episodeNumberLabel = UILabel()
    private let episodeTitleLabel = UILabel()
    private let statusLabel = UILabel()
    private let logTextView = UITextView()
    private let copyButton = UIButton(type: .system)
    private let retryButton = UIButton(type: .system)

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
        setupNavBarItems()
        updateEpisodeInfo()
        startResolve()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        gradientLayer?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        guard let player = currentPlayer, let url = episodeUrl, !url.isEmpty else { return }
        let secs = CMTimeGetSeconds(player.currentTime())
        if secs.isFinite { PlaybackStore.shared.savePosition(secs, for: url) }
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

    private var gradientLayer: CAGradientLayer?
    private var resolveStartTime: Date?
    private var phaseTimer: Timer?

    private func updateEpisodeInfo() {
        guard currentIndex < episodes.count else { return }
        episodeNumberLabel.text = "Tập \(currentIndex + 1)"
        episodeTitleLabel.text = episodes[currentIndex].title
        navigationItem.title = episodes[currentIndex].title
    }

    private func startResolve() {
        updateEpisodeInfo()
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

        guard let episodeUrl = episodeUrl else {
            self.showFailure()
            Logger.shared.log("[PlayerController] episodeUrl = nil")
            return
        }
        Extractor.resolveStream(episodeUrl: episodeUrl) { [weak self] stream in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.phaseTimer?.invalidate()
                self.phaseTimer = nil
                self.activityIndicator.stopAnimating()

                guard let stream = stream else {
                    self.showFailure()
                    Logger.shared.log("[PlayerController] resolveStream trả về nil cho \(episodeUrl)")
                    return
                }

                Logger.shared.log("[PlayerController] Tạo AVPlayer với m3u8=\(stream.url.absoluteString) referer=\(stream.referer)")
                self.statusLabel.text = "Đang khởi động player..."
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

        updateNavBarItems()

        // Seek-to-resume khi user quay lại tập đang xem dở.
        // Quan sát readyToPlay rồi seek (không seek trước khi item ready).
        let savedPosition = PlaybackStore.shared.position(for: episodeUrl ?? "")
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
            guard let self = self, let url = self.episodeUrl else { return }
            let secs = CMTimeGetSeconds(time)
            if secs.isFinite {
                PlaybackStore.shared.savePosition(secs, for: url)
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
        let gLayer = CAGradientLayer()
        gLayer.colors = [
            UIColor(red: 0.08, green: 0.04, blue: 0.12, alpha: 1).cgColor,
            UIColor(red: 0.15, green: 0.08, blue: 0.2, alpha: 1).cgColor,
            UIColor.black.cgColor
        ]
        gLayer.locations = [0.0, 0.5, 1.0]
        gLayer.frame = view.bounds
        view.layer.insertSublayer(gLayer, at: 0)
        gradientLayer = gLayer

        episodeNumberLabel.textColor = .white
        episodeNumberLabel.font = .systemFont(ofSize: 28, weight: .bold)
        episodeNumberLabel.textAlignment = .center
        episodeNumberLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(episodeNumberLabel)

        episodeTitleLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        episodeTitleLabel.font = .systemFont(ofSize: 17, weight: .regular)
        episodeTitleLabel.textAlignment = .center
        episodeTitleLabel.numberOfLines = 2
        episodeTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(episodeTitleLabel)

        activityIndicator.color = .white
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(activityIndicator)

        statusLabel.text = "Đang tải..."
        statusLabel.textColor = UIColor.white.withAlphaComponent(0.5)
        statusLabel.font = .systemFont(ofSize: 13, weight: .regular)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        logTextView.backgroundColor = UIColor(white: 0.1, alpha: 0.95)
        logTextView.textColor = .white
        logTextView.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        logTextView.isEditable = false
        logTextView.isHidden = true
        logTextView.translatesAutoresizingMaskIntoConstraints = false
        logTextView.layer.cornerRadius = 8
        view.addSubview(logTextView)

        copyButton.setTitle("Copy log", for: .normal)
        copyButton.setTitleColor(.white, for: .normal)
        copyButton.backgroundColor = .systemBlue
        copyButton.layer.cornerRadius = 8
        copyButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 20, bottom: 10, right: 20)
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        copyButton.isHidden = true
        copyButton.addTarget(self, action: #selector(copyLogs), for: .touchUpInside)
        view.addSubview(copyButton)

        retryButton.setTitle("Thử lại", for: .normal)
        retryButton.setTitleColor(.white, for: .normal)
        retryButton.backgroundColor = UIColor.white.withAlphaComponent(0.2)
        retryButton.layer.cornerRadius = 8
        retryButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 20, bottom: 10, right: 20)
        retryButton.translatesAutoresizingMaskIntoConstraints = false
        retryButton.isHidden = true
        retryButton.addTarget(self, action: #selector(retry), for: .touchUpInside)
        view.addSubview(retryButton)

        NSLayoutConstraint.activate([
            episodeNumberLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            episodeNumberLabel.bottomAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),

            episodeTitleLabel.topAnchor.constraint(equalTo: episodeNumberLabel.bottomAnchor, constant: 6),
            episodeTitleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            episodeTitleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            episodeTitleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            activityIndicator.topAnchor.constraint(equalTo: episodeTitleLabel.bottomAnchor, constant: 28),
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            statusLabel.topAnchor.constraint(equalTo: activityIndicator.bottomAnchor, constant: 14),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            logTextView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 16),
            logTextView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            logTextView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            logTextView.bottomAnchor.constraint(equalTo: copyButton.topAnchor, constant: -16),

            copyButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            copyButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),

            retryButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            retryButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
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
        if let url = episodeUrl, let player = currentPlayer {
            let secs = CMTimeGetSeconds(player.currentTime())
            if secs.isFinite { PlaybackStore.shared.savePosition(secs, for: url) }
        }
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
        startResolve()
    }

    // MARK: - Nav bar items (không overlay, không che video)

    private func setupNavBarItems() {
        updateNavBarItems()
    }

    private func updateNavBarItems() {
        var items: [UIBarButtonItem] = []

        if episodes.count > 1 {
            let epItem = UIBarButtonItem(image: UIImage(systemName: "list.bullet.rectangle"), style: .plain, target: self, action: #selector(showEpisodePicker))
            epItem.tintColor = .white
            items.append(epItem)
        }

        let speedItem = UIBarButtonItem(image: UIImage(systemName: "speedometer"), style: .plain, target: self, action: #selector(showSpeedPicker))
        speedItem.tintColor = .white
        items.append(speedItem)

        if currentIndex + 1 < episodes.count {
            let nextItem = UIBarButtonItem(image: UIImage(systemName: "forward.fill"), style: .plain, target: self, action: #selector(skipToNextEpisode))
            nextItem.tintColor = .white
            items.append(nextItem)
        }

        navigationItem.rightBarButtonItems = items
    }

    @objc private func skipToNextEpisode() {
        playNextEpisodeIfAvailable()
    }

    @objc private func showSpeedPicker() {
        let speeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
        let picker = SpeedPickerViewController()
        picker.speeds = speeds
        picker.currentSpeed = currentPlayer?.rate ?? 1.0
        picker.onSelect = { [weak self] speed in
            self?.currentPlayer?.rate = speed
        }
        if let sheet = picker.sheetPresentationController {
            sheet.detents = [.medium()]
            sheet.prefersGrabberVisible = true
        }
        present(picker, animated: true)
    }

    private func playNextEpisodeIfAvailable() {
        let next = currentIndex + 1
        guard next < episodes.count else {
            Logger.shared.log("[PlayerController] Đã hết phim — không còn tập tiếp theo.")
            showEndOfSeriesAlert()
            return
        }
        Logger.shared.log("[PlayerController] Auto-next → tập \(next + 1)/\(episodes.count)")

        if let url = episodeUrl { PlaybackStore.shared.clearPosition(for: url) }
        if let movie = movie {
            PlaybackStore.shared.recordWatch(movie: movie, episodeIndex: next, episodeTitle: episodes[next].title)
        }

        currentIndex = next
        episodeUrl = episodes[next].link
        updateEpisodeInfo()
        updateNavBarItems()
        retry()
    }

    private func showEndOfSeriesAlert() {
        if let url = episodeUrl { PlaybackStore.shared.clearPosition(for: url) }
        let alert = UIAlertController(title: "Đã hết phim", message: "Bạn đã xem hết tất cả các tập hiện có.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    @objc private func showEpisodePicker() {
        guard !episodes.isEmpty else { return }
        let pickerVC = EpisodePickerViewController()
        pickerVC.episodes = episodes
        pickerVC.currentIndex = currentIndex
        pickerVC.onSelect = { [weak self] idx in
            guard let self = self, idx != self.currentIndex else { return }
            self.currentIndex = idx
            self.episodeUrl = self.episodes[idx].link
            self.dismiss(animated: true)
            self.updateEpisodeInfo()
            self.updateNavBarItems()
            self.retry()
        }
        if let sheet = pickerVC.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            sheet.prefersEdgeAttachedInCompactHeight = true
        }
        present(pickerVC, animated: true)
    }
}

// MARK: - Episode Picker

final class EpisodePickerViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    var episodes: [Episode] = []
    var currentIndex: Int = 0
    var onSelect: ((Int) -> Void)?

    private let titleLabel = UILabel()
    private var collectionView: UICollectionView!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        titleLabel.text = "Chọn tập"
        titleLabel.font = .systemFont(ofSize: 17, weight: .bold)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        let layout = UICollectionViewFlowLayout()
        let columns: CGFloat = 5
        let spacing: CGFloat = 8
        let insets: CGFloat = 16
        let totalSpacing = insets * 2 + spacing * (columns - 1)
        let cellWidth = (view.bounds.width - totalSpacing) / columns
        layout.itemSize = CGSize(width: cellWidth, height: 44)
        layout.minimumLineSpacing = spacing
        layout.minimumInteritemSpacing = spacing
        layout.sectionInset = UIEdgeInsets(top: 8, left: insets, bottom: 16, right: insets)

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(EpisodePickerCell.self, forCellWithReuseIdentifier: "Cell")
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            collectionView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    func collectionView(_ cv: UICollectionView, numberOfItemsInSection s: Int) -> Int { episodes.count }

    func collectionView(_ cv: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = cv.dequeueReusableCell(withReuseIdentifier: "Cell", for: indexPath) as! EpisodePickerCell
        let isCurrent = indexPath.row == currentIndex
        let ep = episodes[indexPath.row]
        cell.configure(number: indexPath.row + 1, isCurrent: isCurrent, title: ep.title)
        return cell
    }

    func collectionView(_ cv: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        onSelect?(indexPath.row)
    }
}

final class EpisodePickerCell: UICollectionViewCell {
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = 10
        contentView.clipsToBounds = true
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.7
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(number: Int, isCurrent: Bool, title: String) {
        if isCurrent {
            contentView.backgroundColor = UIColor.systemRed
            label.textColor = .white
            label.font = .systemFont(ofSize: 13, weight: .bold)
            label.text = "▶ \(number)"
        } else {
            contentView.backgroundColor = .secondarySystemBackground
            label.textColor = .label
            label.font = .systemFont(ofSize: 13, weight: .semibold)
            label.text = "\(number)"
        }
    }
}

// MARK: - Speed Picker

final class SpeedPickerViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    var speeds: [Float] = []
    var currentSpeed: Float = 1.0
    var onSelect: ((Float) -> Void)?

    private let titleLabel = UILabel()
    private let tableView = UITableView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        titleLabel.text = "Tốc độ phát"
        titleLabel.font = .systemFont(ofSize: 17, weight: .bold)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.isScrollEnabled = false
        tableView.separatorStyle = .singleLine
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            tableView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { speeds.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        let speed = speeds[indexPath.row]
        let isCurrent = abs(speed - currentSpeed) < 0.01
        cell.textLabel?.text = speed == 1.0 ? "1x (thường)" : "\(speed)x"
        cell.textLabel?.font = .systemFont(ofSize: 16, weight: isCurrent ? .bold : .regular)
        cell.textLabel?.textColor = isCurrent ? .systemRed : .label
        cell.accessoryType = isCurrent ? .checkmark : .none
        cell.tintColor = .systemRed
        cell.backgroundColor = .clear
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        onSelect?(speeds[indexPath.row])
        dismiss(animated: true)
    }
}
