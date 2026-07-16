import UIKit

class GenreSelectionViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    private var genres: [GenreOption] = [
        GenreOption(name: "Hành Động", slug: "hanh-dong"), GenreOption(name: "Phiêu Lưu", slug: "phieu-luu"),
        GenreOption(name: "Hài Hước", slug: "hai-huoc"), GenreOption(name: "Tình Cảm", slug: "tinh-cam"),
        GenreOption(name: "Ma Thuật", slug: "ma-thuat"), GenreOption(name: "Viễn Tưởng", slug: "vien-tuong"),
        GenreOption(name: "Kinh Dị", slug: "kinh-di"), GenreOption(name: "Đời Thường", slug: "doi-thuong"),
        GenreOption(name: "Trường Học", slug: "truong-hoc"), GenreOption(name: "Thể Thao", slug: "the-thao"),
        GenreOption(name: "Drama", slug: "drama"), GenreOption(name: "Fantasy", slug: "fantasy"),
        GenreOption(name: "Harem", slug: "harem"), GenreOption(name: "Shounen", slug: "shounen"),
        GenreOption(name: "Mecha", slug: "mecha"), GenreOption(name: "Ecchi", slug: "ecchi"),
        GenreOption(name: "Mystery", slug: "mystery"), GenreOption(name: "Siêu Nhiên", slug: "sieu-nhien"),
        GenreOption(name: "Âm Nhạc", slug: "am-nhac"), GenreOption(name: "Lịch Sử", slug: "lich-su"),
        GenreOption(name: "Trò Chơi", slug: "tro-choi")
    ]
    
    var selectedSlugs = Set<String>()
    var onApply: (([GenreOption]) -> Void)?
    
    private var collectionView: UICollectionView!
    private var applyButton: UIBarButtonItem!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Chọn Thể Loại"

        let bgView = BackgroundView()
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

        let applyBtn = UIBarButtonItem(title: "Áp Dụng", style: .done, target: self, action: #selector(applyTapped))
        applyButton = applyBtn
        navigationItem.rightBarButtonItem = applyButton
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Hủy", style: .plain, target: self, action: #selector(cancelTapped))
        
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 10
        layout.minimumLineSpacing = 10
        layout.sectionInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        layout.estimatedItemSize = CGSize(width: 100, height: 40)
        
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(GenreCell.self, forCellWithReuseIdentifier: "GenreCell")
        collectionView.allowsMultipleSelection = true
        view.addSubview(collectionView)
        updateApplyButton()

        NetworkManager.shared.fetchGenres { [weak self] fetched in
            guard let self = self, !fetched.isEmpty else { return }
            self.genres = fetched
            self.selectedSlugs = self.selectedSlugs.intersection(Set(fetched.map(\.slug)))
            self.updateApplyButton()
            self.collectionView.reloadData()
        }
    }
    
    @objc private func applyTapped() {
        let selected = genres.filter { selectedSlugs.contains($0.slug) }
        dismiss(animated: true) {
            self.onApply?(selected)
        }
    }
    
    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    private func updateApplyButton() {
        let count = selectedSlugs.count
        applyButton.title = count == 0 ? "Áp Dụng" : "Áp Dụng (\(count))"
        applyButton.accessibilityLabel = count == 0
            ? "Áp dụng bộ lọc"
            : "Áp dụng \(count) thể loại"
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return genres.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "GenreCell", for: indexPath) as! GenreCell
        let genre = genres[indexPath.row]
        cell.titleLabel.text = genre.name
        cell.isSelected = selectedSlugs.contains(genre.slug)
        cell.isAccessibilityElement = true
        cell.accessibilityLabel = genre.name
        cell.accessibilityTraits = cell.isSelected ? [.button, .selected] : [.button]
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        selectedSlugs.insert(genres[indexPath.row].slug)
        updateApplyButton()
    }
    
    func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        selectedSlugs.remove(genres[indexPath.row].slug)
        updateApplyButton()
    }
}

class GenreCell: UICollectionViewCell {
    let titleLabel = UILabel()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = UIColor.systemRed.withAlphaComponent(0.06)
        contentView.layer.cornerRadius = 20
        contentView.layer.borderWidth = 1.2
        contentView.layer.borderColor = UIColor.separator.cgColor
        contentView.clipsToBounds = true
        
        titleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)
        
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            titleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16)
        ])
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    override var isSelected: Bool {
        didSet {
            accessibilityTraits = isSelected ? [.button, .selected] : [.button]
            let update = {
                if self.isSelected {
                    self.contentView.backgroundColor = UIColor.systemRed.withAlphaComponent(0.15)
                    self.contentView.layer.borderColor = UIColor.systemRed.cgColor
                    self.titleLabel.textColor = .systemRed
                    self.titleLabel.font = .systemFont(ofSize: 14, weight: .bold)
                } else {
                    self.contentView.backgroundColor = UIColor.systemRed.withAlphaComponent(0.06)
                    self.contentView.layer.borderColor = UIColor.separator.cgColor
                    self.titleLabel.textColor = .label
                    self.titleLabel.font = .systemFont(ofSize: 14, weight: .medium)
                }
            }
            guard !UIAccessibility.isReduceMotionEnabled else { update(); return }
            UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState, .curveEaseOut], animations: update)
        }
    }
}
