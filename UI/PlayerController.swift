import UIKit
import AVKit

class PlayerController: UIViewController {
    var episodeUrl: String! // Truyền link tập phim từ UI vào đây

    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let statusLabel = UILabel()
    private let logTextView = UITextView()
    private let copyButton = UIButton(type: .system)
    private let retryButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        setupLoadingUI()
        startResolve()
    }

    private func startResolve() {
        activityIndicator.startAnimating()
        statusLabel.text = "Đang tải luồng phim..."
        logTextView.isHidden = true
        copyButton.isHidden = true
        retryButton.isHidden = true

        Extractor.resolveStream(episodeUrl: episodeUrl) { [weak self] m3u8 in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.activityIndicator.stopAnimating()

                guard let m3u8 = m3u8 else {
                    self.showFailure()
                    Logger.shared.log("[PlayerController] resolveStream trả về nil cho \(self.episodeUrl ?? "")")
                    return
                }

                self.statusLabel.isHidden = true
                self.logTextView.isHidden = true
                self.copyButton.isHidden = true
                self.retryButton.isHidden = true

                let player = AVPlayer(url: m3u8)
                let playerVC = AVPlayerViewController()
                playerVC.player = player

                self.addChild(playerVC)
                playerVC.view.frame = self.view.bounds
                playerVC.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                self.view.addSubview(playerVC.view)
                playerVC.didMove(toParent: self)
                playerVC.player?.play()
            }
        }
    }

    private func showFailure() {
        statusLabel.text = "Không lấy được luồng phim.\nLog gần nhất ở dưới — bấm Copy để paste lại cho dev."
        logTextView.text = Logger.shared.snapshot()
        logTextView.isHidden = false
        copyButton.isHidden = false
        retryButton.isHidden = false
        // Cuộn về cuối để thấy log mới nhất
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
        Logger.shared.clear()
        startResolve()
    }
}
