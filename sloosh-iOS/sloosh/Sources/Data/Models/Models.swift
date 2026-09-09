import Foundation
import SwiftUI

struct ApiEnvelope<T: Codable>: Codable {
    let success: Bool?
    let data: T?
}

struct MediaResponse: Codable {
    let page: Int?
    let results: [MediaDto]?
    let items: [MediaDto]?
    let pages: Int?
    let total: Int?
    let total_pages: Int?
    let total_results: Int?
    let totalPages: Int?
    let totalResults: Int?

    init(
        page: Int? = nil,
        results: [MediaDto]? = nil,
        items: [MediaDto]? = nil,
        pages: Int? = nil,
        total: Int? = nil,
        total_pages: Int? = nil,
        total_results: Int? = nil,
        totalPages: Int? = nil,
        totalResults: Int? = nil
    ) {
        self.page = page
        self.results = results
        self.items = items
        self.pages = pages
        self.total = total
        self.total_pages = total_pages
        self.total_results = total_results
        self.totalPages = totalPages
        self.totalResults = totalResults
    }
    
    var allItems: [MediaDto] {
        return items ?? results ?? []
    }
    
    var effectiveTotalPages: Int {
        return pages ?? total_pages ?? totalPages ?? 1
    }
    
    var effectiveTotalResults: Int {
        return total ?? total_results ?? totalResults ?? allItems.count
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

    var intValue: Int? {
        switch self {
        case .int(let v): return v
        case .string(let v): return Int(v)
        case .double(let v): return Int(v)
        }
    }
}

struct MediaDto: Codable, Identifiable {
    var id: String { identifier } // Satisfies Identifiable using our custom identifier
    let originalId: AnyCodableValue?
    let title: String?
    let originalTitle: String?
    let year: AnyCodableValue?
    let releaseDate: String?
    let rating: Double?
    let ratings: RatingsV2Dto?
    let poster: String?
    let posterUrl: String?
    let description: String?
    let type: String?
    let genres: [GenreDto]?
    let externalIds: ExternalIdsDto?
    let name: String?
    let poster_path: String?
    let backdrop: String?
    let backdrop_path: String?
    
    enum CodingKeys: String, CodingKey {
        case originalId = "id"
        case title, originalTitle, year, releaseDate, rating, ratings, poster, posterUrl, description, type, genres, externalIds, name, poster_path, backdrop, backdrop_path
    }

    init(
        originalId: AnyCodableValue? = nil,
        title: String? = nil,
        originalTitle: String? = nil,
        year: AnyCodableValue? = nil,
        releaseDate: String? = nil,
        rating: Double? = nil,
        ratings: RatingsV2Dto? = nil,
        poster: String? = nil,
        posterUrl: String? = nil,
        description: String? = nil,
        type: String? = nil,
        genres: [GenreDto]? = nil,
        externalIds: ExternalIdsDto? = nil,
        name: String? = nil,
        poster_path: String? = nil,
        backdrop: String? = nil,
        backdrop_path: String? = nil
    ) {
        self.originalId = originalId
        self.title = title
        self.originalTitle = originalTitle
        self.year = year
        self.releaseDate = releaseDate
        self.rating = rating
        self.ratings = ratings
        self.poster = poster
        self.posterUrl = posterUrl
        self.description = description
        self.type = type
        self.genres = genres
        self.externalIds = externalIds
        self.name = name
        self.poster_path = poster_path
        self.backdrop = backdrop
        self.backdrop_path = backdrop_path
    }
    
