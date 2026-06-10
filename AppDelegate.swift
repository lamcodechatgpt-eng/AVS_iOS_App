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

        let homeNav = makeNav(rootVC: HomeViewController(),
                              title: "AnimeVietsub",
                              tabTitle: "Trang chủ",
                              icon: "house.fill")

        let history = MovieListViewController(); history.source = .history
        let historyNav = makeNav(rootVC: history,
                                 title: "Lịch sử",
                                 tabTitle: "Lịch sử",
                                 icon: "clock.fill")

        let favs = MovieListViewController(); favs.source = .favorites
        let favsNav = makeNav(rootVC: favs,
                              title: "Yêu thích",
                              tabTitle: "Yêu thích",
                              icon: "heart.fill")

        let tabBar = UITabBarController()
        tabBar.viewControllers = [homeNav, historyNav, favsNav]
        if #available(iOS 13.0, *) {
            let tabAppearance = UITabBarAppearance()
            tabAppearance.configureWithOpaqueBackground()
            tabAppearance.backgroundColor = .systemBackground
            tabBar.tabBar.standardAppearance = tabAppearance
            tabBar.tabBar.scrollEdgeAppearance = tabAppearance
        }

        window.rootViewController = tabBar
        self.window = window
        window.makeKeyAndVisible()

        return true
    }

    private func makeNav(rootVC: UIViewController, title: String, tabTitle: String, icon: String) -> UINavigationController {
        rootVC.title = title
        let nav = UINavigationController(rootViewController: rootVC)
        nav.tabBarItem = UITabBarItem(title: tabTitle,
                                      image: UIImage(systemName: icon),
                                      tag: 0)
        if #available(iOS 13.0, *) {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = .systemBackground
            nav.navigationBar.standardAppearance = appearance
            nav.navigationBar.scrollEdgeAppearance = appearance
        }
        return nav
    }
}
