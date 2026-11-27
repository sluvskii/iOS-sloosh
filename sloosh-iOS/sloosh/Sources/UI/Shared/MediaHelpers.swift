import SwiftUI

// MARK: - Rating Color

extension Color {
    /// Цвет рейтинга: зелёный ≥7.5, серый 5–7.5, красный <5.
    static func rating(_ value: Double) -> Color {
        switch value {
        case 7.5...10.0: return Color(red: 0.12, green: 0.73, blue: 0.30)
        case 5.0..<7.5:  return Color(red: 0.50, green: 0.55, blue: 0.60)
        case 0.1..<5.0:  return Color(red: 0.90, green: 0.18, blue: 0.18)
        default:         return Color(red: 0.50, green: 0.55, blue: 0.60)
        }
    }

    /// Цвет возрастного ограничения (ГОСТ / РФ классификация):
    /// 18+ — красный, 16+ — оранжевый, 12+ — янтарный/жёлтый, 6+ — синий/голубой, 0+ — зелёный.
    static func ageRating(_ rating: String) -> Color {
        let clean = rating.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if clean.contains("18") || clean == "r" || clean == "nc-17" {
            return Color(red: 0.95, green: 0.24, blue: 0.24) // Красный (18+)
        } else if clean.contains("16") || clean == "tv-ma" {
            return Color(red: 1.0, green: 0.55, blue: 0.0)   // Оранжевый (16+)
        } else if clean.contains("12") || clean == "pg-13" || clean == "tv-14" {
            return Color(red: 1.0, green: 0.76, blue: 0.03)  // Янтарный/Жёлтый (12+)
        } else if clean.contains("6") || clean == "pg" || clean == "tv-pg" {
            return Color(red: 0.15, green: 0.60, blue: 0.98)  // Синий/Голубой (6+)
        } else if clean.contains("0") || clean == "g" || clean == "tv-g" || clean == "tv-y" {
            return Color(red: 0.18, green: 0.80, blue: 0.44)  // Зелёный (0+)
        }
        return .secondary
    }
}

// MARK: - Anime & Cartoon Detection

/// Определяет, является ли медиа аниме (японская анимация).
func isAnime(_ item: MediaDto) -> Bool {
    let genreIds = item.genres?.compactMap { $0.id?.lowercased() } ?? []
    let genreNames = item.genres?.compactMap { $0.name?.lowercased() } ?? []
    
    if genreIds.contains("anime") || genreIds.contains("аниме") ||
       genreNames.contains("аниме") || genreNames.contains("anime") {
        return true
    }
    
    let countries = item.countries?.compactMap { $0.lowercased() } ?? []
    let isJapan = countries.contains { c in
        c.contains("япония") || c.contains("japan") || c.contains("jp")
    }
    
    let hasAnimation = genreIds.contains("16") || genreIds.contains("мультфильм") ||
                       genreNames.contains("мультфильм") || genreNames.contains("animation")
    return hasAnimation && isJapan
}

/// Облегчённая версия определения аниме по названию.
func isAnimeByTitle(_ title: String?) -> Bool {
    guard let t = title?.lowercased() else { return false }
    let words = t.components(separatedBy: .punctuationCharacters.union(.whitespaces))
    return words.contains("аниме") || words.contains("anime")
}

/// Определяет, является ли медиа мультфильмом/анимацией по жанрам и названию.
func isCartoon(_ item: MediaDto) -> Bool {
    let genreIds = item.genres?.compactMap { $0.id?.lowercased() } ?? []
    let genreNames = item.genres?.compactMap { $0.name?.lowercased() } ?? []
    
    // Strict checking against API genres to prevent false positives (like "Мультиверс" movie)
    return genreIds.contains("16") || genreIds.contains("мультфильм") || genreIds.contains("аниме") ||
           genreNames.contains("мультфильм") || genreNames.contains("аниме") || genreNames.contains("animation")
}

/// Облегчённая версия для случаев, когда жанры недоступны (например, FavoriteDto).
func isCartoonByTitle(_ title: String?) -> Bool {
    guard let t = title?.lowercased() else { return false }
    // More strict checking by splitting words to avoid "мультиверс" triggering
    let words = t.components(separatedBy: .punctuationCharacters.union(.whitespaces))
    return words.contains("мультфильм") || words.contains("мультфильмы") || words.contains("аниме")
}

