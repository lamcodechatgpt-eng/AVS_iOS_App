import UIKit

class EpisodeListViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    var movie: Movie?
    var episodes: [Episode] = []
    var collectionView: UICollectionView!
    private let loader = UIActivityIndicatorView(style: .large)

    private let bgView = BackgroundView()

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = movie?.title

        setupBackground()
        setupCollectionView()
        setupLoader()
        fetchEpisodes()
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
        let columns: CGFloat = 5
        let interItem: CGFloat = 8
        let sideInset: CGFloat = 12
        let totalSpacing = sideInset * 2 + interItem * (columns - 1)
        let cellWidth = (view.bounds.width - totalSpacing) / columns
        layout.itemSize = CGSize(width: cellWidth, height: 50)
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

    @objc private func refresh(_ rc: UIRefreshControl) {
        // Xoá cache để fetch lại
        if let url = movie?.link {
            let key = "episodes." + (url.data(using: .utf8)?.base64EncodedString() ?? url)
            DiskCache.shared.remove(key)
        }
        fetchEpisodes()
    }

    private func fetchEpisodes() {
        guard let movie = movie else { return }
        if episodes.isEmpty { loader.startAnimating() }
        NetworkManager.shared.fetchEpisodes(movieUrl: movie.link) { [weak self] fetched in
            self?.episodes = fetched
            self?.loader.stopAnimating()
            self?.collectionView.refreshControl?.endRefreshing()
            self?.collectionView.reloadData()
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
        h.titleLabel.text = "📺 Danh sách tập (\(episodes.count) tập)"
        return h
    }

    // MARK: - UICollectionViewDelegate
    func collectionView(_ cv: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let playerVC = PlayerController()
        playerVC.episodes = episodes
        playerVC.currentIndex = indexPath.row
        playerVC.episodeUrl = episodes[indexPath.row].link
        self.navigationController?.pushViewController(playerVC, animated: true)
    }
}

// MARK: - Episode Cell
class EpisodeCell: UICollectionViewCell {
    private let label = UILabel()
    private var isWatched = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = 10
        contentView.clipsToBounds = true

        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textColor = .label
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.7
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(with episode: Episode, number: Int, watched: Bool = false) {
        isWatched = watched
        if watched {
            contentView.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.1)
            contentView.layer.borderWidth = 1
            contentView.layer.borderColor = UIColor.systemGreen.withAlphaComponent(0.3).cgColor
            label.textColor = .systemGreen
        } else {
            contentView.backgroundColor = .secondarySystemBackground
            contentView.layer.borderWidth = 1
            contentView.layer.borderColor = UIColor.separator.cgColor
            label.textColor = .label
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
            UIView.animate(withDuration: 0.15) {
                let base = self.isWatched ? UIColor.systemGreen.withAlphaComponent(0.1) : UIColor.secondarySystemBackground
                self.contentView.backgroundColor = self.isHighlighted ? UIColor.systemFill : base
            }
        }
    }
}
