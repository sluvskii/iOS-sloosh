import Foundation
import SwiftUI
import Combine

// MARK: - Live Analytics Models

public struct LiveWatchingMedia: Codable, Sendable, Equatable {
    public let mediaKey: String
    public let title: String
    public let season: Int?
    public let episode: Int?
    public let translation: String
    public let posterUrl: String?
    public let startedAtMs: Int64
    public var updatedAtMs: Int64

    public init(
        mediaKey: String,
        title: String,
        season: Int? = nil,
        episode: Int? = nil,
        translation: String,
        posterUrl: String? = nil,
        startedAtMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        updatedAtMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) {
        self.mediaKey = mediaKey
        self.title = title
        self.season = season
        self.episode = episode
        self.translation = translation
        self.posterUrl = posterUrl
        self.startedAtMs = startedAtMs
        self.updatedAtMs = updatedAtMs
    }

    public var displayEpisodeTitle: String? {
        if let s = season, let e = episode {
            return "Сезон \(s), Серия \(e)"
        }
        return nil
    }
}

public struct LiveSessionItem: Identifiable, Sendable, Equatable {
    public let id: String // sessionId
    public let userId: String?
    public let displayName: String
    public let tag: String?
    public let avatarUrl: String?
    public let platform: String
    public let appVersion: String
    public let lastSeenMs: Int64
    public let isOnline: Bool
    public let media: LiveWatchingMedia?

    public var isWatching: Bool { media != nil }

    public var displayTitle: String {
        let clean = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty { return clean }
        if let t = tag, !t.isEmpty { return "@\(t)" }
        return id.hasPrefix("guest_") ? "Гость (\(platform))" : "Пользователь \(id.prefix(6))"
    }

    public var displayTag: String {
        if let t = tag, !t.isEmpty { return "@\(t.replacingOccurrences(of: "@", with: ""))" }
        return id.hasPrefix("guest_") ? "Гостевая сессия" : ""
    }

    public init(
        id: String,
        userId: String? = nil,
        displayName: String = "",
        tag: String? = nil,
        avatarUrl: String? = nil,
        platform: String = "iOS",
        appVersion: String = "2.0",
        lastSeenMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        isOnline: Bool = true,
        media: LiveWatchingMedia? = nil
    ) {
        self.id = id
        self.userId = userId
        self.displayName = displayName
        self.tag = tag
        self.avatarUrl = avatarUrl
        self.platform = platform
        self.appVersion = appVersion
        self.lastSeenMs = lastSeenMs
        self.isOnline = isOnline
        self.media = media
    }
}

public struct MediaTranslationVote: Identifiable, Sendable, Equatable {
    public var id: String { translation }
    public let translation: String
    public let count: Int
    public let percentage: Double

    public init(translation: String, count: Int, percentage: Double) {
        self.translation = translation
        self.count = count
        self.percentage = percentage
    }
}

public struct MediaAnalyticsStats: Identifiable, Sendable, Equatable {
    public var id: String { mediaKey }
    public let mediaKey: String
    public let title: String
    public let posterUrl: String?
    public let totalPlays: Int
    public let lastPlayedMs: Int64?
    public let translations: [MediaTranslationVote]

    public var topTranslation: MediaTranslationVote? {
        translations.first
    }

    public init(
        mediaKey: String,
        title: String,
        posterUrl: String? = nil,
        totalPlays: Int = 0,
        lastPlayedMs: Int64? = nil,
        translations: [MediaTranslationVote] = []
    ) {
        self.mediaKey = mediaKey
        self.title = title
        self.posterUrl = posterUrl
        self.totalPlays = totalPlays
        self.lastPlayedMs = lastPlayedMs
        self.translations = translations
    }
}

public struct GlobalTranslationStat: Identifiable, Sendable, Equatable {
    public var id: String { translation }
    public let translation: String
    public let count: Int
    public let percentage: Double

    public init(translation: String, count: Int, percentage: Double) {
        self.translation = translation
        self.count = count
        self.percentage = percentage
    }
}

// MARK: - Playback Analytics Service

@MainActor
public final class PlaybackAnalyticsService: ObservableObject {
    public static let shared = PlaybackAnalyticsService()

