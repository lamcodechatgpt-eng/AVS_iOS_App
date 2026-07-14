import UIKit

// MARK: - Section model
enum HomeSection: Int, CaseIterable {
    case hero
    case continueWatching
    case grid
}

struct HomeItem: Hashable {
    let id: String
    let movie: Movie?
    let progress: Double?

    init(movie: Movie?, progress: Double? = nil, namespace: String) {
        self.movie = movie
        self.progress = progress
        let movieID = movie.map {
            let link = $0.link.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return link.isEmpty ? $0.title : link
        } ?? UUID().uuidString
        self.id = "\(namespace):\(movieID)"
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: HomeItem, rhs: HomeItem) -> Bool { lhs.id == rhs.id }
}

final class HomeViewController: UIViewController {
    static func combineGenreMovies(_ groups: [[Movie]]) -> [Movie] {
        var seen = Set<String>()
        return groups.flatMap { $0 }.filter { seen.insert($0.link).inserted }
    }

    // MARK: - Coordinator
    weak var coordinator: HomeCoordinator?

    // MARK: - Data
    private var movies: [Movie] = []
    private var continueWatching: [HomeItem] = []
    private var heroMovies: [Movie] = []

    // MARK: - Views
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<HomeSection, HomeItem>!
    private let spinner = UIActivityIndicatorView(style: .large)
    private let emptyStateLabel = UILabel()
    private let retryButton = UIButton(type: .system)
    private var skeletonVisible = false

    // MARK: - Pagination
    private var currentPage = 2
    private var isLoadingMore = false
    private var hasMore = true
    private var dataGeneration = 0
    private var isPaginationEnabled = true

    // MARK: - Search
    private let suggestionsVC = SearchSuggestionsViewController()
    private var suggestWork: DispatchWorkItem?

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = "AnimeVietsub"
        view.backgroundColor = .bgPrimary

