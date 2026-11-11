import Foundation

/// Numeric movie/TV IDs are different namespaces, not interchangeable aliases.
struct CatalogArtworkIdentity: Hashable {
    let requestId: String
    let mediaType: String?
    let number: String
    let isKinopoisk: Bool

    init?(id: String?, type: String?) {
        guard let id = id?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else { return nil }
        var number = id
        var inferredType = type?.lowercased()
        var kp = false
        for prefix in ["tv_", "movie_", "tmdb_", "kp_"] where id.hasPrefix(prefix) {
            number = String(id.dropFirst(prefix.count))
            if prefix == "tv_" { inferredType = "tv" }
            if prefix == "movie_" { inferredType = "movie" }
            kp = prefix == "kp_"
            break
        }
        guard let value = Int(number), value > 0 else { return nil }
        if inferredType == "series" || inferredType == "serial" { inferredType = "tv" }
        if inferredType != "tv" && inferredType != "movie" { inferredType = nil }
        // Never infer a movie from a number with no media type.
        guard kp || inferredType != nil else { return nil }
        self.number = String(value)
        self.mediaType = inferredType
        self.isKinopoisk = kp
        self.requestId = kp ? "kp_\(value)" : "\(inferredType!)_\(value)"
    }

    func matchesOverride(_ item: MediaArtworkOverride, kpId: Int?) -> Bool {
        // Explicit type disagreement wins even if an erroneous alias carries a KP ID.
        let other = CatalogArtworkIdentity(id: item.mediaId, type: item.mediaType)
        if let mediaType, let otherType = other?.mediaType, mediaType != otherType { return false }
        if let kpId, kpId > 0, item.kpId == kpId { return true }
        if isKinopoisk { return item.mediaId == requestId || item.kpId == Int(number) }
        guard let other, !other.isKinopoisk else { return false }
        return other.requestId == requestId
    }

    func acceptsPosterURL(_ url: String) -> Bool {
        // Old numeric-only poster URLs have exactly the same namespace ambiguity
        // as logo proxies. Keep explicit image paths, never guess from a number.
        !url.contains("/api/v1/images/posters/")
    }

    func acceptsLogoURL(_ url: String) -> Bool {
        // These legacy proxies carry only a number. They may already be present
        // in old DTO/disk caches, so merely removing URL generation is not enough.
        !url.contains("/api/v1/images/logos/")
    }
}
