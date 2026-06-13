import UIKit

// MARK: - Section model
enum HomeSection: Int, CaseIterable {
    case hero
    case continueWatching
    case grid
}

struct HomeItem: Hashable {
    let id = UUID()
    let movie: Movie?
    let progress: Double?

    init(movie: Movie?, progress: Double? = nil) {
        self.movie = movie
        self.progress = progress
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: HomeItem, rhs: HomeItem) -> Bool { lhs.id == rhs.id }
}

final class HomeViewController: UIViewController {

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
    private var skeletonVisible = false

    // MARK: - Pagination
    private var currentPage = 2
    private var isLoadingMore = false
    private var hasMore = true

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
        fetchData()
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
        UICollectionViewCompositionalLayout { [weak self] sectionIndex, _ in
            guard let self = self else { return nil }
            let section = HomeSection(rawValue: sectionIndex) ?? .grid

            switch section {
            case .hero:
                return Self.heroSection()
            case .continueWatching:
                return Self.horizontalScrollSection()
            case .grid:
                return self.gridSection()
            }
        }
    }

    private static func heroSection() -> NSCollectionLayoutSection {
        let h = UIScreen.main.bounds.width * 0.56
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
        section.contentInsets = .init(top: 4, leading: 16, bottom: 16, trailing: 16)
        section.orthogonalScrollingBehavior = .continuous
        section.boundarySupplementaryItems = [headerItem()]
        return section
    }

    private func gridSection() -> NSCollectionLayoutSection {
        let side = (view.bounds.width - 12 * 2 - 10 * 2) / 3
        let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .absolute(side), heightDimension: .absolute(side * 1.6)))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .absolute(side * 1.6)), subitems: [item])
        group.interItemSpacing = .fixed(10)
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = .init(top: 4, leading: 12, bottom: 24, trailing: 12)
        section.boundarySupplementaryItems = [Self.headerItem()]
        return section
    }

    private static func headerItem() -> NSCollectionLayoutBoundarySupplementaryItem {
        .init(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .absolute(44)),
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
                cell.configure(with: item.movie?.thumbUrl, progress: item.progress ?? 0)
                return cell
            case .grid:
                let cell = cv.dequeueReusableCell(withReuseIdentifier: "Movie", for: ip) as! MovieCell
                if let movie = item.movie { cell.configure(with: movie) }
                return cell
            }
        }

        dataSource.supplementaryViewProvider = { cv, kind, ip in
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
        if movies.isEmpty {
            showSkeleton(true)
        }
        NetworkManager.shared.fetchHomeMovies { [weak self] fetched in
            guard let self = self else { return }
            self.movies = fetched
            self.heroMovies = Array(fetched.prefix(5))
            self.loadContinueWatching()
            self.collectionView.refreshControl?.endRefreshing()
            self.showSkeleton(false)
            self.applySnapshot()
        }
    }

    private func loadContinueWatching() {
        continueWatching = PlaybackStore.shared.history().map {
            HomeItem(movie: $0.movie, progress: 0)
        }
    }

    private func applySnapshot() {
        var sections: [HomeSection] = [.hero]
        if !continueWatching.isEmpty { sections.append(.continueWatching) }
        sections.append(.grid)

        var snap = NSDiffableDataSourceSnapshot<HomeSection, HomeItem>()
        snap.appendSections(sections)

        if !heroMovies.isEmpty {
            snap.appendItems(heroMovies.map { HomeItem(movie: $0) }, toSection: .hero)
        }
        if !continueWatching.isEmpty {
            snap.appendItems(continueWatching, toSection: .continueWatching)
        }
        snap.appendItems(movies.map { HomeItem(movie: $0) }, toSection: .grid)

        dataSource.apply(snap, animatingDifferences: false)
    }

    // MARK: - Pagination
    private func loadMore() {
        guard hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        let next = currentPage + 1
        NetworkManager.shared.fetchMoviesPage(next) { [weak self] new in
            guard let self = self else { return }
            self.isLoadingMore = false
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
        DiskCache.shared.remove("home")
        currentPage = 2
        hasMore = true
        isLoadingMore = false
        fetchData()
    }

    // MARK: - Navigation
    private func setupNavigationItems() {
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(image: UIImage(systemName: "square.grid.2x2"), style: .plain, target: self, action: #selector(openGenrePicker)),
            UIBarButtonItem(image: UIImage(systemName: "shuffle"), style: .plain, target: self, action: #selector(openRandom))
        ]
    }

    @objc private func openRandom() {
        guard let pick = movies.randomElement() else { return }
        coordinator?.showDetail(for: pick)
    }

    @objc private func openGenrePicker() {
        let vc = GenreSelectionViewController()
        let nav = UINavigationController(rootViewController: vc)
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        vc.onApply = { [weak self] genres in
            guard !genres.isEmpty else { return }
            self?.loadMultipleGenres(genres)
        }
        present(nav, animated: true)
    }

    private func loadMultipleGenres(_ genres: [(name: String, slug: String)]) {
        navigationItem.title = genres.map(\.name).joined(separator: ", ")
        spinner.startAnimating()
        collectionView.isHidden = true

        var allMovies: [Movie] = []
        var remaining = genres.map(\.slug)
        func next() {
            guard !remaining.isEmpty else {
                var seen = Set<String>()
                self.movies = allMovies.filter { seen.insert($0.link).inserted }
                self.spinner.stopAnimating()
                self.collectionView.isHidden = false
                self.applySnapshot()
                return
            }
            let slug = remaining.removeFirst()
            let url = "\(NetworkManager.shared.resolvedDomain)/the-loai/\(slug)/"
            NetworkManager.shared.fetchHTML(url: url) { html in
                NetworkManager.shared.parseMovies(html: html) { fetched in
                    allMovies.append(contentsOf: fetched)
                    next()
                }
            }
        }
        next()
    }

    // MARK: - Search
    private func setupSearch() {
        suggestionsVC.onSelect = { [weak self] movie in
            self?.navigationItem.searchController?.isActive = false
            self?.coordinator?.showDetail(for: movie)
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
        if ip.row >= movies.count - 6 { loadMore() }
    }

    func collectionView(_: UICollectionView, didSelectItemAt ip: IndexPath) {
        guard let item = dataSource.itemIdentifier(for: ip) else { return }
        if ip.section == HomeSection.grid.rawValue, let movie = item.movie {
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
        let work = DispatchWorkItem {
            NetworkManager.shared.fetchSearchSuggestions(keyword: text) { results in
                self.suggestionsVC.update(movies: results, query: text, loading: false)
            }
        }
        suggestWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        guard let text = searchBar.text, !text.isEmpty else { return }
        let keyword = text.folding(options: .diacriticInsensitive, locale: Locale(identifier: "vi_VN"))
            .replacingOccurrences(of: "đ", with: "d").replacingOccurrences(of: "Đ", with: "D")
            .lowercased().components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: "+")
        spinner.startAnimating()
        collectionView.isHidden = true
        let url = "\(NetworkManager.shared.resolvedDomain)/tim-kiem/\(keyword)/"
        NetworkManager.shared.fetchHTML(url: url) { html in
            NetworkManager.shared.parseMovies(html: html) { fetched in
                self.movies = fetched
                self.spinner.stopAnimating()
                self.collectionView.isHidden = false
                self.applySnapshot()
            }
        }
    }

    func searchBarCancelButtonClicked(_: UISearchBar) {
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
        imageView.image = nil
    }

    func configure(with movie: Movie) {
        titleLabel.text = movie.title
        genreLabel.text = movie.episodeStatus
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
            progressBar.bottomAnchor.constraint(equalTo: progressTrack.bottomAnchor),
            progressBar.widthAnchor.constraint(equalTo: progressTrack.widthAnchor, multiplier: 0.6)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = nil
    }

    func configure(with thumbUrl: String?, progress: Double) {
        if let urlStr = thumbUrl, let url = URL(string: urlStr) {
            ImageLoader.shared.load(url, into: imageView)
        }
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
        imageView.image = nil
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
    }
}