        setupCollectionView()
        setupDataSource()
        setupNavigationItems()
        setupSearch()
        setupSpinner()
        setupEmptyState()
        fetchData()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard dataSource != nil else { return }
        loadContinueWatching()
        applySnapshot()
    }

    // MARK: - Setup
    private func setupCollectionView() {
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: createLayout())
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.delegate = self

        collectionView.register(HeroBannerCell.self, forCellWithReuseIdentifier: "Hero")
        collectionView.register(ContinueWatchingCell.self, forCellWithReuseIdentifier: "CW")
        collectionView.register(MovieCell.self, forCellWithReuseIdentifier: "Movie")
        collectionView.register(SectionHeader.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "Header")

        collectionView.prefetchDataSource = self

        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(pullToRefresh), for: .valueChanged)
        collectionView.refreshControl = refresh

        view.addSubview(collectionView)
    }

    private func createLayout() -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { sectionIndex, environment in
            let section = HomeSection(rawValue: sectionIndex) ?? .grid
            let width = environment.container.effectiveContentSize.width

            switch section {
            case .hero:
                return Self.heroSection(containerWidth: width)
            case .continueWatching:
                return Self.horizontalScrollSection()
            case .grid:
                return Self.gridSection(containerWidth: width)
            }
        }
    }

    private static func heroSection(containerWidth: CGFloat) -> NSCollectionLayoutSection {
        let h = min(max(containerWidth * 0.56, 210), 430)
        let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .fractionalHeight(1)))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .absolute(h)), subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.orthogonalScrollingBehavior = .paging
        return section
    }

    private static func horizontalScrollSection() -> NSCollectionLayoutSection {
        let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .absolute(140), heightDimension: .absolute(200)))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: .absolute(140), heightDimension: .absolute(200)), subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 10
        section.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 16, bottom: 16, trailing: 16)
        section.orthogonalScrollingBehavior = .continuous
        section.boundarySupplementaryItems = [headerItem()]
        return section
    }

    private static func gridSection(containerWidth: CGFloat) -> NSCollectionLayoutSection {
        let columns: Int = containerWidth >= 900 ? 6 : (containerWidth >= 650 ? 5 : (containerWidth >= 480 ? 4 : 3))
        let sideInsets: CGFloat = 12
        let spacing: CGFloat = 10
        let available = containerWidth - sideInsets * 2 - spacing * CGFloat(columns - 1)
        let side = max(80, available / CGFloat(columns))
        let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1),
                                              heightDimension: .fractionalHeight(1))
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(side * 1.6))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitem: item, count: columns)
        group.interItemSpacing = NSCollectionLayoutSpacing.fixed(spacing)
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: sideInsets, bottom: 24, trailing: sideInsets)
        section.boundarySupplementaryItems = [Self.headerItem()]
        return section
    }

    private static func headerItem() -> NSCollectionLayoutBoundarySupplementaryItem {
        let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(44))
        return NSCollectionLayoutBoundarySupplementaryItem(layoutSize: size,
              elementKind: UICollectionView.elementKindSectionHeader,
              alignment: .top)
    }

    // MARK: - DiffableDataSource
    private func setupDataSource() {
        dataSource = UICollectionViewDiffableDataSource<HomeSection, HomeItem>(collectionView: collectionView) { cv, ip, item in
            let section = HomeSection(rawValue: ip.section) ?? .grid
            switch section {
            case .hero:
                let cell = cv.dequeueReusableCell(withReuseIdentifier: "Hero", for: ip) as! HeroBannerCell
                if let movie = item.movie { cell.configure(with: movie) }
                return cell
            case .continueWatching:
                let cell = cv.dequeueReusableCell(withReuseIdentifier: "CW", for: ip) as! ContinueWatchingCell
                cell.configure(with: item.movie, progress: item.progress ?? 0)
                return cell
            case .grid:
                let cell = cv.dequeueReusableCell(withReuseIdentifier: "Movie", for: ip) as! MovieCell
                if let movie = item.movie { cell.configure(with: movie) }
                return cell
            }
        }

        dataSource.supplementaryViewProvider = { [weak self] cv, kind, ip in
            guard let self = self else { return nil }
            let section = HomeSection(rawValue: ip.section) ?? .grid
            guard section != .hero else { return nil }
            let header = cv.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "Header", for: ip) as! SectionHeader
            if section == .continueWatching {
                header.titleLabel.text = "⏵ Tiếp tục xem"
            } else {
                header.titleLabel.text = self.movies.isEmpty ? "Đang tải..." : "🔥 Mới cập nhật (\(self.movies.count))"
            }
            return header
        }
    }

    // MARK: - Data
    private func fetchData() {
        dataGeneration += 1
        let generation = dataGeneration
        isPaginationEnabled = true
        showEmptyState(nil)
        if movies.isEmpty {
            showSkeleton(true)
        }
        NetworkManager.shared.fetchHomeMovies { [weak self] fetched in
            guard let self = self, self.dataGeneration == generation else { return }
            self.movies = fetched
            self.heroMovies = Array(fetched.prefix(5))
            self.loadContinueWatching()
            self.collectionView.refreshControl?.endRefreshing()
            self.showSkeleton(false)
            self.applySnapshot()
            self.showEmptyState(fetched.isEmpty ? "Không tải được danh sách phim.\nKiểm tra domain hoặc kết nối mạng." : nil)
        }
    }

    private func loadContinueWatching() {
        let store = PlaybackStore.shared
        let entries = store.history()
        continueWatching = entries.filter { $0.isCompleted != true }.map { entry in
            let progress = entry.lastEpisodeURL.flatMap { store.progress(for: $0) } ?? 0
            return HomeItem(movie: entry.movie, progress: progress, namespace: "continue")
        }
    }

    private func applySnapshot() {
        let previousItems = Dictionary(uniqueKeysWithValues:
            dataSource.snapshot().itemIdentifiers.map { ($0.id, $0) })
        var snap = NSDiffableDataSourceSnapshot<HomeSection, HomeItem>()
        snap.appendSections(HomeSection.allCases)

        if !heroMovies.isEmpty {
            snap.appendItems(heroMovies.map { HomeItem(movie: $0, namespace: "hero") }, toSection: .hero)
        }
        if !continueWatching.isEmpty {
            snap.appendItems(continueWatching, toSection: .continueWatching)
        }
        snap.appendItems(movies.map { HomeItem(movie: $0, namespace: "grid") }, toSection: .grid)

        // Stable identifiers preserve scroll position during pagination. Explicitly
        // reload only entries whose display payload changed (usually watch progress).
        let changedItems = snap.itemIdentifiers.filter { item in
            guard let previous = previousItems[item.id] else { return false }
            return previous.movie != item.movie || previous.progress != item.progress
        }
        if !changedItems.isEmpty { snap.reloadItems(changedItems) }

        dataSource.apply(snap, animatingDifferences: false)
    }

    // MARK: - Pagination
    private func loadMore() {
        guard isPaginationEnabled, hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        let generation = dataGeneration
        let next = currentPage + 1
        NetworkManager.shared.fetchMoviesPage(next) { [weak self] new in
            guard let self = self else { return }
            self.isLoadingMore = false
            guard self.dataGeneration == generation else { return }
            if new.isEmpty {
                self.hasMore = false
                return
            }
            var seen = Set(self.movies.map { $0.link })
            let fresh = new.filter { seen.insert($0.link).inserted }
            guard !fresh.isEmpty else { self.hasMore = false; return }
            self.movies.append(contentsOf: fresh)
            self.currentPage = next
            self.applySnapshot()
        }
    }

    @objc private func pullToRefresh() {
        navigationItem.title = "AnimeVietsub"
        DiskCache.shared.remove("home")
        currentPage = 2
        hasMore = true
        isLoadingMore = false
        fetchData()
    }

    // MARK: - Navigation
    private func setupNavigationItems() {
        let settings = UIBarButtonItem(image: UIImage(systemName: "gearshape"), style: .plain,
                                       target: self, action: #selector(openDomainSettings))
        settings.accessibilityLabel = "Cài đặt domain"
        let genres = UIBarButtonItem(image: UIImage(systemName: "square.grid.2x2"), style: .plain,
                                     target: self, action: #selector(openGenrePicker))
        genres.accessibilityLabel = "Chọn thể loại"
        let random = UIBarButtonItem(image: UIImage(systemName: "shuffle"), style: .plain,
                                     target: self, action: #selector(openRandom))
        random.accessibilityLabel = "Chọn phim ngẫu nhiên"
        navigationItem.rightBarButtonItems = [settings, genres, random]
    }

    @objc private func openDomainSettings() {
        let alert = UIAlertController(
            title: "Domain",
            message: "Nhập link animevietsub mới:",
            preferredStyle: .alert
        )
        alert.addTextField { tf in
            tf.placeholder = "https://animevietsub.meme"
            tf.keyboardType = .URL
            tf.text = NetworkManager.shared.resolvedDomain
        }
        alert.addAction(UIAlertAction(title: "Huỷ", style: .cancel))
        alert.addAction(UIAlertAction(title: "Lưu", style: .default) { _ in
            guard let text = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return }
            guard let url = URL(string: text),
                  let scheme = url.scheme?.lowercased(),
                  (scheme == "http" || scheme == "https"),
                  url.host != nil else {
                let error = UIAlertController(title: "Domain không hợp lệ",
                                              message: "Hãy nhập địa chỉ đầy đủ, ví dụ https://animevietsub.meme",
                                              preferredStyle: .alert)
                error.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(error, animated: true)
                return
            }
            let previous = NetworkManager.shared.resolvedDomain
            NetworkManager.shared.resolvedDomain = text
            guard NetworkManager.shared.resolvedDomain != previous else { return }
            self.movies.removeAll()
            self.heroMovies.removeAll()
            self.currentPage = 2
            self.hasMore = true
            self.fetchData()
        })
        present(alert, animated: true)
    }

    @objc private func openRandom() {
        guard let pick = movies.randomElement() else { return }
        coordinator?.showDetail(for: pick)
    }

    @objc private func openGenrePicker() {
        let vc = GenreSelectionViewController()
        let nav = UINavigationController(rootViewController: vc)
        if #available(iOS 15.0, *), let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        vc.onApply = { [weak self] genres in
            guard !genres.isEmpty else { return }
            self?.loadMultipleGenres(genres)
        }
        present(nav, animated: true)
    }

    private func loadMultipleGenres(_ genres: [GenreOption]) {
        dataGeneration += 1
        let generation = dataGeneration
        isPaginationEnabled = false
        navigationItem.title = genres.map(\.name).joined(separator: ", ")
        showEmptyState(nil)
        spinner.startAnimating()
        collectionView.isHidden = true

        let requestedDomain = NetworkManager.shared.resolvedDomain
        var results = Array(repeating: [Movie](), count: genres.count)
        var remaining = genres.count

        for (index, genre) in genres.enumerated() {
            let url = "\(requestedDomain)/the-loai/\(genre.slug)/"
            NetworkManager.shared.fetchHTML(
                url: url,
                isCancelled: { [weak self] in
                    guard let self = self else { return true }
                    return self.dataGeneration != generation
                        || NetworkManager.shared.resolvedDomain != requestedDomain
                }
            ) { [weak self] html in
                guard let self = self,
                      self.dataGeneration == generation,
                      NetworkManager.shared.resolvedDomain == requestedDomain else { return }
                NetworkManager.shared.parseMovies(html: html) { [weak self] fetched in
                    guard let self = self, self.dataGeneration == generation else { return }
                    results[index] = fetched
                    remaining -= 1
                    guard remaining == 0 else { return }

                    self.movies = Self.combineGenreMovies(results)
                    self.heroMovies = Array(self.movies.prefix(5))
                    self.spinner.stopAnimating()
                    self.collectionView.isHidden = false
                    self.applySnapshot()
                    self.showEmptyState(self.movies.isEmpty ? "Không tìm thấy phim thuộc các thể loại đã chọn." : nil)
                }
            }
        }
    }

    // MARK: - Search
    private func setupSearch() {
        suggestionsVC.onSelect = { [weak self] movie in
            self?.dismissSearchThen { [weak self] in
                self?.coordinator?.showDetail(for: movie)
            }
        }
        let sc = UISearchController(searchResultsController: suggestionsVC)
        sc.searchBar.delegate = self
        sc.searchResultsUpdater = self
        sc.obscuresBackgroundDuringPresentation = false
        sc.searchBar.placeholder = "Tìm kiếm Anime..."
        sc.searchBar.autocapitalizationType = .none
        navigationItem.searchController = sc
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
    }

    /// UIKit ignores or visually hides a navigation push when it happens during
    /// the search controller's dismissal transition. Wait for that transition to
    /// finish before opening a selected suggestion or rendering full results.
    private func dismissSearchThen(_ completion: @escaping () -> Void) {
        suggestWork?.cancel()
        guard let searchController = navigationItem.searchController,
              searchController.isActive else {
            completion()
            return
        }
        searchController.dismiss(animated: true, completion: completion)
    }

    // MARK: - Skeleton
    private func showSkeleton(_ show: Bool) {
        skeletonVisible = show
        if show {
            spinner.startAnimating()
            collectionView.isHidden = true
        } else {
            spinner.stopAnimating()
            collectionView.isHidden = false
        }
    }

    private func setupSpinner() {
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.color = .accent
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func setupEmptyState() {
        emptyStateLabel.font = .preferredFont(forTextStyle: .body)
        emptyStateLabel.adjustsFontForContentSizeCategory = true
        emptyStateLabel.textColor = .secondaryLabel
        emptyStateLabel.textAlignment = .center
        emptyStateLabel.numberOfLines = 0
        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false

        retryButton.setTitle("Thử lại", for: .normal)
        retryButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        retryButton.addTarget(self, action: #selector(retryHome), for: .touchUpInside)
        retryButton.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(emptyStateLabel)
        view.addSubview(retryButton)
        NSLayoutConstraint.activate([
            emptyStateLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -18),
            emptyStateLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            emptyStateLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),
            retryButton.topAnchor.constraint(equalTo: emptyStateLabel.bottomAnchor, constant: 12),
            retryButton.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
        showEmptyState(nil)
    }

    private func showEmptyState(_ message: String?) {
        emptyStateLabel.text = message
        emptyStateLabel.isHidden = message == nil
        retryButton.isHidden = message == nil
    }

    @objc private func retryHome() {
        navigationItem.title = "AnimeVietsub"
        movies.removeAll()
        heroMovies.removeAll()
        DiskCache.shared.remove("home")
        fetchData()
    }
}

// MARK: - UICollectionViewDelegate + Prefetch
extension HomeViewController: UICollectionViewDelegate, UICollectionViewDataSourcePrefetching {

    func collectionView(_: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        let urls = indexPaths.filter { $0.section == HomeSection.grid.rawValue && $0.row < movies.count }
            .compactMap { URL(string: movies[$0.row].thumbUrl) }
        ImageLoader.shared.prefetch(urls)
    }
    func collectionView(_: UICollectionView, willDisplay _: UICollectionViewCell, forItemAt ip: IndexPath) {
        guard ip.section == HomeSection.grid.rawValue else { return }
        guard movies.count >= 6 else { return }
        if ip.row >= movies.count - 6 { loadMore() }
    }

    func collectionView(_: UICollectionView, didSelectItemAt ip: IndexPath) {
        guard let item = dataSource.itemIdentifier(for: ip) else { return }
        if let movie = item.movie {
            coordinator?.showDetail(for: movie)
        }
    }
}

// MARK: - Search
extension HomeViewController: UISearchBarDelegate, UISearchResultsUpdating {
    func updateSearchResults(for sc: UISearchController) {
        let text = (sc.searchBar.text ?? "").trimmingCharacters(in: .whitespaces)
        suggestWork?.cancel()
        guard !text.isEmpty else {
            suggestionsVC.update(movies: [], query: text, loading: false)
            return
        }
        suggestionsVC.update(movies: suggestionsVC.movies, query: text, loading: true)
        let work = DispatchWorkItem { [weak self, weak sc] in
            NetworkManager.shared.fetchSearchSuggestions(keyword: text) { results in
                guard let self = self,
                      let current = sc?.searchBar.text?.trimmingCharacters(in: .whitespaces),
                      current == text else { return }
                self.suggestionsVC.update(movies: results, query: text, loading: false)
            }
        }
        suggestWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        guard let rawText = searchBar.text else { return }
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard let keyword = SearchUtilities.pathComponent(from: text) else { return }
        dismissSearchThen { [weak self] in
            self?.performFullSearch(keyword: keyword)
        }
    }

    private func performFullSearch(keyword: String) {
        dataGeneration += 1
        let generation = dataGeneration
        isPaginationEnabled = false
        showEmptyState(nil)
        spinner.startAnimating()
        collectionView.isHidden = true
        let requestedDomain = NetworkManager.shared.resolvedDomain
        let url = "\(requestedDomain)/tim-kiem/\(keyword)/"
        NetworkManager.shared.fetchHTML(
            url: url,
            isCancelled: { [weak self] in
                guard let self = self else { return true }
                return self.dataGeneration != generation
                    || NetworkManager.shared.resolvedDomain != requestedDomain
            }
        ) { [weak self] html in
            guard let self = self,
                  self.dataGeneration == generation,
                  NetworkManager.shared.resolvedDomain == requestedDomain else { return }
            NetworkManager.shared.parseMovies(html: html) { [weak self] fetched in
                guard let self = self, self.dataGeneration == generation else { return }
                self.movies = fetched
                self.heroMovies = Array(fetched.prefix(5))
                self.spinner.stopAnimating()
                self.collectionView.isHidden = false
                self.applySnapshot()
                self.showEmptyState(fetched.isEmpty ? "Không tìm thấy phim phù hợp." : nil)
            }
        }
    }

    func searchBarCancelButtonClicked(_: UISearchBar) {
        navigationItem.title = "AnimeVietsub"
        fetchData()
    }
}

// MARK: - HeroBannerCell
final class HeroBannerCell: UICollectionViewCell {
    private let imageView = UIImageView()
    private let overlayGradient = CAGradientLayer()
    private let titleLabel = UILabel()
    private let genreLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(imageView)

        overlayGradient.colors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.85).cgColor]
        overlayGradient.locations = [0.4, 1.0]
        imageView.layer.addSublayer(overlayGradient)

        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        genreLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        genreLabel.textColor = UIColor.white.withAlphaComponent(0.8)
        genreLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(genreLabel)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            titleLabel.bottomAnchor.constraint(equalTo: genreLabel.topAnchor, constant: -4),

            genreLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            genreLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            genreLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -24)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        overlayGradient.frame = imageView.bounds
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        ImageLoader.shared.cancelLoad(for: imageView)
        imageView.image = nil
        imageView.tag = 0
    }

    func configure(with movie: Movie) {
        titleLabel.text = movie.title
        genreLabel.text = movie.episodeStatus
        isAccessibilityElement = true
        accessibilityLabel = movie.title
        accessibilityValue = movie.episodeStatus.isEmpty ? nil : movie.episodeStatus
        accessibilityTraits = .button
        if let url = URL(string: movie.thumbUrl) {
            ImageLoader.shared.load(url, into: imageView)
        }
    }
}

