import UIKit

class GenreSelectionViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    let genres = [
        ("Hành Động", "hanh-dong"), ("Phiêu Lưu", "phieu-luu"), ("Hài Hước", "hai-huoc"),
        ("Tình Cảm", "tinh-cam"), ("Phép Thuật", "phep-thuat"), ("Viễn Tưởng", "vien-tuong"),
        ("Kinh Dị", "kinh-di"), ("Đời Thường", "doi-thuong"), ("Học Đường", "hoc-duong"),
        ("Thể Thao", "the-thao"), ("Drama", "drama"), ("Fantasy", "fantasy"),
        ("Isekai", "isekai"), ("Harem", "harem"), ("Shounen", "shounen"),
        ("Mecha", "mecha"), ("Ecchi", "ecchi"), ("Trinh Thám", "trinh-tham"),
        ("Siêu Nhiên", "sieu-nhien"), ("Âm Nhạc", "am-nhac"), ("Lịch Sử", "lich-su"),
        ("Trò Chơi", "tro-choi")
    ]
    
    var selectedSlugs = Set<String>()
    var onApply: (([(name: String, slug: String)]) -> Void)?
    
    private var collectionView: UICollectionView!
    
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
        navigationItem.rightBarButtonItem = applyBtn
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
    }
    
    @objc private func applyTapped() {
        let selected = genres.filter { selectedSlugs.contains($0.1) }
        dismiss(animated: true) {
            self.onApply?(selected)
        }
    }
    
    @objc private func cancelTapped() {
        dismiss(animated: true)
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return genres.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "GenreCell", for: indexPath) as! GenreCell
        let genre = genres[indexPath.row]
        cell.titleLabel.text = genre.0
        cell.isSelected = selectedSlugs.contains(genre.1)
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        selectedSlugs.insert(genres[indexPath.row].1)
    }
    
    func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        selectedSlugs.remove(genres[indexPath.row].1)
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
            UIView.animate(withDuration: 0.2) {
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
        }
    }
}
