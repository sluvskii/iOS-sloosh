import Foundation

@MainActor
class MoviesRepository: ObservableObject {
    static let shared = MoviesRepository()
    
    // Simple memory cache
    private var popularCache: [Int: [MediaDto]] = [:]
    private var topMoviesCache: [Int: [MediaDto]] = [:]
    private var topTvCache: [Int: [MediaDto]] = [:]
    private var detailsCache: [String: MediaDetailsDto] = [:]
    private var episodeCache: [String: TvEpisodeDetailsDto] = [:]
    
    func getPopularMovies(page: Int = 1) async throws -> [MediaDto] {
        if let cached = popularCache[page] { return cached }
        let response = try await MoviesApi.shared.getPopularMovies(page: page)
        let results = response.data?.results ?? []
        popularCache[page] = results
        return results
    }
    
    func getTopMovies(page: Int = 1) async throws -> [MediaDto] {
        if let cached = topMoviesCache[page] { return cached }
        let response = try await MoviesApi.shared.getTopMovies(page: page)
        let results = response.data?.results ?? []
        topMoviesCache[page] = results
        return results
    }
    
    func getTopTv(page: Int = 1) async throws -> [MediaDto] {
        if let cached = topTvCache[page] { return cached }
        let response = try await MoviesApi.shared.getTopTv(page: page)
        let results = response.data?.results ?? []
        topTvCache[page] = results
        return results
    }
    
    func getDetails(id: String) async throws -> MediaDetailsDto? {
        if let cached = detailsCache[id] { return cached }
        let response = try await MoviesApi.shared.getDetails(id: id)
        if let details = response.data {
            detailsCache[id] = details
        }
        return response.data
    }
    
    func getEpisodeDetails(id: String, season: Int, episode: Int) async throws -> TvEpisodeDetailsDto? {
        let cacheKey = "\(id)-\(season)-\(episode)"
        if let cached = episodeCache[cacheKey] { return cached }
        
        let response = try await MoviesApi.shared.getEpisodeDetails(id: id, season: season, episode: episode)
        if let data = response.data {
            episodeCache[cacheKey] = data
        }
        return response.data
    }
    
    func searchMovies(query: String, page: Int = 1) async throws -> [MediaDto] {
        let response = try await MoviesApi.shared.searchMovies(query: query, page: page)
        return response.data?.results ?? []
    }

    func searchMoviesResponse(query: String, page: Int = 1) async throws -> MediaResponse {
        let response = try await MoviesApi.shared.searchMovies(query: query, page: page)
        return response.data ?? MediaResponse(page: page, results: [], pages: 1, total: 0, total_pages: 1, total_results: 0)
    }
}
