import UIKit

/// Hệ thống thiết kế chuẩn VIP, Cinematic & Dark Glassmorphism cao cấp
public enum AppTheme {
    // MARK: - Core Palette
    public static let primaryAccent = UIColor(red: 0.90, green: 0.04, blue: 0.08, alpha: 1.0) // E50914 Crimson
    public static let secondaryAccent = UIColor(red: 1.00, green: 0.24, blue: 0.43, alpha: 1.0) // FF3D6E Electric Rose
    public static let vipGold = UIColor(red: 1.00, green: 0.72, blue: 0.00, alpha: 1.0) // FFB800 Gold
    public static let emeraldSuccess = UIColor(red: 0.00, green: 0.90, blue: 0.46, alpha: 1.0) // 00E676 Emerald
    
    // MARK: - Backgrounds & Surfaces (OLED Dark)
    public static let backgroundDark = UIColor(red: 0.03, green: 0.03, blue: 0.05, alpha: 1.0) // #08080D True OLED
    public static let cardBackground = UIColor(red: 0.08, green: 0.08, blue: 0.11, alpha: 1.0) // #14141C Deep Surface
    public static let cardBackgroundLighter = UIColor(red: 0.12, green: 0.12, blue: 0.16, alpha: 1.0) // #1F1F29 Elevated
    public static let surfaceGlass = UIColor(white: 0.18, alpha: 0.65)
    public static let surfaceGlassLight = UIColor(white: 1.0, alpha: 0.10)
    public static let glassOverlay = UIColor.black.withAlphaComponent(0.55)
    
    // MARK: - Borders & Highlights
    public static let borderGlass = UIColor(white: 1.0, alpha: 0.10)
    public static let borderHighlight = UIColor(white: 1.0, alpha: 0.22)
    public static let borderAccent = UIColor(red: 0.90, green: 0.04, blue: 0.08, alpha: 0.45)
    
    // MARK: - Typography Colors
    public static let textPrimary = UIColor(white: 0.98, alpha: 1.0)
    public static let textSecondary = UIColor(white: 0.72, alpha: 1.0)
    public static let textMuted = UIColor(white: 0.45, alpha: 1.0)
    
    // MARK: - Gradients
    public static func makePrimaryGradient(frame: CGRect, cornerRadius: CGFloat = 0) -> CAGradientLayer {
        let gradient = CAGradientLayer()
        gradient.frame = frame
        gradient.colors = [
            primaryAccent.cgColor,
            secondaryAccent.cgColor
        ]
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        gradient.cornerRadius = cornerRadius
        return gradient
    }

    public static func makeVipGoldGradient(frame: CGRect, cornerRadius: CGFloat = 0) -> CAGradientLayer {
        let gradient = CAGradientLayer()
        gradient.frame = frame
        gradient.colors = [
            UIColor(red: 1.00, green: 0.84, blue: 0.00, alpha: 1.0).cgColor,
            UIColor(red: 1.00, green: 0.55, blue: 0.00, alpha: 1.0).cgColor
        ]
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        gradient.cornerRadius = cornerRadius
        return gradient
    }

    public static func makeCinematicFadeGradient(frame: CGRect) -> CAGradientLayer {
        let gradient = CAGradientLayer()
        gradient.frame = frame
        gradient.colors = [
            UIColor.clear.cgColor,
            backgroundDark.withAlphaComponent(0.65).cgColor,
            backgroundDark.cgColor
        ]
        gradient.locations = [0.0, 0.65, 1.0]
        return gradient
    }
    
    // MARK: - UI Styling Helpers
    public static func applyGlassCard(to view: UIView, cornerRadius: CGFloat = 16, borderWidth: CGFloat = 1) {
        view.backgroundColor = cardBackground
        view.layer.cornerRadius = cornerRadius
        view.layer.borderWidth = borderWidth
        view.layer.borderColor = borderGlass.cgColor
        view.clipsToBounds = true
    }

    public static func applyGlow(to view: UIView, color: UIColor = primaryAccent, radius: CGFloat = 12, opacity: Float = 0.35) {
        view.layer.shadowColor = color.cgColor
        view.layer.shadowRadius = radius
        view.layer.shadowOpacity = opacity
        view.layer.shadowOffset = CGSize(width: 0, height: 4)
        view.layer.masksToBounds = false
    }

    public static func applyPressFeedback(to view: UIView, isPressed: Bool) {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        UIView.animate(withDuration: 0.15, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) {
            view.transform = isPressed ? CGAffineTransform(scaleX: 0.96, y: 0.96) : .identity
        }
    }
    
    // MARK: - Typography Tokens
    public enum Fonts {
        public static func heroTitle(size: CGFloat = 26) -> UIFont {
            UIFont.systemFont(ofSize: size, weight: .black)
        }
        public static func title(size: CGFloat = 22) -> UIFont {
            UIFont.systemFont(ofSize: size, weight: .bold)
        }
        public static func sectionHeader(size: CGFloat = 18) -> UIFont {
            UIFont.systemFont(ofSize: size, weight: .heavy)
        }
        public static func subhead(size: CGFloat = 15) -> UIFont {
            UIFont.systemFont(ofSize: size, weight: .semibold)
        }
        public static func body(size: CGFloat = 14) -> UIFont {
            UIFont.systemFont(ofSize: size, weight: .regular)
        }
        public static func caption(size: CGFloat = 12) -> UIFont {
            UIFont.systemFont(ofSize: size, weight: .medium)
        }
        public static func badge(size: CGFloat = 11) -> UIFont {
            UIFont.systemFont(ofSize: size, weight: .heavy)
        }
    }
}