// MARK: - TV Talk Show & Reality Detection

/// Определяет, является ли медиа развлекательным ТВ-шоу, ток-шоу, интервью, новостями или реалити-шоу.
/// Используется для фильтрации каталога сериалов и фильмографии актёров,
/// сохраняя при этом полную доступность таких шоу через глобальный поиск.
func isTalkShowOrReality(_ item: MediaDto) -> Bool {
    // 1. Проверка по TMDB Genre ID:
    // 10767 = Talk (Ток-шоу), 10763 = News (Новости), 10764 = Reality (Реалити-шоу)
    let genreIds = item.genres?.compactMap { $0.id?.lowercased() } ?? []
    if genreIds.contains("10767") || genreIds.contains("10763") || genreIds.contains("10764") {
        return true
    }

    // 2. Проверка по наименованиям жанров (RU / EN)
    let genreNames = item.genres?.compactMap { $0.name?.lowercased() } ?? []
    for name in genreNames {
        if name.contains("ток-шоу") || name.contains("talk") ||
           name.contains("реалити") || name.contains("reality") ||
           name.contains("новости") || name.contains("news") ||
           name.contains("телешоу") || name.contains("тв-шоу") ||
           name.contains("тв шоу") || name.contains("интервью") ||
           name.contains("interview") {
            return true
        }
    }

    // 3. Проверка по названию тайтла (известные разговорные / вечерние шоу / интервью / награды)
    let title = (item.title ?? item.name ?? item.originalTitle ?? "").lowercased()
    return isTalkShowOrRealityByTitle(title)
}

/// Проверка названия на принадлежность к разговорным шоу, интервью и реалити-форматам.
func isTalkShowOrRealityByTitle(_ rawTitle: String?) -> Bool {
    guard let title = rawTitle?.lowercased(), !title.isEmpty else { return false }

    let talkPatterns = [
        "the tonight show",
        "jimmy kimmel live",
        "the late late show",
        "the late show with",
        "late night with",
        "the graham norton show",
        "the daily show",
        "the ellen degeneres show",
        "the kelly clarkson show",
        "the drew barrymore show",
        "last week tonight",
        "saturday night live",
        "good morning america",
        "entertainment tonight",
        "inside the actors studio",
        "hot ones",
        "73 questions",
        "actors on actors",
        "вечерний ургант",
        "шоу воли",
        "вдудь",
        "осторожно: собчак",
        "алена, блин",
        "алёна, блин",
        "что было дальше",
        "comedy club",
        "камеди клаб",
        "голубой огонёк",
        "голубой огонек",
        "песня года",
        "пусть говорят",
        "прямой эфир",
        "мужское / женское",
        "давай поженимся",
        "битва экстрасенсов",
        "пацанки",
        "выжить в дубае",
        "звёзды в африке",
        "academy awards",
        "golden globe awards",
        "emmy awards",
        "grammy awards",
        "премия муз-тв",
        "премия muz-tv"
    ]

    for pattern in talkPatterns {
        if title.contains(pattern) {
            return true
        }
    }

    return false
}

// MARK: - Translation Name Sanitization

private final class TranslationNameCache: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: String] = [:]
    private let maxCount = 2048

    func value(for key: String, compute: () -> String) -> String {
        lock.lock()
        if let cached = storage[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let result = compute()
        lock.lock()
        if storage.count >= maxCount {
            storage.removeAll(keepingCapacity: true)
        }
        storage[key] = result
        lock.unlock()
        return result
    }
}

private enum TranslationCleaner {
    struct CompiledLangMatcher {
        let flag: String
        let defaultName: String
        let patterns: [(raw: String, parenRegex: NSRegularExpression, prefixRegex: NSRegularExpression)]
    }

    static let cache = TranslationNameCache()

