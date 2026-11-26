import Foundation

struct AllohaTranslation: Codable, Hashable, Equatable, Sendable {
    let id: String
    let name: String
    let iframeUrl: String
    /// Pre-resolved direct stream URL. Set for films where multiple dubs share a single
    /// iframe URL — bypasses runtime re-resolution and avoids name-matching ambiguity.
    let streamUrl: String?
}

struct AllohaEpisode: Codable, Hashable, Equatable, Sendable {
    let season: Int
    let episode: Int
    let translations: [AllohaTranslation]
}

struct AllohaSeason: Codable, Hashable, Equatable, Sendable {
    let season: Int
    let episodes: [AllohaEpisode]
}

struct AllohaMovie: Codable, Hashable, Equatable, Sendable {
    let title: String
    let iframeUrl: String
    let translations: [AllohaTranslation]
}

struct AllohaApiResult: Codable, Hashable, Equatable, Sendable {
    let title: String
    let isSerial: Bool
    let movie: AllohaMovie?
    let seasons: [AllohaSeason]
}

extension AllohaApiResult {
    var allTranslationNames: [String] {
        if isSerial {
            // Берём порядок из первого эпизода первого сезона (Alloha возвращает популярные первыми)
            // Затем добавляем любые дополнительные имена из других эпизодов
            // Субтитры исключаются из озвучек и доступны независимо в плеере
            var names: [String] = []
            var seen = Set<String>()
            for season in seasons {
                for episode in season.episodes {
                    for t in episode.translations {
                        let lower = t.name.lowercased()
                        if lower.contains("субтитр") || lower.contains("subtitle") {
                            continue
                        }
                        if seen.insert(t.name).inserted {
                            names.append(t.name)
                        }
                    }
                }
            }
            return names
        } else if let movie = movie {
            return movie.translations.map { $0.name }.filter { name in
                let lower = name.lowercased()
                return !lower.contains("субтитр") && !lower.contains("subtitle")
            }
        }
        return []
    }
}

func injectTranslationId(_ id: String, into urlString: String) -> String {
    guard var comps = URLComponents(string: urlString) else { return urlString }
    var items = comps.queryItems ?? []
    items.removeAll { $0.name == "translation" }
    items.append(URLQueryItem(name: "translation", value: id))
    comps.queryItems = items
    return comps.string ?? urlString
}

func injectSeasonEpisode(season: Int, episode: Int, into urlString: String) -> String {
    guard var comps = URLComponents(string: urlString) else { return urlString }
    var items = comps.queryItems ?? []
    items.removeAll { $0.name == "season" || $0.name == "episode" }
    items.append(URLQueryItem(name: "season", value: String(season)))
    items.append(URLQueryItem(name: "episode", value: String(episode)))
    comps.queryItems = items
    return comps.string ?? urlString
}

