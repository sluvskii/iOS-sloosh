import Foundation

struct ApiEnvelope<T: Codable>: Codable {
    let success: Bool?
    let data: T?
}

struct MediaResponse: Codable {
    let page: Int?
    let results: [MediaDto]?
    let pages: Int?
    let total: Int?
    let total_pages: Int?
    let total_results: Int?
    
    var effectiveTotalPages: Int {
        return pages ?? total_pages ?? 1
    }
    
    var effectiveTotalResults: Int {
        return total ?? total_results ?? results?.count ?? 0
    }
}

enum AnyCodableValue: Codable {
    case int(Int)
    case string(String)
    case double(Double)
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
            return
        }
        if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
            return
        }
        if let doubleValue = try? container.decode(Double.self) {
            self = .double(doubleValue)
            return
        }
        throw DecodingError.typeMismatch(AnyCodableValue.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Wrong type for AnyCodableValue"))
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        }
    }
    
    var stringValue: String {
        switch self {
        case .int(let v): return String(v)
        case .string(let v): return v
        case .double(let v): return String(v)
        }
    }
}

struct MediaDto: Codable, Identifiable {
    var id: String { identifier } // Satisfies Identifiable using our custom identifier
    let originalId: AnyCodableValue?
    let title: String?
    let originalTitle: String?
    let year: AnyCodableValue?
    let rating: Double?
    let posterUrl: String?
    let description: String?
    let type: String?
    let genres: [GenreDto]?
    let externalIds: ExternalIdsDto?
    let name: String?
    let poster_path: String?
    
    enum CodingKeys: String, CodingKey {
        case originalId = "id"
        case title, originalTitle, year, rating, posterUrl, description, type, genres, externalIds, name, poster_path
    }
    
    // Identifiable requirement helper
    var identifier: String {
        originalId?.stringValue ?? UUID().uuidString
    }
    
    var displayTitle: String {
        title ?? name ?? originalTitle ?? "Unknown"
    }
    
    var displayPosterUrl: String? {
        normalizeImageUrl(path: posterUrl ?? poster_path)
    }
}

func normalizeImageUrl(path: String?) -> String? {
    guard let path = path?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else { return nil }
    
    if path.hasPrefix("http://") || path.hasPrefix("https://") {
        return path
    }
    
    if path.hasPrefix("/") {
        return "https://api.neomovies.ru" + path
    }
    
    if path.hasPrefix("api/") {
        return "https://api.neomovies.ru/" + path
    }
    
    var id: String? = nil
    if path.allSatisfy({ $0.isNumber }) {
        id = path
    } else if path.hasPrefix("kp_") {
        let suffix = String(path.dropFirst(3))
        if suffix.allSatisfy({ $0.isNumber }) {
            id = suffix
        }
    }
    
    guard let validId = id else { return nil }
    return "https://api.neomovies.ru/api/v1/images/kp_small/\(validId)?fallback=true"
}

struct MediaDetailsDto: Codable {
    let id: String?
    let sourceId: String?
    let title: String?
    let name: String?
    let originalTitle: String?
    let description: String?
    let releaseDate: String?
    let type: String?
    let genres: [GenreDto]?
    let rating: Double?
    let posterUrl: String?
    let backdropUrl: String?
    let duration: Int?
    let country: String?
    let language: String?
    let externalIds: ExternalIdsDto?
    
    var displayPosterUrl: String? {
        normalizeImageUrl(path: posterUrl)
    }
    
    var displayBackdropUrl: String? {
        // We can reuse the same normalizer for backdrop, or just check if it's full URL
        normalizeImageUrl(path: backdropUrl)
    }
}

struct GenreDto: Codable {
    let id: String?
    let name: String?
}

struct ExternalIdsDto: Codable {
    let kp: Int?
    let tmdb: Int?
    let imdb: String?
}

struct SupportItemDto: Codable {
    let id: String?
    let text: String?
}

struct FavoriteDto: Codable {
    let id: String?
    let mediaId: String?
    let type: String?
    let title: String?
    let posterUrl: String?
}

struct FavoriteCheckDto: Codable {
    let isFavorite: Bool
}
