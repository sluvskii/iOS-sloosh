import Foundation

/// Transport text stays readable; comparison keys fold case/ё/punctuation only.
enum CatalogSearchQuery {
    static func text(_ raw: String) -> String {
        String(raw.precomposedStringWithCanonicalMapping
            .components(separatedBy: .whitespacesAndNewlines.union(.controlCharacters))
            .filter { !$0.isEmpty }.joined(separator: " ").prefix(200))
    }

    static func key(_ raw: String) -> String {
        text(raw).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "ru_RU"))
            .replacingOccurrences(of: "ё", with: "е")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Bounded, only after a successful EMPTY response. Never retry network
    /// errors as spelling errors and never replace a nonempty primary result.
    static func alternatives(_ raw: String) -> [String] {
        let query = text(raw).lowercased()
        guard query.count >= 3, query.count <= 100 else { return [] }
        let latin = Array("qwertyuiop[]asdfghjkl;'zxcvbnm,.")
        let russian = Array("йцукенгшщзхъфывапролджэячсмитьбю")
        let hasLatin = query.unicodeScalars.contains { (97...122).contains($0.value) }
        let hasRussian = query.unicodeScalars.contains { (0x430...0x44F).contains($0.value) }
        guard hasLatin != hasRussian else { return [] }
        let map = Dictionary(uniqueKeysWithValues: zip(hasLatin ? latin : russian, hasLatin ? russian : latin))
        let keyboard = String(query.map { map[$0] ?? $0 })
        let transliteration = hasLatin
            ? query.applyingTransform(StringTransform("Latin-Cyrillic"), reverse: false)
            : query.applyingTransform(.toLatin, reverse: false)
        var seen = Set([key(query)])
        return [keyboard, transliteration].compactMap { $0 }.filter {
            !key($0).isEmpty && seen.insert(key($0)).inserted
        }.prefix(2).map { $0 }
    }

    static func suggestions(for query: String, candidates: [String]) -> [String] {
        let needle = key(query)
        var seen = Set<String>()
        let ranked = candidates.prefix(200).compactMap { candidate -> (String, Int)? in
            let title = text(candidate)
            let value = key(title)
            guard !value.isEmpty, seen.insert(value).inserted, value != needle else { return nil }
            if needle.isEmpty || value.hasPrefix(needle) { return (title, 0) }
            if value.contains(needle) { return (title, 1) }
            guard needle.count >= 3, needle.count <= 80 else { return nil }
            let prefix = String(value.prefix(needle.count + 1))
            let distance = editDistance(needle, value.count > needle.count + 2 ? prefix : value)
            return distance <= (needle.count >= 6 ? 2 : 1) ? (title, 2 + distance) : nil
        }
        return ranked.enumerated().sorted {
            $0.element.1 == $1.element.1 ? $0.offset < $1.offset : $0.element.1 < $1.element.1
        }.prefix(6).map { $0.element.0 }
    }

    /// Optimal-string-alignment distance, including adjacent transpositions.
    static func editDistance(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs.prefix(100)), b = Array(rhs.prefix(100))
        var matrix = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { matrix[i][0] = i }
        for j in 0...b.count { matrix[0][j] = j }
        guard !a.isEmpty, !b.isEmpty else { return max(a.count, b.count) }
        for i in 1...a.count {
            for j in 1...b.count {
                matrix[i][j] = min(matrix[i - 1][j] + 1, matrix[i][j - 1] + 1,
                                   matrix[i - 1][j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    matrix[i][j] = min(matrix[i][j], matrix[i - 2][j - 2] + 1)
                }
            }
        }
        return matrix[a.count][b.count]
    }
}

extension SearchFilters {
    var normalized: SearchFilters {
        var copy = self
        copy.type = type.flatMap { raw in
            let value = CatalogSearchQuery.text(raw).uppercased()
            if value.isEmpty { return nil }
            return ["MOVIE": "FILM", "TV": "TV_SERIES", "ANIMATION": "CARTOON"][value] ?? value
        }
        copy.order = order.flatMap { CatalogSearchQuery.text($0).isEmpty ? nil : CatalogSearchQuery.text($0).uppercased() }
        copy.studio = studio.flatMap { CatalogSearchQuery.text($0).isEmpty ? nil : CatalogSearchQuery.text($0) }
        copy.selectedGenres = selectedGenres
        copy.selectedCountries = selectedCountries
        copy.ratingFrom = ratingFrom.flatMap { $0.isFinite ? min(10, max(0, $0)) : nil }
        copy.ratingTo = ratingTo.flatMap { $0.isFinite ? min(10, max(0, $0)) : nil }
        if let low = copy.ratingFrom, let high = copy.ratingTo, low > high {
            copy.ratingFrom = high; copy.ratingTo = low
        }
        copy.yearFrom = yearFrom.map { min(9999, max(1880, $0)) }
        copy.yearTo = yearTo.map { min(9999, max(1880, $0)) }
        if let low = copy.yearFrom, let high = copy.yearTo, low > high {
            copy.yearFrom = high; copy.yearTo = low
        }
        return copy
    }