    private let databaseBaseURL = "https://sloosh-77434-default-rtdb.firebaseio.com"
    private var watchingPingTimer: Timer?
    private var currentWatchingMedia: LiveWatchingMedia?
    private var recordedVotesThisSession = Set<String>()

    @Published public private(set) var activeMediaStatsCache: [String: MediaAnalyticsStats] = [:]

    private init() {}

    // MARK: - Session & Identity

    private var persistentGuestId: String {
        if let stored = UserDefaults.standard.string(forKey: "sloosh_analytics_guest_id"), !stored.isEmpty {
            return stored
        }
        let newId = "guest_" + UUID().uuidString.prefix(8).lowercased()
        UserDefaults.standard.set(newId, forKey: "sloosh_analytics_guest_id")
        return newId
    }

    public var currentSessionId: String {
        if let user = AuthRepository.shared.currentUser, !user.isAnonymous {
            return "usr_\(user.id)"
        }
        return persistentGuestId
    }

    private func makeURL(path: String) async -> URL? {
        let safePath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        var urlString = "\(databaseBaseURL)/\(safePath).json"
        if let token = await AuthRepository.shared.ensureFreshToken(), !token.isEmpty {
            urlString += "?auth=\(token)"
        }
        return URL(string: urlString)
    }

    // MARK: - Key Sanitization for Firebase Realtime Database
    // Firebase RTDB keys cannot contain '.', '$', '#', '[', ']', '/'

    public static func sanitizeKey(_ text: String) -> String {
        text.replacingOccurrences(of: ".", with: "_dot_")
            .replacingOccurrences(of: "/", with: "_slash_")
            .replacingOccurrences(of: "$", with: "_dlr_")
            .replacingOccurrences(of: "#", with: "_hash_")
            .replacingOccurrences(of: "[", with: "_lb_")
            .replacingOccurrences(of: "]", with: "_rb_")
    }

    public static func desanitizeKey(_ key: String) -> String {
        key.replacingOccurrences(of: "_dot_", with: ".")
           .replacingOccurrences(of: "_slash_", with: "/")
           .replacingOccurrences(of: "_dlr_", with: "$")
           .replacingOccurrences(of: "_hash_", with: "#")
           .replacingOccurrences(of: "_lb_", with: "[")
           .replacingOccurrences(of: "_rb_", with: "]")
    }

    // MARK: - Heartbeat & Session Reporting

    public func sendSessionHeartbeat() {
        let sessionId = currentSessionId
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let currentUser = AuthRepository.shared.currentUser
        let isAuth = currentUser != nil && !(currentUser?.isAnonymous ?? true)

        let sessionPayload: [String: Any] = [
            "sessionId": sessionId,
            "userId": isAuth ? (currentUser?.id as Any) : NSNull(),
            "displayName": isAuth ? (currentUser?.displayName ?? "") : "Гость (iOS)",
            "tag": isAuth ? (currentUser?.tag as Any) : NSNull(),
            "avatarUrl": isAuth ? (currentUser?.photoURL as Any) : NSNull(),
            "platform": "iOS",
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0",
            "lastSeenMs": nowMs,
            "isOnline": true
        ]

        Task {
            if let url = await makeURL(path: "active_sessions/\(sessionId)"),
               let data = try? JSONSerialization.data(withJSONObject: sessionPayload) {
                var req = URLRequest(url: url)
                req.httpMethod = "PATCH"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = data
                _ = try? await URLSession.shared.data(for: req)
            }
        }
    }

    // MARK: - Live Watching Reporting

