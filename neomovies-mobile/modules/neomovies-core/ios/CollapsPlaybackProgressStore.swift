import Foundation

public final class CollapsPlaybackProgressStore {
    public static let shared = CollapsPlaybackProgressStore()
    private let defaults = UserDefaults.standard

    private let positionPrefix  = "neomovies.collaps.progress."
    private let durationPrefix  = "neomovies.collaps.dur."
    private let watchedPrefix   = "neomovies.collaps.watched."
    private let updatedAtPrefix = "neomovies.collaps.updatedAt."
    private let lastSeasonPrefix  = "neomovies.collaps.lastSeason."
    private let lastEpisodePrefix = "neomovies.collaps.lastEpisode."

    private init() {}

    // MARK: - Per-item progress

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
        defaults.synchronize()
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
        defaults.synchronize()
    }

    public func loadUpdatedAtMs(mediaId: String) -> Int {
        guard !mediaId.isEmpty else { return 0 }
        return defaults.integer(forKey: updatedAtPrefix + mediaId)
    }

    // MARK: - Last-played tracking (per kpId)

    public func saveLastPlayed(kpId: Int, season: Int?, episode: Int?) {
        if let s = season { defaults.set(s, forKey: lastSeasonPrefix + "kp_\(kpId)") }
        if let e = episode { defaults.set(e, forKey: lastEpisodePrefix + "kp_\(kpId)") }
        defaults.synchronize()
    }

    public func loadLastSeason(kpId: Int) -> Int? {
        let v = defaults.integer(forKey: lastSeasonPrefix + "kp_\(kpId)")
        return v > 0 ? v : nil
    }

    public func loadLastEpisode(kpId: Int) -> Int? {
        let v = defaults.integer(forKey: lastEpisodePrefix + "kp_\(kpId)")
        return v > 0 ? v : nil
    }

    // MARK: - Key prefix exposure (for scanning in module)

    public var positionKeyPrefix: String { positionPrefix }
}
