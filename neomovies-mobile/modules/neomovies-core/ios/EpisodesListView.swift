import ExpoModulesCore
import UIKit

fileprivate struct EpisodeRow {
  let season: Int
  let episode: Int
  let title: String
  let description: String
  let progress: Int
  let stillUrl: String?
  let fallbackPosterUrl: String?
  let tmdbRating: Double?
  let imdbRating: Double?
}

final class EpisodesListView: ExpoView, UITableViewDataSource, UITableViewDelegate {
  let onEpisodePress = EventDispatcher()
  let onContentHeight = EventDispatcher()
  let onDownloadPress = EventDispatcher()

  private let tableView = UITableView(frame: .zero, style: .plain)
  private var items: [EpisodeRow] = []
  private var textColor: UIColor = .label
  private var secondaryTextColor: UIColor = .secondaryLabel
  private var rowBackgroundColor: UIColor = .clear
  private var borderColor: UIColor = .clear

  required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)
    tableView.translatesAutoresizingMaskIntoConstraints = false
    tableView.dataSource = self
    tableView.delegate = self
    tableView.separatorStyle = .none
    tableView.showsVerticalScrollIndicator = false
    tableView.isScrollEnabled = false
    tableView.rowHeight = UITableView.automaticDimension
    tableView.estimatedRowHeight = 108
    tableView.backgroundColor = .clear
    tableView.register(EpisodeCell.self, forCellReuseIdentifier: "cell")
    addSubview(tableView)
    NSLayoutConstraint.activate([
      tableView.topAnchor.constraint(equalTo: topAnchor),
      tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
      tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
      tableView.bottomAnchor.constraint(equalTo: bottomAnchor)
    ])
  }

  func setEpisodes(_ value: [[String: Any]]) {
    let previous = items
    let nextItems: [EpisodeRow] = value.compactMap { raw -> EpisodeRow? in
      guard let season = raw["season"] as? Int ?? (raw["season"] as? NSNumber)?.intValue,
            let episode = raw["episode"] as? Int ?? (raw["episode"] as? NSNumber)?.intValue else { return nil }
      return EpisodeRow(
        season: season,
        episode: episode,
        title: (raw["title"] as? String) ?? "",
        description: (raw["description"] as? String) ?? "",
        progress: min(max((raw["progress"] as? Int ?? (raw["progress"] as? NSNumber)?.intValue ?? 0), 0), 100),
        stillUrl: raw["stillUrl"] as? String,
        fallbackPosterUrl: raw["fallbackPosterUrl"] as? String,
        tmdbRating: raw["tmdbRating"] as? Double ?? (raw["tmdbRating"] as? NSNumber)?.doubleValue,
        imdbRating: raw["imdbRating"] as? Double ?? (raw["imdbRating"] as? NSNumber)?.doubleValue
      )
    }
    let canPatch =
      previous.count == nextItems.count &&
      zip(previous, nextItems).allSatisfy { $0.season == $1.season && $0.episode == $1.episode }
    items = nextItems
    if canPatch {
      let changed = items.indices.filter { idx in
        let old = previous[idx]
        let cur = nextItems[idx]
        return old.title != cur.title || old.description != cur.description || old.progress != cur.progress || old.tmdbRating != cur.tmdbRating || old.imdbRating != cur.imdbRating || old.stillUrl != cur.stillUrl
      }
      if !changed.isEmpty {
        UIView.performWithoutAnimation {
          tableView.reloadRows(at: changed.map { IndexPath(row: $0, section: 0) }, with: .none)
        }
      }
    } else {
      UIView.performWithoutAnimation {
        tableView.reloadData()
      }
    }
    DispatchQueue.main.async { [weak self] in self?.emitContentHeight() }
  }

  func setTextColor(_ hex: String?) { textColor = Self.color(hex, fallback: .label); tableView.reloadData() }
  func setSecondaryTextColor(_ hex: String?) { secondaryTextColor = Self.color(hex, fallback: .secondaryLabel); tableView.reloadData() }
  func setBackgroundColorHex(_ hex: String?) { rowBackgroundColor = Self.color(hex, fallback: .clear); tableView.reloadData() }
  func setBorderColor(_ hex: String?) { borderColor = Self.color(hex, fallback: .clear); tableView.reloadData() }

  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { items.count }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let item = items[indexPath.row]
    let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! EpisodeCell
    cell.configure(
      item: item,
      textColor: textColor,
      secondaryTextColor: secondaryTextColor,
      bgColor: rowBackgroundColor,
      borderColor: borderColor
    )
    return cell
  }

  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    let item = items[indexPath.row]
    onEpisodePress(["season": item.season, "episode": item.episode])
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    emitContentHeight()
  }

  private func emitContentHeight() {
    tableView.layoutIfNeeded()
    onContentHeight(["height": tableView.contentSize.height])
  }

  private static func color(_ hex: String?, fallback: UIColor) -> UIColor {
    guard let hex, !hex.isEmpty else { return fallback }
    var text = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    if text.hasPrefix("#") { text.removeFirst() }
    guard text.count == 6, let value = Int(text, radix: 16) else { return fallback }
    return UIColor(red: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255, blue: CGFloat(value & 0xFF) / 255, alpha: 1)
  }
}

