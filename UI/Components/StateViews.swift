import UIKit

/// View hiển thị khi danh sách rỗng, lỗi mạng hoặc offline mang phong cách VIP Glassmorphic
public final class StateView: UIView {
    private let containerCard = UIView()
    private let iconBadgeView = UIView()
    private let iconImageView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let actionButton = UIButton(type: .custom)
    private var buttonGradient: CAGradientLayer?

    public var onRetryTap: (() -> Void)?

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        backgroundColor = .clear

        // Container Card dạng Glassmorphism cao cấp
        containerCard.translatesAutoresizingMaskIntoConstraints = false
        AppTheme.applyGlassCard(to: containerCard, cornerRadius: 24, borderWidth: 1)
        containerCard.backgroundColor = AppTheme.cardBackground.withAlphaComponent(0.85)
        addSubview(containerCard)

        // Huy hiệu icon tròn có ánh sáng nền
        iconBadgeView.translatesAutoresizingMaskIntoConstraints = false
        iconBadgeView.backgroundColor = AppTheme.primaryAccent.withAlphaComponent(0.12)
        iconBadgeView.layer.cornerRadius = 32
        iconBadgeView.layer.borderWidth = 1.5
        iconBadgeView.layer.borderColor = AppTheme.primaryAccent.withAlphaComponent(0.35).cgColor
        iconBadgeView.clipsToBounds = true
        containerCard.addSubview(iconBadgeView)

        iconImageView.tintColor = AppTheme.secondaryAccent
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconBadgeView.addSubview(iconImageView)

        // Title
        titleLabel.font = AppTheme.Fonts.title(size: 19)
        titleLabel.textColor = AppTheme.textPrimary
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        containerCard.addSubview(titleLabel)

        // Subtitle
        subtitleLabel.font = AppTheme.Fonts.body(size: 14)
        subtitleLabel.textColor = AppTheme.textSecondary
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        containerCard.addSubview(subtitleLabel)

        // Nút bấm Gradient VIP
        actionButton.titleLabel?.font = AppTheme.Fonts.subhead(size: 15)
        actionButton.setTitleColor(.white, for: .normal)
        actionButton.layer.cornerRadius = 22
        actionButton.clipsToBounds = true
        actionButton.contentEdgeInsets = UIEdgeInsets(top: 12, left: 28, bottom: 12, right: 28)
        actionButton.addTarget(self, action: #selector(didTapAction), for: .touchUpInside)
        actionButton.addTarget(self, action: #selector(buttonTouchDown), for: [.touchDown, .touchDragEnter])
        actionButton.addTarget(self, action: #selector(buttonTouchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        AppTheme.applyGlow(to: actionButton, color: AppTheme.primaryAccent, radius: 10, opacity: 0.4)
        containerCard.addSubview(actionButton)

        NSLayoutConstraint.activate([
            containerCard.centerXAnchor.constraint(equalTo: centerXAnchor),
            containerCard.centerYAnchor.constraint(equalTo: centerYAnchor),
            containerCard.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 28),
            containerCard.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -28),
            containerCard.widthAnchor.constraint(lessThanOrEqualToConstant: 380),

            iconBadgeView.topAnchor.constraint(equalTo: containerCard.topAnchor, constant: 32),
            iconBadgeView.centerXAnchor.constraint(equalTo: containerCard.centerXAnchor),
            iconBadgeView.widthAnchor.constraint(equalToConstant: 64),
            iconBadgeView.heightAnchor.constraint(equalToConstant: 64),

            iconImageView.centerXAnchor.constraint(equalTo: iconBadgeView.centerXAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: iconBadgeView.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 32),
            iconImageView.heightAnchor.constraint(equalToConstant: 32),

            titleLabel.topAnchor.constraint(equalTo: iconBadgeView.bottomAnchor, constant: 18),
            titleLabel.leadingAnchor.constraint(equalTo: containerCard.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: containerCard.trailingAnchor, constant: -24),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            subtitleLabel.leadingAnchor.constraint(equalTo: containerCard.leadingAnchor, constant: 24),
            subtitleLabel.trailingAnchor.constraint(equalTo: containerCard.trailingAnchor, constant: -24),

            actionButton.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 24),
            actionButton.centerXAnchor.constraint(equalTo: containerCard.centerXAnchor),
            actionButton.heightAnchor.constraint(equalToConstant: 44),
            actionButton.bottomAnchor.constraint(equalTo: containerCard.bottomAnchor, constant: -32)
        ])
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        if let grad = buttonGradient {
            grad.frame = actionButton.bounds
        }
    }

    private func applyGradientToButton() {
        buttonGradient?.removeFromSuperlayer()
        let grad = AppTheme.makePrimaryGradient(frame: actionButton.bounds, cornerRadius: 22)
        actionButton.layer.insertSublayer(grad, at: 0)
        buttonGradient = grad
    }

    @objc private func buttonTouchDown() {
        AppTheme.applyPressFeedback(to: actionButton, isPressed: true)
    }

    @objc private func buttonTouchUp() {
        AppTheme.applyPressFeedback(to: actionButton, isPressed: false)
    }

    @objc private func didTapAction() {
        onRetryTap?()
    }

    public func configure(iconName: String, title: String, subtitle: String, buttonTitle: String? = nil) {
        let config = UIImage.SymbolConfiguration(pointSize: 28, weight: .semibold)
        iconImageView.image = UIImage(systemName: iconName, withConfiguration: config)
        titleLabel.text = title
        subtitleLabel.text = subtitle
        if let btnTitle = buttonTitle {
            actionButton.setTitle(btnTitle, for: .normal)
            actionButton.isHidden = false
            DispatchQueue.main.async { [weak self] in
                self?.applyGradientToButton()
            }
        } else {
            actionButton.isHidden = true
        }
    }
}
