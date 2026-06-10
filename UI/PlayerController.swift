import UIKit
import AVKit

class PlayerController: UIViewController {
    var episodeUrl: String! // Truyền link tập phim từ UI vào đây

    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let statusLabel = UILabel()
    private let logTextView = UITextView()
    private let copyButton = UIButton(type: .system)
    private let retryButton = UIButton(type: .system)

    private var statusObservation: NSKeyValueObservation?
    private var errorObserver: NSObjectProtocol?
    private var stallObserver: NSObjectProtocol?
    private var accessLogObserver: NSObjectProtocol?
    private var errorLogObserver: NSObjectProtocol?
    private var diagTimer: Timer?
    private weak var currentPlayerItem: AVPlayerItem?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        setupLoadingUI()
        startResolve()
    }

    deinit {
        phaseTimer?.invalidate()
        diagTimer?.invalidate()
        statusObservation?.invalidate()
        if let o = errorObserver { NotificationCenter.default.removeObserver(o) }
        if let o = stallObserver { NotificationCenter.default.removeObserver(o) }
        if let o = accessLogObserver { NotificationCenter.default.removeObserver(o) }
        if let o = errorLogObserver { NotificationCenter.default.removeObserver(o) }
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
        // Khi luồng đến từ file:// (đã decode data URL), KHÔNG set Referer/UA —
        // những header này áp xuống tất cả segment requests và Google Photos đôi khi
        // trả khác nhau tuỳ Referer. Để rỗng cho an toàn.
        let isLocalFile = stream.url.isFileURL
        let assetOptions: [String: Any]
        if isLocalFile {
            assetOptions = [:]
            Logger.shared.log("[PlayerController] Local file URL — không gắn HTTP headers")
        } else {
            let headers: [String: String] = [
                "Referer": stream.referer,
                "Origin": String(stream.referer.dropLast()),
                "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
            ]
            assetOptions = ["AVURLAssetHTTPHeaderFieldsKey": headers]
        }
        let asset = AVURLAsset(url: stream.url, options: assetOptions)
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

        addChild(playerVC)
        playerVC.view.frame = view.bounds
        playerVC.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(playerVC.view)
        playerVC.didMove(toParent: self)

        statusLabel.isHidden = true
        logTextView.isHidden = true
        copyButton.isHidden = true
        retryButton.isHidden = true

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
        statusObservation?.invalidate()
        statusObservation = nil
        if let o = errorObserver { NotificationCenter.default.removeObserver(o); errorObserver = nil }
        if let o = stallObserver { NotificationCenter.default.removeObserver(o); stallObserver = nil }
        if let o = accessLogObserver { NotificationCenter.default.removeObserver(o); accessLogObserver = nil }
        if let o = errorLogObserver { NotificationCenter.default.removeObserver(o); errorLogObserver = nil }
        for child in children {
            child.willMove(toParent: nil)
            child.view.removeFromSuperview()
            child.removeFromParent()
        }
        Logger.shared.clear()
        startResolve()
    }
}