    static let releaseTagsRegex = try! NSRegularExpression(
        pattern: "(?i)[a-z0-9._-]{3,}(?:2160p|1080p|720p|480p|internal|web-dl|web-dlrip|bdrip|bluray|hdr10|hdr|dv|hevc|x264|x265|spacehd\\d*)[a-z0-9._-]*"
    )
    static let codecRegex = try! NSRegularExpression(
        pattern: "(?i)\\b(?:AC3|E-AC3|EAC3|DDP|DD|DTS-HD|DTS|TrueHD|AAC|FLAC|MP3|PCM|LPCM)\\s*(?:5[.]?1|7[.]?1|2[.]?0|51)?(?:\\s*@\\s*\\d+\\s*(?:kbps|kbit|кбит/с|кб/с)?)?"
    )
    static let atBitrateRegex = try! NSRegularExpression(
        pattern: "(?i)@\\s*\\d+\\s*(?:kbps|kbit|кбит/с|кб/с)?"
    )
    static let bitrateRegex = try! NSRegularExpression(
        pattern: "(?i)\\b\\d+\\s*(?:kbps|kbit|кбит/с|кб/с)\\b"
    )
    static let sourceTagRegex = try! NSRegularExpression(
        pattern: "(?i)\\b(?:Blu-ray(?:\\s*CEE)?|BDRip|WEB-DL|HDTV|Line)\\b"
    )
    static let channelsRegex = try! NSRegularExpression(
        pattern: "(?i)\\b(?:5[.]?1|7[.]?1|2[.]?0)\\b"
    )
    static let hdrezkaRegex = try! NSRegularExpression(
        pattern: "(?i)\\bHDrezka\\s+St(?:\\.|\\b)"
    )
    static let whitespaceRegex = try! NSRegularExpression(pattern: "\\s+")
    static let dashNormalizeRegex = try! NSRegularExpression(pattern: "\\s*[–—-]\\s*")
    static let dubPrefixRegex = try! NSRegularExpression(
        pattern: "(?i)^(?:профессиональный\\s+|проф[.]\\s+|полный\\s+)?(?:дублированный|дубляж)[:\\s-]+(.+)$"
    )
    static let voicePrefixRegex = try! NSRegularExpression(
        pattern: "(?i)^(?:профессиональный\\s+|проф[.]\\s+|любительский\\s+|люб[.]\\s+)?(?:многоголосый|двухголосый|одноголосый|закадровый)[:\\s-]+(.+)$"
    )

    static let compiledLanguages: [CompiledLangMatcher] = {
        let specs: [(flag: String, defaultName: String, patterns: [String])] = [
            ("🇷🇺", "Русский", ["russian", "русский", "рус", "ru"]),
            ("🇺🇸", "Оригинал", ["original", "оригинальный", "оригинал", "english", "английский", "англ", "eng", "usa", "en"]),
            ("🇺🇦", "Украинский", ["ukrainian", "украинский", "укр", "ukr", "uk"]),
            ("🇯🇵", "Японский", ["japanese", "японский", "япон", "jap", "ja"]),
            ("🇰🇷", "Корейский", ["korean", "корейский", "корей", "kor", "ko"]),
            ("🇨🇳", "Китайский", ["chinese", "китайский", "китай", "chi", "zh"]),
            ("🇰🇿", "Казахский", ["kazakh", "казахский", "казах", "kaz", "kz"]),
            ("🇬🇪", "Грузинский", ["georgian", "грузинский", "грузин", "geo", "ka"]),
            ("🇫🇷", "Французский", ["french", "французский", "француз", "fra", "fr"]),
            ("🇩🇪", "Немецкий", ["german", "немецкий", "немец", "ger", "de"]),
            ("🇪🇸", "Испанский", ["spanish", "испанский", "испан", "spa", "es"]),
            ("🇮🇹", "Итальянский", ["italian", "итальянский", "итальян", "ita", "it"]),
            ("🇹🇷", "Турецкий", ["turkish", "турецкий", "турец", "tur", "tr"])
        ]
        return specs.compactMap { spec in
            let compiled = spec.patterns.compactMap { pattern -> (String, NSRegularExpression, NSRegularExpression)? in
                guard let paren = try? NSRegularExpression(pattern: "(?i)[\\(\\[]\\s*\(pattern)\\s*[\\)\\]]"),
                      let prefix = try? NSRegularExpression(pattern: "(?i)^\(pattern)[:\\s-]+") else {
                    return nil
                }
                return (pattern, paren, prefix)
            }
            return CompiledLangMatcher(flag: spec.flag, defaultName: spec.defaultName, patterns: compiled)
        }
    }()