    // Identifiable requirement helper
    var identifier: String {
        if let originalId = originalId?.stringValue, !originalId.isEmpty {
            return originalId
        }

        let titlePart = (title ?? name ?? originalTitle ?? "unknown")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let yearPart = year?.stringValue ?? ""
        let posterPart = (poster ?? posterUrl ?? poster_path ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let typePart = (type ?? "unknown").lowercased()

        return "fallback|\(typePart)|\(titlePart)|\(yearPart)|\(posterPart)"
    }
    
    var displayTitle: String {
        title ?? name ?? originalTitle ?? "Unknown"
    }
    
    var displayPosterUrl: String? {
        if let p = poster, !p.isEmpty {
            return normalizeImageUrl(path: p, id: originalId?.stringValue)
        }
        if let p = posterUrl, !p.isEmpty {
            return normalizeImageUrl(path: p, id: originalId?.stringValue)
        }
        if let path = poster_path, !path.isEmpty {
            return normalizeImageUrl(path: path, id: originalId?.stringValue) ?? (path.hasPrefix("http") ? path : "https://api-sloosh.vercel.app/api/v1/images/tmdb/w500\(path)")
        }
        return nil
    }

    var displayBackdropUrl: String? {
        if let b = backdrop, !b.isEmpty {
            return normalizeImageUrl(path: b, id: originalId?.stringValue) ?? b
        }
        if let path = backdrop_path, !path.isEmpty {
            return normalizeImageUrl(path: path, id: originalId?.stringValue) ?? (path.hasPrefix("http") ? path : "https://api-sloosh.vercel.app/api/v1/images/tmdb/original\(path)")
        }
        return displayPosterUrl
    }

    var isUnreleased: Bool {
        if let releaseDate = releaseDate, !releaseDate.isEmpty {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            if let date = formatter.date(from: releaseDate) {
                return date > Date()
            }
        }
        if let yearInt = year?.intValue {
            let currentYear = Calendar.current.component(.year, from: Date())
            if yearInt > currentYear {
                return true
            }
        }
        return false
    }
}

func adjustExternalImageUrl(urlStr: String, isLowQuality: Bool) -> String {
    var result = urlStr
    
    // 1. Kinopoisk (Yandex Avatars)
    if result.contains("get-kinopoisk-image") || result.contains("mds.yandex.net") {
        if let lastSlashIndex = result.lastIndex(of: "/") {
            let base = result[..<lastSlashIndex]
            let suffix = isLowQuality ? "300x450" : "orig"
            result = String(base) + "/" + suffix
        }
    }
    
    // 2. TMDB
    else if result.contains("image.tmdb.org/t/p/") {
        if isLowQuality {
            result = result.replacingOccurrences(of: "/original/", with: "/w342/")
            result = result.replacingOccurrences(of: "/w500/", with: "/w342/")
        } else {
            result = result.replacingOccurrences(of: "/w342/", with: "/w500/")
        }
        result = result.replacingOccurrences(of: "https://image.tmdb.org/t/p/", with: "https://api-sloosh.vercel.app/api/v1/images/tmdb/")
    }
    
    // 3. Backend Kinopoisk proxy (/kp/ -> /kp_small/)
    else {
        if isLowQuality {
            if result.contains("/kp/") {
                result = result.replacingOccurrences(of: "/kp/", with: "/kp_small/")
            }
        } else {
            if result.contains("/kp_small/") {
                result = result.replacingOccurrences(of: "/kp_small/", with: "/kp/")
            }
        }
    }
    
    return result
}

func normalizeImageUrl(path: String?, id: String? = nil) -> String? {
    if let p = path, p.contains("no-poster") {
        return nil
    }
    
    let baseUrl = "https://api-sloosh.vercel.app"
    let isLowQuality = UserDefaults.standard.string(forKey: "posterQuality") == "low"
    
    var rawUrl = path
    if let url = rawUrl {
        if url.contains("no-poster") {
            return nil
        }
        rawUrl = adjustExternalImageUrl(urlStr: url, isLowQuality: isLowQuality)
    }
    
    if let val = rawUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !val.isEmpty {
        if val.contains("no-poster") {
            return nil
        }
        if val.hasPrefix("http://") || val.hasPrefix("https://") {
            let proxied = val.replacingOccurrences(of: "https://image.tmdb.org/t/p/", with: "https://api-sloosh.vercel.app/api/v1/images/tmdb/")
            return proxied
        }
        if val.hasPrefix("/") {
            if val.hasSuffix(".jpg") || val.hasSuffix(".png") || val.hasSuffix(".jpeg") || val.hasSuffix(".webp") {
                let size = isLowQuality ? "w342" : "w500"
                return "https://api-sloosh.vercel.app/api/v1/images/tmdb/\(size)\(val)"
            }
            return (baseUrl + val).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? (baseUrl + val)
        }
        if val.hasPrefix("api/") {
            return (baseUrl + "/" + val).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? (baseUrl + "/" + val)
        }
    }
    
    // Fallback to ID-based poster only if path was not explicitly empty or marked no-poster
    guard let pathStr = path, !pathStr.isEmpty, !pathStr.contains("no-poster") else {
        return nil
    }
    
    let sanitizedId = id?.replacingOccurrences(of: "kp_", with: "")
    guard let validId = sanitizedId, validId.allSatisfy({ $0.isNumber }) else {
        return nil
    }
    let qualityPath = isLowQuality ? "kp_small" : "kp"
    return "\(baseUrl)/api/v1/images/\(qualityPath)/\(validId)?fallback=true"
}

struct MediaDetailsDto: Codable {
    let id: String?
    let title: String?
    let originalTitle: String?
    let description: String?
    let type: String?
    let year: Int?
    let releaseDate: String?
    let genres: [String]?
    let countries: [String]?
    let duration: Int?
    let poster: String?
    let backdrop: String?
    let logo: String?
    let cast: [CastMemberDto]?
    let directors: [CrewMemberDto]?
    let writers: [CrewMemberDto]?
    let crew: [CrewMemberDto]?
    let trailers: [TrailerVideoDto]?
    let ratings: RatingsV2Dto?
    let ids: IdsDto?
    let externalIds: ExternalIdsDto?
    let productionCompanies: [ProductionCompanyDto]?
    let networks: [NetworkDto]?
    let collection: MovieCollectionDto?
    let similar: [MediaDto]?
    let budget: Int?
    let revenue: Int?
    let ageRating: String?
    let status: String?
    let nextEpisodeToAir: TvNextEpisodeDto?
    