    var activeCount: Int {
        [type != nil, order != nil, ratingFrom != nil || ratingTo != nil,
         yearFrom != nil || yearTo != nil, !selectedGenres.isEmpty,
         !selectedCountries.isEmpty, studio != nil].filter { $0 }.count
    }
}

enum CatalogSearchPolicy {
    private static let genreGroups: [[String]] = [
        ["28", "10759", "боевик", "action", "action & adventure"], ["35", "комедия", "comedy"],
        ["18", "драма", "drama"], ["878", "фантастика", "science fiction", "sci-fi", "научная фантастика"],
        ["14", "фэнтези", "fantasy"], ["10765", "нф и фэнтези", "sci-fi & fantasy"],
        ["53", "триллер", "thriller"], ["27", "ужасы", "horror"],
        ["9648", "детектив", "mystery"], ["10749", "мелодрама", "romance"],
        ["12", "приключения", "adventure"], ["16", "мультфильм", "animation"],
        ["80", "криминал", "crime"], ["10751", "семейный", "family"],
        ["99", "документальный", "documentary"], ["10752", "10768", "военный", "war", "war & politics"],
        ["36", "история", "history"], ["аниме", "anime"]
    ]
    private static let countryGroups = [
        ["россия", "ru", "russia"], ["сша", "us", "usa", "united states", "united states of america"],
        ["великобритания", "gb", "uk", "united kingdom"], ["франция", "fr", "france"],
        ["южная корея", "kr", "south korea", "korea, republic of"], ["япония", "jp", "japan"],
        ["ссср", "su", "ussr", "soviet union"], ["германия", "de", "germany"], ["испания", "es", "spain"],
        ["италия", "it", "italy"], ["турция", "tr", "turkey", "türkiye"], ["канада", "ca", "canada"],
        ["индия", "in", "india"], ["китай", "cn", "china"]
    ]

    private static func canonical(_ value: String, groups: [[String]]) -> String {
        let key = CatalogSearchQuery.key(value)
        return groups.first { $0.contains { CatalogSearchQuery.key($0) == key } }?.first ?? key
    }

    static func hasTitle(_ item: MediaDto) -> Bool {
        [item.title, item.name, item.originalTitle].contains { !CatalogSearchQuery.text($0 ?? "").isEmpty }
    }

    /// All selected genres, any selected country; AND between independent fields.
    /// Unknown metadata is not evidence of a match in title-search responses.
    static func matches(_ item: MediaDto, filters: SearchFilters, serverFiltered: Bool = false) -> Bool {
        let f = filters.normalized
        // A named genre wins over an ambiguous numeric namespace. A legacy
        // numeric 16 paired with "Комедия" must not turn a film into animation.
        let genres = Set((item.genres ?? []).compactMap { genre -> String? in
            if let name = genre.name, !CatalogSearchQuery.text(name).isEmpty {
                return canonical(name, groups: genreGroups)
            }
            return genre.id.map { canonical($0, groups: genreGroups) }
        })
        let countries = Set((item.countries ?? []).map { canonical($0, groups: countryGroups) })
        let rawType = item.type?.lowercased() ?? ""
        let anime = rawType == "anime" || genres.contains("аниме") || (genres.contains("16") && countries.contains("япония"))
        let animation = rawType == "cartoon" || rawType == "animation" || genres.contains("16") || anime
        if let type = f.type {
            let rawID = item.originalId?.stringValue ?? ""
            let tv = ["tv", "tv_series", "series", "mini_series", "show", "serial", "tv-series", "tv_show"].contains(rawType) || rawID.hasPrefix("tv_")
            let film = ["movie", "film", "cinema"].contains(rawType) || rawID.hasPrefix("movie_")
            switch type.uppercased() {
            case "FILM", "MOVIE":
                if tv || animation || (!film && !serverFiltered) { return false }
            case "TV_SERIES", "TV":
                if film || animation || (!tv && !serverFiltered) { return false }
            case "CARTOON":
                if anime { return false }
                if !animation && (!serverFiltered || !genres.isEmpty) { return false }
            case "ANIME":
                if !anime && (!serverFiltered || (!genres.isEmpty && !countries.isEmpty)) { return false }
            default: break
            }
        }
        if f.ratingFrom != nil || f.ratingTo != nil {
            let rating = item.effectiveRating
            if rating <= 0 { if !serverFiltered { return false } }
            else if rating < (f.ratingFrom ?? 0) || rating > (f.ratingTo ?? 10) { return false }
        }
        if f.yearFrom != nil || f.yearTo != nil {
            if let year = item.effectiveYear {
                if year < (f.yearFrom ?? Int.min) || year > (f.yearTo ?? Int.max) { return false }
            } else if !serverFiltered { return false }
        }
        if !f.selectedGenres.isEmpty {
            let targets = Set(f.selectedGenres.map { canonical($0, groups: genreGroups) })
            // Combined TV genre overlaps both sci-fi and fantasy, not vice versa.
            var expanded = genres
            if anime { expanded.insert("аниме") }
            if genres.contains("10765") { expanded.formUnion(["878", "14"]) }
            if targets.contains("10765"), !genres.isDisjoint(with: ["878", "14"]) { expanded.insert("10765") }
            if !expanded.isSuperset(of: targets) && !(genres.isEmpty && serverFiltered) { return false }
        }
        if !f.selectedCountries.isEmpty {
            let targets = Set(f.selectedCountries.map { canonical($0, groups: countryGroups) })
            if countries.isDisjoint(with: targets) && !(countries.isEmpty && serverFiltered) { return false }
        }
        return true
    }