func normalizedAllohaTranslationName(_ raw: String?) -> String {
    guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
        return ""
    }

    value = value
        .replacingOccurrences(of: "💬", with: "")
        .replacingOccurrences(of: "(?i)\\b(?:AC3|E-AC3|EAC3|DDP|DD|DTS-HD|DTS|TrueHD|AAC|FLAC|MP3|PCM|LPCM)\\s*(?:5[.]?1|7[.]?1|2[.]?0|51)?(?:\\s*@\\s*\\d+\\s*(?:kbps|kbit|кбит/с|кб/с)?)?", with: "", options: .regularExpression)
        .replacingOccurrences(of: "(?i)@\\s*\\d+\\s*(?:kbps|kbit|кбит/с|кб/с)?", with: "", options: .regularExpression)
        .replacingOccurrences(of: "(?i)\\b\\d+\\s*(?:kbps|kbit|кбит/с|кб/с)\\b", with: "", options: .regularExpression)
        .replacingOccurrences(of: "(?i)\\b(?:Blu-ray(?:\\s*CEE)?|BDRip|WEB-DL|HDTV|Line)\\b", with: "", options: .regularExpression)
        .replacingOccurrences(of: "(?i)\\((?:Russian|Ukrainian|Kazakh|English|Uzbek|Turkish|Georgian|Japanese|Korean|Chinese)\\)", with: "", options: .regularExpression)
        .replacingOccurrences(of: "(?i)\\bDUB\\b", with: "Дубляж", options: .regularExpression)
        .replacingOccurrences(of: "(?i)\\bMVO\\b", with: "Многоголосый", options: .regularExpression)
        .replacingOccurrences(of: "(?i)\\bDVO\\b", with: "Двухголосый", options: .regularExpression)
        .replacingOccurrences(of: "(?i)\\bAVO\\b", with: "Авторский", options: .regularExpression)
        .replacingOccurrences(of: "(?i)\\bПМ\\b", with: "Проф. многоголосый", options: .regularExpression)
        .replacingOccurrences(of: "(?i)\\bПД\\b", with: "Проф. двухголосый", options: .regularExpression)
        .replacingOccurrences(of: "(?i)\\bЛМ\\b", with: "Люб. многоголосый", options: .regularExpression)
        .replacingOccurrences(of: "(?i)\\bЛД\\b", with: "Люб. двухголосый", options: .regularExpression)
        .replacingOccurrences(of: "[", with: " ")
        .replacingOccurrences(of: "]", with: " ")
        .replacingOccurrences(of: "(", with: " ")
        .replacingOccurrences(of: ")", with: " ")
        .replacingOccurrences(of: "|", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)

    while value.hasPrefix("-") || value.hasPrefix(",") || value.hasPrefix("–") || value.hasPrefix("—") {
        value = String(value.dropFirst()).trimmingCharacters(in: .whitespaces)
    }
    while value.hasSuffix("-") || value.hasSuffix(",") || value.hasSuffix("–") || value.hasSuffix("—") {
        value = String(value.dropLast()).trimmingCharacters(in: .whitespaces)
    }

    value = value
        .replacingOccurrences(of: "(?i)\\bHDrezka\\s+St(?:\\.|\\b)", with: "HDrezka Studio", options: .regularExpression)
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)

    return value
}

func detectLanguageTag(in text: String) -> String? {
    let lower = text.lowercased()
    if lower.contains("украин") || lower.contains("ukrain") || lower.contains("укр") || lower.contains("ukr") || lower == "uk" {
        return "ukr"
    }
    if lower.contains("казах") || lower.contains("kazakh") || lower.contains("kaz") || lower == "kk" {
        return "kaz"
    }
    if lower.contains("узбек") || lower.contains("uzbek") || lower.contains("узб") || lower.contains("uzb") || lower == "uz" {
        return "uzb"
    }
    if lower.contains("оригинал") || lower.contains("original") || lower.contains("english") || lower.contains("английск") || lower == "en" || lower.range(of: #"(?:^|[^a-z])eng(?:\d*$|[^a-z])"#, options: .regularExpression) != nil {
        return "eng"
    }
    if lower.contains("грузин") || lower.contains("georgian") || lower.contains("geo") {
        return "geo"
    }
    if lower.contains("турец") || lower.contains("turkish") || lower.contains("turk") {
        return "tur"
    }
    if lower.contains("япон") || lower.contains("japan") || lower.contains("jap") {
        return "jap"
    }
    if lower.contains("корей") || lower.contains("korean") || lower.contains("kor") {
        return "kor"
    }
    if lower.contains("китай") || lower.contains("chinese") || lower.contains("chi") {
        return "chi"
    }
    if lower.contains("русск") || lower.contains("russian") || lower == "ru" || lower.range(of: #"(?:^|[^a-z])rus(?:\d*$|[^a-z])"#, options: .regularExpression) != nil || lower.contains("дубл") || lower.contains("дуб") || lower.contains("закадр") || lower.contains("многоголос") {
        return "rus"
    }
    return nil
}

/// Проверяет, относится ли название дорожки к оригиналу / английскому языку
func isOriginalOrEnglishTranslation(_ name: String?) -> Bool {
    guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
        return false
    }
    let lower = name.lowercased()
    if lower.contains("дубл") || lower.contains("дуб") || lower.contains("русск") || lower.contains("полное дублирование") {
        return false
    }
    if lower == "en" || lower == "eng" || lower == "оригинал" || lower == "original" {
        return true
    }
    if lower.contains("оригинал") || lower.contains("original") || lower.contains("english") || lower.contains("английск") {
        return true
    }
    return detectLanguageTag(in: name) == "eng"
}

/// Проверяет, является ли дорожка русской (дубляж, закадровый перевод или студийный)
func isRussianTranslation(_ name: String?) -> Bool {
    guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
        return false
    }
    if isOriginalOrEnglishTranslation(name) {
        return false
    }
    let tag = detectLanguageTag(in: name)
    if let tag, tag != "rus" {
        return false
    }
    return true
}

