import UIKit

/// Hiển thị live suggestions khi user gõ trên search bar Home.
/// Mỗi hàng có poster trái + title + episode status, tap để mở MovieInfoVC.
class SearchSuggestionsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyLabel = UILabel()
    private let loader = UIActivityIndicatorView(style: .medium)

    var movies: [Movie] = []
    private var lastQuery: String = ""
    private var loading: Bool = false

    var onSelect: ((Movie) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        tableView.frame = view.bounds
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 72
        tableView.register(SuggestionCell.self, forCellReuseIdentifier: "SugCell")
        tableView.tableFooterView = UIView()
        view.addSubview(tableView)

        emptyLabel.font = .systemFont(ofSize: 14)
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)
        loader.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(loader)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            loader.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loader.centerYAnchor.constraint(equalTo: emptyLabel.centerYAnchor, constant: -32)
        ])
        refreshState()
    }

    func update(movies: [Movie], query: String, loading: Bool) {
        self.movies = movies
        self.lastQuery = query
        self.loading = loading
        loadViewIfNeeded()
        tableView.reloadData()
        refreshState()
    }

    private func refreshState() {
        if loading {
            loader.startAnimating()
            emptyLabel.text = "Đang tìm \"\(lastQuery)\"..."
            emptyLabel.isHidden = false
            tableView.isHidden = movies.isEmpty
        } else {
            loader.stopAnimating()
            if movies.isEmpty {
                emptyLabel.text = lastQuery.isEmpty ? "Gõ để tìm phim" : "Không tìm thấy \"\(lastQuery)\""
                emptyLabel.isHidden = false
                tableView.isHidden = true
            } else {
                emptyLabel.isHidden = true
                tableView.isHidden = false
            }
        }
    }

    // MARK: - UITableView

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { movies.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SugCell", for: indexPath) as! SuggestionCell
        cell.configure(with: movies[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        onSelect?(movies[indexPath.row])
    }
}

// MARK: - Suggestion cell

final class SuggestionCell: UITableViewCell {
    private let poster = UIImageView()
    private let titleLabel = UILabel()
    private let statusLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .default

        poster.contentMode = .scaleAspectFill
        poster.clipsToBounds = true
        poster.layer.cornerRadius = 6
        poster.backgroundColor = .tertiarySystemFill
        poster.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 14.5, weight: .semibold)
        titleLabel.numberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 1
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(poster)
        contentView.addSubview(titleLabel)
        contentView.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            poster.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            poster.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            poster.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            poster.widthAnchor.constraint(equalToConstant: 42),

            titleLabel.leadingAnchor.constraint(equalTo: poster.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),

            statusLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            statusLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        poster.image = nil
        titleLabel.text = nil
        statusLabel.text = nil
    }

    func configure(with movie: Movie) {
        titleLabel.text = movie.title
        statusLabel.text = movie.episodeStatus
        if let url = URL(string: movie.thumbUrl) {
            ImageLoader.shared.load(url, into: poster)
        }
    }
}