    enum CodingKeys: String, CodingKey {
        case id, title, originalTitle, description, type, year, releaseDate
        case genres, countries, duration, poster, backdrop, logo, cast, directors, writers, crew, trailers
        case ratings, ids, externalIds, productionCompanies, networks, collection, similar
        case budget, revenue, ageRating, status, nextEpisodeToAir
    }

    init(
        id: String? = nil,
        title: String? = nil,
        originalTitle: String? = nil,
        description: String? = nil,
        type: String? = nil,
        year: Int? = nil,
        releaseDate: String? = nil,
        genres: [String]? = nil,
        countries: [String]? = nil,
        duration: Int? = nil,
        poster: String? = nil,
        backdrop: String? = nil,
        logo: String? = nil,
        cast: [CastMemberDto]? = nil,
        directors: [CrewMemberDto]? = nil,
        writers: [CrewMemberDto]? = nil,
        crew: [CrewMemberDto]? = nil,
        trailers: [TrailerVideoDto]? = nil,
        ratings: RatingsV2Dto? = nil,
        ids: IdsDto? = nil,
        externalIds: ExternalIdsDto? = nil,
        productionCompanies: [ProductionCompanyDto]? = nil,
        networks: [NetworkDto]? = nil,
        collection: MovieCollectionDto? = nil,
        similar: [MediaDto]? = nil,
        budget: Int? = nil,
        revenue: Int? = nil,
        ageRating: String? = nil,
        status: String? = nil,
        nextEpisodeToAir: TvNextEpisodeDto? = nil
    ) {
        self.id = id
        self.title = title
        self.originalTitle = originalTitle
        self.description = description
        self.type = type
        self.year = year
        self.releaseDate = releaseDate
        self.genres = genres
        self.countries = countries
        self.duration = duration
        self.poster = poster
        self.backdrop = backdrop
        self.logo = logo
        self.cast = cast
        self.directors = directors
        self.writers = writers
        self.crew = crew
        self.trailers = trailers
        self.ratings = ratings
        self.ids = ids
        self.externalIds = externalIds ?? (ids != nil ? ExternalIdsDto(kp: ids?.kp, tmdb: ids?.tmdb, imdb: ids?.imdb) : nil)
        self.productionCompanies = productionCompanies
        self.networks = networks
        self.collection = collection
        self.similar = similar
        self.budget = budget
        self.revenue = revenue
        self.ageRating = ageRating
        self.status = status
        self.nextEpisodeToAir = nextEpisodeToAir
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        if let idStr = try? container.decodeIfPresent(String.self, forKey: .id) {
            self.id = idStr
        } else if let idInt = try? container.decodeIfPresent(Int.self, forKey: .id) {
            self.id = String(idInt)
        } else {
            self.id = nil
        }
        
        self.title = try? container.decodeIfPresent(String.self, forKey: .title)
        self.originalTitle = try? container.decodeIfPresent(String.self, forKey: .originalTitle)
        self.description = try? container.decodeIfPresent(String.self, forKey: .description)
        self.type = try? container.decodeIfPresent(String.self, forKey: .type)
        
        if let yearInt = try? container.decodeIfPresent(Int.self, forKey: .year) {
            self.year = yearInt
        } else if let yearStr = try? container.decodeIfPresent(String.self, forKey: .year), let y = Int(yearStr) {
            self.year = y
        } else {
            self.year = nil
        }
        
        self.releaseDate = try? container.decodeIfPresent(String.self, forKey: .releaseDate)
        
        if let stringGenres = try? container.decodeIfPresent([String].self, forKey: .genres) {
            self.genres = stringGenres
        } else if let objectGenres = try? container.decodeIfPresent([GenreDto].self, forKey: .genres) {
            self.genres = objectGenres.compactMap { $0.name }.filter { !$0.isEmpty }
        } else {
            self.genres = nil
        }
        
        if let rawCountries = try? container.decodeIfPresent([String].self, forKey: .countries) {
            self.countries = rawCountries.map { CountryLocalizer.format($0) }.filter { !$0.isEmpty }
        } else {
            self.countries = nil
        }
        self.duration = try? container.decodeIfPresent(Int.self, forKey: .duration)
        self.poster = try? container.decodeIfPresent(String.self, forKey: .poster)
        self.backdrop = try? container.decodeIfPresent(String.self, forKey: .backdrop)
        self.logo = try? container.decodeIfPresent(String.self, forKey: .logo)
        self.cast = try? container.decodeIfPresent([CastMemberDto].self, forKey: .cast)
        self.directors = try? container.decodeIfPresent([CrewMemberDto].self, forKey: .directors)
        self.writers = try? container.decodeIfPresent([CrewMemberDto].self, forKey: .writers)
        self.crew = try? container.decodeIfPresent([CrewMemberDto].self, forKey: .crew)
        self.trailers = try? container.decodeIfPresent([TrailerVideoDto].self, forKey: .trailers)
        self.ratings = try? container.decodeIfPresent(RatingsV2Dto.self, forKey: .ratings)
        
        let decodedIds = try? container.decodeIfPresent(IdsDto.self, forKey: .ids)
        let decodedExt = try? container.decodeIfPresent(ExternalIdsDto.self, forKey: .externalIds)
        if let ids = decodedIds {
            self.ids = ids
            self.externalIds = decodedExt ?? ExternalIdsDto(kp: ids.kp, tmdb: ids.tmdb, imdb: ids.imdb)
        } else if let ext = decodedExt {
            self.externalIds = ext
            self.ids = IdsDto(kp: ext.kp, imdb: ext.imdb, tmdb: ext.tmdb)
        } else {
            self.ids = nil
            self.externalIds = nil
        }

        self.productionCompanies = try? container.decodeIfPresent([ProductionCompanyDto].self, forKey: .productionCompanies)
        self.networks = try? container.decodeIfPresent([NetworkDto].self, forKey: .networks)
        self.collection = try? container.decodeIfPresent(MovieCollectionDto.self, forKey: .collection)
        self.similar = try? container.decodeIfPresent([MediaDto].self, forKey: .similar)
        
        if let b = try? container.decodeIfPresent(Int.self, forKey: .budget) {
            self.budget = b
        } else if let bDbl = try? container.decodeIfPresent(Double.self, forKey: .budget) {
            self.budget = Int(bDbl)
        } else {
            self.budget = nil
        }
        
        if let r = try? container.decodeIfPresent(Int.self, forKey: .revenue) {
            self.revenue = r
        } else if let rDbl = try? container.decodeIfPresent(Double.self, forKey: .revenue) {
            self.revenue = Int(rDbl)
        } else {
            self.revenue = nil
        }

        self.ageRating = try? container.decodeIfPresent(String.self, forKey: .ageRating)
        self.status = try? container.decodeIfPresent(String.self, forKey: .status)
        self.nextEpisodeToAir = try? container.decodeIfPresent(TvNextEpisodeDto.self, forKey: .nextEpisodeToAir)
    }
    