/// Вычисляет ранжирование озвучки для правильной сортировки (меньше число = выше приоритет для зрителя)
func translationRank(_ name: String) -> Int {
    let lower = name.lowercased()
    let lang = detectLanguageTag(in: name)

    if let lang, lang != "rus" && lang != "eng" {
        return 80
    }
    if lower.contains("субтитр") || lower.contains("subtitle") {
        return 70
    }
    if isOriginalOrEnglishTranslation(name) {
        return 90
    }
    if lower.contains("дубл") || lower.contains("дуб") || lower.contains("полное дублирование") {
        return 10
    }
    let topStudios = ["пифагор", "невафильм", "red head sound", "rhs", "flarrow"]
    if topStudios.contains(where: { lower.contains($0) }) {
        return 20
    }
    let proKeywords = ["профессиональн", "проф", "многоголос", "hdrezka", "lostfilm", "кубик в кубе"]
    if proKeywords.contains(where: { lower.contains($0) }) {
        return 30
    }
    return 40
}

func isTranslationNoiseWord(_ word: String) -> Bool {
    let noise: Set<String> = [
        "studio", "студия", "дубляж", "дублированный", "дублирование", "полное",
        "многоголосый", "двухголосый", "одноголосый", "авторский", "закадровый", "озвучка",
        "профессиональный", "проф", "любительский", "люб", "production", "films", "film",
        "team", "voice", "line", "перевод", "голос", "звук", "чистый", "версия", "театральная",
        "расширенная", "режиссерская", "режиссёрская", "рус", "укр", "русский", "russian",
        "украинский", "ukrainian", "полный", "оригинал", "original", "english", "eng"
    ]
    return noise.contains(word.lowercased())
}

private let studioAliasGroups: [(canonical: String, aliases: [String])] = [
    ("redheadsound", ["red head sound", "rhs"]),
    ("flarrow", ["flarrow films", "flarrow"]),
    ("lostfilm", ["lostfilm", "лостфильм"]),
    ("tvshows", ["tvshows"]),
    ("newstudio", ["newstudio", "ньюстудио"]),
    ("newcomers", ["newcomers"]),
    ("alexfilm", ["alexfilm"]),
    ("kubik", ["кубик в кубе", "кубик"]),
    ("hdrezka", ["hdrezka", "rezka"]),
    ("baibako", ["baibako"]),
    ("jaskier", ["jaskier", "жаскир"]),
    ("novamedia", ["novamedia", "новамедиа"]),
    ("amedia", ["amedia", "амедиа"]),
    ("vsi", ["vsi"]),
    ("ironvoice", ["iron voice"]),
    ("kuraj", ["кураж бамбей"]),
    ("kravec", ["кравец-рекордз", "кравец"]),
    ("focus", ["focusstudio"]),
    ("pifagor", ["пифагор"]),
    ("nevafilm", ["невафильм"]),
    ("uateam", ["uateam"]),
    ("nezupyniai", ["незупиняйпродакшн"]),
    ("ams", ["ams"]),
    ("fox", ["fox"]),
    ("omskbird", ["omskbird"]),
    ("novafilm", ["novafilm"]),
    ("rentv", ["рен-тв", "рен тв"])
]

private func canonicalStudioIds(in text: String) -> Set<String> {
    let lower = text.lowercased()
    var matched = Set<String>()
    for group in studioAliasGroups {
        for alias in group.aliases {
            let escaped = NSRegularExpression.escapedPattern(for: alias)
            if let regex = try? NSRegularExpression(pattern: "(?i)(?:^|[^a-zа-яё0-9])\(escaped)(?:$|[^a-zа-яё0-9])"),
               regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)) != nil {
                matched.insert(group.canonical)
                break
            }
        }
    }
    return matched
}

private func distinctiveTranslationTokens(in text: String) -> [String] {
    text.lowercased()
        .replacingOccurrences(of: "ё", with: "е")
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { $0.count >= 4 && !isTranslationNoiseWord($0) }
}

