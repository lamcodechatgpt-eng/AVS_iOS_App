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
    private weak var currentPlayerItem: AVPlayerItem?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        setupLoadingUI()
        startResolve()
    }

    deinit {
        statusObservation?.invalidate()
        if let o = errorObserver { NotificationCenter.default.removeObserver(o) }
        if let o = stallObserver { NotificationCenter.default.removeObserver(o) }
    }

    private func startResolve() {
        activityIndicator.startAnimating()
        statusLabel.text = "Đang tải luồng phim..."
        logTextView.isHidden = true
        copyButton.isHidden = true
        retryButton.isHidden = true

        Extractor.resolveStream(episodeUrl: episodeUrl) { [weak self] stream in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.activityIndicator.stopAnimating()

                guard let stream = stream else {
                    self.showFailure()
                    Logger.shared.log("[PlayerController] resolveStream trả về nil cho \(self.episodeUrl ?? "")")
                    return
                }

                Logger.shared.log("[PlayerController] Tạo AVPlayer với m3u8=\(stream.url.absoluteString) referer=\(stream.referer)")
                self.preflightAndAttach(stream: stream)
            }
        }
    }

    /// Gửi HEAD request tới m3u8 trước khi giao cho AVPlayer để xác minh server thực sự
    /// chấp nhận. Nếu trả 403/404 thì rõ ràng Referer/cookie/expiry là vấn đề; nếu 200
    /// nhưng AVPlayer vẫn fail thì lỗi là codec / HLS variant / format.
    private func preflightAndAttach(stream: Stream) {
        var req = URLRequest(url: stream.url)
        req.httpMethod = "HEAD"
        req.timeoutInterval = 8
        req.setValue(stream.referer, forHTTPHeaderField: "Referer")
        req.setValue(String(stream.referer.dropLast()), forHTTPHeaderField: "Origin")
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { _, resp, err in
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
                // Vẫn thử attach để có log AVPlayer cho dù preflight có lỗi.
                self.attachPlayer(for: stream)
            }
        }.resume()
    }

    private func attachPlayer(for stream: Stream) {
        // Một số server stream từ chối khi thiếu Referer / User-Agent. AVPlayer mặc định
        // không gửi Referer nên hiện logo gạch chéo. Truyền tay qua AVURLAsset.
        let headers: [String: String] = [
            "Referer": stream.referer,
            "Origin": String(stream.referer.dropLast()), // bỏ '/' cuối để thành origin
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
        ]
        // Key "AVURLAssetHTTPHeaderFieldsKey" là private nhưng được dùng rộng rãi.
        let asset = AVURLAsset(url: stream.url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
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
        statusObservation?.invalidate()
        statusObservation = nil
        if let o = errorObserver { NotificationCenter.default.removeObserver(o); errorObserver = nil }
        if let o = stallObserver { NotificationCenter.default.removeObserver(o); stallObserver = nil }
        for child in children {
            child.willMove(toParent: nil)
            child.view.removeFromSuperview()
            child.removeFromParent()
        }
        Logger.shared.clear()
        startResolve()
    }
}
