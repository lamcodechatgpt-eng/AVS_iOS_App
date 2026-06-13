import UIKit

extension UIColor {
    // MARK: - Background
    static let bgPrimary = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.04, alpha: 1) : UIColor(white: 1, alpha: 1) }
    static let bgSecondary = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.08, alpha: 1) : UIColor(white: 0.96, alpha: 1) }
    static let bgTertiary = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.12, alpha: 1) : UIColor(white: 0.91, alpha: 1) }
    static let bgCard = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.1, alpha: 1) : UIColor(white: 1, alpha: 1) }

    // MARK: - Accent
    static let accent = UIColor.systemRed
    static let accentDimmed = UIColor.systemRed.withAlphaComponent(0.6)

    // MARK: - Text
    static let textPrimary = UIColor.label
    static let textSecondary = UIColor.secondaryLabel
    static let textTertiary = UIColor.tertiaryLabel
    static let textOnAccent = UIColor.white

    // MARK: - Special
    static let separatorThemed = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.22, alpha: 1) : UIColor(white: 0.78, alpha: 1) }
    static let overlayDark = UIColor.black.withAlphaComponent(0.45)
    static let overlayLight = UIColor.white.withAlphaComponent(0.12)

    // MARK: - Shimmer
    static let shimmerBase = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.15, alpha: 1) : UIColor(white: 0.85, alpha: 1) }
    static let shimmerHighlight = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.22, alpha: 1) : UIColor(white: 0.92, alpha: 1) }

    // MARK: - State
    static let success = UIColor.systemGreen
    static let warning = UIColor.systemOrange
    static let error = UIColor.systemRed
}
