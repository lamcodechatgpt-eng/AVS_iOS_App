import UIKit

class EpisodeListViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    var movie: Movie?
    var episodes: [Episode] = []
    var collectionView: UICollectionView!
    private let loader = UIActivityIndicatorView(style: .large)
    private let emptyLabel = UILabel()
    private var lastLayoutWidth: CGFloat = 0
    private var currentEpisodeIndex: Int?

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = movie?.title
        view.backgroundColor = AppTheme.backgroundDark

        setupCollectionView()
        setupLoader()
        setupEmptyLabel()
        fetchEpisodes()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate { _ in
            self.updateCollectionViewLayout(for: size.width)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = collectionView.bounds.width
        guard abs(width - lastLayoutWidth) > 0.5 else { return }
        lastLayoutWidth = width
        updateCollectionViewLayout(for: width)
    }

    private func updateCollectionViewLayout(for width: CGFloat) {
        guard let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout else { return }
        let interItem: CGFloat = 8
        let sideInset: CGFloat = 12
        let columns = max(4, min(10, Int((width - sideInset * 2 + interItem) / 68)))
        let totalSpacing = sideInset * 2 + interItem * CGFloat(columns - 1)
        let cellWidth = (width - totalSpacing) / CGFloat(columns)
        layout.itemSize = CGSize(width: cellWidth, height: 50)
        layout.headerReferenceSize = CGSize(width: width, height: 40)
        layout.invalidateLayout()
    }

    private func setupCollectionView() {
        let layout = UICollectionViewFlowLayout()
        let interItem: CGFloat = 8
        let sideInset: CGFloat = 12
        layout.itemSize = CGSize(width: 60, height: 50)
        layout.minimumLineSpacing = 10
        layout.minimumInteritemSpacing = interItem
        layout.sectionInset = UIEdgeInsets(top: 16, left: sideInset, bottom: 16, right: sideInset)
        layout.headerReferenceSize = CGSize(width: view.bounds.width, height: 40)

        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.alwaysBounceVertical = true
        collectionView.register(EpisodeCell.self, forCellWithReuseIdentifier: "EpisodeCell")
        collectionView.register(SectionHeader.self,
                                forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                                withReuseIdentifier: "Header")

        let refresh = UIRefreshControl()
        refresh.tintColor = AppTheme.textPrimary
        refresh.addTarget(self, action: #selector(refresh(_:)), for: .valueChanged)
        collectionView.refreshControl = refresh

        view.addSubview(collectionView)
    }

    private func setupLoader() {
        loader.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(loader)
        NSLayoutConstraint.activate([
            loader.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loader.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func setupEmptyLabel() {
        emptyLabel.text = "Không tải được danh sách tập.\nKéo xuống để thử lại."
        emptyLabel.font = AppTheme.Fonts.body(size: 15)
        emptyLabel.adjustsFontForContentSizeCategory = true
        emptyLabel.textColor = AppTheme.textSecondary
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.isHidden = true
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24)
        ])
    }

    @objc private func refresh(_ rc: UIRefreshControl) {
        // Xoá cache để fetch lại
        if let url = movie?.link {
            let normalized = NetworkManager.shared.normalizeURL(url)
            let key = "episodes." + (normalized.data(using: .utf8)?.base64EncodedString() ?? normalized)
            DiskCache.shared.remove(key)
        }
        fetchEpisodes()
    }

    private func fetchEpisodes() {
        guard let movie = movie else { return }
        emptyLabel.isHidden = true
        if episodes.isEmpty { loader.startAnimating() }
        NetworkManager.shared.fetchEpisodes(movieUrl: movie.link) { [weak self] fetched in
            guard let self = self else { return }
            self.episodes = fetched
            self.currentEpisodeIndex = self.findCurrentEpisodeIndex(in: fetched, movie: movie)
            self.loader.stopAnimating()
            self.collectionView.refreshControl?.endRefreshing()
            self.collectionView.reloadData()
            self.emptyLabel.isHidden = !fetched.isEmpty
            if let index = self.currentEpisodeIndex, fetched.indices.contains(index) {
                DispatchQueue.main.async {
                    guard self.collectionView.numberOfItems(inSection: 0) > index else { return }
                    self.collectionView.scrollToItem(at: IndexPath(item: index, section: 0),
                                                     at: .centeredVertically,
                                                     animated: false)
                }
            }
        }
    }

    private func findCurrentEpisodeIndex(in fetched: [Episode], movie: Movie) -> Int? {
        guard let entry = PlaybackStore.shared.history().first(where: {
            $0.movie.persistenceID == movie.persistenceID && $0.isCompleted != true
        }) else { return nil }
        if let url = entry.lastEpisodeURL {
            let identifier = ContentIdentifier.make(from: url)
            if let index = fetched.firstIndex(where: { $0.persistenceID == identifier }) {
                return index
            }
        }
        return fetched.indices.contains(entry.lastEpisodeIndex) ? entry.lastEpisodeIndex : nil
    }

    // MARK: - UICollectionViewDataSource
    func collectionView(_ cv: UICollectionView, numberOfItemsInSection s: Int) -> Int { episodes.count }

    func collectionView(_ cv: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = cv.dequeueReusableCell(withReuseIdentifier: "EpisodeCell", for: indexPath) as! EpisodeCell
        let ep = episodes[indexPath.row]
        let progress = PlaybackStore.shared.progress(for: ep.link) ?? 0
        cell.configure(with: ep,
                       number: indexPath.row + 1,
                       watched: progress > 0,
                       progress: progress,
                       isCurrent: indexPath.row == currentEpisodeIndex)
        return cell
    }

    func collectionView(_ cv: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        let h = cv.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "Header", for: indexPath) as! SectionHeader
        h.configure(title: "Danh sách tập", detail: "\(episodes.count) tập")
        return h
    }

    // MARK: - UICollectionViewDelegate
    func collectionView(_ cv: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let playerVC = PlayerController()
        playerVC.episodes = episodes
        playerVC.currentIndex = indexPath.row
        playerVC.episodeUrl = episodes[indexPath.row].link
        playerVC.movie = movie
        self.navigationController?.pushViewController(playerVC, animated: true)
    }
}

