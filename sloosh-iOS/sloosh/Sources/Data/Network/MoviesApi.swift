import Foundation

enum NetworkError: LocalizedError {
    case invalidURL
    case noData
    case decodingError
    case serverError(Int)
    case noInternetConnection
    case timeout
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Некорректный адрес сервера"
        case .noData:
            return "Сервер не вернул данные"
        case .decodingError:
            return "Ошибка обработки ответа сервера"
        case .serverError(let code):
            return "Ошибка сервера (\(code))"
        case .noInternetConnection:
            return "Нет подключения к интернету"
        case .timeout:
            return "Превышено время ожидания ответа"
        }
    }
}

class MoviesApi {
    static let shared = MoviesApi()
    
    // Production base URL on Vercel
    private let baseURL = "https://api-sloosh.vercel.app"
    
    private let session: URLSession
    private let decoder = JSONDecoder()
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15.0
        config.timeoutIntervalForResource = 30.0
        config.requestCachePolicy = .useProtocolCachePolicy
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
        
        let maxRetries = 3
        var lastError: Error = NetworkError.timeout
        
        for attempt in 0..<maxRetries {
            if attempt > 0 {
                // Экспоненциальная задержка: 0.5с, 1с, 2с
                let delay = UInt64(500_000_000) * UInt64(1 << (attempt - 1)) // 0.5s * 2^(attempt-1)
                try? await Task.sleep(nanoseconds: delay)
            }
            
            do {
                let (data, response) = try await session.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    lastError = NetworkError.serverError(500)
                    continue
                }
                
                // 4xx — не ретраим, это клиентская ошибка
                if (400...499).contains(httpResponse.statusCode) {
                    throw NetworkError.serverError(httpResponse.statusCode)
                }
                
                // 5xx — ретраим
                if !(200...299).contains(httpResponse.statusCode) {
                    lastError = NetworkError.serverError(httpResponse.statusCode)
                    continue
                }
                
                return try self.decoder.decode(T.self, from: data)
            } catch let error as NetworkError {
                // Наши собственные ошибки — пробрасываем немедленно (4xx, invalidURL)
                throw error
            } catch let urlError as URLError {
                if urlError.code == .notConnectedToInternet || urlError.code == .networkConnectionLost {
                    lastError = NetworkError.noInternetConnection
                    // При отсутствии интернета нет смысла ретраить немедленно, но
                    // даём одну-две попытки на случай нестабильного соединения
                    continue
                } else if urlError.code == .timedOut {
                    lastError = NetworkError.timeout
                    continue
                } else if urlError.code == .cancelled {
                    throw URLError(.cancelled)
                }
                lastError = NetworkError.noInternetConnection
                continue
            } catch {
                // DecodingError — не ретраим
                print("Decoding error: \(error)")
                throw NetworkError.decodingError
            }
        }
        
        throw lastError
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
    
    func getCartoons(page: Int = 1) async throws -> ApiEnvelope<MediaResponse> {
        return try await performRequest(endpoint: "api/v1/cartoons", queryItems: [URLQueryItem(name: "page", value: String(page))])
    }

    func getAnime(page: Int = 1, order: String? = nil) async throws -> ApiEnvelope<MediaResponse> {
        var queryItems = [URLQueryItem(name: "page", value: String(page))]
        if let order = order, !order.isEmpty {
            queryItems.append(URLQueryItem(name: "order", value: order))
        }
        return try await performRequest(endpoint: "api/v1/anime", queryItems: queryItems)
    }
    
    func getDetails(id: String, type: String? = nil) async throws -> ApiEnvelope<MediaDetailsDto> {
        let cleanId = id.replacingOccurrences(of: "tv_", with: "").replacingOccurrences(of: "movie_", with: "")
        let inferredType = type ?? (id.hasPrefix("tv_") ? "tv" : (id.hasPrefix("movie_") ? "movie" : nil))
        
        let endpoint: String
        if inferredType == "tv" {
            endpoint = "api/v2/tv/\(cleanId)"
        } else {
            endpoint = "api/v2/movie/\(cleanId)"
        }
        
        var queryItems: [URLQueryItem] = []
        if let t = inferredType {
            queryItems.append(URLQueryItem(name: "type", value: t))
        }
        
        return try await performRequest(endpoint: endpoint, queryItems: queryItems)
    }
    
    func getSeason(id: String, season: Int) async throws -> ApiEnvelope<TvSeasonDto> {
        return try await performRequest(endpoint: "api/v1/tv/\(id)/season/\(season)")
    }
    
    func getEpisodeDetails(id: String, season: Int, episode: Int) async throws -> ApiEnvelope<TvEpisodeDetailsDto> {
        return try await performRequest(endpoint: "api/v1/tv/\(id)/season/\(season)/episode/\(episode)")
    }

    func getPersonDetails(id: Int) async throws -> ApiEnvelope<PersonDetailsDto> {
        return try await performRequest(endpoint: "api/v2/person/\(id)")
    }
    
    func searchMovies(query: String, page: Int = 1) async throws -> ApiEnvelope<MediaResponse> {
        var queryItems = [
            URLQueryItem(name: "page", value: String(page))
        ]
        
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            queryItems.append(URLQueryItem(name: "query", value: trimmed))
        }
        
        // v1/search использует Kinopoisk Full-Text Fuzzy Search:
        // - правильно обрабатывает опечатки, е/ё, транслит
        // - даёт корректный порядок результатов по релевантности
        return try await performRequest(endpoint: "api/v1/search", queryItems: queryItems)
    }

    func discoverMovies(filters: SearchFilters, page: Int = 1) async throws -> ApiEnvelope<MediaResponse> {
        var queryItems = [
            URLQueryItem(name: "page", value: String(page))
        ]
        
        if let type = filters.type, !type.isEmpty {
            queryItems.append(URLQueryItem(name: "type", value: type))
        }
        
        if let order = filters.order, !order.isEmpty {
            queryItems.append(URLQueryItem(name: "order", value: order))
        }
        
        if let genres = filters.genres, !genres.isEmpty {
            queryItems.append(URLQueryItem(name: "genres", value: genres.lowercased()))
        }
        
        if let countries = filters.countries, !countries.isEmpty {
            queryItems.append(URLQueryItem(name: "countries", value: countries))
        }

        if let ratingFrom = filters.ratingFrom, ratingFrom > 1.0 {
            queryItems.append(URLQueryItem(name: "ratingFrom", value: String(format: "%.1f", ratingFrom)))
        }

        if let yearFrom = filters.yearFrom, yearFrom > 1980 {
            queryItems.append(URLQueryItem(name: "yearFrom", value: String(yearFrom)))
        }
        
        // api/v2/search — серверный движок каталога с поддержкой параметров фильтров
        return try await performRequest(endpoint: "api/v2/search", queryItems: queryItems)
    }

    // MARK: - Categories & Collections (feat/ts-migration)

    func getCategories() async throws -> ApiEnvelope<[CategorySectionDto]> {
        return try await performRequest(endpoint: "api/v1/categories")
    }

    func getCollection(id: String, page: Int = 1) async throws -> ApiEnvelope<MediaResponse> {
        let queryItems = [
            URLQueryItem(name: "page", value: String(page))
        ]
        return try await performRequest(endpoint: "api/v1/collection/\(id)", queryItems: queryItems)
    }

    func getRelatedByStudio(type: String, id: String, page: Int = 1) async throws -> ApiEnvelope<RelatedStudioResponse> {
        let cleanType = (type.lowercased().contains("tv") || type.lowercased().contains("serial")) ? "tv" : "movie"
        let cleanId = id.replacingOccurrences(of: "kp_", with: "")
        let queryItems = [
            URLQueryItem(name: "page", value: String(page))
        ]
        return try await performRequest(endpoint: "api/v1/media/\(cleanType)/\(cleanId)/related/studio", queryItems: queryItems)
    }

    func getMovieCollection(id: String) async throws -> ApiEnvelope<MovieCollectionDto> {
        let cleanId = id.replacingOccurrences(of: "kp_", with: "")
        return try await performRequest(endpoint: "api/v1/media/movie/\(cleanId)/collection")
    }

    func getRelatedByCast(type: String, id: String, page: Int = 1) async throws -> ApiEnvelope<MediaResponse> {
        let cleanType = (type.lowercased().contains("tv") || type.lowercased().contains("serial")) ? "tv" : "movie"
        let cleanId = id.replacingOccurrences(of: "kp_", with: "")
        let queryItems = [
            URLQueryItem(name: "page", value: String(page))
        ]
        return try await performRequest(endpoint: "api/v1/media/\(cleanType)/\(cleanId)/related/cast", queryItems: queryItems)
    }
}