    var isUnreleased: Bool {
        if let status = status?.lowercased() {
            if ["planned", "in production", "post production", "rumored", "upcoming"].contains(status) {
                return true
            }
        }
        if let releaseDate = releaseDate, !releaseDate.isEmpty {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            if let date = formatter.date(from: releaseDate) {
                return date > Date()
            }
        }
        if let year = year {
            let currentYear = Calendar.current.component(.year, from: Date())
            if year > currentYear {
                return true
            }
        }
        return false
    }

    var formattedReleaseDate: String? {
        guard let releaseDate = releaseDate, !releaseDate.isEmpty else { return nil }
        let inputFormatter = DateFormatter()
        inputFormatter.locale = Locale(identifier: "en_US_POSIX")
        inputFormatter.dateFormat = "yyyy-MM-dd"
        guard let date = inputFormatter.date(from: releaseDate) else { return releaseDate }
        
        let outputFormatter = DateFormatter()
        outputFormatter.locale = Locale(identifier: "ru_RU")
        outputFormatter.dateFormat = "d MMMM yyyy"
        return outputFormatter.string(from: date)
    }

    static func formatMoney(_ amount: Int?) -> String? {
        guard let amount = amount, amount > 0 else { return nil }
        if amount >= 1_000_000_000 {
            let val = Double(amount) / 1_000_000_000.0
            return String(format: "$%.1f млрд", val).replacingOccurrences(of: ".0", with: "")
        } else if amount >= 1_000_000 {
            let val = Double(amount) / 1_000_000.0
            return String(format: "$%.1f млн", val).replacingOccurrences(of: ".0", with: "")
        } else if amount >= 1_000 {
            let val = Double(amount) / 1_000.0
            return String(format: "$%.0f тыс.", val)
        } else {
            return "$\(amount)"
        }
    }

    var formattedBudget: String? {
        Self.formatMoney(budget)
    }

    var formattedRevenue: String? {
        Self.formatMoney(revenue)
    }

    var displayPosterUrl: String? {
        normalizeImageUrl(path: poster, id: id)
    }
    
    var displayBackdropUrl: String? {
        if let backdrop = backdrop, !backdrop.isEmpty {
            return normalizeImageUrl(path: backdrop, id: id) ?? backdrop
        }
        if let poster = poster, !poster.isEmpty {
            return normalizeImageUrl(path: poster, id: id) ?? poster
        }
        guard let validId = id?.replacingOccurrences(of: "kp_", with: ""), !validId.isEmpty else { return nil }
        return "https://api-sloosh.vercel.app/api/v1/images/backdrops/\(validId)/original"
    }
    
    var previewBackdropUrl: String? {
        if let backdrop = backdrop, !backdrop.isEmpty {
            return normalizeImageUrl(path: backdrop, id: id) ?? backdrop
        }
        if let poster = poster, !poster.isEmpty {
            return normalizeImageUrl(path: poster, id: id) ?? poster
        }
        guard let validId = id?.replacingOccurrences(of: "kp_", with: ""), !validId.isEmpty else { return nil }
        return "https://api-sloosh.vercel.app/api/v1/images/backdrops/\(validId)/small"
    }

