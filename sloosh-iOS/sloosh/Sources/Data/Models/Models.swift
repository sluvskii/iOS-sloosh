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
        
        let text = " \(title ?? "") \(originalTitle ?? "") \(description ?? "") ".lowercased()

        // 1. Marvel
        if let marvel = StudioBrand.find(by: "marvel") {
            let marvelKeywords = [
                "marvel", "марвел", "мстители", "avengers", "железный человек", "iron man",
                "человек-паук", "человек паук", "spider-man", "spiderman", "тор: ", "тор ", " thor",
                "локи", "loki", "капитан америка", "captain america", " халк", "hulk",
                "стражи галактики", "guardians of the galaxy", "дэдпул", "дедпул", "deadpool",
                "росомаха", "wolverine", "люди икс", "люди-икс", "x-men",
                "доктор стрэндж", "доктор стрендж", "doctor strange", "черная пантера", "чёрная пантера", "black panther",
                "человек-муравей", "человек муравей", "ant-man", "соколиный глаз", "hawkeye",
                "вандавижн", "wandavision", "веном", "venom", "вечные", "eternals",
                "шан-чи", "shang-chi", "квантомания", "daredevil", "сорвиголова", "морбиус", "танос"
            ]
            if marvelKeywords.contains(where: { text.contains($0) }) {
                return marvel
            }
        }

        // 2. DC
        if let dc = StudioBrand.find(by: "dc") {
            let dcKeywords = [
                " dc ", "dc comics", "диси", "бэтмен", "батмен", "batman",
                "супермен", "superman", "джокер", "joker", "харли квинн", "harley quinn",
                "чудо-женщина", "чудо женщина", "wonder woman", "аквамен", "aquaman",
                "флэш", "the flash", "шазам", "shazam", "отряд самоубийц", "suicide squad",
                "лига справедливости", "justice league", "миротворец", "peacemaker",
                "готэм", "gotham", "пингвин", "the penguin", "черный адам", "чёрный адам"
            ]
            if dcKeywords.contains(where: { text.contains($0) }) {
                return dc
            }
        }

        // 3. Pixar
        if let pixar = StudioBrand.find(by: "pixar") {
            let pixarKeywords = [
                "pixar", "пиксар", "история игрушек", "toy story", "тачки", "тачки 2", "тачки 3", " cars",
                "в поисках немо", "finding nemo", "в поисках дори", "головоломка", "inside out",
                "вверх", "корпорация монстров", "monsters, inc", "суперсемейка", "the incredibles",
                "рататуй", "ratatouille", "тайна коко", " coco", "душа", " soul", "лука", " luca",
                "я краснею", "turning red", "элементарно", "elemental", "храбрая сердцем",
                "хороший динозавр", "вперед", "onward", "базз лайтер", "lightyear", "валл-и", "wall-e"
            ]
            if pixarKeywords.contains(where: { text.contains($0) }) {
                return pixar
            }
        }

        // 4. Disney
        if let disney = StudioBrand.find(by: "disney") {
            let disneyKeywords = [
                "disney", "дисне", "холодное сердце", "frozen", "король лев", "lion king",
                "русалочка", "little mermaid", "моана", "moana", "энканто", "encanto",
                "зверополис", "zootopia", "рапунцель", "tangled", "красавица и чудовище", "beauty and the beast",
                "аладдин", "aladdin", "мулан", "mulan", "покахонтас", "геркулес", "hercules",
                "пиноккио", "тарзан", "дамбо", "бэмби", "белоснежка", "snow white", "круэлла", "cruella", "малефисента"
            ]
            if disneyKeywords.contains(where: { text.contains($0) }) {
                return disney
            }
        }

        // 5. DreamWorks
        if let dreamworks = StudioBrand.find(by: "dreamworks") {
            let dwKeywords = [
                "dreamworks", "дримворкс", "дримворк", "шрек", "shrek", "кот в сапогах", "puss in boots",
                "как приручить дракона", "how to train your dragon", "кунг-фу панда", "кунг фу панда", "kung fu panda",
                "мадагаскар", "madagascar", "босс-молокосос", "босс молокосос", "the boss baby",
                "тролли", "trolls", "плохие парни", "the bad guys", "мегамозг", "megamind",
                "подводная братва", "синдбад", "дикий робот", "the wild robot"
            ]
            if dwKeywords.contains(where: { text.contains($0) }) {
                return dreamworks
            }
        }

        // 6. HBO
        if let hbo = StudioBrand.find(by: "hbo") {
            let hboKeywords = [
                "hbo", "эйчби", "игра престолов", "game of thrones", "дом дракона", "house of the dragon",
                "чернобыль", "chernobyl", "настоящий детектив", "true detective", "наследники", "succession",
                "клан сопрано", "the sopranos", "прослушка", "the wire", "белый лотос", "the white lotus",
                "эйфория", "euphoria", "одни из нас", "одних из нас", "the last of us",
                "мир дикого запада", "westworld", "секс в большом городе", "sex and the city", "барри", "кремниевая долина"
            ]
            if hboKeywords.contains(where: { text.contains($0) }) {
                return hbo
            }
        }

        // 7. Netflix
        if let netflix = StudioBrand.find(by: "netflix") {
            let netflixKeywords = [
                "netflix", "нетфликс", "очень странные дела", "stranger things", "игра в кальмара", "squid game",
                "уэнсдэй", "уэнздей", "wednesday", "ведьмак", "the witcher", "бумажный дом", "money heist",
                "la casa de papel", "аркейн", "arcane", "половое воспитание", "sex education",
                "корона", "the crown", "черное зеркало", "чёрное зеркало", "black mirror",
                "люпен", "lupin", "озарк", "ozark", "бриджертоны", "bridgerton"
            ]
            if netflixKeywords.contains(where: { text.contains($0) }) {
                return netflix
            }
        }

        // 8. Apple TV+
        if let apple = StudioBrand.find(by: "apple-tv-plus") {
            let appleKeywords = [
                "apple tv", "apple+", "эппл тв", "тед лассо", "ted lasso", "утреннее шоу", "the morning show",
                "разделение", "severance", "основание", "foundation", "медленные лошади", "slow horses",
                "бункер", "silo", "ради всего человечества", "убийцы цветочной луны"
            ]
            if appleKeywords.contains(where: { text.contains($0) }) {
                return apple
            }
        }

        // 9. A24
        if let a24 = StudioBrand.find(by: "a24") {
            let a24Keywords = [
                "a24", "всё везде и сразу", "все везде и сразу", "everything everywhere all at once",
                "солнцестояние", "midsommar", "реинкарнация", "hereditary", "кит", "the whale",
                "лунный свет", "moonlight", "маяк", "the lighthouse", "гражданская война", "civil war",
                "прошлые жизни", "past lives", "зона интересов", "zone of interest"
            ]
            if a24Keywords.contains(where: { text.contains($0) }) {
                return a24
            }
        }

        // 10. Warner Bros.
        if let warner = StudioBrand.find(by: "warner-bros") {
            let warnerKeywords = [
                "warner", "уорнер", "гарри поттер", "harry potter", "фантастические твари", "fantastic beasts",
                "властелин колец", "lord of the rings", "хоббит", "the hobbit", "матрица", "the matrix",
                "дюна", "dune"
            ]
            if warnerKeywords.contains(where: { text.contains($0) }) {
                return warner
            }
        }

        // 11. Universal
        if let universal = StudioBrand.find(by: "universal") {
            let universalKeywords = [
                "universal", "юниверсал", "форсаж", "fast & furious", "парк юрского периода", "мир юрского периода",
                "jurassic park", "jurassic world", "оппенгеймер", "oppenheimer", "челюсти", "jaws",
                "назад в будущее", "back to the future", "гадкий я", "despicable me", "миньоны", "minions"
            ]
            if universalKeywords.contains(where: { text.contains($0) }) {
                return universal
            }
        }

        // 12. Paramount
        if let paramount = StudioBrand.find(by: "paramount") {
            let paramountKeywords = [
                "paramount", "парамаунт", "миссия невыполнима", "mission: impossible", "трансформеры", "transformers",
                "крестный отец", "крёстный отец", "the godfather", "топ ган", "top gun", "индиана джонс",
                "тихое место", "a quiet place", "соник в кино", "sonic the hedgehog", "йеллоустоун", "yellowstone"
            ]
            if paramountKeywords.contains(where: { text.contains($0) }) {
                return paramount
            }
        }

        // 13. Sony Pictures
        if let sony = StudioBrand.find(by: "sony-pictures") {
            let sonyKeywords = [
                "sony pictures", "сони пикчерз", "сони пикчерс", "через вселенные", "into the spider-verse",
                "охотники за привидениями", "ghostbusters", "джуманджи", "jumanji", "люди в черном"
            ]
            if sonyKeywords.contains(where: { text.contains($0) }) {
                return sony
            }
        }

        // 14. 20th Century
        if let century = StudioBrand.find(by: "20th-century-studios") {
            let centuryKeywords = [
                "20th century", "двадцатый век", "аватар", "avatar", "чужой", "alien", "хищник", "predator",
                "планета обезьян", "planet of the apes", "крепкий орешек", "die hard", "титаник", "titanic"
            ]
            if centuryKeywords.contains(where: { text.contains($0) }) {
                return century
            }
        }

        // General fallback for brand name in text
        for brand in StudioBrand.all {
            if text.contains(brand.name.lowercased()) {
                return brand
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

    init(id: String, name: String, slug: String, isNetwork: Bool, aliases: [String] = []) {
        self.id = id
        self.name = name
        self.slug = slug
        self.isNetwork = isNetwork
        self.aliases = aliases
    }
    
    static let all: [StudioBrand] = [
        StudioBrand(
            id: "marvel",
            name: "Marvel",
            slug: "marvel",
            isNetwork: false,
            aliases: ["marvel", "марвел", "marvel studios", "marvel entertainment", "marvel comics"]
        ),
        StudioBrand(
            id: "dc",
            name: "DC",
            slug: "dc",
            isNetwork: false,
            aliases: ["dc", "диси", "dc entertainment", "dc comics", "dc studios"]
        ),
        StudioBrand(
            id: "a24",
            name: "A24",
            slug: "a24",
            isNetwork: false,
            aliases: ["a24"]
        ),
        StudioBrand(
            id: "pixar",
            name: "Pixar",
            slug: "pixar",
            isNetwork: false,
            aliases: ["pixar", "пиксар", "pixar animation", "pixar animation studios"]
        ),
        StudioBrand(
            id: "disney",
            name: "Disney",
            slug: "disney",
            isNetwork: false,
            aliases: ["disney", "дисне", "дискей", "walt disney", "walt disney pictures", "walt disney animation"]
        ),
        StudioBrand(
            id: "warner-bros",
            name: "Warner Bros.",
            slug: "warner-bros",
            isNetwork: false,
            aliases: ["warner", "уорнер", "warner bros", "warner bros.", "warner brothers", "warner pictures"]
        ),
        StudioBrand(
            id: "universal",
            name: "Universal",
            slug: "universal",
            isNetwork: false,
            aliases: ["universal", "юниверсал", "universal pictures", "universal studios"]
        ),
        StudioBrand(
            id: "paramount",
            name: "Paramount",
            slug: "paramount",
            isNetwork: false,
            aliases: ["paramount", "парамаунт", "paramount pictures"]
        ),
        StudioBrand(
            id: "20th-century-studios",
            name: "20th Century",
            slug: "20th-century-studios",
            isNetwork: false,
            aliases: ["20th century", "двадцатый век", "20th century fox", "20th century studios"]
        ),
        StudioBrand(
            id: "sony-pictures",
            name: "Sony Pictures",
            slug: "sony-pictures",
            isNetwork: false,
            aliases: ["sony", "сони", "sony pictures", "columbia pictures", "tristar pictures"]
        ),
        StudioBrand(
            id: "dreamworks",
            name: "DreamWorks",
            slug: "dreamworks",
            isNetwork: false,
            aliases: ["dreamworks", "дримворкс", "dreamworks animation"]
        ),
        
        // Networks / Streamings
        StudioBrand(
            id: "netflix",
            name: "Netflix",
            slug: "netflix",
            isNetwork: true,
            aliases: ["netflix", "нетфликс"]
        ),
        StudioBrand(
            id: "hbo",
            name: "HBO",
            slug: "hbo",
            isNetwork: true,
            aliases: ["hbo", "эйчби", "hbo max", "max", "hbo films"]
        ),
        StudioBrand(
            id: "apple-tv-plus",
            name: "Apple TV+",
            slug: "apple-tv-plus",
            isNetwork: true,
            aliases: ["apple tv", "apple tv+", "apple+", "эппл тв", "apple original films"]
        ),
        StudioBrand(
            id: "prime-video",
            name: "Prime Video",
            slug: "prime-video",
            isNetwork: true,
            aliases: ["prime video", "amazon prime", "amazon studios", "прайм видео"]
        ),
        StudioBrand(
            id: "hulu",
            name: "Hulu",
            slug: "hulu",
            isNetwork: true,
            aliases: ["hulu", "хулу"]
        ),
        StudioBrand(
            id: "cartoon-network",
            name: "Cartoon Network",
            slug: "cartoon-network",
            isNetwork: true,
            aliases: ["cartoon network", "картун нетворк"]
        ),
        StudioBrand(
            id: "adult-swim",
            name: "Adult Swim",
            slug: "adult-swim",
            isNetwork: true,
            aliases: ["adult swim", "эдалт свим"]
        ),
    ]
    
    static func find(by nameOrId: String) -> StudioBrand? {
        let clean = nameOrId.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { return nil }
        return all.first { brand in
            brand.id.lowercased() == clean ||
            brand.slug.lowercased() == clean ||
            brand.name.lowercased() == clean ||
            clean.contains(brand.id.lowercased()) ||
            clean.contains(brand.name.lowercased()) ||
            brand.aliases.contains(where: { clean.contains($0) || $0.contains(clean) })
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