    public func startWatching(
        mediaKey: String,
        title: String,
        season: Int? = nil,
        episode: Int? = nil,
        translation: String,
        posterUrl: String? = nil
    ) {
        stopWatchingPing()

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let media = LiveWatchingMedia(
            mediaKey: mediaKey,
            title: title,
            season: season,
            episode: episode,
            translation: translation,
            posterUrl: posterUrl,
            startedAtMs: nowMs,
            updatedAtMs: nowMs
        )
        self.currentWatchingMedia = media

        // 1. Immediately report now watching to active session
        reportWatchingState(media: media)

        // 2. Also register translation vote/pick
        recordTranslationPick(
            mediaKey: mediaKey,
            title: title,
            translation: translation,
            posterUrl: posterUrl
        )

        // 3. Schedule 20s heartbeat during playback
        watchingPingTimer = Timer.scheduledTimer(withTimeInterval: 20.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, var m = self.currentWatchingMedia else { return }
                m.updatedAtMs = Int64(Date().timeIntervalSince1970 * 1000)
                self.currentWatchingMedia = m
                self.reportWatchingState(media: m)
            }
        }
    }

    public func updateWatching(season: Int?, episode: Int?, translation: String) {
        guard var current = currentWatchingMedia else { return }
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let updated = LiveWatchingMedia(
            mediaKey: current.mediaKey,
            title: current.title,
            season: season,
            episode: episode,
            translation: translation,
            posterUrl: current.posterUrl,
            startedAtMs: current.startedAtMs,
            updatedAtMs: nowMs
        )
        self.currentWatchingMedia = updated
        reportWatchingState(media: updated)

        recordTranslationPick(
            mediaKey: current.mediaKey,
            title: current.title,
            translation: translation,
            posterUrl: current.posterUrl
        )
    }

    public func stopWatching() {
        stopWatchingPing()
        self.currentWatchingMedia = nil

        let sessionId = currentSessionId
        Task {
            if let url = await makeURL(path: "active_sessions/\(sessionId)/media") {
                var req = URLRequest(url: url)
                req.httpMethod = "DELETE"
                _ = try? await URLSession.shared.data(for: req)
            }
        }
    }

    private func stopWatchingPing() {
        watchingPingTimer?.invalidate()
        watchingPingTimer = nil
    }

    private func reportWatchingState(media: LiveWatchingMedia) {
        let sessionId = currentSessionId
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let currentUser = AuthRepository.shared.currentUser
        let isAuth = currentUser != nil && !(currentUser?.isAnonymous ?? true)

        var mediaDict: [String: Any] = [
            "mediaKey": media.mediaKey,
            "title": media.title,
            "translation": media.translation,
            "startedAtMs": media.startedAtMs,
            "updatedAtMs": media.updatedAtMs
        ]
        if let s = media.season { mediaDict["season"] = s }
        if let e = media.episode { mediaDict["episode"] = e }
        if let p = media.posterUrl { mediaDict["posterUrl"] = p }

        let payload: [String: Any] = [
            "sessionId": sessionId,
            "userId": isAuth ? (currentUser?.id as Any) : NSNull(),
            "displayName": isAuth ? (currentUser?.displayName ?? "") : "Гость (iOS)",
            "tag": isAuth ? (currentUser?.tag as Any) : NSNull(),
            "avatarUrl": isAuth ? (currentUser?.photoURL as Any) : NSNull(),
            "platform": "iOS",
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0",
            "lastSeenMs": nowMs,
            "isOnline": true,
            "media": mediaDict
        ]

        Task {
            if let url = await makeURL(path: "active_sessions/\(sessionId)"),
               let data = try? JSONSerialization.data(withJSONObject: payload) {
                var req = URLRequest(url: url)
                req.httpMethod = "PATCH"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = data
                _ = try? await URLSession.shared.data(for: req)
            }
        }
    }

    // MARK: - Translation Voiceover Vote Recording

    public func recordTranslationPick(
        mediaKey: String,
        title: String,
        translation: String,
        posterUrl: String? = nil
    ) {
        let cleanTrans = translation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTrans.isEmpty, !mediaKey.isEmpty else { return }

        // Deduplicate per app session so seeking or replay doesn't flood counts
        let voteKey = "\(currentSessionId)_\(mediaKey)_\(cleanTrans)"
        if recordedVotesThisSession.contains(voteKey) {
            return
        }
        recordedVotesThisSession.insert(voteKey)

        let safeVoiceKey = Self.sanitizeKey(cleanTrans)

        Task {
            // 1. Atomic increment in /media_stats/{mediaKey}
            let mediaPatch: [String: Any] = [
                "title": title,
                "posterUrl": posterUrl as Any,
                "totalPlays": [".sv": ["increment": 1]],
                "lastPlayedMs": [".sv": "timestamp"],
                "translations/\(safeVoiceKey)": [".sv": ["increment": 1]]
            ]
            if let url = await makeURL(path: "media_stats/\(mediaKey)"),
               let data = try? JSONSerialization.data(withJSONObject: mediaPatch) {
                var req = URLRequest(url: url)
                req.httpMethod = "PATCH"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = data
                _ = try? await URLSession.shared.data(for: req)
            }

            // 2. Atomic increment in /global_stats/translations
            let globalPatch: [String: Any] = [
                safeVoiceKey: [".sv": ["increment": 1]]
            ]
            if let url2 = await makeURL(path: "global_stats/translations"),
               let data2 = try? JSONSerialization.data(withJSONObject: globalPatch) {
                var req = URLRequest(url: url2)
                req.httpMethod = "PATCH"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = data2
                _ = try? await URLSession.shared.data(for: req)
            }
        }
    }

    // MARK: - Queries for Admin Dashboard & Client Views

    /// Fetches currently active sessions and currently watching sessions
    public func fetchLiveSessions() async -> (online: [LiveSessionItem], watching: [LiveSessionItem], totalGuests: Int) {
        guard let url = await makeURL(path: "active_sessions"),
              let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              !data.isEmpty, String(data: data, encoding: .utf8) != "null",
              let rawDict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return ([], [], 0)
        }

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        // Sessions active within last 2 minutes (120 seconds) are considered online
        let activeThresholdMs: Int64 = 120_000

        var onlineItems: [LiveSessionItem] = []
        var watchingItems: [LiveSessionItem] = []
        var guestCount = 0

        for (sId, val) in rawDict {
            guard let dict = val as? [String: Any] else { continue }
            let lastSeen = (dict["lastSeenMs"] as? NSNumber)?.int64Value ?? 0
            if nowMs - lastSeen > activeThresholdMs {
                continue // Inactive / stale session
            }

            let uId = dict["userId"] as? String
            let name = (dict["displayName"] as? String) ?? ""
            let tag = dict["tag"] as? String
            let avatar = dict["avatarUrl"] as? String
            let platform = (dict["platform"] as? String) ?? "iOS"
            let appVersion = (dict["appVersion"] as? String) ?? "2.0"
            let isOnline = (dict["isOnline"] as? Bool) ?? true

            if uId == nil || uId?.isEmpty == true || sId.hasPrefix("guest_") {
                guestCount += 1
            }

            var mediaObj: LiveWatchingMedia? = nil
            if let mDict = dict["media"] as? [String: Any],
               let mKey = mDict["mediaKey"] as? String,
               let mTitle = mDict["title"] as? String,
               let mTrans = mDict["translation"] as? String {
                let mSeason = (mDict["season"] as? NSNumber)?.intValue
                let mEpisode = (mDict["episode"] as? NSNumber)?.intValue
                let mPoster = mDict["posterUrl"] as? String
                let mStarted = (mDict["startedAtMs"] as? NSNumber)?.int64Value ?? lastSeen
                let mUpdated = (mDict["updatedAtMs"] as? NSNumber)?.int64Value ?? lastSeen

                // Media is considered actively playing if pinged within last 60 seconds
                if nowMs - mUpdated < 90_000 {
                    mediaObj = LiveWatchingMedia(
                        mediaKey: mKey,
                        title: mTitle,
                        season: mSeason,
                        episode: mEpisode,
                        translation: mTrans,
                        posterUrl: mPoster,
                        startedAtMs: mStarted,
                        updatedAtMs: mUpdated
                    )
                }
            }

            let item = LiveSessionItem(
                id: sId,
                userId: uId,
                displayName: name,
                tag: tag,
                avatarUrl: avatar,
                platform: platform,
                appVersion: appVersion,
                lastSeenMs: lastSeen,
                isOnline: isOnline,
                media: mediaObj
            )

            onlineItems.append(item)
            if item.isWatching {
                watchingItems.append(item)
            }
        }

        // Sort watching items by most recently updated
        watchingItems.sort { ($0.media?.updatedAtMs ?? 0) > ($1.media?.updatedAtMs ?? 0) }
        onlineItems.sort { $0.lastSeenMs > $1.lastSeenMs }

        return (onlineItems, watchingItems, guestCount)
    }

    /// Fetches translation votes and percentages for a single media item
    public func fetchMediaStats(mediaKey: String) async -> MediaAnalyticsStats? {
        if let cached = activeMediaStatsCache[mediaKey] {
            return cached
        }

        guard let url = await makeURL(path: "media_stats/\(mediaKey)"),
              let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              !data.isEmpty, String(data: data, encoding: .utf8) != "null",
              let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }

        let title = (dict["title"] as? String) ?? ""
        let poster = dict["posterUrl"] as? String
        let totalPlays = (dict["totalPlays"] as? NSNumber)?.intValue ?? 0
        let lastPlayed = (dict["lastPlayedMs"] as? NSNumber)?.int64Value

        var votes: [MediaTranslationVote] = []
        if let rawTrans = dict["translations"] as? [String: Any] {
            let totalVotes = rawTrans.values.compactMap { ($0 as? NSNumber)?.intValue }.reduce(0, +)
            for (safeKey, countVal) in rawTrans {
                guard let count = (countVal as? NSNumber)?.intValue, count > 0 else { continue }
                let realName = Self.desanitizeKey(safeKey)
                let pct = totalVotes > 0 ? (Double(count) / Double(totalVotes)) * 100.0 : 0.0
                votes.append(MediaTranslationVote(translation: realName, count: count, percentage: pct))
            }
        }

        votes.sort { $0.count > $1.count }

        let stats = MediaAnalyticsStats(
            mediaKey: mediaKey,
            title: title,
            posterUrl: poster,
            totalPlays: totalPlays,
            lastPlayedMs: lastPlayed,
            translations: votes
        )

        activeMediaStatsCache[mediaKey] = stats
        return stats
    }

    /// Fetches top media statistics for Admin Panel
    public func fetchTopMediaAnalytics() async -> [MediaAnalyticsStats] {
        guard let url = await makeURL(path: "media_stats"),
              let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              !data.isEmpty, String(data: data, encoding: .utf8) != "null",
              let rawDict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return []
        }

        var results: [MediaAnalyticsStats] = []
        for (mKey, val) in rawDict {
            guard let dict = val as? [String: Any] else { continue }
            let title = (dict["title"] as? String) ?? ""
            let poster = dict["posterUrl"] as? String
            let totalPlays = (dict["totalPlays"] as? NSNumber)?.intValue ?? 0
            let lastPlayed = (dict["lastPlayedMs"] as? NSNumber)?.int64Value

            var votes: [MediaTranslationVote] = []
            if let rawTrans = dict["translations"] as? [String: Any] {
                let totalVotes = rawTrans.values.compactMap { ($0 as? NSNumber)?.intValue }.reduce(0, +)
                for (safeKey, countVal) in rawTrans {
                    guard let count = (countVal as? NSNumber)?.intValue, count > 0 else { continue }
                    let realName = Self.desanitizeKey(safeKey)
                    let pct = totalVotes > 0 ? (Double(count) / Double(totalVotes)) * 100.0 : 0.0
                    votes.append(MediaTranslationVote(translation: realName, count: count, percentage: pct))
                }
            }
            votes.sort { $0.count > $1.count }

            results.append(MediaAnalyticsStats(
                mediaKey: mKey,
                title: title,
                posterUrl: poster,
                totalPlays: totalPlays,
                lastPlayedMs: lastPlayed,
                translations: votes
            ))
        }

        results.sort { $0.totalPlays > $1.totalPlays }
        return results
    }

    /// Fetches global translation statistics across the entire platform
    public func fetchGlobalTranslationStats() async -> [GlobalTranslationStat] {
        guard let url = await makeURL(path: "global_stats/translations"),
              let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              !data.isEmpty, String(data: data, encoding: .utf8) != "null",
              let rawDict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return []
        }

        let totalSum = rawDict.values.compactMap { ($0 as? NSNumber)?.intValue }.reduce(0, +)
        var items: [GlobalTranslationStat] = []

        for (safeKey, val) in rawDict {
            guard let count = (val as? NSNumber)?.intValue, count > 0 else { continue }
            let realName = Self.desanitizeKey(safeKey)
            let pct = totalSum > 0 ? (Double(count) / Double(totalSum)) * 100.0 : 0.0
            items.append(GlobalTranslationStat(translation: realName, count: count, percentage: pct))
        }

        items.sort { $0.count > $1.count }
        return items
    }
}
