import UIKit

final class SkeletonView: UIView {
    private let gradientLayer = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        clipsToBounds = true
        layer.cornerRadius = 10
        gradientLayer.locations = [0, 0.5, 1]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0.3)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.7)
        layer.addSublayer(gradientLayer)
        updateColors()
    }

    private func updateColors() {
        let base = UIColor(red: 0.10, green: 0.10, blue: 0.14, alpha: 1.0)
        let highlight = UIColor(red: 0.18, green: 0.18, blue: 0.24, alpha: 1.0)
        gradientLayer.colors = [base.cgColor, highlight.cgColor, base.cgColor]
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateColors()
    }

    func startShimmer() {
        gradientLayer.removeAnimation(forKey: "shimmer")
        let anim = CABasicAnimation(keyPath: "locations")
        anim.fromValue = [-1.0, -0.5, 0.0]
        anim.toValue = [1.0, 1.5, 2.0]
        anim.duration = 1.35
        anim.repeatCount = .infinity
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        gradientLayer.add(anim, forKey: "shimmer")
    }

    func stopShimmer() {
        gradientLayer.removeAnimation(forKey: "shimmer")
    }
}
