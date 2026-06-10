import UIKit
import AVKit

class PlayerController: UIViewController {
    var episodeUrl: String! // Truyền link tập phim từ UI vào đây

    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let statusLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        setupLoadingUI()

        Extractor.resolveStream(episodeUrl: episodeUrl) { [weak self] m3u8 in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.activityIndicator.stopAnimating()

                guard let m3u8 = m3u8 else {
                    self.statusLabel.text = "Không lấy được luồng phim.\nWeb mở được nhưng app chưa bắt được link luồng.\nXem log [Extractor] trong Console để biết HTML server trả về gì."
                    print("[PlayerController] resolveStream trả về nil cho \(self.episodeUrl ?? "")")
                    return
                }

                self.statusLabel.isHidden = true

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

        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusLabel.topAnchor.constraint(equalTo: activityIndicator.bottomAnchor, constant: 16),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)
        ])

        activityIndicator.startAnimating()
    }
}