private final class EpisodeCell: UITableViewCell {
  private static let imageCache = NSCache<NSString, UIImage>()
  private let thumb = UIImageView()
  private let progressBadge = UILabel()
  private let progressTrack = UIView()
  private let progressFill = UIView()
  private var progressFillWidth: NSLayoutConstraint?
  private let playBadge = UIView()
  private let playIcon = LucideIconView(kind: .play)
  private let titleLabel = UILabel()
  private let metaLabel = UILabel()
  private let descLabel = UILabel()
  private let downloadWrap = UIView()
  private let downloadIcon = LucideIconView(kind: .download)
  private var imageTask: URLSessionDataTask?
  private var imageURL: String?
  private var episodeData: EpisodeRow?

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    selectionStyle = .none
    backgroundColor = .clear
    contentView.backgroundColor = .clear

    thumb.translatesAutoresizingMaskIntoConstraints = false
    thumb.layer.cornerRadius = 10
    thumb.clipsToBounds = true
    thumb.contentMode = .scaleAspectFill
    contentView.addSubview(thumb)

    progressBadge.translatesAutoresizingMaskIntoConstraints = false
    progressBadge.font = .systemFont(ofSize: 10, weight: .bold)
    progressBadge.textColor = .white
    progressBadge.backgroundColor = UIColor.black.withAlphaComponent(0.65)
    progressBadge.layer.cornerRadius = 8
    progressBadge.clipsToBounds = true
    progressBadge.textAlignment = .center
    contentView.addSubview(progressBadge)

    progressTrack.translatesAutoresizingMaskIntoConstraints = false
    progressTrack.backgroundColor = UIColor.white.withAlphaComponent(0.3)
    thumb.addSubview(progressTrack)
    progressFill.translatesAutoresizingMaskIntoConstraints = false
    progressFill.backgroundColor = .white
    thumb.addSubview(progressFill)
    playBadge.translatesAutoresizingMaskIntoConstraints = false
    playBadge.backgroundColor = UIColor.black.withAlphaComponent(0.55)
    playBadge.layer.cornerRadius = 14
    thumb.addSubview(playBadge)
    playIcon.translatesAutoresizingMaskIntoConstraints = false
    playIcon.fillColor = .white
    playBadge.addSubview(playIcon)

    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.font = .boldSystemFont(ofSize: 17)
    titleLabel.numberOfLines = 1
    contentView.addSubview(titleLabel)

    metaLabel.translatesAutoresizingMaskIntoConstraints = false
    metaLabel.font = .systemFont(ofSize: 14, weight: .medium)
    contentView.addSubview(metaLabel)

    descLabel.translatesAutoresizingMaskIntoConstraints = false
    descLabel.font = .systemFont(ofSize: 14)
    descLabel.numberOfLines = 2
    contentView.addSubview(descLabel)

    downloadWrap.translatesAutoresizingMaskIntoConstraints = false
    downloadWrap.layer.cornerRadius = 16
    downloadWrap.layer.borderWidth = 1
    contentView.addSubview(downloadWrap)
    downloadIcon.translatesAutoresizingMaskIntoConstraints = false
    downloadWrap.addSubview(downloadIcon)
    
