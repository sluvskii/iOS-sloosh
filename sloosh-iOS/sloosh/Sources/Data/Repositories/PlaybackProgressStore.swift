import Foundation

public struct PlaybackProgressRecord: Identifiable, Codable {
    public let mediaId: String
    public let kpId: Int
    public let season: Int?
    public let episode: Int?
    public var positionSec: Double
    public var durationSec: Double
    public var watched: Bool
    public var updatedAtMs: Int

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

public struct PlaybackProgressStoreState: Codable {
    public var records: [String: PlaybackProgressRecord] = [:]
    public var metadata: [String: PlaybackMediaMetadata] = [:]
    public var lastVoiceovers: [String: String] = [:]
    public var lastSeasons: [String: Int] = [:]
    public var lastEpisodes: [String: Int] = [:]
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

    private static let episodeRegex = try! NSRegularExpression(pattern: "^kp_(\\d+)_s(\\d+)_e(\\d+)$")
    private static let movieRegex   = try! NSRegularExpression(pattern: "^kp_(\\d+)$")

    private let dataStore = JSONDataStore<PlaybackProgressStoreState>(fileName: "playback_progress")
    private var state: PlaybackProgressStoreState
    private let queue = DispatchQueue(label: "ru.neomovies.progressstore.sync", attributes: .concurrent)

    private init() {
        state = PlaybackProgressStoreState()
        if UserDefaults.standard.bool(forKey: "neomovies.collaps.migrated") == false {
            migrateFromUserDefaults()
            UserDefaults.standard.set(true, forKey: "neomovies.collaps.migrated")
        } else {
            state = dataStore.load(defaultValue: PlaybackProgressStoreState())
        }
    }

    private func saveState() {
        dataStore.save(state)
    }

    private func getRecord(mediaId: String) -> PlaybackProgressRecord? {
        queue.sync { state.records[mediaId] }
    }

