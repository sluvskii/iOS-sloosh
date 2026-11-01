import Foundation

// Network/cache adapters only. Tests compile the actual Models, identity policy,
// URL sizing functions and catalog repository instead of copies of production code.
@MainActor
final class MoviesApi {
    static let shared = MoviesApi()
    nonisolated static let activeImagesBaseURL = "https://api.sloosh.workers.dev"
    var responses: [String: MediaImagesResponseDto] = [:]
    var requests: [String] = []
    func getMediaImages(id: String, type: String?) async throws -> ApiEnvelope<MediaImagesResponseDto> {
        let key = "\(type ?? "")|\(id)"
        requests.append(key)
        try await Task.sleep(for: .milliseconds(20))
        return ApiEnvelope(success: true, status: nil, data: responses[key])
    }
}

@MainActor
final class MoviesRepository {
    static let shared = MoviesRepository()
    func getCachedDetails(id: String, type: String?) -> MediaDetailsDto? { nil }
}

final class MediaOverridesRepository {
    static let shared = MediaOverridesRepository()
    var items: [MediaArtworkOverride] = []
    func catalogOverride(id: String?, type: String?, kpId: Int?) -> MediaArtworkOverride? {
        guard let identity = CatalogArtworkIdentity(id: id, type: type) else { return nil }
        return items.first { identity.matchesOverride($0, kpId: kpId) }
    }
    func override(for id: String?, tmdbId: Int?, kpId: Int?) -> MediaArtworkOverride? { nil }
}
