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
