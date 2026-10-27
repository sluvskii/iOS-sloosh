import Foundation
import Combine

@MainActor
final class RemoteCampaignStore: ObservableObject {
    static let shared = RemoteCampaignStore()
    @Published private(set) var campaigns: [RemoteCampaign] = []
    private var fetchedAt: Date = .distantPast
    private let defaults: UserDefaults
    private let cacheKey = "sloosh_editorial_campaigns_v1"

    private struct Cache: Codable {
        let fetchedAt: Date
        let campaigns: [RemoteCampaign]
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: cacheKey), data.count <= RemoteCampaignConfig.maximumBytes,
           let cache = try? JSONDecoder().decode(Cache.self, from: data),
           RemoteCampaignConfig.isCacheFresh(fetchedAt: cache.fetchedAt, now: Date()) {
            campaigns = Array(cache.campaigns.filter(\.isValid).prefix(12))
            fetchedAt = cache.fetchedAt
        }
    }

    /// Called only after a successful endpoint.json response. Offline failures do
    /// not erase a still-fresh cache; a missing/disabled section is a kill switch.
    func apply(_ data: Data?, now: Date = Date()) {
        let updated = RemoteCampaignConfig.decode(data)
        fetchedAt = now
        // Publish even an unchanged payload: a successful refresh can revive
        // a previously expired offline cache without changing campaign content.
        campaigns = updated
        if let encoded = try? JSONEncoder().encode(Cache(fetchedAt: now, campaigns: updated)) {
            defaults.set(encoded, forKey: cacheKey)
        }
    }

    func detailsCampaign(id: String?, type: String?, tmdbId: Int?, at now: Date) -> RemoteCampaign? {
        guard RemoteCampaignConfig.isCacheFresh(fetchedAt: fetchedAt, now: now) else { return nil }
        let matching = campaigns.filter {
            $0.enabled && $0.matches(mediaId: id, mediaType: type, tmdbId: tmdbId)
                && now < $0.expiresAt
        }
        // An upcoming higher-priority event must not mask an already-active one.
        return matching.first { $0.isActive(at: now) }
            ?? matching.filter { now < $0.startsAt }.min { $0.startsAt < $1.startsAt }
    }

    func isFresh(at now: Date) -> Bool {
        RemoteCampaignConfig.isCacheFresh(fetchedAt: fetchedAt, now: now)
    }
}
