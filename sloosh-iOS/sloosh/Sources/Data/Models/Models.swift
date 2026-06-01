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
        let rawUrl = posterUrl ?? poster_path
        return normalizeImageUrl(path: rawUrl, id: originalId?.stringValue)
    }
}

func normalizeImageUrl(path: String?, id: String? = nil) -> String? {
    let baseUrl = "https://api.neomovies.ru"
    
    if let val = path?.trimmingCharacters(in: .whitespacesAndNewlines), !val.isEmpty {
        if val.hasPrefix("http://") || val.hasPrefix("https://") {
            return val.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? val
        }
        if val.hasPrefix("/") {
            return (baseUrl + val).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? (baseUrl + val)
        }
        if val.hasPrefix("api/") {
            return (baseUrl + "/" + val).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? (baseUrl + "/" + val)
        }
    }
    
    // Fallback to ID-based poster if no valid path was found
    guard let validId = id, validId.allSatisfy({ $0.isNumber }) else {
        return nil
    }
    return "\(baseUrl)/api/v1/images/kp_small/\(validId)?fallback=true"
}

func normalizeLogoUrl(id: String?, size: String = "w500") -> String? {
    let baseUrl = "https://api.neomovies.ru"
    guard let rawId = id?.replacingOccurrences(of: "kp_", with: "").trimmingCharacters(in: .whitespacesAndNewlines),
          !rawId.isEmpty else {
        return nil
    }
    return "\(baseUrl)/api/v1/images/logos/\(rawId)/\(size)"
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
        normalizeImageUrl(path: posterUrl, id: id)
    }
    
    var displayBackdropUrl: String? {
        normalizeImageUrl(path: backdropUrl, id: id)
    }

    var displayLogoUrl: String? {
        normalizeLogoUrl(id: id ?? sourceId ?? externalIds?.kp?.description)
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
    let name: String?
    let type: String?
    let text: String?
    let description: String?
    let contributions: [String]?
    let year: Int?
    let isActive: Bool?
}

struct FavoriteDto: Codable, Identifiable {
    let id: String?
    let mediaId: String?
    let type: String?
    let title: String?
    let posterUrl: String?
    
    // Mapping to MediaDto for UI reuse
    func toMediaDto() -> MediaDto {
        return MediaDto(
            originalId: .string(mediaId ?? UUID().uuidString),
            title: title,
            originalTitle: nil,
            year: nil,
            rating: nil, // We don't save rating in favorites locally right now
            posterUrl: posterUrl,
            description: nil,
            type: type,
            genres: nil,
            externalIds: nil,
            name: title,
            poster_path: posterUrl
        )
    }
}

struct FavoriteCheckDto: Codable {
    let isFavorite: Bool
}

enum VideoQualityPreference: String, CaseIterable, Identifiable {
    case ask = "Спрашивать каждый раз"
    case auto = "Авто"
    case q1080 = "1080p"
    case q720 = "720p"
    case q480 = "480p"
    case q360 = "360p"
    
    var id: String { self.rawValue }
}
