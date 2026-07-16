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

        let bgView = BackgroundView()
        bgView.setStyle(.default)
        bgView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bgView)
        view.sendSubviewToBack(bgView)
        NSLayoutConstraint.activate([
            bgView.topAnchor.constraint(equalTo: view.topAnchor),
            bgView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bgView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bgView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        tableView.frame = view.bounds
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 84
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.contentInset = UIEdgeInsets(top: 8, left: 0, bottom: 12, right: 0)
        tableView.register(SuggestionCell.self, forCellReuseIdentifier: "SugCell")
        tableView.tableFooterView = UIView()
        view.addSubview(tableView)

        emptyLabel.font = .preferredFont(forTextStyle: .body)
        emptyLabel.adjustsFontForContentSizeCategory = true
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
    private let cardView = UIView()
    private let poster = UIImageView()
    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none

        cardView.backgroundColor = .secondarySystemBackground
        cardView.layer.cornerRadius = 14
        cardView.clipsToBounds = true
        cardView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cardView)

        poster.contentMode = .scaleAspectFill
        poster.clipsToBounds = true
        poster.layer.cornerRadius = 8
        poster.backgroundColor = .tertiarySystemFill
        poster.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = .preferredFont(forTextStyle: .caption1)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 1
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        chevron.tintColor = .tertiaryLabel
        chevron.contentMode = .scaleAspectFit
        chevron.translatesAutoresizingMaskIntoConstraints = false

        cardView.addSubview(poster)
        cardView.addSubview(titleLabel)
        cardView.addSubview(statusLabel)
        cardView.addSubview(chevron)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),

            poster.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 10),
            poster.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 8),
            poster.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -8),
            poster.widthAnchor.constraint(equalToConstant: 46),

            titleLabel.leadingAnchor.constraint(equalTo: poster.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -8),
            titleLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 12),

            statusLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            statusLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),

            chevron.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -12),
            chevron.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 10)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        ImageLoader.shared.cancelLoad(for: poster)
        poster.image = nil
        poster.tag = 0
        titleLabel.text = nil
        statusLabel.text = nil
    }

    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        let changes = {
            self.cardView.transform = highlighted ? CGAffineTransform(scaleX: 0.985, y: 0.985) : .identity
            self.cardView.alpha = highlighted ? 0.82 : 1
        }
        if animated {
            UIView.animate(withDuration: 0.12, delay: 0, options: [.beginFromCurrentState, .curveEaseOut], animations: changes)
        } else {
            changes()
        }
    }

    func configure(with movie: Movie) {
        titleLabel.text = movie.title
        statusLabel.text = movie.episodeStatus
        if let url = URL(string: movie.thumbUrl) {
            ImageLoader.shared.load(url, into: poster)
        }
        isAccessibilityElement = true
        accessibilityLabel = movie.title
        accessibilityValue = movie.episodeStatus.isEmpty ? nil : movie.episodeStatus
        accessibilityTraits = .button
    }
}
