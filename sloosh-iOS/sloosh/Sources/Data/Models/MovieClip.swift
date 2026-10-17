import Foundation

// MARK: - Movie Clip Model (Кино-момент)

public struct MovieClip: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: String
    public let mediaId: Int
    public let mediaType: String // "movie" or "tv"
    public let title: String
    public let posterPath: String?
    public let backdropPath: String?
    public let logoPath: String?
    public let season: Int?
    public let episode: Int?
    public let translationName: String?
    public let startTime: Double
    public let endTime: Double
    public let caption: String
    public let authorId: String
    public let authorName: String
    public let authorAvatar: String?
    public let createdAtMs: Int64
    public var likesCount: Int
    public var commentsCount: Int
    public var viewsCount: Int
    public let streamUrl: String?
    public let iframeUrl: String?
    public let kpId: Int?
    public let tmdbId: Int?

    public var duration: Double {
        max(1.0, endTime - startTime)
    }

    public var isSeries: Bool {
        mediaType == "tv" || (season != nil && episode != nil)
    }

    public var subtitleInfo: String {
        if isSeries, let s = season, let e = episode {
            if let t = translationName, !t.isEmpty {
                return "\(s) сезон, \(e) серия • \(t)"
            }
            return "\(s) сезон, \(e) серия"
        } else if let t = translationName, !t.isEmpty {
            return t
        }
        return "Момент из фильма"
    }

    public var displayThumbnailUrl: String? {
        if let path = posterPath ?? backdropPath, !path.isEmpty {
            if path.hasPrefix("http://") || path.hasPrefix("https://") {
                return path
            }
            return "\(MoviesApi.activeImagesBaseURL)/api/v1/images/tmdb/w500\(path)"
        }
        return nil
    }

    public var timecodeFormatted: String {
        let total = max(0, Int(duration.rounded()))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }

    public var formattedDuration: String {
        let totalSec = Int(duration.rounded())
        if totalSec >= 60 {
            let m = totalSec / 60
            let s = totalSec % 60
            if s == 0 {
                return "\(m) мин"
            }
            return "\(m) мин \(s) сек"
        }
        return "\(totalSec) сек"
    }

    public var timecodeRangeFormatted: String {
        func fmt(_ sec: Double) -> String {
            let total = Int(sec)
            let h = total / 3600
            let m = (total % 3600) / 60
            let s = total % 60
            if h > 0 {
                return String(format: "%d:%02d:%02d", h, m, s)
            }
            return String(format: "%02d:%02d", m, s)
        }
        return "\(fmt(startTime)) – \(fmt(endTime))"
    }

    public init(
        id: String = UUID().uuidString,
        mediaId: Int,
        mediaType: String = "movie",
        title: String,
        posterPath: String? = nil,
        backdropPath: String? = nil,
        logoPath: String? = nil,
        season: Int? = nil,
        episode: Int? = nil,
        translationName: String? = nil,
        startTime: Double,
        endTime: Double,
        caption: String = "",
        authorId: String,
        authorName: String,
        authorAvatar: String? = nil,
        createdAtMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        likesCount: Int = 0,
        commentsCount: Int = 0,
        viewsCount: Int = 0,
        streamUrl: String? = nil,
        iframeUrl: String? = nil,
        kpId: Int? = nil,
        tmdbId: Int? = nil
    ) {
        self.id = id
        self.mediaId = mediaId
        self.mediaType = mediaType
        self.title = title
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.logoPath = logoPath
        self.season = season
        self.episode = episode
        self.translationName = translationName
        self.startTime = startTime
        self.endTime = endTime
        self.caption = caption
        self.authorId = authorId
        self.authorName = authorName
        self.authorAvatar = authorAvatar
        self.createdAtMs = createdAtMs
        self.likesCount = likesCount
        self.commentsCount = commentsCount
        self.viewsCount = viewsCount
        self.streamUrl = streamUrl
        self.iframeUrl = iframeUrl
        self.kpId = kpId
        self.tmdbId = tmdbId
    }

    private enum CodingKeys: String, CodingKey {
        case id, mediaId, mediaType, title, posterPath, backdropPath, logoPath
        case season, episode, translationName, startTime, endTime, caption
        case authorId, authorName, authorAvatar, createdAtMs
        case likesCount, commentsCount, viewsCount, streamUrl, iframeUrl, kpId, tmdbId
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.id = (try? container.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString

        if let mId = try? container.decodeIfPresent(Int.self, forKey: .mediaId) {
            self.mediaId = mId
        } else if let mStr = try? container.decodeIfPresent(String.self, forKey: .mediaId), let mInt = Int(mStr) {
            self.mediaId = mInt
        } else {
            self.mediaId = 0
        }

        self.mediaType = (try? container.decodeIfPresent(String.self, forKey: .mediaType)) ?? "movie"
        self.title = (try? container.decodeIfPresent(String.self, forKey: .title)) ?? ""
        self.posterPath = try? container.decodeIfPresent(String.self, forKey: .posterPath)
        self.backdropPath = try? container.decodeIfPresent(String.self, forKey: .backdropPath)
        self.logoPath = try? container.decodeIfPresent(String.self, forKey: .logoPath)

        if let s = try? container.decodeIfPresent(Int.self, forKey: .season) {
            self.season = s
        } else if let sStr = try? container.decodeIfPresent(String.self, forKey: .season), let sInt = Int(sStr) {
            self.season = sInt
        } else {
            self.season = nil
        }

        if let e = try? container.decodeIfPresent(Int.self, forKey: .episode) {
            self.episode = e
        } else if let eStr = try? container.decodeIfPresent(String.self, forKey: .episode), let eInt = Int(eStr) {
            self.episode = eInt
        } else {
            self.episode = nil
        }

        self.translationName = try? container.decodeIfPresent(String.self, forKey: .translationName)

        if let st = try? container.decodeIfPresent(Double.self, forKey: .startTime) {
            self.startTime = st
        } else if let stInt = try? container.decodeIfPresent(Int.self, forKey: .startTime) {
            self.startTime = Double(stInt)
        } else if let stStr = try? container.decodeIfPresent(String.self, forKey: .startTime), let stD = Double(stStr) {
            self.startTime = stD
        } else {
            self.startTime = 0.0
        }

        if let et = try? container.decodeIfPresent(Double.self, forKey: .endTime) {
            self.endTime = et
        } else if let etInt = try? container.decodeIfPresent(Int.self, forKey: .endTime) {
            self.endTime = Double(etInt)
        } else if let etStr = try? container.decodeIfPresent(String.self, forKey: .endTime), let etD = Double(etStr) {
            self.endTime = etD
        } else {
            self.endTime = 0.0
        }

        self.caption = (try? container.decodeIfPresent(String.self, forKey: .caption)) ?? ""
        self.authorId = (try? container.decodeIfPresent(String.self, forKey: .authorId)) ?? ""
        self.authorName = (try? container.decodeIfPresent(String.self, forKey: .authorName)) ?? "Зритель"
        self.authorAvatar = try? container.decodeIfPresent(String.self, forKey: .authorAvatar)

        if let cr = try? container.decodeIfPresent(Int64.self, forKey: .createdAtMs) {
            self.createdAtMs = cr
        } else if let crD = try? container.decodeIfPresent(Double.self, forKey: .createdAtMs) {
            self.createdAtMs = Int64(crD)
        } else {
            self.createdAtMs = Int64(Date().timeIntervalSince1970 * 1000)
        }

        self.likesCount = (try? container.decodeIfPresent(Int.self, forKey: .likesCount)) ?? 0
        self.commentsCount = (try? container.decodeIfPresent(Int.self, forKey: .commentsCount)) ?? 0
        self.viewsCount = (try? container.decodeIfPresent(Int.self, forKey: .viewsCount)) ?? 0

        self.streamUrl = try? container.decodeIfPresent(String.self, forKey: .streamUrl)
        self.iframeUrl = try? container.decodeIfPresent(String.self, forKey: .iframeUrl)

        if let kp = try? container.decodeIfPresent(Int.self, forKey: .kpId) {
            self.kpId = kp
        } else if let kpStr = try? container.decodeIfPresent(String.self, forKey: .kpId), let kpInt = Int(kpStr) {
            self.kpId = kpInt
        } else {
            self.kpId = nil
        }

        if let tmdb = try? container.decodeIfPresent(Int.self, forKey: .tmdbId) {
            self.tmdbId = tmdb
        } else if let tmdbStr = try? container.decodeIfPresent(String.self, forKey: .tmdbId), let tmdbInt = Int(tmdbStr) {
            self.tmdbId = tmdbInt
        } else {
            self.tmdbId = nil
        }
    }
}

