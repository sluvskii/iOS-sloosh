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
    enum Unit: CaseIterable {
        case months, days, hours, minutes, seconds

        func label(for value: Int) -> String {
            let forms: (one: String, few: String, many: String)
            switch self {
            case .months: forms = ("месяц", "месяца", "месяцев")
            case .days: forms = ("день", "дня", "дней")
            case .hours: forms = ("час", "часа", "часов")
            case .minutes: forms = ("минута", "минуты", "минут")
            case .seconds: forms = ("секунда", "секунды", "секунд")
            }
            // 11–14 take precedence over the last digit: 111 дней, not день.
            // magnitude also avoids overflow for Int.min.
            let lastHundred = value.magnitude % 100
            if (11...14).contains(lastHundred) { return forms.many }
            switch value.magnitude % 10 {
            case 1: return forms.one
            case 2...4: return forms.few
            default: return forms.many
            }
        }
    }

    var spokenDescription: String {
        [(months, Unit.months), (days, .days), (hours, .hours), (minutes, .minutes), (seconds, .seconds)]
            .map { "\($0.0) \($0.1.label(for: $0.0))" }
            .joined(separator: ", ")
    }

    let months: Int
    let days: Int
    let hours: Int
    let minutes: Int
    let seconds: Int

    init(until target: Date, now: Date, timeZone: TimeZone = .gmt) {
        // Months and residual days are calendar units, not fixed 30-day buckets.
        // Fix the Gregorian calendar and event zone, independent of device settings.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard target > now else {
            months = 0; days = 0; hours = 0; minutes = 0; seconds = 0
            return
        }
        // Work at whole-second precision: the last fraction of a second still
        // shows 01, and calendar boundaries never inherit subsecond noise.
        let start = Date(timeIntervalSinceReferenceDate: floor(now.timeIntervalSinceReferenceDate))
        let remaining = min(315_576_000, ceil(target.timeIntervalSince(start)))
        let end = start.addingTimeInterval(remaining)
        let parts = calendar.dateComponents([.month, .day, .hour, .minute, .second], from: start, to: end)
        months = max(0, parts.month ?? 0)
        days = max(0, parts.day ?? 0)
        hours = max(0, parts.hour ?? 0)
        minutes = max(0, parts.minute ?? 0)
        seconds = max(0, parts.second ?? 0)
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
