import UIKit

class MovieInfoViewController: UIViewController {

    var movie: Movie!

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let bannerImage = UIImageView()
    private let titleLabel = UILabel()
    private let metaLabel = UILabel()
    private let descLabel = UILabel()
    private let genreStack = UIStackView()
    private let watchButton = UIButton(type: .system)
    private let favButton = UIButton(type: .system)
    private let continueButton = UIButton(type: .system)
    private let loader = UIActivityIndicatorView(style: .medium)

    private var episodes: [Episode] = []
    private var details: MovieDetails?
    private var resumeEpisodeIndex: Int?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = movie.title

        setupNavBar()
        setupViews()
        bindMovie()
        fetchDetails()
        fetchEpisodes()
        loadResumeIfAny()

        // Lịch sử được ghi khi user thực sự bấm play, không phải mở info → ko log ở đây.
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadResumeIfAny()    // Quay lại từ player → refresh nút "Tiếp tục"
        refreshFavButton()
    }

    private func setupNavBar() {
        favButton.translatesAutoresizingMaskIntoConstraints = false
        let barItem = UIBarButtonItem(image: UIImage(systemName: "heart"),
                                      style: .plain,
                                      target: self,
                                      action: #selector(toggleFavorite))
        navigationItem.rightBarButtonItem = barItem
        refreshFavButton()
    }

    private func refreshFavButton() {
        let isFav = PlaybackStore.shared.isFavorite(movie)
        let img = UIImage(systemName: isFav ? "heart.fill" : "heart")
        navigationItem.rightBarButtonItem?.image = img
        navigationItem.rightBarButtonItem?.tintColor = isFav ? .systemRed : .label
    }

    @objc private func toggleFavorite() {
        _ = PlaybackStore.shared.toggleFavorite(movie)
        refreshFavButton()
    }

    private func setupViews() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        let bannerHeightConstraint: NSLayoutConstraint
        bannerImage.contentMode = .scaleAspectFill
        bannerImage.clipsToBounds = true
        bannerImage.backgroundColor = .tertiarySystemFill
        bannerImage.translatesAutoresizingMaskIntoConstraints = false
        let bannerWrap = UIView()
        bannerWrap.clipsToBounds = true
        bannerWrap.addSubview(bannerImage)
        bannerHeightConstraint = bannerImage.heightAnchor.constraint(equalTo: bannerImage.widthAnchor, multiplier: 9.0/16.0)
        NSLayoutConstraint.activate([
            bannerImage.topAnchor.constraint(equalTo: bannerWrap.topAnchor),
            bannerImage.leadingAnchor.constraint(equalTo: bannerWrap.leadingAnchor),
            bannerImage.trailingAnchor.constraint(equalTo: bannerWrap.trailingAnchor),
            bannerImage.bottomAnchor.constraint(equalTo: bannerWrap.bottomAnchor),
            bannerHeightConstraint
        ])

        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        titleLabel.numberOfLines = 0
        metaLabel.font = .systemFont(ofSize: 13)
        metaLabel.textColor = .secondaryLabel
        metaLabel.numberOfLines = 1

        descLabel.font = .systemFont(ofSize: 15)
        descLabel.textColor = .label
        descLabel.numberOfLines = 0

        genreStack.axis = .horizontal
        genreStack.spacing = 8
        genreStack.distribution = .fillProportionally
        let genreScroll = UIScrollView()
        genreScroll.showsHorizontalScrollIndicator = false
        genreScroll.translatesAutoresizingMaskIntoConstraints = false
        genreScroll.addSubview(genreStack)
        genreStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            genreStack.topAnchor.constraint(equalTo: genreScroll.topAnchor),
            genreStack.leadingAnchor.constraint(equalTo: genreScroll.leadingAnchor),
            genreStack.trailingAnchor.constraint(equalTo: genreScroll.trailingAnchor),
            genreStack.bottomAnchor.constraint(equalTo: genreScroll.bottomAnchor),
            genreStack.heightAnchor.constraint(equalTo: genreScroll.heightAnchor)
        ])

        watchButton.setTitle("▶  Xem từ đầu", for: .normal)
        styleAccentButton(watchButton)
        watchButton.addTarget(self, action: #selector(watchFromBeginning), for: .touchUpInside)

        continueButton.setTitle("⏵ Đang tải...", for: .normal)
        styleAccentButton(continueButton, accent: false)
        continueButton.addTarget(self, action: #selector(continueWatching), for: .touchUpInside)
        continueButton.isHidden = true

        let buttonsRow = UIStackView(arrangedSubviews: [continueButton, watchButton])
        buttonsRow.axis = .horizontal
        buttonsRow.spacing = 12
        buttonsRow.distribution = .fillEqually

        loader.startAnimating()

        let allEpisodesButton = UIButton(type: .system)
        allEpisodesButton.setTitle("📺  Danh sách tập", for: .normal)
        styleAccentButton(allEpisodesButton, accent: false)
        allEpisodesButton.addTarget(self, action: #selector(showAllEpisodes), for: .touchUpInside)

        [bannerWrap, titleLabel, metaLabel, genreScroll, buttonsRow, allEpisodesButton, descLabel, loader].forEach { stack.addArrangedSubview($0) }

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -32),
            genreScroll.heightAnchor.constraint(equalToConstant: 34)
        ])
    }

    private func styleAccentButton(_ btn: UIButton, accent: Bool = true) {
        btn.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        btn.backgroundColor = accent ? .systemRed : .secondarySystemFill
        btn.setTitleColor(accent ? .white : .label, for: .normal)
        btn.layer.cornerRadius = 12
        btn.clipsToBounds = true
        btn.contentEdgeInsets = UIEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
    }

    private func bindMovie() {
        titleLabel.text = movie.title
        metaLabel.text = movie.episodeStatus
        // Dùng poster làm placeholder banner cho đến khi có ảnh chính từ details.
        if let url = URL(string: movie.thumbUrl) {
            ImageLoader.shared.load(url, into: bannerImage)
        }
    }

    private func fetchDetails() {
        NetworkManager.shared.fetchMovieDetails(movieUrl: movie.link) { [weak self] details in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.details = details
                self.applyDetails()
            }
        }
    }

    private func applyDetails() {
        guard let d = details else { return }
        var metaParts: [String] = []
        if !d.year.isEmpty { metaParts.append(d.year) }
        if !d.rating.isEmpty { metaParts.append("⭐ \(d.rating)") }
        if !movie.episodeStatus.isEmpty { metaParts.append(movie.episodeStatus) }
        metaLabel.text = metaParts.joined(separator: "  •  ")

        descLabel.text = d.description.isEmpty ? "(Chưa có mô tả)" : d.description

        // Banner thật từ details nếu có.
        if !d.bannerUrl.isEmpty, let url = URL(string: d.bannerUrl) {
            ImageLoader.shared.load(url, into: bannerImage)
        }

        // Genre chips
        genreStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for g in d.genres.prefix(8) {
            let chip = UILabel()
            chip.text = "  \(g)  "
            chip.font = .systemFont(ofSize: 12, weight: .semibold)
            chip.textColor = .systemRed
            chip.backgroundColor = UIColor.systemRed.withAlphaComponent(0.1)
            chip.layer.cornerRadius = 12
            chip.clipsToBounds = true
            genreStack.addArrangedSubview(chip)
        }
    }

    private func fetchEpisodes() {
        NetworkManager.shared.fetchEpisodes(movieUrl: movie.link) { [weak self] eps in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.episodes = eps
                self.loader.stopAnimating()
                self.loader.isHidden = true
                self.watchButton.setTitle("▶  Xem tập 1", for: .normal)
                self.loadResumeIfAny()
            }
        }
    }

    private func loadResumeIfAny() {
        // Tìm tập gần nhất user đã xem từ HistoryEntry; nếu không có, check
        // positionMap cho từng episode trong danh sách.
        let history = PlaybackStore.shared.history()
        if let h = history.first(where: { $0.movie.link == movie.link }),
           h.lastEpisodeIndex < episodes.count {
            resumeEpisodeIndex = h.lastEpisodeIndex
            continueButton.setTitle("⏵ Tiếp tục \(h.lastEpisodeTitle)", for: .normal)
            continueButton.isHidden = false
            return
        }
        continueButton.isHidden = true
        resumeEpisodeIndex = nil
    }

    // MARK: - Actions

    @objc private func watchFromBeginning() {
        guard !episodes.isEmpty else { return }
        openPlayer(at: 0)
    }

    @objc private func continueWatching() {
        guard let idx = resumeEpisodeIndex, idx < episodes.count else { return }
        openPlayer(at: idx)
    }

    @objc private func showAllEpisodes() {
        let listVC = EpisodeListViewController()
        listVC.movie = movie
        navigationController?.pushViewController(listVC, animated: true)
    }

    private func openPlayer(at index: Int) {
        let playerVC = PlayerController()
        playerVC.episodes = episodes
        playerVC.currentIndex = index
        playerVC.episodeUrl = episodes[index].link
        playerVC.movie = movie
        navigationController?.pushViewController(playerVC, animated: true)
    }
}