    // Add tap gesture for download button
    let downloadTap = UITapGestureRecognizer(target: self, action: #selector(downloadTapped))
    downloadWrap.addGestureRecognizer(downloadTap)
    downloadWrap.isUserInteractionEnabled = true

    NSLayoutConstraint.activate([
      thumb.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      thumb.topAnchor.constraint(equalTo: contentView.topAnchor),
      thumb.widthAnchor.constraint(equalToConstant: 148),
      thumb.heightAnchor.constraint(equalToConstant: 83),
      thumb.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -12),

      progressBadge.leadingAnchor.constraint(equalTo: thumb.leadingAnchor, constant: 6),
      progressBadge.topAnchor.constraint(equalTo: thumb.topAnchor, constant: 6),
      progressBadge.heightAnchor.constraint(equalToConstant: 20),
      progressBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 40),

      progressTrack.leadingAnchor.constraint(equalTo: thumb.leadingAnchor),
      progressTrack.trailingAnchor.constraint(equalTo: thumb.trailingAnchor),
      progressTrack.bottomAnchor.constraint(equalTo: thumb.bottomAnchor),
      progressTrack.heightAnchor.constraint(equalToConstant: 3),
      progressFill.leadingAnchor.constraint(equalTo: thumb.leadingAnchor),
      progressFill.bottomAnchor.constraint(equalTo: thumb.bottomAnchor),
      progressFill.heightAnchor.constraint(equalToConstant: 3),
      playBadge.topAnchor.constraint(equalTo: thumb.topAnchor, constant: 6),
      playBadge.trailingAnchor.constraint(equalTo: thumb.trailingAnchor, constant: -6),
      playBadge.widthAnchor.constraint(equalToConstant: 28),
      playBadge.heightAnchor.constraint(equalToConstant: 28),
      playIcon.centerXAnchor.constraint(equalTo: playBadge.centerXAnchor),
      playIcon.centerYAnchor.constraint(equalTo: playBadge.centerYAnchor),
      playIcon.widthAnchor.constraint(equalToConstant: 16),
      playIcon.heightAnchor.constraint(equalToConstant: 16),

      titleLabel.leadingAnchor.constraint(equalTo: thumb.trailingAnchor, constant: 12),
      titleLabel.topAnchor.constraint(equalTo: thumb.topAnchor),
      titleLabel.trailingAnchor.constraint(equalTo: downloadWrap.leadingAnchor, constant: -8),

      metaLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
      metaLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
      metaLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

      descLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
      descLabel.topAnchor.constraint(equalTo: metaLabel.bottomAnchor, constant: 4),
      descLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
      descLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -12),

      downloadWrap.topAnchor.constraint(equalTo: thumb.topAnchor, constant: 2),
      downloadWrap.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      downloadWrap.widthAnchor.constraint(equalToConstant: 32),
      downloadWrap.heightAnchor.constraint(equalToConstant: 32),
      downloadIcon.centerXAnchor.constraint(equalTo: downloadWrap.centerXAnchor),
      downloadIcon.centerYAnchor.constraint(equalTo: downloadWrap.centerYAnchor),
      downloadIcon.widthAnchor.constraint(equalToConstant: 16),
      downloadIcon.heightAnchor.constraint(equalToConstant: 16),
    ])
    progressFillWidth = progressFill.widthAnchor.constraint(equalToConstant: 0)
    progressFillWidth?.isActive = true
  }

  required init?(coder: NSCoder) {
    return nil
  }

  func configure(item: EpisodeRow, textColor: UIColor, secondaryTextColor: UIColor, bgColor: UIColor, borderColor: UIColor) {
    episodeData = item
    titleLabel.textColor = textColor
    metaLabel.textColor = secondaryTextColor
    descLabel.textColor = secondaryTextColor
    downloadWrap.layer.borderColor = borderColor.cgColor
    downloadIcon.strokeColor = secondaryTextColor
    titleLabel.text = "\(item.episode). \(item.title)"
    let rating = item.tmdbRating != nil ? String(format: " · TMDB %.1f", item.tmdbRating!) : (item.imdbRating != nil ? String(format: " · IMDb %.1f", item.imdbRating!) : "")
    metaLabel.text = "S\(item.season) · E\(item.episode)\(rating)"
    descLabel.text = item.description
    progressBadge.isHidden = item.progress <= 0
    progressBadge.text = "\(item.progress)%"
    progressFillWidth?.constant = CGFloat(item.progress) / 100 * 148
    progressFill.isHidden = item.progress <= 0

    let rawUrl = item.stillUrl ?? item.fallbackPosterUrl
    if rawUrl == imageURL {
      return
    }
    imageTask?.cancel()
    imageURL = rawUrl
    guard let raw = rawUrl, let url = URL(string: raw) else {
      thumb.image = nil
      return
    }
    if let cached = Self.imageCache.object(forKey: raw as NSString) {
      thumb.image = cached
      return
    }
    imageTask = URLSession.shared.dataTask(with: url) { data, _, _ in
      guard let data, let image = UIImage(data: data) else { return }
      Self.imageCache.setObject(image, forKey: raw as NSString)
      DispatchQueue.main.async {
        if self.imageURL == raw {
          self.thumb.image = image
        }
      }
    }
    imageTask?.resume()
  }
  
  @objc private func downloadTapped() {
    guard let item = episodeData else { return }
    // Find the EpisodesListView parent and trigger the event
    if let tableView = superview as? UITableView,
       let indexPath = tableView.indexPath(for: self),
       let listView = tableView.delegate as? EpisodesListView {
      listView.onDownloadPress(["season": item.season, "episode": item.episode])
    }
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    imageTask?.cancel()
  }
}

