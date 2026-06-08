import UIKit
import AVKit

class PlayerController: UIViewController {
    var episodeUrl: String! // Truyền link tập phim từ UI vào đây

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        
        Extractor.resolveStream(episodeUrl: episodeUrl) { [weak self] m3u8 in
            guard let m3u8 = m3u8 else {
                print("Failed to resolve stream. Obfuscated or missing.")
                return
            }
            DispatchQueue.main.async {
                let player = AVPlayer(url: m3u8)
                let playerVC = AVPlayerViewController()
                playerVC.player = player
                
                self?.addChild(playerVC)
                self?.view.addSubview(playerVC.view)
                playerVC.view.frame = self?.view.frame ?? .zero
                playerVC.player?.play()
            }
        }
    }
}