    static func replacing(_ regex: NSRegularExpression, in string: String, with template: String) -> String {
        let range = NSRange(location: 0, length: string.utf16.count)
        return regex.stringByReplacingMatches(in: string, options: [], range: range, withTemplate: template)
    }
}

/// Очищает и красиво форматирует названия озвучек (убирает тех. релиз-теги типа INTERNAL2160pWEB-DL, динамически извлекает язык и флаг)
func cleanTranslationName(_ rawName: String) -> String {
    let trimmedInput = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedInput.isEmpty else { return "По умолчанию" }

    return TranslationCleaner.cache.value(for: trimmedInput) {
        var name = trimmedInput

        // 1. Убираем громоздкие сцен-теги релиза (2160p, WEB-DL, BDRip и т.д.)
        name = TranslationCleaner.replacing(TranslationCleaner.releaseTagsRegex, in: name, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // 1b. Убираем аудио-кодеки, каналы и битрейты (DD 51 @ 448 kbps, AC3 5.1 @ 640 kbps, AAC 2.0 и т.д.)
        name = TranslationCleaner.replacing(TranslationCleaner.codecRegex, in: name, with: "")
        name = TranslationCleaner.replacing(TranslationCleaner.atBitrateRegex, in: name, with: "")
        name = TranslationCleaner.replacing(TranslationCleaner.bitrateRegex, in: name, with: "")
        name = TranslationCleaner.replacing(TranslationCleaner.sourceTagRegex, in: name, with: "")
        name = TranslationCleaner.replacing(TranslationCleaner.channelsRegex, in: name, with: "")
        name = TranslationCleaner.replacing(TranslationCleaner.hdrezkaRegex, in: name, with: "HDrezka Studio")

        // 2. Субтитры
        if name.localizedCaseInsensitiveContains("субтитр") || name.localizedCaseInsensitiveContains("subtitle") {
            return "💬 \(name)"
        }

        // 3. Динамическое извлечение языка из тегов вида (Russian), (English), [Ukrainian] или префиксов
        var detectedFlag: String?
        var detectedDefaultName: String = "Русский"
        var cleanRemainder = name

        for lang in TranslationCleaner.compiledLanguages {
            for patternEntry in lang.patterns {
                let parenRange = NSRange(location: 0, length: cleanRemainder.utf16.count)
                if patternEntry.parenRegex.firstMatch(in: cleanRemainder, options: [], range: parenRange) != nil {
                    detectedFlag = lang.flag
                    detectedDefaultName = lang.defaultName
                    cleanRemainder = patternEntry.parenRegex.stringByReplacingMatches(in: cleanRemainder, options: [], range: parenRange, withTemplate: " ")
                    break
                }

                let prefixRange = NSRange(location: 0, length: cleanRemainder.utf16.count)
                if patternEntry.prefixRegex.firstMatch(in: cleanRemainder, options: [], range: prefixRange) != nil {
                    detectedFlag = lang.flag
                    detectedDefaultName = lang.defaultName
                    cleanRemainder = patternEntry.prefixRegex.stringByReplacingMatches(in: cleanRemainder, options: [], range: prefixRange, withTemplate: " ")
                    break
                }

                if cleanRemainder.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == patternEntry.raw {
                    detectedFlag = lang.flag
                    detectedDefaultName = lang.defaultName
                    cleanRemainder = ""
                    break
                }
            }
            if detectedFlag != nil { break }
        }

        // Очищаем оставшиеся скобки, спецсимволы и лишние пробелы
        cleanRemainder = cleanRemainder
            .replacingOccurrences(of: "(", with: " ")
            .replacingOccurrences(of: ")", with: " ")
            .replacingOccurrences(of: "[", with: " ")
            .replacingOccurrences(of: "]", with: " ")
            .replacingOccurrences(of: "|", with: " ")
        cleanRemainder = TranslationCleaner.replacing(TranslationCleaner.whitespaceRegex, in: cleanRemainder, with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Очищаем тире и префиксы вида "Многоголосый - " при наличии названия студии,
        // но сохраняем "Дубляж" если это дубляж!
        cleanRemainder = TranslationCleaner.replacing(TranslationCleaner.dashNormalizeRegex, in: cleanRemainder, with: " - ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let dashRange = cleanRemainder.range(of: " - ") {
            let prefix = String(cleanRemainder[..<dashRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            let suffix = String(cleanRemainder[dashRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            let lowerPrefix = prefix.lowercased()
            if lowerPrefix.contains("дубл") {
                cleanRemainder = suffix.isEmpty ? "Дубляж" : "Дубляж \(suffix)"
            } else if lowerPrefix.contains("многоголос") || lowerPrefix.contains("двухголос") || lowerPrefix.contains("закадр") || lowerPrefix.contains("проф") || lowerPrefix.contains("люб") {
                if !suffix.isEmpty {
                    cleanRemainder = suffix
                }
            }
        } else {
            let range = NSRange(location: 0, length: cleanRemainder.utf16.count)
            var matchedDub = false
            if let match = TranslationCleaner.dubPrefixRegex.firstMatch(in: cleanRemainder, options: [], range: range),
               let groupRange = Range(match.range(at: 1), in: cleanRemainder) {
                let studioPart = String(cleanRemainder[groupRange]).trimmingCharacters(in: .whitespaces)
                if !studioPart.isEmpty {
                    cleanRemainder = "Дубляж \(studioPart)"
                    matchedDub = true
                }
            }

            if !matchedDub,
               let match = TranslationCleaner.voicePrefixRegex.firstMatch(in: cleanRemainder, options: [], range: range),
               let groupRange = Range(match.range(at: 1), in: cleanRemainder) {
                let studioPart = String(cleanRemainder[groupRange]).trimmingCharacters(in: .whitespaces)
                if !studioPart.isEmpty {
                    cleanRemainder = studioPart
                }
            }
        }

        if cleanRemainder.lowercased() == "дублированный" {
            cleanRemainder = "Дубляж"
        }

        while cleanRemainder.hasPrefix("-") || cleanRemainder.hasPrefix(",") || cleanRemainder.hasPrefix("–") || cleanRemainder.hasPrefix("—") {
            cleanRemainder = String(cleanRemainder.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        while cleanRemainder.hasSuffix("-") || cleanRemainder.hasSuffix(",") || cleanRemainder.hasSuffix("–") || cleanRemainder.hasSuffix("—") {
            cleanRemainder = String(cleanRemainder.dropLast()).trimmingCharacters(in: .whitespaces)
        }

        let flag = detectedFlag ?? "🇷🇺"

        // Если осталась только цифра дорожки (например "(English) 8" -> "8") или строка пуста
        if cleanRemainder.isEmpty || Int(cleanRemainder) != nil {
            return "\(flag) \(detectedDefaultName)"
        }

        return "\(flag) \(cleanRemainder)"
    }
}

/// Возвращает уникальные понятные названия для всего списка озвучек за один O(N) проход
func displayTranslationNames(for allRawNames: [String]) -> [String] {
    guard !allRawNames.isEmpty else { return [] }
    let cleaned = allRawNames.map(cleanTranslationName)
    var totals: [String: Int] = [:]
    totals.reserveCapacity(cleaned.count)
    for name in cleaned {
        totals[name, default: 0] += 1
    }
    var seen: [String: Int] = [:]
    seen.reserveCapacity(totals.count)
    return cleaned.map { name in
        if (totals[name] ?? 0) > 1 {
            let next = (seen[name] ?? 0) + 1
            seen[name] = next
            return "\(name) #\(next)"
        }
        return name
    }
}

/// Возвращает уникальное понятное название для озвучки с учётом её индекса в общем списке
func displayTranslationName(_ rawName: String, at indexInAll: Int, in allRawNames: [String]) -> String {
    let cleaned = cleanTranslationName(rawName)

    // Посчитаем, сколько раз данное очищенное название встречается во ВСЁМ списке
    let totalDuplicates = allRawNames.reduce(into: 0) { count, item in
        if cleanTranslationName(item) == cleaned { count += 1 }
    }

    if totalDuplicates > 1 {
        // Посчитаем, каким по счёту является текущий элемент среди равных до индекса indexInAll включительно
        var occurrence = 0
        let maxIdx = max(0, min(indexInAll, allRawNames.count - 1))
        if maxIdx < allRawNames.count {
            for i in 0...maxIdx {
                if cleanTranslationName(allRawNames[i]) == cleaned {
                    occurrence += 1
                }
            }
        }
        return "\(cleaned) #\(occurrence)"
    }

    return cleaned
}
