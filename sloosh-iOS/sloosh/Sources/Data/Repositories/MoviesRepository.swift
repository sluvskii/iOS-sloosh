import Foundation

@MainActor
class MoviesRepository: ObservableObject {
    static let shared = MoviesRepository()
    
    func getPopularMovies(page: Int = 1) async throws -> [MediaDto] {
        let response = try await MoviesApi.shared.getPopularMovies(page: page)
        return response.data?.results ?? []
    }
    
    func getTopMovies(page: Int = 1) async throws -> [MediaDto] {
        let response = try await MoviesApi.shared.getTopMovies(page: page)
        return response.data?.results ?? []
    }
    
    func getTopTv(page: Int = 1) async throws -> [MediaDto] {
        let response = try await MoviesApi.shared.getTopTv(page: page)
        return response.data?.results ?? []
    }
    
    func getDetails(id: String) async throws -> MediaDetailsDto? {
        let response = try await MoviesApi.shared.getDetails(id: id)
        return response.data
    }
    
    func searchMovies(query: String, page: Int = 1) async throws -> [MediaDto] {
        let response = try await MoviesApi.shared.searchMovies(query: query, page: page)
        return response.data?.results ?? []
    }
}
