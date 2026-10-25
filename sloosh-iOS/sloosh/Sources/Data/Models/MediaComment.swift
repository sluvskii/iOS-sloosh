import Foundation

// MARK: - Media Comment Model

/// Комментарий к фильму или сериалу.
/// Хранится в Firebase RTDB: `media_comments/{mediaKey}/{commentId}`.
///
/// `mediaKey` в узле не дублируется — он определяется путём (`kp_123`, `tmdb_456`).
public struct MediaComment: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public let authorId: String
    public let authorName: String
    public let authorTag: String?
    public let authorAvatar: String?
    public let text: String
    public let createdAtMs: Int64
    public var isSpoiler: Bool
    /// `[uid: true]` — карта лайков прямо в узле комментария.
    /// Счётчик не расходится с данными и не требует отдельного поля.
    public var likedBy: [String: Bool]?

    public var likesCount: Int { likedBy?.count ?? 0 }

    public func isLiked(by uid: String?) -> Bool {
        guard let uid, !uid.isEmpty else { return false }
        return likedBy?[uid] == true
    }

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
        let months = days / 30
        if months < 12 { return "\(months) мес" }
        return "\(months / 12) г"
    }

    public init(
        id: String = UUID().uuidString,
        authorId: String,
        authorName: String,
        authorTag: String? = nil,
        authorAvatar: String? = nil,
        text: String,
        createdAtMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        isSpoiler: Bool = false,
        likedBy: [String: Bool]? = nil
    ) {
        self.id = id
        self.authorId = authorId
        self.authorName = authorName
        self.authorTag = authorTag
        self.authorAvatar = authorAvatar
        self.text = text
        self.createdAtMs = createdAtMs
        self.isSpoiler = isSpoiler
        self.likedBy = likedBy
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        self.authorId = try c.decodeIfPresent(String.self, forKey: .authorId) ?? ""
        self.authorName = try c.decodeIfPresent(String.self, forKey: .authorName) ?? "Пользователь"
        self.authorTag = try c.decodeIfPresent(String.self, forKey: .authorTag)
        self.authorAvatar = try c.decodeIfPresent(String.self, forKey: .authorAvatar)
        self.text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        self.createdAtMs = try c.decodeIfPresent(Int64.self, forKey: .createdAtMs) ?? 0
        self.isSpoiler = try c.decodeIfPresent(Bool.self, forKey: .isSpoiler) ?? false
        self.likedBy = try c.decodeIfPresent([String: Bool].self, forKey: .likedBy)
    }
}

// MARK: - Sorting

public enum MediaCommentSort: String, CaseIterable, Identifiable {
    case newest
    case popular

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .newest: return "Новые"
        case .popular: return "Популярные"
        }
    }
}

// MARK: - Limits

public enum MediaCommentLimits {
    public static let maxLength = 1000
    public static let pageSize = 200
    /// Минимальный интервал между отправками с одного устройства.
    public static let sendCooldown: TimeInterval = 15
}

// MARK: - Reports (moderation)

/// Одна жалоба на комментарий — узел `media_comment_reports/{commentId}/{uid}`.
public struct MediaCommentReport: Codable, Sendable, Equatable {
    public let reason: String?
    public let mediaKey: String?
    public let commentAuthorId: String?
    public let createdAtMs: Int64?

    public var reasonTitle: String {
        switch reason ?? "" {
        case "spam": return "Спам"
        case "abuse": return "Оскорбления"
        case "spoiler": return "Спойлер без пометки"
        default: return "Жалоба"
        }
    }

    public var reasonIcon: String {
        switch reason ?? "" {
        case "spam": return "envelope.badge.fill"
        case "abuse": return "hand.raised.fill"
        case "spoiler": return "eye.slash.fill"
        default: return "flag.fill"
        }
    }
}

/// Жалобы, сгруппированные по комментарию — строка админской модерации.
public struct CommentReportGroup: Identifiable, Sendable, Equatable {
    public let id: String
    public let mediaKey: String
    public let reports: [MediaCommentReport]
    public var comment: MediaComment?
    /// Не удалось загрузить комментарий (сеть/права), а не «его нет».
    public var commentLoadFailed: Bool = false
    /// Человеческое название тайтла, подтягивается из API по mediaKey.
    public var mediaTitle: String?
    public var posterUrl: String?

    public var reportsCount: Int { reports.count }

    public var createdAtMs: Int64 {
        reports.compactMap { $0.createdAtMs }.max() ?? 0
    }

    public var reasonCounts: [(title: String, icon: String, count: Int)] {
        var grouped: [String: (title: String, icon: String, count: Int)] = [:]
        for report in reports {
            let key = report.reason ?? "other"
            var entry = grouped[key] ?? (report.reasonTitle, report.reasonIcon, 0)
            entry.count += 1
            grouped[key] = entry
        }
        return grouped.values.sorted { $0.count > $1.count }
    }

    public var authorName: String {
        comment?.authorName ?? "Удалённый пользователь"
    }

    public var authorAvatar: String? {
        comment?.authorAvatar
    }

    public var displayTitle: String {
        if let mediaTitle, !mediaTitle.isEmpty { return mediaTitle }
        return mediaKey
    }
}

// MARK: - Media Key

extension MediaDetailsDto {
    /// Стабильный ключ тайтла для комментариев: `kp_…` → `tmdb_…` → внутренний id.
    var commentsMediaKey: String {
        if let kp = externalIds?.kp ?? ids?.kp, kp > 0 {
            return "kp_\(kp)"
        }
        if let tmdb = externalIds?.tmdb ?? ids?.tmdb, tmdb > 0 {
            return "tmdb_\(tmdb)"
        }
        return id ?? ""
    }
}
