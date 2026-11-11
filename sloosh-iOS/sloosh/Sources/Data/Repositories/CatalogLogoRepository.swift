import Foundation

/// Fetch missing catalog logos from the existing typed artwork endpoint, never
/// from a guessed numeric image-proxy URL. Coalesce requests across shelves.
@MainActor
final class CatalogLogoRepository {
    static let shared = CatalogLogoRepository()
    struct Artwork {
        var logo: String?
        var textlessPoster: String?
        var poster: String?
    }
    private struct Entry {
        let artwork: Artwork
        let expires: Date
    }
    private var cache: [CatalogArtworkIdentity: Entry] = [:]
    private var inFlight: [CatalogArtworkIdentity: Task<Artwork, Never>] = [:]

    private var generation = 0

    func invalidate() {
        generation += 1
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
        cache.removeAll()
    }

    func logo(for identity: CatalogArtworkIdentity) async -> String? {
        await artwork(for: identity).logo
    }

    func artwork(for identity: CatalogArtworkIdentity) async -> Artwork {
        if let entry = cache[identity], entry.expires > Date() { return entry.artwork }
        if let task = inFlight[identity] { return await task.value }
        let started = generation
        let task = Task<Artwork, Never> {
            guard let response = try? await MoviesApi.shared.getMediaImages(id: identity.requestId, type: identity.mediaType),
                  let data = response.data else { return Artwork() }
            func rank(_ language: String?) -> Int {
                switch language?.lowercased() {
                case "ru": return 0
                case "en": return 1
                case nil, "": return 2
                default: return 3
                }
            }
            let logos = (data.logos ?? []).enumerated().sorted {
                let a = rank($0.element.iso6391), b = rank($1.element.iso6391)
                return a == b ? $0.offset < $1.offset : a < b
            }
            let logo = logos.first { identity.acceptsLogoURL($0.element.url) }?.element.url
            let poster = data.posters?.first {
                ($0.iso6391 == nil || $0.iso6391 == "") && identity.acceptsPosterURL($0.url)
            }?.url
            let standard = (data.posters ?? []).enumerated().sorted {
                let a = rank($0.element.iso6391), b = rank($1.element.iso6391)
                return a == b ? $0.offset < $1.offset : a < b
            }.first { identity.acceptsPosterURL($0.element.url) }?.element.url
            return Artwork(logo: logo, textlessPoster: poster, poster: standard)
        }
        inFlight[identity] = task
        let result = await task.value
        guard started == generation else { return Artwork() }
        inFlight[identity] = nil
        if cache.count >= 128 { cache = cache.filter { $0.value.expires > Date() }; if cache.count >= 128 { cache.removeAll() } }
        let missing = result.logo == nil && result.textlessPoster == nil
        cache[identity] = Entry(artwork: result, expires: Date().addingTimeInterval(missing ? 60 : 1800))
        return result
    }
}
