import UIKit

class HomeViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UISearchBarDelegate, UISearchResultsUpdating {

    var collectionView: UICollectionView!
    var movies: [Movie] = []
    let activityIndicator = UIActivityIndicatorView(style: .large)

    // Infinite scroll state
    private var currentPage = 2          // home + page 1 + page 2 đã load sẵn
    private var isLoadingMore = false
    private var hasMore = true

    // Live search
    private let suggestionsVC = SearchSuggestionsViewController()
    private var suggestSearchWork: DispatchWorkItem?
    
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
        let infoVC = MovieInfoViewController()
        infoVC.movie = pick
        self.navigationController?.pushViewController(infoVC, animated: true)
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
        suggestionsVC.onSelect = { [weak self] movie in
            guard let self = self else { return }
            self.navigationItem.searchController?.isActive = false
            let infoVC = MovieInfoViewController()
            infoVC.movie = movie
            self.navigationController?.pushViewController(infoVC, animated: true)
        }
        let searchController = UISearchController(searchResultsController: suggestionsVC)
        searchController.searchBar.delegate = self
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Tìm kiếm Anime..."
        searchController.searchBar.autocapitalizationType = .none
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
    }

    // Gõ chữ nào hiện gợi ý tương ứng — debounce 300ms.
    func updateSearchResults(for searchController: UISearchController) {
        let text = (searchController.searchBar.text ?? "").trimmingCharacters(in: .whitespaces)
        suggestSearchWork?.cancel()
        guard !text.isEmpty else {
            suggestionsVC.update(movies: [], query: text, loading: false)
            return
        }
        suggestionsVC.update(movies: suggestionsVC.movies, query: text, loading: true)
        let work = DispatchWorkItem { [weak self] in
            NetworkManager.shared.fetchSearchSuggestions(keyword: text) { results in
                self?.suggestionsVC.update(movies: results, query: text, loading: false)
            }
        }
        suggestSearchWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
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
        // 3 cột với spacing đẹp + tỉ lệ poster 2:3 (chuẩn anime cover).
        let columns: CGFloat = 3
        let interItem: CGFloat = 10
        let sideInset: CGFloat = 12
        let totalSpacing = sideInset * 2 + interItem * (columns - 1)
        let cellWidth = (view.bounds.width - totalSpacing) / columns
        // Tăng chiều cao 1.6 (thay 1.5) để text có chỗ rộng + thấy luôn ribbon ep.
        layout.itemSize = CGSize(width: cellWidth, height: cellWidth * 1.6)
        layout.minimumLineSpacing = interItem
        layout.minimumInteritemSpacing = interItem
        layout.sectionInset = UIEdgeInsets(top: 4, left: sideInset, bottom: 24, right: sideInset)
        layout.headerReferenceSize = CGSize(width: view.bounds.width, height: 48)
        layout.footerReferenceSize = CGSize(width: view.bounds.width, height: 60)

        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.alwaysBounceVertical = true
        collectionView.register(MovieCell.self, forCellWithReuseIdentifier: "MovieCell")
        collectionView.register(SectionHeaderView.self,
                                forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                                withReuseIdentifier: "Header")
        collectionView.register(LoadMoreFooterView.self,
                                forSupplementaryViewOfKind: UICollectionView.elementKindSectionFooter,
                                withReuseIdentifier: "Footer")

        // Pull to refresh
        let refresh = UIRefreshControl()
        refresh.tintColor = .label
        refresh.addTarget(self, action: #selector(pullToRefresh), for: .valueChanged)
        collectionView.refreshControl = refresh

        view.addSubview(collectionView)
    }

    @objc private func pullToRefresh() {
        // Xoá cache home để fetch lại.
        DiskCache.shared.remove("home")
        // Reset infinite scroll
        currentPage = 2
        hasMore = true
        isLoadingMore = false
        fetchData()
    }

    // Section header với title, footer với loading state
    func collectionView(_ cv: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        if kind == UICollectionView.elementKindSectionFooter {
            let f = cv.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "Footer", for: indexPath) as! LoadMoreFooterView
            if isLoadingMore {
                f.show(state: .loading)
            } else if !hasMore {
                f.show(state: .done)
            } else {
                f.show(state: .idle)
            }
            return f
        }
        let h = cv.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "Header", for: indexPath) as! SectionHeaderView
        h.titleLabel.text = movies.isEmpty ? "Đang tải..." : "🔥 Mới cập nhật (\(movies.count) phim)"
        return h
    }

    // Infinite scroll: khi user thấy item cách cuối ≤ 6 → load page kế.
    func collectionView(_ cv: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard hasMore, !isLoadingMore, !movies.isEmpty else { return }
        let triggerIndex = movies.count - 6
        if indexPath.row >= triggerIndex {
            loadMore()
        }
    }

    private func loadMore() {
        isLoadingMore = true
        let nextPage = currentPage + 1
        reloadFooter()
        Logger.shared.log("[InfiniteScroll] Loading page \(nextPage) (đã có \(movies.count) phim)")
        NetworkManager.shared.fetchMoviesPage(nextPage) { [weak self] new in
            guard let self = self else { return }
            if new.isEmpty {
                self.hasMore = false
                self.isLoadingMore = false
                self.reloadFooter()
                Logger.shared.log("[InfiniteScroll] Page \(nextPage) rỗng — đã hết phim")
                return
            }
            var seen = Set(self.movies.map { $0.link })
            let fresh = new.filter { seen.insert($0.link).inserted }
            if fresh.isEmpty {
                // Toàn dup → server đã wrap về đầu hoặc hết content thật sự.
                self.hasMore = false
                Logger.shared.log("[InfiniteScroll] Page \(nextPage) toàn dup → dừng infinite scroll")
            } else {
                let startIndex = self.movies.count
                self.movies.append(contentsOf: fresh)
                self.currentPage = nextPage
                Logger.shared.log("[InfiniteScroll] Page \(nextPage) thêm \(fresh.count) phim mới (tổng \(self.movies.count))")
                // Chỉ insert items mới thay vì reloadData → giữ scroll vị trí.
                let paths = (startIndex..<self.movies.count).map { IndexPath(item: $0, section: 0) }
                self.collectionView.performBatchUpdates {
                    self.collectionView.insertItems(at: paths)
                }
            }
            self.isLoadingMore = false
            self.reloadFooter()
        }
    }

    private func reloadFooter() {
        if let footer = collectionView.supplementaryView(forElementKind: UICollectionView.elementKindSectionFooter,
                                                         at: IndexPath(item: 0, section: 0)) as? LoadMoreFooterView {
            if isLoadingMore { footer.show(state: .loading) }
            else if !hasMore { footer.show(state: .done) }
            else { footer.show(state: .idle) }
        }
    }
    
    private func fetchData() {
        if movies.isEmpty {
            activityIndicator.startAnimating()
            collectionView.isHidden = true
        }
        NetworkManager.shared.fetchHomeMovies { [weak self] fetchedMovies in
            self?.movies = fetchedMovies
            self?.activityIndicator.stopAnimating()
            self?.collectionView.isHidden = false
            self?.collectionView.refreshControl?.endRefreshing()
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
        let infoVC = MovieInfoViewController()
        infoVC.movie = movie
        self.navigationController?.pushViewController(infoVC, animated: true)
    }
}

