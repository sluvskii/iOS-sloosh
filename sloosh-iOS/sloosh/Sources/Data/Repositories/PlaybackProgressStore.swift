import Foundation

public struct PlaybackProgressRecord: Identifiable {
    public let mediaId: String
    public let kpId: Int
    public let season: Int?
    public let episode: Int?
    public let positionSec: Double
    public let durationSec: Double
    public let watched: Bool
    public let updatedAtMs: Int

    public var id: String { mediaId }

    public var isEpisode: Bool {
        season != nil && episode != nil
    }

    public var progressFraction: Double {
        guard durationSec.isFinite, durationSec > 0, positionSec.isFinite else { return 0 }
        return max(0, min(positionSec / durationSec, 0.999))
    }
}

public struct PlaybackMediaMetadata: Codable {
    public let kpId: Int
    public let detailsId: String
    public let title: String
    public let type: String?
    public let posterUrl: String?
    public let backdropUrl: String?
    public let logoUrl: String?
}

public final class PlaybackProgressStore {
    public static let shared = PlaybackProgressStore()
    private let defaults = UserDefaults.standard

    private let positionPrefix  = "neomovies.collaps.progress."
    private let durationPrefix  = "neomovies.collaps.dur."
    private let watchedPrefix   = "neomovies.collaps.watched."
    private let updatedAtPrefix = "neomovies.collaps.updatedAt."
    private let lastSeasonPrefix  = "neomovies.collaps.lastSeason."
    private let lastEpisodePrefix = "neomovies.collaps.lastEpisode."
    private let metadataPrefix = "neomovies.collaps.meta."

    // Компилируются один раз при запуске приложения, а не при каждом вызове listProgressRecords()
    private static let episodeRegex = try! NSRegularExpression(pattern: "^kp_(\\d+)_s(\\d+)_e(\\d+)$")
    private static let movieRegex   = try! NSRegularExpression(pattern: "^kp_(\\d+)$")

    private init() {}

    public func save(mediaId: String, positionSec: Double, durationSec: Double? = nil) {
        guard !mediaId.isEmpty, positionSec.isFinite, positionSec >= 0 else { return }
        defaults.set(positionSec, forKey: positionPrefix + mediaId)
        defaults.set(Int(Date().timeIntervalSince1970 * 1000), forKey: updatedAtPrefix + mediaId)
        if let dur = durationSec, dur > 0, dur.isFinite {
            defaults.set(dur, forKey: durationPrefix + mediaId)
            if positionSec / dur >= 0.9 {
                defaults.set(true, forKey: watchedPrefix + mediaId)
            }
        }
    }

    public func load(mediaId: String) -> Double {
        guard !mediaId.isEmpty else { return 0 }
        return defaults.double(forKey: positionPrefix + mediaId)
    }

    public func loadDuration(mediaId: String) -> Double {
        guard !mediaId.isEmpty else { return 0 }
        return defaults.double(forKey: durationPrefix + mediaId)
    }

    public func normalizedProgress(mediaId: String) -> Double? {
        guard !mediaId.isEmpty else { return nil }
        let position = load(mediaId: mediaId)
        let duration = loadDuration(mediaId: mediaId)
        guard position.isFinite, duration.isFinite, duration > 0 else { return nil }
        return max(0, min(position / duration, 0.999))
    }

    public func loadWatched(mediaId: String) -> Bool {
        guard !mediaId.isEmpty else { return false }
        return defaults.bool(forKey: watchedPrefix + mediaId)
    }

    public func markAsWatched(mediaId: String) {
        guard !mediaId.isEmpty else { return }
        defaults.set(true, forKey: watchedPrefix + mediaId)
    }

    public func setWatched(mediaId: String, watched: Bool) {
        guard !mediaId.isEmpty else { return }
        defaults.set(watched, forKey: watchedPrefix + mediaId)
        defaults.set(Int(Date().timeIntervalSince1970 * 1000), forKey: updatedAtPrefix + mediaId)
    }

    public func loadUpdatedAtMs(mediaId: String) -> Int {
        guard !mediaId.isEmpty else { return 0 }
        return defaults.integer(forKey: updatedAtPrefix + mediaId)
    }