// MARK: - Episode Cell
class EpisodeCell: UICollectionViewCell {
    private let label = UILabel()
    private let statusIcon = UIImageView()
    private let progressView = UIProgressView(progressViewStyle: .bar)
    private var isWatched = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = 10
        contentView.clipsToBounds = true

        progressView.trackTintColor = AppTheme.surfaceGlass
        progressView.progressTintColor = AppTheme.primaryAccent
        progressView.layer.cornerRadius = 1.5
        progressView.clipsToBounds = true
        progressView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(progressView)

        statusIcon.contentMode = .scaleAspectFit
        statusIcon.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(statusIcon)

        label.font = AppTheme.Fonts.subhead(size: 14)
        label.textColor = AppTheme.textPrimary
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.7
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)

        NSLayoutConstraint.activate([
            statusIcon.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            statusIcon.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            statusIcon.widthAnchor.constraint(equalToConstant: 14),
            statusIcon.heightAnchor.constraint(equalTo: statusIcon.widthAnchor),
            label.leadingAnchor.constraint(equalTo: statusIcon.trailingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            progressView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            progressView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            progressView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -3),
            progressView.heightAnchor.constraint(equalToConstant: 3)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(with episode: Episode,
                   number: Int,
                   watched: Bool = false,
                   progress: Double = 0,
                   isCurrent: Bool = false) {
        isWatched = watched
        accessibilityLabel = episode.title.isEmpty ? "Tập \(number)" : episode.title
        accessibilityValue = watched
            ? "Đã xem \(Int((min(max(progress, 0), 1) * 100).rounded())) phần trăm"
            : "Chưa xem"
        accessibilityTraits = .button
        progressView.progress = Float(min(max(progress, 0), 1))
        progressView.isHidden = progress <= 0
        accessibilityHint = isCurrent ? "Tập đang xem dở" : nil
        if watched {
            contentView.backgroundColor = AppTheme.primaryAccent.withAlphaComponent(0.2)
            contentView.layer.borderWidth = 1
            contentView.layer.borderColor = AppTheme.primaryAccent.withAlphaComponent(0.4).cgColor
            label.textColor = AppTheme.primaryAccent
            statusIcon.image = UIImage(systemName: "checkmark.circle.fill")
            statusIcon.tintColor = AppTheme.primaryAccent
        } else {
            contentView.backgroundColor = AppTheme.cardBackground
            contentView.layer.borderWidth = 1
            contentView.layer.borderColor = AppTheme.surfaceGlass.cgColor
            label.textColor = AppTheme.textPrimary
            statusIcon.image = UIImage(systemName: "play.circle")
            statusIcon.tintColor = AppTheme.textSecondary
        }

        if isCurrent {
            contentView.layer.borderWidth = 2
            contentView.layer.borderColor = AppTheme.secondaryAccent.cgColor
            accessibilityTraits.insert(.selected)
        }

        let raw = episode.title.lowercased()
        if let _ = raw.range(of: #"tập\s*\d+"#, options: .regularExpression),
           let m = raw.range(of: #"\d+"#, options: .regularExpression) {
            label.text = String(raw[m])
        } else if !episode.title.isEmpty {
            label.text = episode.title.replacingOccurrences(of: "Tập", with: "").trimmingCharacters(in: .whitespaces)
            if label.text?.isEmpty == true { label.text = "\(number)" }
        } else {
            label.text = "\(number)"
        }
    }

    override var isHighlighted: Bool {
        didSet {
            guard !UIAccessibility.isReduceMotionEnabled else { return }
            UIView.animate(withDuration: 0.15, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) {
                let base = self.isWatched ? AppTheme.primaryAccent.withAlphaComponent(0.2) : AppTheme.cardBackground
                self.contentView.backgroundColor = self.isHighlighted ? AppTheme.surfaceGlass : base
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.96, y: 0.96) : .identity
            }
        }
    }
}