// MARK: - Custom Cell
class MovieCell: UICollectionViewCell {
    let imageView = UIImageView()
    let titleLabel = UILabel()
    let epsLabel = UILabel()
    let gradientLayer = CAGradientLayer()
    private var currentImageTask: URLSessionDataTask?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .secondarySystemBackground
        contentView.layer.cornerRadius = 12
        contentView.clipsToBounds = true
        // Shadow trên cell (không clip để render được)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.22
        layer.shadowRadius = 6
        layer.shadowOffset = CGSize(width: 0, height: 3)
        layer.masksToBounds = false

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = .tertiarySystemFill
        imageView.translatesAutoresizingMaskIntoConstraints = false

        // Gradient từ trong suốt → đen ở dưới poster để text dễ đọc.
        gradientLayer.colors = [
            UIColor.clear.cgColor,
            UIColor.black.withAlphaComponent(0.85).cgColor
        ]
        gradientLayer.locations = [0.55, 1.0]

        titleLabel.font = .systemFont(ofSize: 12.5, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        epsLabel.font = .systemFont(ofSize: 10, weight: .bold)
        epsLabel.textColor = .white
        epsLabel.backgroundColor = UIColor.systemRed.withAlphaComponent(0.95)
        epsLabel.layer.cornerRadius = 6
        epsLabel.clipsToBounds = true
        epsLabel.textAlignment = .center
        epsLabel.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(imageView)
        imageView.layer.addSublayer(gradientLayer)
        contentView.addSubview(titleLabel)
        contentView.addSubview(epsLabel)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            titleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),

            epsLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            epsLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -6),
            epsLabel.heightAnchor.constraint(equalToConstant: 20)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = imageView.bounds
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        currentImageTask?.cancel()
        imageView.image = nil
        titleLabel.text = nil
        epsLabel.text = nil
        epsLabel.isHidden = true
    }

    func configure(with movie: Movie) {
        titleLabel.text = movie.title
        let trimmed = movie.episodeStatus.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            epsLabel.isHidden = true
        } else {
            epsLabel.isHidden = false
            epsLabel.text = "  \(trimmed)  "
        }
        if let url = URL(string: movie.thumbUrl) {
            currentImageTask = ImageLoader.shared.load(url, into: imageView)
        }
    }
}

// MARK: - Section header

final class SectionHeaderView: UICollectionReusableView {
    let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel.font = .systemFont(ofSize: 17, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Footer hiển thị "đang tải / đã hết / idle" cho infinite scroll

final class LoadMoreFooterView: UICollectionReusableView {
    enum State { case idle, loading, done }

    private let spinner = UIActivityIndicatorView(style: .medium)
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        addSubview(spinner)

        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
            spinner.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            label.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 6),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func show(state: State) {
        switch state {
        case .idle:
            spinner.stopAnimating()
            label.text = nil
        case .loading:
            spinner.startAnimating()
            label.text = "Đang tải thêm phim..."
        case .done:
            spinner.stopAnimating()
            label.text = "🎬 Đã hết phim"
        }
    }
}