// MARK: - Clip Comment Model

public struct ClipComment: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: String
    public let clipId: String
    public let authorId: String
    public let authorName: String
    public let authorAvatar: String?
    public let text: String
    public let createdAtMs: Int64
    public var likesCount: Int

    public var authorInitials: String {
        let parts = authorName.split(separator: " ")
        if parts.count >= 2, let first = parts[0].first, let second = parts[1].first {
            return "\(first)\(second)".uppercased()
        } else if let first = authorName.first {
            return String(first).uppercased()
        }
        return "S"
    }

    public var timeAgoFormatted: String {
        let seconds = max(0, Int64(Date().timeIntervalSince1970) - (createdAtMs / 1000))
        if seconds < 60 { return "только что" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) мин" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) ч" }
        let days = hours / 24
        if days < 30 { return "\(days) дн" }
        return "\(days / 30) мес"
    }

    public init(
        id: String = UUID().uuidString,
        clipId: String,
        authorId: String,
        authorName: String,
        authorAvatar: String? = nil,
        text: String,
        createdAtMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        likesCount: Int = 0
    ) {
        self.id = id
        self.clipId = clipId
        self.authorId = authorId
        self.authorName = authorName
        self.authorAvatar = authorAvatar
        self.text = text
        self.createdAtMs = createdAtMs
        self.likesCount = likesCount
    }
}
