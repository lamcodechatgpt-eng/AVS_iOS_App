import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        let window = UIWindow(frame: UIScreen.main.bounds)
        let homeVC = HomeViewController()
        let navigationController = UINavigationController(rootViewController: homeVC)
        
        // Cài đặt giao diện NavigationBar để tránh bị trong suốt
        if #available(iOS 13.0, *) {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = .systemBackground
            navigationController.navigationBar.standardAppearance = appearance
            navigationController.navigationBar.scrollEdgeAppearance = appearance
        }
        
        window.rootViewController = navigationController
        self.window = window
        window.makeKeyAndVisible()
        
        return true
    }
}
