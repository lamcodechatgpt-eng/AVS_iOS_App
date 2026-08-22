import UIKit

/// Token hệ thống giao diện tiêu chuẩn mang hơi hướng Dark Glassmorphism, Cinematic Aesthetic.
public enum AppTheme {
    public static let primaryAccent = UIColor(red: 0.90, green: 0.04, blue: 0.08, alpha: 1.0) // E50914 Red
    public static let secondaryAccent = UIColor(red: 1.00, green: 0.24, blue: 0.43, alpha: 1.0) // FF3D6E Pink Red
    public static let backgroundDark = UIColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1.0)
    public static let cardBackground = UIColor(red: 0.12, green: 0.12, blue: 0.15, alpha: 1.0)
    public static let surfaceGlass = UIColor(white: 0.15, alpha: 0.7)
    public static let glassOverlay = UIColor.black.withAlphaComponent(0.4)
    public static let textPrimary = UIColor(white: 0.96, alpha: 1.0)
    public static let textSecondary = UIColor(white: 0.70, alpha: 1.0)
    
    public static func applyGlassCard(to view: UIView, cornerRadius: CGFloat = 12) {
        view.backgroundColor = cardBackground
        view.layer.cornerRadius = cornerRadius
        view.layer.borderWidth = 1
        view.layer.borderColor = surfaceGlass.cgColor
        view.clipsToBounds = true
    }
    
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
    }
}