    private func mutateRecord(mediaId: String, mutate: (inout PlaybackProgressRecord) -> Void) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            if var record = self.state.records[mediaId] {
                mutate(&record)
                record.updatedAtMs = Int(Date().timeIntervalSince1970 * 1000)
                self.state.records[mediaId] = record
            } else {
                // Determine kpId, season, episode from mediaId
                let range = NSRange(mediaId.startIndex..., in: mediaId)
                var kpId = 0
                var season: Int? = nil
                var episode: Int? = nil

                if let match = Self.episodeRegex.firstMatch(in: mediaId, range: range) {
                    if let kpRange = Range(match.range(at: 1), in: mediaId),
                       let seasonRange = Range(match.range(at: 2), in: mediaId),
                       let episodeRange = Range(match.range(at: 3), in: mediaId) {
                        kpId = Int(mediaId[kpRange]) ?? 0
                        season = Int(mediaId[seasonRange])
                        episode = Int(mediaId[episodeRange])
                    }
                } else if let match = Self.movieRegex.firstMatch(in: mediaId, range: range) {
                    if let kpRange = Range(match.range(at: 1), in: mediaId) {
                        kpId = Int(mediaId[kpRange]) ?? 0
                    }
                }

                var record = PlaybackProgressRecord(
                    mediaId: mediaId,
                    kpId: kpId,
                    season: season,
                    episode: episode,
                    positionSec: 0,
                    durationSec: 0,
                    watched: false,
                    updatedAtMs: Int(Date().timeIntervalSince1970 * 1000)
                )
                mutate(&record)
                self.state.records[mediaId] = record
            }
            self.saveState()
        }
    }

    public func save(mediaId: String, positionSec: Double, durationSec: Double? = nil) {
        guard !mediaId.isEmpty, positionSec.isFinite, positionSec >= 0 else { return }
        mutateRecord(mediaId: mediaId) { record in
            record.positionSec = positionSec
            if let dur = durationSec, dur > 0, dur.isFinite {
                record.durationSec = dur
                if positionSec / dur >= 0.9 {
                    record.watched = true
                }
            }
        }
    }

    public func load(mediaId: String) -> Double {
        guard !mediaId.isEmpty else { return 0 }
        return getRecord(mediaId: mediaId)?.positionSec ?? 0
    }

    public func loadDuration(mediaId: String) -> Double {
        guard !mediaId.isEmpty else { return 0 }
        return getRecord(mediaId: mediaId)?.durationSec ?? 0
    }

    public func normalizedProgress(mediaId: String) -> Double? {
        guard !mediaId.isEmpty else { return nil }
        guard let record = getRecord(mediaId: mediaId) else { return nil }
        let duration = record.durationSec
        let position = record.positionSec
        guard position.isFinite, duration.isFinite, duration > 0 else { return nil }
        return max(0, min(position / duration, 0.999))
    }

    public func loadWatched(mediaId: String) -> Bool {
        guard !mediaId.isEmpty else { return false }
        return getRecord(mediaId: mediaId)?.watched ?? false
    }

    public func markAsWatched(mediaId: String) {
        guard !mediaId.isEmpty else { return }
        mutateRecord(mediaId: mediaId) { record in
            record.watched = true
        }
    }

    public func setWatched(mediaId: String, watched: Bool) {
        guard !mediaId.isEmpty else { return }
        mutateRecord(mediaId: mediaId) { record in
            record.watched = watched
        }
    }

    public func loadUpdatedAtMs(mediaId: String) -> Int {
        guard !mediaId.isEmpty else { return 0 }
        return getRecord(mediaId: mediaId)?.updatedAtMs ?? 0
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

        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            self.state.metadata["kp_\(kpId)"] = snapshot
            self.saveState()
        }
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
        return queue.sync { state.metadata["kp_\(kpId)"] }
    }

    public func listProgressRecords(kpId: Int? = nil) -> [PlaybackProgressRecord] {
        return queue.sync {
            var results: [PlaybackProgressRecord] = []
            var seriesKpIds = Set<Int>()
            
            // Episodes first
            for (_, record) in state.records {
                if record.isEpisode {
                    if let kpId = kpId, record.kpId != kpId { continue }
                    seriesKpIds.insert(record.kpId)
                    results.append(record)
                }
            }
            
            // Movies
            for (_, record) in state.records {
                if !record.isEpisode {
                    if let kpId = kpId, record.kpId != kpId { continue }
                    if seriesKpIds.contains(record.kpId) { continue }
                    results.append(record)
                }
            }
            
            return results.sorted { $0.updatedAtMs > $1.updatedAtMs }
        }
    }

    public func saveLastVoiceover(kpId: Int, source: String, voiceover: String?) {
        let key = "neomovies.\(source).lastVoiceover.kp_\(kpId)"
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            if let v = voiceover {
                self.state.lastVoiceovers[key] = v
            } else {
                self.state.lastVoiceovers.removeValue(forKey: key)
            }
            self.saveState()
        }
    }

    public func loadLastVoiceover(kpId: Int, source: String) -> String? {
        let key = "neomovies.\(source).lastVoiceover.kp_\(kpId)"
        return queue.sync { state.lastVoiceovers[key] }
    }

    public func saveLastPlayed(kpId: Int, season: Int?, episode: Int?) {
        let sKey = "kp_\(kpId)"
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            if let s = season { self.state.lastSeasons[sKey] = s }
            if let e = episode { self.state.lastEpisodes[sKey] = e }
            self.saveState()
        }
    }

    public func loadLastSeason(kpId: Int) -> Int? {
        let sKey = "kp_\(kpId)"
        return queue.sync { state.lastSeasons[sKey] }
    }

    public func loadLastEpisode(kpId: Int) -> Int? {
        let sKey = "kp_\(kpId)"
        return queue.sync { state.lastEpisodes[sKey] }
    }

    public var positionKeyPrefix: String { positionPrefix }

    private func migrateFromUserDefaults() {
        let allDefaults = defaults.dictionaryRepresentation()
        let prefix = positionPrefix
        var migratedRecords: [String: PlaybackProgressRecord] = .init()

        for key in allDefaults.keys {
            guard key.hasPrefix(prefix) else { continue }
            let mediaId = String(key.dropFirst(prefix.count))
            
            let range = NSRange(mediaId.startIndex..., in: mediaId)
            var kpId = 0
            var season: Int? = nil
            var episode: Int? = nil

            if let match = Self.episodeRegex.firstMatch(in: mediaId, range: range) {
                if let kpRange = Range(match.range(at: 1), in: mediaId),
                   let seasonRange = Range(match.range(at: 2), in: mediaId),
                   let episodeRange = Range(match.range(at: 3), in: mediaId) {
                    kpId = Int(mediaId[kpRange]) ?? 0
                    season = Int(mediaId[seasonRange])
                    episode = Int(mediaId[episodeRange])
                }
            } else if let match = Self.movieRegex.firstMatch(in: mediaId, range: range) {
                if let kpRange = Range(match.range(at: 1), in: mediaId) {
                    kpId = Int(mediaId[kpRange]) ?? 0
                }
            }

            let pos = defaults.double(forKey: positionPrefix + mediaId)
            let dur = defaults.double(forKey: durationPrefix + mediaId)
            let watched = defaults.bool(forKey: watchedPrefix + mediaId)
            let updatedAt = defaults.integer(forKey: updatedAtPrefix + mediaId)

            let record = PlaybackProgressRecord(
                mediaId: mediaId,
                kpId: kpId,
                season: season,
                episode: episode,
                positionSec: pos,
                durationSec: dur,
                watched: watched,
                updatedAtMs: updatedAt
            )
            migratedRecords[mediaId] = record
        }

        self.state.records = migratedRecords

        for key in allDefaults.keys {
            if key.hasPrefix(metadataPrefix) {
                if let data = defaults.data(forKey: key),
                   let meta = try? JSONDecoder().decode(PlaybackMediaMetadata.self, from: data) {
                    let mapKey = key.replacingOccurrences(of: metadataPrefix, with: "")
                    self.state.metadata[mapKey] = meta
                }
            } else if key.contains(".lastVoiceover.") {
                if let val = defaults.string(forKey: key) {
                    self.state.lastVoiceovers[key] = val
                }
            } else if key.hasPrefix(lastSeasonPrefix) {
                let mapKey = key.replacingOccurrences(of: lastSeasonPrefix, with: "")
                self.state.lastSeasons[mapKey] = defaults.integer(forKey: key)
            } else if key.hasPrefix(lastEpisodePrefix) {
                let mapKey = key.replacingOccurrences(of: lastEpisodePrefix, with: "")
                self.state.lastEpisodes[mapKey] = defaults.integer(forKey: key)
            }
        }

        // Save migrated state to JSON
        saveState()

        // Clean up old defaults
        for key in allDefaults.keys {
            if key.hasPrefix("neomovies.collaps.") {
                defaults.removeObject(forKey: key)
            }
        }
    }
}
