import UIKit

class HomeViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UISearchBarDelegate {
    
    var collectionView: UICollectionView!
    var movies: [Movie] = []
    let activityIndicator = UIActivityIndicatorView(style: .large)
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "AnimeVietsub"
        self.view.backgroundColor = .systemBackground

        setupNavigationBarButtons()
        setupSearchBar()
        setupCollectionView()
        setupLoadingIndicator()

        fetchData()
    }

    private func setupNavigationBarButtons() {
        let randomBtn = UIBarButtonItem(image: UIImage(systemName: "shuffle"),
                                        style: .plain,
                                        target: self,
                                        action: #selector(openRandomMovie))
        let genreBtn = UIBarButtonItem(image: UIImage(systemName: "square.grid.2x2"),
                                       style: .plain,
                                       target: self,
                                       action: #selector(openGenrePicker))
        navigationItem.rightBarButtonItems = [randomBtn, genreBtn]
    }

    @objc private func openRandomMovie() {
        guard !movies.isEmpty else { return }
        let pick = movies.randomElement()!
        Logger.shared.log("[Random] Mở phim ngẫu nhiên: \(pick.title)")
        let episodeVC = EpisodeListViewController()
        episodeVC.movie = pick
        self.navigationController?.pushViewController(episodeVC, animated: true)
    }

    @objc private func openGenrePicker() {
        // Trích genre slug từ link <a href="/the-loai/...">. Parse từ HTML home.
        let alert = UIAlertController(title: "Đang tải thể loại...", message: nil, preferredStyle: .actionSheet)
        present(alert, animated: true)

        NetworkManager.shared.fetchHTML(url: NetworkManager.shared.resolvedDomain) { [weak self] html in
            let genres = Self.parseGenres(from: html)
            DispatchQueue.main.async {
                alert.dismiss(animated: true) {
                    self?.presentGenreList(genres)
                }
            }
        }
    }

    private func presentGenreList(_ genres: [(name: String, slug: String)]) {
        let sheet = UIAlertController(title: "Thể loại", message: nil, preferredStyle: .actionSheet)
        for g in genres.prefix(20) {
            sheet.addAction(UIAlertAction(title: g.name, style: .default) { [weak self] _ in
                self?.loadGenre(slug: g.slug, name: g.name)
            })
        }
        sheet.addAction(UIAlertAction(title: "Đóng", style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.barButtonItem = navigationItem.rightBarButtonItems?.last
        }
        present(sheet, animated: true)
    }

    private func loadGenre(slug: String, name: String) {
        title = "Thể loại: \(name)"
        activityIndicator.startAnimating()
        collectionView.isHidden = true
        let url = "\(NetworkManager.shared.resolvedDomain)/the-loai/\(slug)/"
        Logger.shared.log("[Genre] Load \(url)")
        NetworkManager.shared.fetchHTML(url: url) { [weak self] html in
            NetworkManager.shared.parseMovies(html: html) { fetched in
                Logger.shared.log("[Genre] kết quả: \(fetched.count) phim")
                self?.movies = fetched
                self?.activityIndicator.stopAnimating()
                self?.collectionView.isHidden = false
                self?.collectionView.reloadData()
            }
        }
    }

    /// Bóc danh sách genre từ trang chủ. AVS link kiểu /the-loai/hanh-dong/.
    private static func parseGenres(from html: String) -> [(name: String, slug: String)] {
        let pattern = "(?i)<a[^>]*?href=\"[^\"]*?/the-loai/([a-z0-9-]+)/?\"[^>]*>([^<]{2,40})</a>"
        var result: [(String, String)] = []
        var seen = Set<String>()
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        for m in matches {
            guard let slugRange = Range(m.range(at: 1), in: html),
                  let nameRange = Range(m.range(at: 2), in: html) else { continue }
            let slug = String(html[slugRange])
            let name = String(html[nameRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            if seen.contains(slug) || name.isEmpty { continue }
            seen.insert(slug)
            result.append((name, slug))
        }
        return result
    }
    
    private func setupSearchBar() {
        let searchController = UISearchController(searchResultsController: nil)
        searchController.searchBar.delegate = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Tìm kiếm Anime..."
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
    }
    
    private func setupLoadingIndicator() {
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.color = .systemRed
        view.addSubview(activityIndicator)
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
    
    private func setupCollectionView() {
        let layout = UICollectionViewFlowLayout()
        let width = (view.bounds.width - 30) / 2
        layout.itemSize = CGSize(width: width, height: width * 1.5)
        layout.sectionInset = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(MovieCell.self, forCellWithReuseIdentifier: "MovieCell")
        
        view.addSubview(collectionView)
    }
    
    private func fetchData() {
        activityIndicator.startAnimating()
        collectionView.isHidden = true
        
        NetworkManager.shared.fetchHomeMovies { [weak self] fetchedMovies in
            self?.movies = fetchedMovies
            self?.activityIndicator.stopAnimating()
            self?.collectionView.isHidden = false
            self?.collectionView.reloadData()
        }
    }
    
    private func fixKeyword(_ str: String) -> String {
        // Fold dấu trước (Bộ Đôi → Bo Doi) vì URL search của AVS không hỗ trợ dấu.
        let folded = str
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "vi_VN"))
            // Đ/đ folding diacriticInsensitive không xử lý, replace tay.
            .replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: "Đ", with: "D")
            .lowercased()
        let charsToRemove = "<>`~!@#$%^&*()_|=?;:'\",.{}[]\\/"
        var clean = folded
        clean.removeAll { charsToRemove.contains($0) }
        return clean.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: "+")
    }

    // MARK: - Search
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        guard let text = searchBar.text, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let keyword = fixKeyword(text)
        let searchUrl = "\(NetworkManager.shared.resolvedDomain)/tim-kiem/\(keyword)/"
        Logger.shared.log("[Search] keyword='\(text)' → '\(keyword)' → \(searchUrl)")

        activityIndicator.startAnimating()
        collectionView.isHidden = true

        NetworkManager.shared.fetchHTML(url: searchUrl) { [weak self] html in
            NetworkManager.shared.parseMovies(html: html) { fetchedMovies in
                Logger.shared.log("[Search] kết quả: \(fetchedMovies.count) phim")
                self?.movies = fetchedMovies
                self?.activityIndicator.stopAnimating()
                self?.collectionView.isHidden = false
                self?.collectionView.reloadData()
            }
        }
    }
    
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        fetchData()
    }
    
    // MARK: - UICollectionViewDataSource
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return movies.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "MovieCell", for: indexPath) as! MovieCell
        let movie = movies[indexPath.row]
        cell.configure(with: movie)
        return cell
    }
    
    // MARK: - UICollectionViewDelegate
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let movie = movies[indexPath.row]
        let episodeVC = EpisodeListViewController()
        episodeVC.movie = movie
        self.navigationController?.pushViewController(episodeVC, animated: true)
    }
}