func allohaTranslationNamesMatch(_ lhs: String?, _ rhs: String?, exactOnly: Bool = false) -> Bool {
    guard let lhsRaw = lhs?.trimmingCharacters(in: .whitespacesAndNewlines), !lhsRaw.isEmpty,
          let rhsRaw = rhs?.trimmingCharacters(in: .whitespacesAndNewlines), !rhsRaw.isEmpty else {
        return false
    }

    let left = normalizedAllohaTranslationName(lhsRaw).lowercased().replacingOccurrences(of: "ё", with: "е")
    let right = normalizedAllohaTranslationName(rhsRaw).lowercased().replacingOccurrences(of: "ё", with: "е")

    // Subtitles must never match audio voiceovers
    let leftIsSub = left.contains("субтитр") || left.contains("subtitle")
    let rightIsSub = right.contains("субтитр") || right.contains("subtitle")
    if leftIsSub != rightIsSub {
        return false
    }

    if left == right {
        return true
    }

    let leftStudios = canonicalStudioIds(in: left)
    let rightStudios = canonicalStudioIds(in: right)

    // Strict language mismatch check on raw strings
    let langLeft = detectLanguageTag(in: lhsRaw)
    let langRight = detectLanguageTag(in: rhsRaw)

    if let langLeft, langLeft != "rus", langRight != langLeft {
        return false
    }
    if let langRight, langRight != "rus", langLeft != langRight {
        return false
    }
    if let langLeft, let langRight, langLeft != langRight {
        return false
    }

    if exactOnly {
        return false
    }

    // Both mention distinct studios: require canonical alias intersection (e.g. RHS == Red Head Sound, Novamedia != Amedia)
    if !leftStudios.isEmpty && !rightStudios.isEmpty {
        if leftStudios.isDisjoint(with: rightStudios) {
            return false
        }
        if left.contains("дубл") != right.contains("дубл") {
            return false
        }
        return true
    }

    if leftStudios.isEmpty != rightStudios.isEmpty {
        return false
    }

    // Generic same non-Russian regional language (only when no competing studio names exist)
    if let langLeft, let langRight, langLeft == langRight && langLeft != "rus" {
        let leftWords = Set(distinctiveTranslationTokens(in: left))
        let rightWords = Set(distinctiveTranslationTokens(in: right))
        if leftWords.isEmpty || rightWords.isEmpty {
            return true
        }
        return !leftWords.isDisjoint(with: rightWords)
    }

    let isOriginalOrEnglish: (String) -> Bool = { name in
        isOriginalOrEnglishTranslation(name)
    }
    if isOriginalOrEnglish(left) && isOriginalOrEnglish(right) {
        return true
    }

    // Handle Dubbing vs Voiceover
    let leftHasDub = left.contains("дубл")
    let rightHasDub = right.contains("дубл")
    if leftHasDub && rightHasDub {
        if let langLeft, let langRight {
            return langLeft == langRight
        }
        return true
    }

    // Generic Russian track label ("Russian", "Русский", "ru", "rus") matches generic Russian dubbing only
    let isGenericRussian: (String) -> Bool = { name in
        let n = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return n == "русский" || n == "russian" || n == "rus" || n == "ru" || n == "рус" || n == "русская"
    }
    let isGenericRussianDub: (String) -> Bool = { name in
        let n = name.lowercased()
        return (n.contains("дубл") || n.contains("дуб") || n.contains("полное дублирование")) && !n.contains("укр")
    }
    if (isGenericRussian(left) && isGenericRussianDub(right)) ||
       (isGenericRussian(right) && isGenericRussianDub(left)) {
        return true
    }

    let leftWords = Set(distinctiveTranslationTokens(in: left))
    let rightWords = Set(distinctiveTranslationTokens(in: right))
    if !leftWords.isEmpty && !rightWords.isEmpty {
        return !leftWords.isDisjoint(with: rightWords)
    }

    return false
}