// MARK: - ContinueWatchingCell
final class ContinueWatchingCell: UICollectionViewCell {
    private let imageView = UIImageView()
    private let progressBar = UIView()
    private let progressTrack = UIView()
    private var progressWidthConstraint: NSLayoutConstraint!

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = 10
        contentView.clipsToBounds = true

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = .bgTertiary
        imageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(imageView)

        progressTrack.backgroundColor = UIColor.white.withAlphaComponent(0.2)
        progressTrack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(progressTrack)

        progressBar.backgroundColor = .accent
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressTrack.addSubview(progressBar)

        progressWidthConstraint = progressBar.widthAnchor.constraint(equalTo: progressTrack.widthAnchor, multiplier: 0)
        progressWidthConstraint.isActive = true

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            progressTrack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            progressTrack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            progressTrack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            progressTrack.heightAnchor.constraint(equalToConstant: 3),

            progressBar.leadingAnchor.constraint(equalTo: progressTrack.leadingAnchor),
            progressBar.topAnchor.constraint(equalTo: progressTrack.topAnchor),
            progressBar.bottomAnchor.constraint(equalTo: progressTrack.bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        ImageLoader.shared.cancelLoad(for: imageView)
        imageView.image = nil
        imageView.tag = 0
    }

    func configure(with movie: Movie?, progress: Double) {
        if let urlStr = movie?.thumbUrl, let url = URL(string: urlStr) {
            ImageLoader.shared.load(url, into: imageView)
        }
        let ratio = min(max(progress, 0), 1)
        isAccessibilityElement = true
        accessibilityLabel = movie?.title ?? "Phim đang xem"
        accessibilityValue = "Đã xem \(Int((ratio * 100).rounded())) phần trăm"
        accessibilityTraits = .button
        progressWidthConstraint.isActive = false
        progressWidthConstraint = progressBar.widthAnchor.constraint(equalTo: progressTrack.widthAnchor, multiplier: CGFloat(ratio))
        progressWidthConstraint.isActive = true
    }
}