    public func saveMetadata(
        kpId: Int,
        detailsId: String,
        title: String,
        type: String?,
        posterUrl: String?,
        backdropUrl: String?,
        logoUrl: String?
    ) {
        guard kpId > 0, !detailsId.isEmpty, !title.isEmpty else { return }

        let snapshot = PlaybackMediaMetadata(
            kpId: kpId,
            detailsId: detailsId,
            title: title,
            type: type,
            posterUrl: posterUrl,
            backdropUrl: backdropUrl,
            logoUrl: logoUrl
        )

        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: metadataPrefix + "kp_\(kpId)")
    }

    func saveMetadata(details: MediaDetailsDto) {
        guard let kpId = details.externalIds?.kp else { return }

        let detailsId = details.id ?? details.sourceId ?? String(kpId)
        let title = details.title ?? details.name ?? details.originalTitle ?? "Без названия"

        saveMetadata(
            kpId: kpId,
            detailsId: detailsId,
            title: title,
            type: details.type,
            posterUrl: details.displayPosterUrl,
            backdropUrl: details.displayBackdropUrl ?? details.displayPosterUrl,
            logoUrl: details.displayLogoUrl
        )
    }

    public func loadMetadata(kpId: Int) -> PlaybackMediaMetadata? {
        guard kpId > 0 else { return nil }
        guard let data = defaults.data(forKey: metadataPrefix + "kp_\(kpId)") else { return nil }
        return try? JSONDecoder().decode(PlaybackMediaMetadata.self, from: data)
    }

    public func listProgressRecords(kpId: Int? = nil) -> [PlaybackProgressRecord] {
        let allDefaults = defaults.dictionaryRepresentation()
        let prefix = positionPrefix

        guard !allDefaults.isEmpty else { return [] }

        let episodeRegex = Self.episodeRegex
        let movieRegex   = Self.movieRegex

        var records: [PlaybackProgressRecord] = []
        var seriesKpIds = Set<Int>()

        for key in allDefaults.keys {
            guard key.hasPrefix(prefix) else { continue }

            let mediaId = String(key.dropFirst(prefix.count))
            let range = NSRange(mediaId.startIndex..., in: mediaId)

            guard let match = episodeRegex.firstMatch(in: mediaId, range: range) else { continue }
            guard
                let kpRange = Range(match.range(at: 1), in: mediaId),
                let seasonRange = Range(match.range(at: 2), in: mediaId),
                let episodeRange = Range(match.range(at: 3), in: mediaId),
                let itemKpId = Int(mediaId[kpRange]),
                let season = Int(mediaId[seasonRange]),
                let episode = Int(mediaId[episodeRange])
            else {
                continue
            }

            if let kpId, itemKpId != kpId { continue }
            seriesKpIds.insert(itemKpId)

            records.append(
                PlaybackProgressRecord(
                    mediaId: mediaId,
                    kpId: itemKpId,
                    season: season,
                    episode: episode,
                    positionSec: load(mediaId: mediaId),
                    durationSec: loadDuration(mediaId: mediaId),
                    watched: loadWatched(mediaId: mediaId),
                    updatedAtMs: loadUpdatedAtMs(mediaId: mediaId)
                )
            )
        }

        for key in allDefaults.keys {
            guard key.hasPrefix(prefix) else { continue }

            let mediaId = String(key.dropFirst(prefix.count))
            let range = NSRange(mediaId.startIndex..., in: mediaId)

            guard let match = movieRegex.firstMatch(in: mediaId, range: range) else { continue }
            guard
                let kpRange = Range(match.range(at: 1), in: mediaId),
                let itemKpId = Int(mediaId[kpRange])
            else {
                continue
            }

            if let kpId, itemKpId != kpId { continue }
            if seriesKpIds.contains(itemKpId) { continue }

            records.append(
                PlaybackProgressRecord(
                    mediaId: mediaId,
                    kpId: itemKpId,
                    season: nil,
                    episode: nil,
                    positionSec: load(mediaId: mediaId),
                    durationSec: loadDuration(mediaId: mediaId),
                    watched: loadWatched(mediaId: mediaId),
                    updatedAtMs: loadUpdatedAtMs(mediaId: mediaId)
                )
            )
        }

        return records.sorted { $0.updatedAtMs > $1.updatedAtMs }
    }

    public func saveLastVoiceover(kpId: Int, source: String, voiceover: String?) {
        let key = "neomovies.\(source).lastVoiceover.kp_\(kpId)"
        if let v = voiceover {
            defaults.set(v, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    public func loadLastVoiceover(kpId: Int, source: String) -> String? {
        let key = "neomovies.\(source).lastVoiceover.kp_\(kpId)"
        return defaults.string(forKey: key)
    }

    public func saveLastPlayed(kpId: Int, season: Int?, episode: Int?) {
        if let s = season { defaults.set(s, forKey: lastSeasonPrefix + "kp_\(kpId)") }
        if let e = episode { defaults.set(e, forKey: lastEpisodePrefix + "kp_\(kpId)") }
    }

    public func loadLastSeason(kpId: Int) -> Int? {
        let v = defaults.integer(forKey: lastSeasonPrefix + "kp_\(kpId)")
        return v > 0 ? v : nil
    }

    public func loadLastEpisode(kpId: Int) -> Int? {
        let v = defaults.integer(forKey: lastEpisodePrefix + "kp_\(kpId)")
        return v > 0 ? v : nil
    }

    public var positionKeyPrefix: String { positionPrefix }
}