/// Находит наиболее подходящий вариант аудиодорожки из audioVariants для заданной целевой озвучки
func findMatchingAudioVariant(
    in audioVariants: [[String: Any]],
    for targetVoice: String?,
    isDedicatedIframe: Bool = false
) -> [String: Any]? {
    guard !audioVariants.isEmpty else { return nil }
    guard let target = targetVoice?.trimmingCharacters(in: .whitespacesAndNewlines), !target.isEmpty else {
        if let rus = audioVariants.first(where: {
            guard let url = $0["url"] as? String, !url.isEmpty else { return false }
            return isRussianTranslation($0["title"] as? String)
        }) {
            return rus
        }
        return audioVariants.first(where: { (($0["url"] as? String) ?? "").isEmpty == false })
    }

    // 1. Exact match by title
    if let match = audioVariants.first(where: { allohaTranslationNamesMatch($0["title"] as? String, target, exactOnly: true) }) {
        return match
    }

    // 2. Fuzzy / studio alias match
    if let match = audioVariants.first(where: { allohaTranslationNamesMatch($0["title"] as? String, target, exactOnly: false) }) {
        return match
    }

    // 3. Whole-word author/studio token match before generic language fallback
    let targetWords = Set(distinctiveTranslationTokens(in: target))
    if !targetWords.isEmpty {
        if let match = audioVariants.first(where: {
            let title = ($0["title"] as? String) ?? ""
            return !targetWords.isDisjoint(with: Set(distinctiveTranslationTokens(in: title)))
        }) {
            return match
        }
    }

    // 4. Language tag match only when target does not ask for a specific studio missing from variants
    let targetStudios = canonicalStudioIds(in: target)
    if targetStudios.isEmpty, let targetLang = detectLanguageTag(in: target) {
        if let match = audioVariants.first(where: {
            guard let title = $0["title"] as? String else { return false }
            return detectLanguageTag(in: title) == targetLang
        }) {
            return match
        }
    }

    if isDedicatedIframe {
        return nil
    }

    let targetClean = normalizedAllohaTranslationName(target).lowercased()
    let isGenericTarget = targetClean.isEmpty || targetClean == "дубляж" || targetClean == "русский" || targetClean == "многоголосый"
    let targetIsRussian = isRussianTranslation(target)
    let targetIsOriginal = isOriginalOrEnglishTranslation(target)

    if isGenericTarget && targetIsRussian && audioVariants.count > 1 {
        if let rusVariant = audioVariants.first(where: {
            let t = ($0["title"] as? String) ?? ""
            return isRussianTranslation(t)
        }) {
            return rusVariant
        }
        let v0Title = (audioVariants[0]["title"] as? String) ?? ""
        if isOriginalOrEnglishTranslation(v0Title) {
            return audioVariants[1]
        }
    } else if targetIsOriginal && audioVariants.count > 1 {
        if let engVariant = audioVariants.first(where: {
            let t = ($0["title"] as? String) ?? ""
            return isOriginalOrEnglishTranslation(t)
        }) {
            return engVariant
        }
    }

    return nil
}

/// Выбирает наиболее подходящую озвучку для пользователя, отдавая строгий приоритет
/// русскому дубляжу перед оригиналом, если пользователь явно не выбрал оригинал.
func bestTranslation(in translations: [AllohaTranslation], preferredName: String?) -> AllohaTranslation? {
    guard !translations.isEmpty else { return nil }

    if let preferredName, !preferredName.isEmpty,
       let match = translations.first(where: { allohaTranslationNamesMatch($0.name, preferredName, exactOnly: true) }) {
        return match
    }

    if let preferredName, !preferredName.isEmpty,
       let match = translations.first(where: { allohaTranslationNamesMatch($0.name, preferredName, exactOnly: false) }) {
        return match
    }

    if let global = UserDefaults.standard.string(forKey: "alloha_last_translation_name"),
       !isOriginalOrEnglishTranslation(global),
       let match = translations.first(where: { allohaTranslationNamesMatch($0.name, global, exactOnly: false) }) {
        return match
    }

    if let dubMatch = translations.first(where: {
        let n = $0.name.lowercased()
        let tag = detectLanguageTag(in: $0.name)
        return (n.contains("дубл") || n.contains("дуб") || n.contains("полное дублирование")) &&
               (tag == nil || tag == "rus") &&
               !isOriginalOrEnglishTranslation($0.name)
    }) {
        return dubMatch
    }

    let topStudios = ["пифагор", "невафильм", "red head sound", "rhs", "flarrow"]
    if let studioMatch = translations.first(where: { t in
        let n = t.name.lowercased()
        return topStudios.contains(where: { n.contains($0) }) && isRussianTranslation(t.name)
    }) {
        return studioMatch
    }

    let proKeywords = ["профессиональн", "проф", "многоголос", "hdrezka", "lostfilm", "кубик в кубе"]
    if let proMatch = translations.first(where: { t in
        let n = t.name.lowercased()
        return proKeywords.contains(where: { n.contains($0) }) && isRussianTranslation(t.name)
    }) {
        return proMatch
    }

    if let anyRus = translations.first(where: { isRussianTranslation($0.name) }) {
        return anyRus
    }

    return translations.first
}
