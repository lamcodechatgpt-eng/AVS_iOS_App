import UIKit

/// VC dùng chung cho Lịch sử và Yêu thích — render danh sách Movie giống Home
/// nhưng đọc từ PlaybackStore thay vì NetworkManager.
class MovieListViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    enum Source {
        case history
        case favorites

        var title: String {
            switch self {
            case .history: return "Lịch sử"
            case .favorites: return "Yêu thích"
            }
        }
        var emptyText: String {
            switch self {
            case .history: return "Bạn chưa xem phim nào.\nLịch sử sẽ xuất hiện sau khi bạn xem."
            case .favorites: return "Chưa có phim yêu thích.\nMở 1 phim, bấm ❤️ để thêm."
            }
        }
    }

    var source: Source = .history

    private var collectionView: UICollectionView!
    private var movies: [Movie] = []
    private var historySubtitles: [Int: String] = [:]
    private let emptyLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = source.title
        view.backgroundColor = .systemBackground
        setupCollection()
        setupEmptyLabel()
        if source == .history {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                image: UIImage(systemName: "trash"),
                style: .plain,
                target: self,
                action: #selector(clearAll)
            )
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    private func setupCollection() {
        let layout = UICollectionViewFlowLayout()
        let columns: CGFloat = 3
        let interItem: CGFloat = 10
        let sideInset: CGFloat = 12
        let totalSpacing = sideInset * 2 + interItem * (columns - 1)
        let cellWidth = (view.bounds.width - totalSpacing) / columns
        layout.itemSize = CGSize(width: cellWidth, height: cellWidth * 1.5)
        layout.minimumLineSpacing = interItem
        layout.minimumInteritemSpacing = interItem
        layout.sectionInset = UIEdgeInsets(top: 12, left: sideInset, bottom: 12, right: sideInset)

        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.alwaysBounceVertical = true
        collectionView.register(MovieCell.self, forCellWithReuseIdentifier: "MovieCell")
        view.addSubview(collectionView)
    }

    private func setupEmptyLabel() {
        emptyLabel.text = source.emptyText
        emptyLabel.font = .systemFont(ofSize: 14)
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)
        ])
    }

    private func reload() {
        historySubtitles.removeAll()
        switch source {
        case .history:
            let entries = PlaybackStore.shared.history()
            movies = entries.map { $0.movie }
            for (idx, e) in entries.enumerated() {
                historySubtitles[idx] = "▶ \(e.lastEpisodeTitle)"
            }
        case .favorites:
            movies = PlaybackStore.shared.favorites()
        }
        collectionView.reloadData()
        emptyLabel.isHidden = !movies.isEmpty
    }

    @objc private func clearAll() {
        let alert = UIAlertController(title: "Xoá toàn bộ lịch sử?", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Huỷ", style: .cancel))
        alert.addAction(UIAlertAction(title: "Xoá", style: .destructive) { [weak self] _ in
            PlaybackStore.shared.clearHistory()
            self?.reload()
        })
        present(alert, animated: true)
    }

    // MARK: - DataSource

    func collectionView(_ cv: UICollectionView, numberOfItemsInSection section: Int) -> Int { movies.count }

    func collectionView(_ cv: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = cv.dequeueReusableCell(withReuseIdentifier: "MovieCell", for: indexPath) as! MovieCell
        var m = movies[indexPath.row]
        if let subtitle = historySubtitles[indexPath.row], !subtitle.isEmpty {
            // Tận dụng episodeStatus làm subtitle hiển thị "▶ Tập X"
            m.episodeStatus = subtitle
        }
        cell.configure(with: m)
        return cell
    }

    func collectionView(_ cv: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let infoVC = MovieInfoViewController()
        infoVC.movie = movies[indexPath.row]
        navigationController?.pushViewController(infoVC, animated: true)
    }
}
