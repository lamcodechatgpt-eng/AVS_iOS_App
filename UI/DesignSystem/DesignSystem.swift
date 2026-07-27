import UIKit

/// Token hệ thống giao diện tiêu chuẩn Netflix / Crunchyroll Dark Aesthetic
public enum AppTheme {
    public static let primaryAccent = UIColor(red: 0.90, green: 0.04, blue: 0.08, alpha: 1.0) // E50914 Red
    public static let backgroundDark = UIColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1.0)
    public static let cardBackground = UIColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1.0)
    public static let glassOverlay = UIColor.black.withAlphaComponent(0.4)

    public enum Fonts {
        public static func heroTitle(size: CGFloat = 22) -> UIFont {
            UIFont.systemFont(ofSize: size, weight: .bold)
        }
        public static func sectionHeader(size: CGFloat = 18) -> UIFont {
            UIFont.systemFont(ofSize: size, weight: .semibold)
        }
        public static func body(size: CGFloat = 14) -> UIFont {
            UIFont.systemFont(ofSize: size, weight: .regular)
        }
    }
}
