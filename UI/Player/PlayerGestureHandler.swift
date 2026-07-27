import UIKit
import MediaPlayer

public protocol PlayerGestureHandlerDelegate: AnyObject {
    func didDoubleTapSeek(isForward: Bool)
    func didChangeBrightness(level: CGFloat)
    func didChangeVolume(level: Float)
}

/// Control handler xử lý các cử chỉ vuốt, chạm kép trên Player Screen
public final class PlayerGestureHandler: NSObject {
    private weak var containerView: UIView?
    public weak var delegate: PlayerGestureHandlerDelegate?

    private var initialTouchLocation: CGPoint = .zero

    public init(containerView: UIView) {
        self.containerView = containerView
        super.init()
        setupGestureRecognizers()
    }

    private func setupGestureRecognizers() {
        guard let view = containerView else { return }

        // Double Tap Gesture Seek (+10s / -10s)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTap)

        // Pan Gesture (Brightness & Volume)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        view.addGestureRecognizer(pan)
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard let view = containerView else { return }
        let touchPoint = gesture.location(in: view)
        let isForward = touchPoint.x > (view.bounds.width / 2.0)
        delegate?.didDoubleTapSeek(isForward: isForward)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let view = containerView else { return }
        let location = gesture.location(in: view)
        let translation = gesture.translation(in: view)

        switch gesture.state {
        case .began:
            initialTouchLocation = location
        case .changed:
            let deltaY = -translation.y / view.bounds.height
            if initialTouchLocation.x < (view.bounds.width / 2.0) {
                // Nửa màn hình bên trái -> Điều chỉnh Độ Sáng (Brightness)
                let current = UIScreen.main.brightness
                let newLevel = max(0, min(1.0, current + deltaY))
                UIScreen.main.brightness = newLevel
                delegate?.didChangeBrightness(level: newLevel)
            } else {
                // Nửa màn hình bên phải -> Điều chỉnh Âm Lượng (Volume)
                delegate?.didChangeVolume(level: Float(deltaY))
            }
        default:
            break
        }
    }
}