private final class LucideIconView: UIView {
  enum Kind { case play, download }
  var strokeColor: UIColor = .white {
    didSet { shape.strokeColor = strokeColor.cgColor; shape.fillColor = fillColor?.cgColor }
  }
  var fillColor: UIColor? = nil {
    didSet { shape.fillColor = fillColor?.cgColor }
  }
  private let kind: Kind
  private let shape = CAShapeLayer()

  init(kind: Kind) {
    self.kind = kind
    super.init(frame: .zero)
    isOpaque = false
    layer.addSublayer(shape)
    shape.lineCap = .round
    shape.lineJoin = .round
    shape.lineWidth = 2
    strokeColor = .white
    shape.strokeColor = UIColor.white.cgColor
    shape.fillColor = nil
  }

  required init?(coder: NSCoder) { return nil }

  override func layoutSubviews() {
    super.layoutSubviews()
    shape.frame = bounds
    let sx = bounds.width / 24
    let sy = bounds.height / 24
    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * sx, y: y * sy) }
    let path = UIBezierPath()
    switch kind {
    case .play:
      // Lucide play icon: M5 5a2 2 0 0 1 3.008-1.728l11.997 6.998a2 2 0 0 1 .003 3.458l-12 7A2 2 0 0 1 5 19z
      path.move(to: point(5, 5))
      path.addCurve(to: point(8.008, 3.272), controlPoint1: point(5, 3.895), controlPoint2: point(6.306, 3.097))
      path.addLine(to: point(20.005, 10.27))
      path.addCurve(to: point(20.008, 13.728), controlPoint1: point(21.093, 11.175), controlPoint2: point(21.095, 12.823))
      path.addLine(to: point(8.008, 20.728))
      path.addCurve(to: point(5, 19), controlPoint1: point(6.306, 20.903), controlPoint2: point(5, 20.105))
      path.close()
    case .download:
      // SVG paths:
      // M12 15V3
      path.move(to: point(12, 15))
      path.addLine(to: point(12, 3))
      // M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4
      path.move(to: point(21, 15))
      path.addLine(to: point(21, 19))
      path.addArc(withCenter: point(19, 19), radius: 2 * min(sx, sy), startAngle: 0, endAngle: .pi / 2, clockwise: true)
      path.addLine(to: point(5, 21))
      path.addArc(withCenter: point(5, 19), radius: 2 * min(sx, sy), startAngle: .pi / 2, endAngle: .pi, clockwise: true)
      path.addLine(to: point(3, 15))
      // m7 10 5 5 5-5
      path.move(to: point(7, 10))
      path.addLine(to: point(12, 15))
      path.addLine(to: point(17, 10))
    }
    shape.path = path.cgPath
  }
}
