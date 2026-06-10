import UIKit
import AVFoundation

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        // Bật audio session để Picture-in-Picture + background audio hoạt động.
        // .playback cho phép phát khi app vào background hoặc khoá màn.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)

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