    var displayLogoUrl: String? {
        if let logo = logo, !logo.isEmpty {
            return normalizeImageUrl(path: logo, id: id) ?? logo
        }
        return nil
    }

    var identifiedStudio: StudioBrand? {
        if let companies = productionCompanies, !companies.isEmpty {
            for c in companies {
                if let brand = StudioBrand.find(by: c.name) {
                    return brand
                }
            }
        }
        if let nets = networks, !nets.isEmpty {
            for n in nets {
                if let brand = StudioBrand.find(by: n.name) {
                    return brand
                }
            }
        }
        return nil
    }
}

public struct GenreDto: Codable {
    public let id: String?
    public let name: String?

    public init(id: String? = nil, name: String? = nil) {
        self.id = id
        self.name = name
    }
    
    public var idString: String? { id }

    enum CodingKeys: String, CodingKey {
        case id, name
    }

    public init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let str = try? single.decode(String.self) {
            self.id = nil
            self.name = str
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let strId = try? container.decodeIfPresent(String.self, forKey: .id) {
            self.id = strId
        } else if let intId = try? container.decodeIfPresent(Int.self, forKey: .id) {
            self.id = String(intId)
        } else {
            self.id = nil
        }
        self.name = try? container.decodeIfPresent(String.self, forKey: .name)
    }
}

struct ExternalIdsDto: Codable {
    let kp: Int?
    let tmdb: Int?
    let imdb: String?

    init(kp: Int? = nil, tmdb: Int? = nil, imdb: String? = nil) {
        self.kp = kp
        self.tmdb = tmdb
        self.imdb = imdb
    }
}

struct RatingsV2Dto: Codable {
    let kp: Double?
    let imdb: Double?
    let tmdb: Double?
}

struct IdsDto: Codable {
    let kp: Int?
    let imdb: String?
    let tmdb: Int?

    init(kp: Int? = nil, imdb: String? = nil, tmdb: Int? = nil) {
        self.kp = kp
        self.imdb = imdb
        self.tmdb = tmdb
    }
}

enum CountryLocalizer {
    private static let countryCodeToRu: [String: String] = [
        "US": "США", "USA": "США", "GB": "Великобритания", "UK": "Великобритания",
        "RU": "Россия", "SU": "СССР", "FR": "Франция", "DE": "Германия",
        "IT": "Италия", "ES": "Испания", "JP": "Япония", "KR": "Южная Корея",
        "CN": "Китай", "HK": "Гонконг", "TW": "Тайвань", "CA": "Канада",
        "AU": "Австралия", "IN": "Индия", "TR": "Турция", "SE": "Швеция",
        "NO": "Норвегия", "DK": "Дания", "FI": "Финляндия", "NL": "Нидерланды",
        "BE": "Бельгия", "PL": "Польша", "CZ": "Чехия", "AT": "Австрия",
        "CH": "Швейцария", "IE": "Ирландия", "NZ": "Новая Зеландия", "ZA": "ЮАР",
        "IL": "Израиль", "UA": "Украина", "BY": "Беларусь", "KZ": "Казахстан",
        "TH": "Таиланд", "ID": "Индонезия", "IS": "Исландия", "GR": "Греция",
        "PT": "Португалия", "MX": "Мексика", "BR": "Бразилия", "AR": "Аргентина",
        "AE": "ОАЭ", "EG": "Египет", "GE": "Грузия", "AM": "Армения"
    ]

    private static let englishNameToRu: [String: String] = [
        "united states of america": "США",
        "united states": "США",
        "usa": "США",
        "united kingdom": "Великобритания",
        "great britain": "Великобритания",
        "uk": "Великобритания",
        "england": "Великобритания",
        "russia": "Россия",
        "russian federation": "Россия",
        "soviet union": "СССР",
        "ussr": "СССР",
        "france": "Франция",
        "germany": "Германия",
        "italy": "Италия",
        "spain": "Испания",
        "japan": "Япония",
        "south korea": "Южная Корея",
        "korea, republic of": "Южная Корея",
        "republic of korea": "Южная Корея",
        "korea": "Южная Корея",
        "china": "Китай",
        "hong kong": "Гонконг",
        "taiwan": "Тайвань",
        "canada": "Канада",
        "australia": "Австралия",
        "india": "Индия",
        "turkey": "Турция",
        "türkiye": "Турция",
        "sweden": "Швеция",
        "norway": "Норвегия",
        "denmark": "Дания",
        "finland": "Финляндия",
        "netherlands": "Нидерланды",
        "belgium": "Бельгия",
        "poland": "Польша",
        "czech republic": "Чехия",
        "czechia": "Чехия",
        "austria": "Австрия",
        "switzerland": "Швейцария",
        "ireland": "Ирландия",
        "new zealand": "Новая Зеландия",
        "south africa": "ЮАР",
        "israel": "Израиль",
        "ukraine": "Украина",
        "belarus": "Беларусь",
        "kazakhstan": "Казахстан",
        "thailand": "Таиланд",
        "indonesia": "Индонезия",
        "philippines": "Филиппины",
        "iceland": "Исландия",
        "greece": "Греция",
        "portugal": "Португалия",
        "united arab emirates": "ОАЭ",
        "uae": "ОАЭ",
        "mexico": "Мексика",
        "brazil": "Бразилия",
        "argentina": "Аргентина"
    ]

