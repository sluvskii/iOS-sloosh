import Foundation

/// Fetch missing catalog logos from the existing typed artwork endpoint, never
/// from a guessed numeric image-proxy URL. Coalesce requests across shelves.
@MainActor
final class CatalogLogoRepository {
    static let shared = CatalogLogoRepository()
    private struct Entry {
        let url: String?
        let expires: Date
    }
    private var cache: [CatalogArtworkIdentity: Entry] = [:]
    private var inFlight: [CatalogArtworkIdentity: Task<String?, Never>] = [:]

    func logo(for identity: CatalogArtworkIdentity) async -> String? {
        if let entry = cache[identity], entry.expires > Date() { return entry.url }
        if let task = inFlight[identity] { return await task.value }
        let task = Task<String?, Never> {
            guard let response = try? await MoviesApi.shared.getMediaImages(id: identity.requestId, type: identity.mediaType),
                  let logos = response.data?.logos else { return nil }
            // Keep server order within each language preference.
            let ranked = logos.enumerated().sorted { lhs, rhs in
                func rank(_ language: String?) -> Int {
                    switch language?.lowercased() {
                    case "ru": return 0
                    case "en": return 1
                    case nil, "": return 2
                    default: return 3
                    }
                }
                let a = rank(lhs.element.iso6391), b = rank(rhs.element.iso6391)
                return a == b ? lhs.offset < rhs.offset : a < b
            }
            return ranked.first(where: { identity.acceptsLogoURL($0.element.url) })?.element.url
        }
        inFlight[identity] = task
        let result = await task.value
        inFlight[identity] = nil
        if cache.count >= 128 { cache = cache.filter { $0.value.expires > Date() }; if cache.count >= 128 { cache.removeAll() } }
        cache[identity] = Entry(url: result, expires: Date().addingTimeInterval(result == nil ? 60 : 1800))
        return result
    }
}
