import UIKit

protocol Coordinator: AnyObject {
    var navigationController: UINavigationController { get set }
    var childCoordinators: [Coordinator] { get set }
    func start()
}

extension Coordinator {
    func addChild(_ child: Coordinator) {
        childCoordinators.append(child)
    }

    func removeChild(_ child: Coordinator) {
        childCoordinators.removeAll { $0 === child }
    }
}

final class AppCoordinator: Coordinator {
    var navigationController: UINavigationController
    var childCoordinators: [Coordinator] = []

    private let window: UIWindow

    init(window: UIWindow) {
        self.window = window
        navigationController = UINavigationController()
    }

    func start() {
        let tabCoordinator = TabCoordinator(navigationController: navigationController)
        addChild(tabCoordinator)
        tabCoordinator.start()

        window.rootViewController = navigationController
        window.makeKeyAndVisible()

        NetworkManager.shared.domainFailureHandler = { [weak self] failedHost in
            self?.promptNewDomain(failedHost: failedHost)
        }
    }

    private func promptNewDomain(failedHost: String) {
        guard let top = UIViewController.topMost else { return }
        let alert = UIAlertController(
            title: "Domain không hoạt động",
            message: "\(failedHost) không truy cập được.\nNhập link mới (vd: https://animevietsub.pl):",
            preferredStyle: .alert
        )
        alert.addTextField { tf in
            tf.placeholder = "https://animevietsub.pl"
            tf.keyboardType = .URL
            tf.text = NetworkManager.shared.resolvedDomain
        }
        alert.addAction(UIAlertAction(title: "Để sau", style: .cancel))
        alert.addAction(UIAlertAction(title: "Lưu & thử lại", style: .default) { _ in
            guard let text = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return }
            NetworkManager.shared.resolvedDomain = text
        })
        top.present(alert, animated: true)
    }
}

extension UIViewController {
    static var topMost: UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return nil }
        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }
}

final class TabCoordinator: Coordinator {
    var navigationController: UINavigationController
    var childCoordinators: [Coordinator] = []

    init(navigationController: UINavigationController) {
        self.navigationController = navigationController
    }

    func start() {
        let tabBarController = UITabBarController()

        let homeNav = UINavigationController()
        let homeCoordinator = HomeCoordinator(navigationController: homeNav)
        addChild(homeCoordinator)
        homeCoordinator.start()
        homeNav.tabBarItem = UITabBarItem(title: nil, image: UIImage(systemName: "house"), selectedImage: UIImage(systemName: "house.fill"))
        homeNav.tabBarItem.imageInsets = UIEdgeInsets(top: 6, left: 0, bottom: -6, right: 0)

        let historyVC = MovieListViewController()
        historyVC.source = .history
        let historyNav = UINavigationController(rootViewController: historyVC)
        historyNav.tabBarItem = UITabBarItem(title: nil, image: UIImage(systemName: "clock"), selectedImage: UIImage(systemName: "clock.fill"))
        historyNav.tabBarItem.imageInsets = UIEdgeInsets(top: 6, left: 0, bottom: -6, right: 0)

        let favoritesVC = MovieListViewController()
        favoritesVC.source = .favorites
        let favoritesNav = UINavigationController(rootViewController: favoritesVC)
        favoritesNav.tabBarItem = UITabBarItem(title: nil, image: UIImage(systemName: "heart"), selectedImage: UIImage(systemName: "heart.fill"))
        favoritesNav.tabBarItem.imageInsets = UIEdgeInsets(top: 6, left: 0, bottom: -6, right: 0)

        tabBarController.viewControllers = [homeNav, historyNav, favoritesNav]
        tabBarController.tabBar.tintColor = .accent
        tabBarController.selectedIndex = 0

        navigationController.setViewControllers([tabBarController], animated: false)
        navigationController.setNavigationBarHidden(true, animated: false)
    }
}

final class HomeCoordinator: Coordinator {
    var navigationController: UINavigationController
    var childCoordinators: [Coordinator] = []

    init(navigationController: UINavigationController) {
        self.navigationController = navigationController
    }

    func start() {
        let homeVC = HomeViewController()
        homeVC.coordinator = self
        navigationController.setViewControllers([homeVC], animated: false)
    }

    func showDetail(for movie: Movie) {
        let detailVC = MovieInfoViewController()
        detailVC.movie = movie
        navigationController.pushViewController(detailVC, animated: true)
    }

    func showPlayer(episodeUrl: String, episodes: [Episode], index: Int, movie: Movie?) {
        let playerVC = PlayerController()
        playerVC.episodeUrl = episodeUrl
        playerVC.episodes = episodes
        playerVC.currentIndex = index
        playerVC.movie = movie
        navigationController.pushViewController(playerVC, animated: true)
    }
}