    static func format(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let upper = trimmed.uppercased()
        if let match = countryCodeToRu[upper] {
            return match
        }

        let lower = trimmed.lowercased()
        if let match = englishNameToRu[lower] {
            return match
        }

        if upper.count == 2 {
            let locale = Locale(identifier: "ru_RU")
            if let localized = locale.localizedString(forRegionCode: upper), !localized.isEmpty {
                return localized
            }
        }

        return trimmed
    }
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

struct TvEpisodeDetailsDto: Codable {
    let id: Int?
    let name: String?
    let overview: String?
    let airDate: String?
    let seasonNumber: Int?
    let episodeNumber: Int?
    let stillPath: String?
    let language: String?
    let ratings: EpisodeRatingsDto?
}

struct TvNextEpisodeDto: Codable {
    let id: Int?
    let name: String?
    let overview: String?
    let airDate: String?
    let episodeNumber: Int?
    let seasonNumber: Int?
}

struct TvSeasonEpisodeDto: Codable, Identifiable {
    let id: Int?
    let name: String?
    let overview: String?
    let airDate: String?
    let episodeNumber: Int?
    let seasonNumber: Int?
    let stillPath: String?
    let voteAverage: Double?
    let duration: Int?
}

struct TvSeasonDto: Codable {
    let id: Int?
    let name: String?
    let overview: String?
    let seasonNumber: Int?
    let poster: String?
    let airDate: String?
    let episodes: [TvSeasonEpisodeDto]?
}

struct EpisodeRatingsDto: Codable {
    let kp: Double?
    let tmdb: Double?
    let imdb: Double?
}

// MARK: - Studios, Networks & Collections

struct ProductionCompanyDto: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let logo: String?
    let logos: [String: String]?
    
    init(id: Int, name: String, logo: String? = nil, logos: [String: String]? = nil) {
        self.id = id
        self.name = name
        self.logo = logo
        self.logos = logos
    }
}

struct NetworkDto: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let logo: String?
    let logos: [String: String]?
    
    init(id: Int, name: String, logo: String? = nil, logos: [String: String]? = nil) {
        self.id = id
        self.name = name
        self.logo = logo
        self.logos = logos
    }
}

struct CastMemberDto: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let originalName: String?
    let character: String?
    let photo: String?
    
    init(id: Int, name: String, originalName: String? = nil, character: String? = nil, photo: String? = nil) {
        self.id = id
        self.name = name
        self.originalName = originalName
        self.character = character
        self.photo = photo
    }
}

struct CrewMemberDto: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let originalName: String?
    let role: String?
    let photo: String?
    
    init(id: Int, name: String, originalName: String? = nil, role: String? = nil, photo: String? = nil) {
        self.id = id
        self.name = name
        self.originalName = originalName
        self.role = role
        self.photo = photo
    }
}

struct PersonDetailsDto: Codable, Identifiable {
    let id: Int
    let name: String
    let originalName: String?
    let biography: String?
    let birthday: String?
    let deathday: String?
    let placeOfBirth: String?
    let photo: String?
    let knownForDepartment: String?
    let department: String?
    let gender: Int?
    let filmography: [MediaDto]?
    let photos: [String]?
    let awards: String?
    let keyProjects: String?
    let interestingFact: String?

    var age: Int? {
        guard let birthday = birthday, !birthday.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let birthDate = formatter.date(from: birthday) else { return nil }
        let calendar = Calendar.current
        let now = Date()
        let ageComponents = calendar.dateComponents([.year], from: birthDate, to: now)
        return ageComponents.year
    }

    var formattedBirthdayWithAge: String? {
        guard let birthday = birthday, !birthday.isEmpty else { return nil }
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = "yyyy-MM-dd"
        guard let date = inputFormatter.date(from: birthday) else { return birthday }
        let outputFormatter = DateFormatter()
        outputFormatter.locale = Locale(identifier: "ru_RU")
        outputFormatter.dateFormat = "d MMMM yyyy"
        let dateStr = outputFormatter.string(from: date)
        if let age = age {
            let suffix: String
            let lastDigit = age % 10
            let lastTwoDigits = age % 100
            if lastTwoDigits >= 11 && lastTwoDigits <= 19 {
                suffix = "лет"
            } else if lastDigit == 1 {
                suffix = "год"
            } else if lastDigit >= 2 && lastDigit <= 4 {
                suffix = "года"
            } else {
                suffix = "лет"
            }
            return "\(dateStr) (\(age) \(suffix))"
        }
        return dateStr
    }
}

