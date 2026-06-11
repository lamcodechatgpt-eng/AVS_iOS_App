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

        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = .systemBackground
        tabAppearance.stackedLayoutAppearance.normal.iconColor = .secondaryLabel
        tabAppearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.secondaryLabel]
        tabAppearance.stackedLayoutAppearance.selected.iconColor = .systemRed
        tabAppearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor.systemRed]
        tabBar.tabBar.standardAppearance = tabAppearance
        tabBar.tabBar.scrollEdgeAppearance = tabAppearance

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

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .systemBackground
        appearance.titleTextAttributes = [.font: UIFont.systemFont(ofSize: 17, weight: .bold)]
        nav.navigationBar.standardAppearance = appearance
        nav.navigationBar.scrollEdgeAppearance = appearance
        nav.navigationBar.tintColor = .systemRed

        return nav
    }
}
