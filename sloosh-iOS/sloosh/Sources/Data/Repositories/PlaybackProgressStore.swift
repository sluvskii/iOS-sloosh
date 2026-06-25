import Foundation

public final class PlaybackProgressStore {
    public static let shared = PlaybackProgressStore()
    private let defaults = UserDefaults.standard

    private let positionPrefix  = "neomovies.collaps.progress."
    private let durationPrefix  = "neomovies.collaps.dur."
    private let watchedPrefix   = "neomovies.collaps.watched."
    private let updatedAtPrefix = "neomovies.collaps.updatedAt."
    private let lastSeasonPrefix  = "neomovies.collaps.lastSeason."
    private let lastEpisodePrefix = "neomovies.collaps.lastEpisode."

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
