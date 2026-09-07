import Foundation
import SwiftUI

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
    let rating: Double?
    let ratings: RatingsV2Dto?
    let posterUrl: String?
    let description: String?
    let type: String?
    let genres: [GenreDto]?
    let externalIds: ExternalIdsDto?
    let name: String?
    let poster_path: String?
    
    enum CodingKeys: String, CodingKey {
        case originalId = "id"
        case title, originalTitle, year, rating, ratings, posterUrl, description, type, genres, externalIds, name, poster_path
    }

    init(
        originalId: AnyCodableValue? = nil,
        title: String? = nil,
        originalTitle: String? = nil,
        year: AnyCodableValue? = nil,
        rating: Double? = nil,
        ratings: RatingsV2Dto? = nil,
        posterUrl: String? = nil,
        description: String? = nil,
        type: String? = nil,
        genres: [GenreDto]? = nil,
        externalIds: ExternalIdsDto? = nil,
        name: String? = nil,
        poster_path: String? = nil
    ) {
        self.originalId = originalId
        self.title = title
        self.originalTitle = originalTitle
        self.year = year
        self.rating = rating
        self.ratings = ratings
        self.posterUrl = posterUrl
        self.description = description
        self.type = type
        self.genres = genres
        self.externalIds = externalIds
        self.name = name
        self.poster_path = poster_path
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
        let posterPart = (posterUrl ?? poster_path ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let typePart = (type ?? "unknown").lowercased()

        return "fallback|\(typePart)|\(titlePart)|\(yearPart)|\(posterPart)"
    }
    
    var displayTitle: String {
        title ?? name ?? originalTitle ?? "Unknown"
    }
    
    var displayPosterUrl: String? {
        let rawUrl = posterUrl ?? poster_path
        return normalizeImageUrl(path: rawUrl, id: originalId?.stringValue)
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
    
    let baseUrl = "https://api.neome.uk"
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
            return val.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? val
        }
        if val.hasPrefix("/") {
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
    let ratings: RatingsV2Dto?
    let ids: IdsDto?
    let productionCompanies: [ProductionCompanyDto]?
    let networks: [NetworkDto]?
    let collection: MovieCollectionDto?
    
    var displayPosterUrl: String? {
        normalizeImageUrl(path: poster, id: id)
    }
    
    var displayBackdropUrl: String? {
        let isLowQuality = UserDefaults.standard.string(forKey: "posterQuality") == "low"
        guard let validId = id?.replacingOccurrences(of: "kp_", with: ""), !validId.isEmpty else { return nil }
        let size = isLowQuality ? "large" : "original"
        return "https://api.neome.uk/api/v1/images/backdrops/\(validId)/\(size)"
    }
    
    var previewBackdropUrl: String? {
        guard let validId = id?.replacingOccurrences(of: "kp_", with: ""), !validId.isEmpty else { return nil }
        return "https://api.neome.uk/api/v1/images/backdrops/\(validId)/small"
    }

    var displayLogoUrl: String? {
        guard let validId = id?.replacingOccurrences(of: "kp_", with: ""), !validId.isEmpty else { return nil }
        return "https://api.neome.uk/api/v1/images/logos/\(validId)/original"
    }

    var identifiedStudio: StudioBrand? {
        if let companies = productionCompanies {
            for c in companies {
                if let brand = StudioBrand.find(by: c.name) {
                    return brand
                }
            }
        }
        if let nets = networks {
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
}

struct ExternalIdsDto: Codable {
    let kp: Int?
    let tmdb: Int?
    let imdb: String?
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
    let label: String?
    let page: Int?
    let totalPages: Int?
    let totalResults: Int?
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
    let searchFranchises: [String]
    let excludedKeywords: [String]

    init(
        id: String,
        name: String,
        slug: String,
        isNetwork: Bool,
        aliases: [String] = [],
        searchFranchises: [String] = [],
        excludedKeywords: [String] = []
    ) {
        self.id = id
        self.name = name
        self.slug = slug
        self.isNetwork = isNetwork
        self.aliases = aliases
        self.searchFranchises = searchFranchises
        self.excludedKeywords = excludedKeywords
    }
    
    static let all: [StudioBrand] = [
        StudioBrand(
            id: "marvel",
            name: "Marvel",
            slug: "marvel",
            isNetwork: false,
            aliases: ["marvel", "марвел", "marvel studios", "marvel entertainment", "marvel comics"],
            searchFranchises: [
                "Мстители", "Железный человек", "Тор", "Первый мститель",
                "Стражи Галактики", "Доктор Стрэндж", "Черная пантера", "Локи",
                "Вандавижн", "Шан-Чи", "Вечные", "Капитан Марвел"
            ],
            excludedKeywords: [
                "шазам", "shazam", "мейзел", "maisel", "revengers", "неуловимые",
                "люди икс", "x-men", "росомаха", "wolverine", "deadpool", "дэдпул",
                "морбиус", "morbius", "человек-паук", "spider-man", "веном", "venom", "1961"
            ]
        ),
        StudioBrand(
            id: "dc",
            name: "DC",
            slug: "dc",
            isNetwork: false,
            aliases: ["dc", "диси", "dc entertainment", "dc comics", "dc studios", "dc films"],
            searchFranchises: [
                "Бэтмен", "Темный рыцарь", "Джокер", "Супермен",
                "Лига справедливости", "Шазам", "Аквамен", "Флэш",
                "Отряд самоубийц", "Миротворец", "Хранители", "Константин", "Чудо-женщина"
            ],
            excludedKeywords: ["marvel", "марвел"]
        ),
        StudioBrand(
            id: "a24",
            name: "A24",
            slug: "a24",
            isNetwork: false,
            aliases: ["a24"],
            searchFranchises: [
                "Всё везде и сразу", "Солнцестояние", "Реинкарнация", "Кит",
                "Маяк", "Падение империи", "Прошлые жизни", "Стальная хватка",
                "Лобстер", "Легенда о Зеленом рыцаре"
            ]
        ),
        StudioBrand(
            id: "pixar",
            name: "Pixar",
            slug: "pixar",
            isNetwork: false,
            aliases: ["pixar", "пиксар", "pixar animation", "pixar animation studios"],
            searchFranchises: [
                "История игрушек", "Тачки", "Корпорация монстров", "ВАЛЛ-И",
                "Вверх", "Головоломка", "Тайна Коко", "Душа",
                "В поисках Немо", "Рататуй", "Суперсемейка", "Элементарно", "Лука", "Вперед"
            ]
        ),
        StudioBrand(
            id: "disney",
            name: "Disney",
            slug: "disney",
            isNetwork: false,
            aliases: ["disney", "дисне", "дискей", "walt disney", "walt disney pictures", "walt disney animation"],
            searchFranchises: [
                "Король Лев", "Холодное сердце", "Зверополис", "Аладдин",
                "Красавица и чудовище", "Моана", "Рапунцель", "Пираты Карибского моря",
                "Русалочка", "Мулан"
            ],
            excludedKeywords: ["marvel", "марвел", "star wars", "звездные войны"]
        ),
        StudioBrand(
            id: "warner-bros",
            name: "Warner Bros.",
            slug: "warner-bros",
            isNetwork: false,
            aliases: ["warner", "уорнер", "warner bros", "warner bros.", "warner brothers", "warner pictures"],
            searchFranchises: [
                "Гарри Поттер", "Фантастические твари", "Властелин колец", "Хоббит",
                "Матрица", "Дюна", "Начало", "Престиж", "Шерлок Холмс"
            ]
        ),
        StudioBrand(
            id: "universal",
            name: "Universal",
            slug: "universal",
            isNetwork: false,
            aliases: ["universal", "юниверсал", "universal pictures", "universal studios"],
            searchFranchises: [
                "Оппенгеймер", "Форсаж", "Парк юрского периода", "Мир юрского периода",
                "Назад в будущее", "Гадкий я", "Миньоны", "Челюсти", "Нечто"
            ]
        ),
        StudioBrand(
            id: "paramount",
            name: "Paramount",
            slug: "paramount",
            isNetwork: false,
            aliases: ["paramount", "парамаунт", "paramount pictures"],
            searchFranchises: [
                "Миссия невыполнима", "Трансформеры", "Топ Ган", "Крестный отец",
                "Интерстеллар", "Соник в кино", "Тихое место", "Форрест Гамп", "Гладиатор", "Волк с Уолл-стрит"
            ]
        ),
        StudioBrand(
            id: "20th-century-studios",
            name: "20th Century",
            slug: "20th-century-studios",
            isNetwork: false,
            aliases: ["20th century", "двадцатый век", "20th century fox", "20th century studios", "fox searchlight"],
            searchFranchises: [
                "Люди Икс", "Росомаха", "Дэдпул", "Логан",
                "Аватар", "Чужой", "Хищник", "Планета обезьян",
                "Крепкий орешек", "Титаник", "Kingsman", "Ледниковый период", "Бойцовский клуб"
            ]
        ),
        StudioBrand(
            id: "sony-pictures",
            name: "Sony Pictures",
            slug: "sony-pictures",
            isNetwork: false,
            aliases: ["sony", "сони", "sony pictures", "columbia pictures", "tristar pictures", "tri-star"],
            searchFranchises: [
                "Человек-паук", "Веном", "Морбиус", "Джуманджи",
                "Охотники за привидениями", "Люди в черном", "Плохие парни",
                "Однажды в Голливуде", "Бегущий по лезвию 2049", "Анчартед", "Гран туризмо", "Малыш на драйве"
            ]
        ),
        StudioBrand(
            id: "dreamworks",
            name: "DreamWorks",
            slug: "dreamworks",
            isNetwork: false,
            aliases: ["dreamworks", "дримворкс", "dreamworks animation"],
            searchFranchises: [
                "Шрек", "Как приручить дракона", "Кунг-фу панда", "Мадагаскар",
                "Кот в сапогах", "Мегамозг", "Дикий робот", "Семейка Крудс", "Босс-молокосос"
            ]
        ),
        
        // Networks / Streamings
        StudioBrand(
            id: "netflix",
            name: "Netflix",
            slug: "netflix",
            isNetwork: true,
            aliases: ["netflix", "нетфликс"],
            searchFranchises: [
                "Очень странные дела", "Игра в кальмара", "Уэнсдэй", "Ведьмак",
                "Бумажный дом", "Аркейн", "Черное зеркало", "Люпен", "Озарк",
                "Корона", "Ход королевы", "Бриджертоны"
            ]
        ),
        StudioBrand(
            id: "hbo",
            name: "HBO",
            slug: "hbo",
            isNetwork: true,
            aliases: ["hbo", "эйчби", "hbo max", "max", "hbo films"],
            searchFranchises: [
                "Игра престолов", "Дом дракона", "Чернобыль", "Одни из нас",
                "Настоящий детектив", "Клан Сопрано", "Эйфория", "Белый лотос",
                "Наследники", "Прослушка", "Барри"
            ]
        ),
        StudioBrand(
            id: "apple-tv-plus",
            name: "Apple TV+",
            slug: "apple-tv-plus",
            isNetwork: true,
            aliases: ["apple tv", "apple tv+", "apple+", "эппл тв", "apple original films"],
            searchFranchises: [
                "Тед Лассо", "Разделение", "Утреннее шоу", "Бункер",
                "Основание", "Медленные лошади", "Убийцы цветочной луны", "Защищая Джейкоба"
            ]
        ),
        StudioBrand(
            id: "prime-video",
            name: "Prime Video",
            slug: "prime-video",
            isNetwork: true,
            aliases: ["prime video", "amazon prime", "amazon studios", "прайм видео"],
            searchFranchises: [
                "Пацаны", "Властелин колец: Кольца власти", "Джек Ричер",
                "Фоллаут", "Непобедимый", "Джентльмены"
            ]
        ),
        StudioBrand(
            id: "hulu",
            name: "Hulu",
            slug: "hulu",
            isNetwork: true,
            aliases: ["hulu", "хулу"],
            searchFranchises: [
                "Медведь", "Рассказ служанки", "Убийства в одном здании", "Сёгун", "Фарго"
            ]
        ),
        StudioBrand(
            id: "cartoon-network",
            name: "Cartoon Network",
            slug: "cartoon-network",
            isNetwork: true,
            aliases: ["cartoon network", "картун нетворк"],
            searchFranchises: [
                "Время приключений", "Самурай Джек", "Обычный мультик", "По ту сторону изгороди", "Удивительный мир Гамбола"
            ]
        ),
        StudioBrand(
            id: "adult-swim",
            name: "Adult Swim",
            slug: "adult-swim",
            isNetwork: true,
            aliases: ["adult swim", "эдалт свим"],
            searchFranchises: [
                "Рик и Морти", "Первобытный", "Робоцып"
            ]
        ),
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
        
        // Exact match with aliases
        if let aliasMatch = all.first(where: { brand in
            brand.aliases.contains(where: { $0.lowercased() == clean })
        }) {
            return aliasMatch
        }
        
        // Word-boundary / token match: company name contains the studio name/alias as a distinct token
        return all.first { brand in
            for alias in brand.aliases {
                let lowerAlias = alias.lowercased()
                if lowerAlias.count <= 3 {
                    let pattern = "(^|[^a-zA-Z0-9а-яА-ЯёЁ])" + NSRegularExpression.escapedPattern(for: lowerAlias) + "([^a-zA-Z0-9а-яА-ЯёЁ]|$)"
                    if clean.range(of: pattern, options: .regularExpression) != nil {
                        return true
                    }
                } else {
                    if clean.contains(lowerAlias) {
                        return true
                    }
                }
            }
            return false
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