    static func merge(_ existing: [MediaDto], _ incoming: [MediaDto], order: String?) -> [MediaDto] {
        var seen = Set<String>()
        let items = (existing + incoming).filter { hasTitle($0) && seen.insert($0.artworkIdentifier).inserted }
        return items.enumerated().sorted { a, b in
            if order == "YEAR" {
                let ay = a.element.effectiveYear ?? 0, by = b.element.effectiveYear ?? 0
                if ay != by { return ay > by }
                let ad = a.element.releaseDate ?? "", bd = b.element.releaseDate ?? ""
                if ad != bd { return ad > bd }
            } else if order == "RATING", a.element.effectiveRating != b.element.effectiveRating {
                return a.element.effectiveRating > b.element.effectiveRating
            }
            return a.offset < b.offset
        }.map(\.element)
    }
}

enum CatalogSearchError: LocalizedError {
    case invalidResponse
    case studioWithTitle

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Не удалось прочитать результаты. Попробуйте ещё раз."
        case .studioWithTitle: return "Поиск по названию внутри студии пока недоступен. Откройте подборку студии отдельно."
        }
    }
}

/// Shared by transport and tests: stable sets and locale-independent decimals.
enum CatalogSearchRequest {
    static func encodedQuery(_ items: [URLQueryItem]) -> String? {
        var components = URLComponents()
        components.queryItems = items
        // URLSearchParams-style servers interpret a raw '+' as a space.
        // URLComponents alone deliberately leaves '+' unescaped.
        return components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
    }

    static func discoveryItems(filters: SearchFilters, page: Int) -> [URLQueryItem] {
        let f = filters.normalized
        var items = [URLQueryItem(name: "page", value: String(max(1, min(500, page))))]
        for (name, value) in [("type", f.type), ("order", f.order), ("genres", f.genres),
                              ("countries", f.countries), ("studio", f.studio)] {
            if let value { items.append(URLQueryItem(name: name, value: value)) }
        }
        for (name, value) in [("ratingFrom", f.ratingFrom), ("ratingTo", f.ratingTo)] {
            if let value { items.append(URLQueryItem(name: name, value: String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value))) }
        }
        for (name, value) in [("yearFrom", f.yearFrom), ("yearTo", f.yearTo)] {
            if let value { items.append(URLQueryItem(name: name, value: String(value))) }
        }
        return items
    }
}

/// One removable chip per independent constraint, not one per selected genre.
enum CatalogSearchFilter: String, CaseIterable, Identifiable {
    case type, order, rating, year, genres, countries, studio
    var id: String { rawValue }

    func label(in filters: SearchFilters) -> String? {
        let f = filters.normalized
        switch self {
        case .type:
            return f.type.map { ["FILM": "Фильмы", "TV_SERIES": "Сериалы", "CARTOON": "Мультфильмы", "ANIME": "Аниме"][$0] ?? $0 }
        case .order:
            return f.order.map { ["YEAR": "По году", "RATING": "По рейтингу", "NUM_VOTE": "По популярности"][$0] ?? $0 }
        case .rating:
            guard f.ratingFrom != nil || f.ratingTo != nil else { return nil }
            func number(_ value: Double) -> String { String(format: "%.1f", locale: Locale(identifier: "ru_RU"), value) }
            if let low = f.ratingFrom, let high = f.ratingTo { return "Рейтинг \(number(low))–\(number(high))" }
            if let low = f.ratingFrom { return "Рейтинг от \(number(low))" }
            return "Рейтинг до \(number(f.ratingTo!))"
        case .year:
            guard f.yearFrom != nil || f.yearTo != nil else { return nil }
            if let low = f.yearFrom, let high = f.yearTo { return low == high ? String(low) : "\(low)–\(high)" }
            if let low = f.yearFrom { return "С \(low) года" }
            return "До \(f.yearTo!) года"
        case .genres: return f.selectedGenres.isEmpty ? nil : f.selectedGenres.sorted().joined(separator: ", ").capitalized
        case .countries: return f.selectedCountries.isEmpty ? nil : f.selectedCountries.sorted().joined(separator: ", ")
        case .studio: return f.studio.map { StudioBrand.find(by: $0)?.name ?? $0 }
        }
    }

    func removing(from filters: SearchFilters) -> SearchFilters {
        var f = filters
        switch self {
        case .type: f.type = nil
        case .order: f.order = nil
        case .rating: f.ratingFrom = nil; f.ratingTo = nil
        case .year: f.yearFrom = nil; f.yearTo = nil
        case .genres: f.genres = nil
        case .countries: f.countries = nil
        case .studio: f.studio = nil
        }
        return f.normalized
    }
}
