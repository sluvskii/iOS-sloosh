import Foundation

/// Data-only editorial content, never executable UI, HTML, arbitrary routes or scripts.
struct RemoteCampaign: Codable, Equatable, Identifiable {
    enum Kind: String, Codable { case countdown, feature }
    enum Theme: String, Codable { case emerald, crimson, neutral }
    enum Completion: String, Codable { case hide, message }

    let id: String
    let enabled: Bool
    let kind: Kind
    let title: String
    let subtitle: String
    let mediaId: String
    let theme: Theme
    let startsAt: Date
    let expiresAt: Date
    let countdownTo: Date?
    let timeZone: String
    let afterCountdown: Completion
    let completedText: String?
    let disclaimer: String?
    let artworkURL: String?
    let bundledArtwork: String?
    let priority: Int

    var mediaType: String { mediaId.hasPrefix("tv_") ? "tv" : "movie" }
    var numericMediaId: String { String(mediaId.dropFirst(mediaType == "tv" ? 3 : 6)) }

    var isValid: Bool {
        guard !id.isEmpty, id.count <= 64,
              id.range(of: "^[a-zA-Z0-9_-]+$", options: .regularExpression) != nil,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 100,
              !subtitle.isEmpty, subtitle.count <= 160,
              mediaId.range(of: "^(movie|tv)_[1-9][0-9]{0,9}$", options: .regularExpression) != nil,
              expiresAt > startsAt,
              TimeZone(identifier: timeZone) != nil,
              (disclaimer?.count ?? 0) <= 240, (completedText?.count ?? 0) <= 100,
              bundledArtwork == nil || bundledArtwork == "doomsday" else { return false }
        if let artworkURL {
            guard artworkURL.count <= 2048, let url = URL(string: artworkURL),
                  url.scheme == "https", url.host != nil, url.user == nil, url.password == nil else { return false }
        }
        if kind == .countdown {
            guard let countdownTo, countdownTo > startsAt, countdownTo <= expiresAt else { return false }
            if afterCountdown == .message && (completedText?.isEmpty != false) { return false }
        }
        return true
    }

    func isActive(at now: Date) -> Bool {
        guard enabled, now >= startsAt, now < expiresAt else { return false }
        if kind == .countdown, let countdownTo, now >= countdownTo {
            return afterCountdown == .message
        }
        return true
    }

    func matches(mediaId id: String?, mediaType type: String?, tmdbId: Int?) -> Bool {
        if let type, (type == "tv") != (mediaType == "tv") { return false }
        if let tmdbId { return String(tmdbId) == numericMediaId }
        return id == mediaId || id == numericMediaId
    }

    func premiereDateLabel() -> String {
        guard let countdownTo else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = TimeZone(identifier: timeZone)
        formatter.dateFormat = "d MMMM yyyy"
        return formatter.string(from: countdownTo)
    }
}

struct CampaignCountdown: Equatable {
    let days: Int
    let hours: Int
    let minutes: Int
    let seconds: Int

    init(until target: Date, now: Date) {
        // Round up, so the final second is not presented as zero prematurely.
        let remaining = max(0, min(315_576_000, ceil(target.timeIntervalSince(now))))
        let total = Int(remaining)
        days = total / 86_400
        hours = (total % 86_400) / 3_600
        minutes = (total % 3_600) / 60
        seconds = total % 60
    }
}

/// Isolates bad entries: one malformed campaign cannot break the endpoint config
/// or prevent other, valid editorial content from loading.
enum RemoteCampaignConfig {
    static let maximumBytes = 64 * 1024
    static let maximumCacheAge: TimeInterval = 72 * 60 * 60

    static func decode(_ data: Data?) -> [RemoteCampaign] {
        guard let data, data.count <= maximumBytes,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = root["version"] as? Int, version == 1,
              let enabled = root["enabled"] as? Bool, enabled,
              let items = root["items"] as? [Any] else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var seen = Set<String>()
        return items.prefix(12).compactMap { item in
            guard JSONSerialization.isValidJSONObject(item),
                  let bytes = try? JSONSerialization.data(withJSONObject: item),
                  let campaign = try? decoder.decode(RemoteCampaign.self, from: bytes),
                  campaign.isValid, seen.insert(campaign.id).inserted else { return nil }
            return campaign
        }.sorted {
            $0.priority == $1.priority ? $0.id < $1.id : $0.priority > $1.priority
        }
    }

    static func isCacheFresh(fetchedAt: Date, now: Date) -> Bool {
        let age = now.timeIntervalSince(fetchedAt)
        return age >= 0 && age <= maximumCacheAge
    }
}