struct TrailerVideoDto: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let key: String
    let site: String
    let url: String
    
    init(id: String, name: String, key: String, site: String, url: String) {
        self.id = id
        self.name = name
        self.key = key
        self.site = site
        self.url = url
    }

    var isYouTube: Bool {
        site.lowercased() == "youtube"
    }

    var thumbnailUrl: URL? {
        if isYouTube {
            return URL(string: "https://img.youtube.com/vi/\(key)/hqdefault.jpg")
        }
        return nil
    }

    var maxResThumbnailUrl: URL? {
        if isYouTube {
            return URL(string: "https://img.youtube.com/vi/\(key)/maxresdefault.jpg")
        }
        return nil
    }

    var embedUrl: URL? {
        if isYouTube {
            return URL(string: "https://www.youtube-nocookie.com/embed/\(key)?autoplay=1&playsinline=1&rel=0&modestbranding=1&iv_load_policy=3")
        }
        return URL(string: url)
    }

    var youtubeWebUrl: URL? {
        if isYouTube {
            return URL(string: "https://www.youtube.com/watch?v=\(key)")
        }
        return URL(string: url)
    }

    var youtubeAppUrl: URL? {
        if isYouTube {
            return URL(string: "youtube://watch?v=\(key)")
        }
        return nil
    }

    var typeTag: String {
        let lower = name.lowercased()
        if lower.contains("тизер") || lower.contains("teaser") {
            return "Тизер"
        }
        return "Трейлер"
    }
}

struct MovieCollectionDto: Codable, Identifiable {
    let id: Int?
    let name: String?
    let overview: String?
    let poster: String?
    let backdrop: String?
    let parts: [MediaDto]?
    
    init(id: Int? = nil, name: String? = nil, overview: String? = nil, poster: String? = nil, backdrop: String? = nil, parts: [MediaDto]? = nil) {
        self.id = id
        self.name = name
        self.overview = overview
        self.poster = poster
        self.backdrop = backdrop
        self.parts = parts
    }
}

struct RelatedStudioResponse: Codable {
    let items: [MediaDto]?
    let results: [MediaDto]?
    let label: String?
    let page: Int?
    let totalPages: Int?
    let totalResults: Int?
    let total_pages: Int?
    let total_results: Int?

    init(
        items: [MediaDto]? = nil,
        results: [MediaDto]? = nil,
        label: String? = nil,
        page: Int? = nil,
        totalPages: Int? = nil,
        totalResults: Int? = nil,
        total_pages: Int? = nil,
        total_results: Int? = nil
    ) {
        self.items = items
        self.results = results
        self.label = label
        self.page = page
        self.totalPages = totalPages ?? total_pages
        self.totalResults = totalResults ?? total_results
        self.total_pages = total_pages ?? totalPages
        self.total_results = total_results ?? totalResults
    }
    
    var allItems: [MediaDto] {
        return items ?? results ?? []
    }
}

struct CategorySectionDto: Codable, Identifiable {
    var id: String { section }
    let section: String
    let items: [CategoryItemDto]
}

struct CategoryItemDto: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let slug: String?
    let type: String?
    let backdrop: String?
    
    init(id: String, name: String, slug: String? = nil, type: String? = nil, backdrop: String? = nil) {
        self.id = id
        self.name = name
        self.slug = slug
        self.type = type
        self.backdrop = backdrop
    }
}

struct StudioBrand: Identifiable, Hashable {
    let id: String
    let name: String
    let slug: String
    let isNetwork: Bool
    let aliases: [String]

    init(
        id: String,
        name: String,
        slug: String,
        isNetwork: Bool,
        aliases: [String] = []
    ) {
        self.id = id
        self.name = name
        self.slug = slug
        self.isNetwork = isNetwork
        self.aliases = aliases
    }
    
