import Foundation

enum NetworkError: Error {
    case invalidURL
    case noData
    case decodingError
    case serverError(Int)
}

class MoviesApi {
    static let shared = MoviesApi()
    
    // Default base URL from android project (would normally be in config)
    private let baseURL = "https://api.neome.uk"
    
    private let session: URLSession
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15.0
        config.timeoutIntervalForResource = 30.0
        config.requestCachePolicy = .returnCacheDataElseLoad
        self.session = URLSession(configuration: config)
    }
    
    private func performRequest<T: Codable>(endpoint: String, method: String = "GET", queryItems: [URLQueryItem] = []) async throws -> T {
        var components = URLComponents(string: "\(baseURL)/\(endpoint)")
        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }
        
        guard let url = components?.url else {
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        // Add auth headers if needed
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 500
            throw NetworkError.serverError(statusCode)
        }
        
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        } catch {
            print("Decoding error: \(error)")
            throw NetworkError.decodingError
        }
    }
    
    func getPopularMovies(page: Int = 1) async throws -> ApiEnvelope<MediaResponse> {
        return try await performRequest(endpoint: "api/v1/movies/popular", queryItems: [URLQueryItem(name: "page", value: String(page))])
    }
    
    func getTopMovies(page: Int = 1) async throws -> ApiEnvelope<MediaResponse> {
        return try await performRequest(endpoint: "api/v1/movies/top-rated", queryItems: [URLQueryItem(name: "page", value: String(page))])
    }
    
    func getTopTv(page: Int = 1) async throws -> ApiEnvelope<MediaResponse> {
        return try await performRequest(endpoint: "api/v1/tv/top-rated", queryItems: [URLQueryItem(name: "page", value: String(page))])
    }
    
    func getDetails(id: String) async throws -> ApiEnvelope<MediaDetailsDto> {
        return try await performRequest(endpoint: "api/v2/movie/\(id)")
    }
    
    func getEpisodeDetails(id: String, season: Int, episode: Int) async throws -> ApiEnvelope<TvEpisodeDetailsDto> {
        return try await performRequest(endpoint: "api/v1/tv/\(id)/season/\(season)/episode/\(episode)")
    }
    
    func searchMovies(query: String, page: Int = 1, filters: SearchFilters? = nil) async throws -> ApiEnvelope<MediaResponse> {
        var queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "page", value: String(page))
        ]
        
        if let filters = filters {
            if let type = filters.type { queryItems.append(URLQueryItem(name: "type", value: type)) }
            if let order = filters.order { queryItems.append(URLQueryItem(name: "order", value: order)) }
            if let rFrom = filters.ratingFrom { queryItems.append(URLQueryItem(name: "ratingFrom", value: String(rFrom))) }
            if let rTo = filters.ratingTo { queryItems.append(URLQueryItem(name: "ratingTo", value: String(rTo))) }
            if let yFrom = filters.yearFrom { queryItems.append(URLQueryItem(name: "yearFrom", value: String(yFrom))) }
            if let yTo = filters.yearTo { queryItems.append(URLQueryItem(name: "yearTo", value: String(yTo))) }
            if let genres = filters.genres { queryItems.append(URLQueryItem(name: "genres", value: genres)) }
            if let countries = filters.countries { queryItems.append(URLQueryItem(name: "countries", value: countries)) }
        }
        
        return try await performRequest(endpoint: "api/v2/search", queryItems: queryItems)
    }
}
