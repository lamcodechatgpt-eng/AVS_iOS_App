import UIKit

final class BackgroundView: UIView {
    private let gradientLayer = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        gradientLayer.colors = [
            UIColor.systemBackground.cgColor,
            UIColor.systemBackground.cgColor
        ]
        gradientLayer.locations = [0.0, 1.0]
        layer.addSublayer(gradientLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
    }

    func setStyle(_ style: BackgroundStyle) {
        gradientLayer.colors = style.colors
        gradientLayer.locations = style.locations
    }
}

enum BackgroundStyle {
    case `default`
    case dark
    case accent

    var colors: [CGColor] {
        switch self {
        case .default:
            return [
                UIColor.systemBackground.cgColor,
                UIColor.systemGroupedBackground.cgColor
            ]
        case .dark:
            return [
                UIColor.black.cgColor,
                UIColor(red: 0.08, green: 0.08, blue: 0.12, alpha: 1).cgColor
            ]
        case .accent:
            return [
                UIColor.systemBackground.cgColor,
                UIColor.systemRed.withAlphaComponent(0.05).cgColor
            ]
        }
    }

    var locations: [NSNumber] {
        return [0.0, 1.0]
    }
}