// MARK: - SectionHeader
final class SectionHeader: UICollectionReusableView {
    let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel.font = .systemFont(ofSize: 19, weight: .bold)
        titleLabel.textColor = .textPrimary
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

// MARK: - MovieCell (giữ nguyên style hiện tại)
class MovieCell: UICollectionViewCell {
    let imageView = UIImageView()
    let titleLabel = UILabel()
    let epsLabel = UILabel()
    let epsBackground = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
    let gradientLayer = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .bgTertiary
        contentView.layer.cornerRadius = 14
        contentView.clipsToBounds = true

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false

        gradientLayer.colors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.9).cgColor]
        gradientLayer.locations = [0.5, 1.0]

        titleLabel.font = .systemFont(ofSize: 13, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        epsLabel.font = .systemFont(ofSize: 11, weight: .heavy)
        epsLabel.textColor = .white
        epsLabel.textAlignment = .center
        epsLabel.translatesAutoresizingMaskIntoConstraints = false

        epsBackground.layer.cornerRadius = 8
        epsBackground.clipsToBounds = true
        epsBackground.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(imageView)
        imageView.layer.addSublayer(gradientLayer)
        contentView.addSubview(titleLabel)
        contentView.addSubview(epsBackground)
        epsBackground.contentView.addSubview(epsLabel)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
            titleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),

            epsBackground.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            epsBackground.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            epsBackground.heightAnchor.constraint(equalToConstant: 22),

            epsLabel.leadingAnchor.constraint(equalTo: epsBackground.contentView.leadingAnchor, constant: 6),
            epsLabel.trailingAnchor.constraint(equalTo: epsBackground.contentView.trailingAnchor, constant: -6),
            epsLabel.centerYAnchor.constraint(equalTo: epsBackground.contentView.centerYAnchor)
        ])
        setupShadow()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = imageView.bounds
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        ImageLoader.shared.cancelLoad(for: imageView)
        imageView.image = nil
        imageView.tag = 0
        titleLabel.text = nil
        epsLabel.text = nil
        epsBackground.isHidden = true
    }

    private func setupShadow() {
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.2
        layer.shadowRadius = 6
        layer.shadowOffset = CGSize(width: 0, height: 3)
        layer.masksToBounds = false
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: contentView.layer.cornerRadius).cgPath
    }

    override var bounds: CGRect {
        didSet {
            layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: contentView.layer.cornerRadius).cgPath
        }
    }

    func configure(with movie: Movie) {
        titleLabel.text = movie.title
        let trimmed = movie.episodeStatus.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            epsBackground.isHidden = true
        } else {
            epsBackground.isHidden = false
            epsLabel.text = trimmed
        }
        if let url = URL(string: movie.thumbUrl) {
            ImageLoader.shared.load(url, into: imageView)
        }
        isAccessibilityElement = true
        accessibilityLabel = movie.title
        accessibilityValue = trimmed.isEmpty ? nil : trimmed
        accessibilityTraits = .button
    }
}
