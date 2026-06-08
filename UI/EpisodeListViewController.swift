import UIKit

class EpisodeListViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    
    var movie: Movie?
    var episodes: [Episode] = []
    var tableView: UITableView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = movie?.title
        self.view.backgroundColor = .systemBackground
        
        setupTableView()
        fetchEpisodes()
    }
    
    private func setupTableView() {
        tableView = UITableView(frame: view.bounds, style: .plain)
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "EpisodeCell")
        
        view.addSubview(tableView)
    }
    
    private func fetchEpisodes() {
        guard let movie = movie else { return }
        NetworkManager.shared.fetchEpisodes(movieUrl: movie.link) { [weak self] fetchedEpisodes in
            self?.episodes = fetchedEpisodes
            self?.tableView.reloadData()
        }
    }
    
    // MARK: - UITableViewDataSource
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return episodes.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "EpisodeCell", for: indexPath)
        let episode = episodes[indexPath.row]
        cell.textLabel?.text = episode.title
        cell.accessoryType = .disclosureIndicator
        return cell
    }
    
    // MARK: - UITableViewDelegate
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let episode = episodes[indexPath.row]
        
        // Push PlayerController
        let playerVC = PlayerController()
        playerVC.episodeUrl = episode.link
        self.navigationController?.pushViewController(playerVC, animated: true)
    }
}