    static let all: [StudioBrand] = [
        StudioBrand(id: "marvel", name: "Marvel", slug: "marvel", isNetwork: false, aliases: ["marvel", "марвел"]),
        StudioBrand(id: "dc", name: "DC", slug: "dc", isNetwork: false, aliases: ["dc", "диси"]),
        StudioBrand(id: "a24", name: "A24", slug: "a24", isNetwork: false, aliases: ["a24"]),
        StudioBrand(id: "pixar", name: "Pixar", slug: "pixar", isNetwork: false, aliases: ["pixar", "пиксар"]),
        StudioBrand(id: "disney", name: "Disney", slug: "disney", isNetwork: false, aliases: ["disney", "дисне"]),
        StudioBrand(id: "warner-bros", name: "Warner Bros.", slug: "warner-bros", isNetwork: false, aliases: ["warner", "уорнер"]),
        StudioBrand(id: "universal", name: "Universal", slug: "universal", isNetwork: false, aliases: ["universal", "юниверсал"]),
        StudioBrand(id: "paramount", name: "Paramount", slug: "paramount", isNetwork: false, aliases: ["paramount", "парамаунт"]),
        StudioBrand(id: "20th-century-studios", name: "20th Century", slug: "20th-century-studios", isNetwork: false, aliases: ["20th century", "двадцатый век"]),
        StudioBrand(id: "sony-pictures", name: "Sony Pictures", slug: "sony-pictures", isNetwork: false, aliases: ["sony", "сони"]),
        StudioBrand(id: "dreamworks", name: "DreamWorks", slug: "dreamworks", isNetwork: false, aliases: ["dreamworks", "дримворкс"]),
        
        // Networks / Streamings
        StudioBrand(id: "netflix", name: "Netflix", slug: "netflix", isNetwork: true, aliases: ["netflix", "нетфликс"]),
        StudioBrand(id: "hbo", name: "HBO", slug: "hbo", isNetwork: true, aliases: ["hbo", "эйчби"]),
        StudioBrand(id: "apple-tv-plus", name: "Apple TV+", slug: "apple-tv-plus", isNetwork: true, aliases: ["apple tv", "эппл тв"]),
        StudioBrand(id: "prime-video", name: "Prime Video", slug: "prime-video", isNetwork: true, aliases: ["prime video", "прайм видео", "amazon"]),
        StudioBrand(id: "cartoon-network", name: "Cartoon Network", slug: "cartoon-network", isNetwork: true, aliases: ["cartoon network", "картун нетворк"]),
        StudioBrand(id: "adult-swim", name: "Adult Swim", slug: "adult-swim", isNetwork: true, aliases: ["adult swim", "эдалт свим"]),
    ]
    
    static func find(by nameOrId: String) -> StudioBrand? {
        let clean = nameOrId.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { return nil }
        
        // Exact match with ID, slug, or name
        if let exact = all.first(where: {
            $0.id.lowercased() == clean ||
            $0.slug.lowercased() == clean ||
            $0.name.lowercased() == clean
        }) {
            return exact
        }
        
        // Match with aliases
        return all.first { brand in
            brand.aliases.contains(where: { clean.contains($0.lowercased()) })
        }
    }
}

public struct FavoriteDto: Codable, Identifiable {
    public let id: String?
    public let mediaId: String?
    public let type: String?
    public let title: String?
    public let posterUrl: String?
    public let rating: Double?
    public let year: String?
    public let genres: [GenreDto]?

    public init(
        id: String? = nil,
        mediaId: String? = nil,
        type: String? = nil,
        title: String? = nil,
        posterUrl: String? = nil,
        rating: Double? = nil,
        year: String? = nil,
        genres: [GenreDto]? = nil
    ) {
        self.id = id
        self.mediaId = mediaId
        self.type = type
        self.title = title
        self.posterUrl = posterUrl
        self.rating = rating
        self.year = year
        self.genres = genres
    }
    
    // Mapping to MediaDto for UI reuse
    func toMediaDto() -> MediaDto {
        return MediaDto(
            originalId: .string(mediaId ?? UUID().uuidString),
            title: title,
            originalTitle: nil,
            year: year != nil ? .string(year!) : nil,
            rating: rating,
            posterUrl: posterUrl,
            description: nil,
            type: type,
            genres: genres,
            externalIds: nil,
            name: title,
            poster_path: posterUrl
        )
    }
}

struct FavoriteCheckDto: Codable {
    let isFavorite: Bool
}

enum VideoQualityPreference: String, CaseIterable, Identifiable, Codable {
    case ask = "Спрашивать каждый раз"
    case auto = "Авто"

    case q1080 = "1080p"
    case q720 = "720p"
    case q480 = "480p"
    case q360 = "360p"
    
    var id: String { self.rawValue }

    var title: String {
        switch self {
        case .ask:
            return "Спрашивать"
        default:
            return rawValue
        }
    }
}

enum CardStyle: String, CaseIterable, Identifiable {
    case classic = "classic"
    case overlay = "overlay"
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .classic: return "Классический"
        case .overlay: return "Инфо внутри постера"
        }
    }
}

enum CardDensity: String, CaseIterable, Identifiable {
    case regular = "regular"
    case compact = "compact"
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .regular: return "Стандартная"
        case .compact: return "Компактная"
        }
    }
}

enum PosterQuality: String, CaseIterable, Identifiable {
    case high = "high"
    case low = "low"
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .high: return "Высокое"
        case .low: return "Низкое"
        }
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system = "system"
    case light = "light"
    case dark = "dark"
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .system: return "Системная"
        case .light: return "Светлая"
        case .dark: return "Тёмная"
        }
    }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct SearchFilters: Equatable, Hashable {
    var type: String?
    var order: String?
    var ratingFrom: Double?
    var ratingTo: Double?
    var yearFrom: Int?
    var yearTo: Int?
    var genres: String?
    var countries: String?
    
    var isEmpty: Bool {
        return type == nil && order == nil && ratingFrom == nil && ratingTo == nil && yearFrom == nil && yearTo == nil && genres == nil && countries == nil
    }
}
