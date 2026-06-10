import UIKit

class EpisodeListViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    var movie: Movie?
    var episodes: [Episode] = []
    var collectionView: UICollectionView!
    private let loader = UIActivityIndicatorView(style: .large)

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = movie?.title
        self.view.backgroundColor = .systemBackground

        setupCollectionView()
        setupLoader()
        fetchEpisodes()
    }

    private func setupCollectionView() {
        let layout = UICollectionViewFlowLayout()
        let columns: CGFloat = 5
        let interItem: CGFloat = 8
        let sideInset: CGFloat = 12
        let totalSpacing = sideInset * 2 + interItem * (columns - 1)
        let cellWidth = (view.bounds.width - totalSpacing) / columns
        layout.itemSize = CGSize(width: cellWidth, height: 48)
        layout.minimumLineSpacing = interItem
        layout.minimumInteritemSpacing = interItem
        layout.sectionInset = UIEdgeInsets(top: 16, left: sideInset, bottom: 16, right: sideInset)

        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.alwaysBounceVertical = true
        collectionView.register(EpisodeCell.self, forCellWithReuseIdentifier: "EpisodeCell")

        let refresh = UIRefreshControl()
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
        cell.configure(with: episodes[indexPath.row], number: indexPath.row + 1)
        return cell
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

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .secondarySystemBackground
        contentView.layer.cornerRadius = 8
        contentView.clipsToBounds = true
        contentView.layer.borderWidth = 1
        contentView.layer.borderColor = UIColor.separator.cgColor

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

    func configure(with episode: Episode, number: Int) {
        // Trích số tập nếu có; nếu không thì show số thứ tự
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
                self.contentView.backgroundColor = self.isHighlighted ? .systemFill : .secondarySystemBackground
            }
        }
    }
}
