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
    var cached: MediaDetailsDto?
    func getCachedDetails(id: String, type: String?) -> MediaDetailsDto? { cached }
}

final class MediaOverridesRepository {
    static let shared = MediaOverridesRepository()
    var items: [MediaArtworkOverride] = []
    func catalogOverride(id: String?, type: String?, kpId: Int?) -> MediaArtworkOverride? {
        ArtworkOverrideStore.resolve(items, id: id, type: type, kpId: kpId)
    }
    func override(for id: String?, tmdbId: Int?, kpId: Int?, type: String? = nil) -> MediaArtworkOverride? {
        ArtworkOverrideStore.resolve(items, id: id, type: type, tmdbId: tmdbId, kpId: kpId)
    }
}