// MARK: - Custom Cell
class MovieCell: UICollectionViewCell {
    let imageView = UIImageView()
    let titleLabel = UILabel()
    let epsLabel = UILabel()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .secondarySystemBackground
        contentView.layer.cornerRadius = 8
        contentView.clipsToBounds = true
        
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        
        titleLabel.font = .systemFont(ofSize: 14, weight: .bold)
        titleLabel.numberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        epsLabel.font = .systemFont(ofSize: 12, weight: .medium)
        epsLabel.textColor = .white
        epsLabel.backgroundColor = UIColor.red.withAlphaComponent(0.8)
        epsLabel.layer.cornerRadius = 4
        epsLabel.clipsToBounds = true
        epsLabel.translatesAutoresizingMaskIntoConstraints = false
        
        contentView.addSubview(imageView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(epsLabel)
        
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.heightAnchor.constraint(equalTo: contentView.heightAnchor, multiplier: 0.8),
            
            titleLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 4),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
            
            epsLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            epsLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4)
        ])
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    func configure(with movie: Movie) {
        titleLabel.text = movie.title
        epsLabel.text = " \(movie.episodeStatus) "
        
        // Load image (Basic)
        if let url = URL(string: movie.thumbUrl) {
            DispatchQueue.global().async {
                if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                    DispatchQueue.main.async {
                        self.imageView.image = image
                    }
                }
            }
        }
    }
}
