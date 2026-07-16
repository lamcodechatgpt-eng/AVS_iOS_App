import UIKit

class EpisodeListViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    var movie: Movie?
    var episodes: [Episode] = []
    var collectionView: UICollectionView!
    private let loader = UIActivityIndicatorView(style: .large)
    private let emptyLabel = UILabel()
    private var lastLayoutWidth: CGFloat = 0

    private let bgView = BackgroundView()

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = movie?.title

        setupBackground()
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

    private func setupBackground() {
        bgView.setStyle(.accent)
        bgView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bgView)
        view.sendSubviewToBack(bgView)
        NSLayoutConstraint.activate([
            bgView.topAnchor.constraint(equalTo: view.topAnchor),
            bgView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bgView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bgView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
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
        refresh.tintColor = .label
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
        emptyLabel.font = .preferredFont(forTextStyle: .body)
        emptyLabel.adjustsFontForContentSizeCategory = true
        emptyLabel.textColor = .secondaryLabel
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
            self?.episodes = fetched
            self?.loader.stopAnimating()
            self?.collectionView.refreshControl?.endRefreshing()
            self?.collectionView.reloadData()
            self?.emptyLabel.isHidden = !fetched.isEmpty
        }
    }

    // MARK: - UICollectionViewDataSource
    func collectionView(_ cv: UICollectionView, numberOfItemsInSection s: Int) -> Int { episodes.count }

    func collectionView(_ cv: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = cv.dequeueReusableCell(withReuseIdentifier: "EpisodeCell", for: indexPath) as! EpisodeCell
        let ep = episodes[indexPath.row]
        let hasPosition = PlaybackStore.shared.position(for: ep.link) != nil
        cell.configure(with: ep, number: indexPath.row + 1, watched: hasPosition)
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
    private var isWatched = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = 10
        contentView.clipsToBounds = true

        statusIcon.contentMode = .scaleAspectFit
        statusIcon.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(statusIcon)

        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textColor = .label
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
            label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(with episode: Episode, number: Int, watched: Bool = false) {
        isWatched = watched
        accessibilityLabel = episode.title.isEmpty ? "Tập \(number)" : episode.title
        accessibilityValue = watched ? "Đã xem một phần" : "Chưa xem"
        accessibilityTraits = .button
        if watched {
            contentView.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.1)
            contentView.layer.borderWidth = 1
            contentView.layer.borderColor = UIColor.systemGreen.withAlphaComponent(0.3).cgColor
            label.textColor = .systemGreen
            statusIcon.image = UIImage(systemName: "checkmark.circle.fill")
            statusIcon.tintColor = .systemGreen
        } else {
            contentView.backgroundColor = .secondarySystemBackground
            contentView.layer.borderWidth = 1
            contentView.layer.borderColor = UIColor.separator.cgColor
            label.textColor = .label
            statusIcon.image = UIImage(systemName: "play.circle")
            statusIcon.tintColor = .secondaryLabel
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
                let base = self.isWatched ? UIColor.systemGreen.withAlphaComponent(0.1) : UIColor.secondarySystemBackground
                self.contentView.backgroundColor = self.isHighlighted ? UIColor.systemFill : base
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.96, y: 0.96) : .identity
            }
        }
    }
}
