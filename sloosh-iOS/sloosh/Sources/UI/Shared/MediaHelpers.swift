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

// MARK: - Cartoon Detection

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

// MARK: - Translation Name Sanitization

/// Очищает и красиво форматирует названия озвучек (убирает тех. релиз-теги типа INTERNAL2160pWEB-DL, динамически извлекает язык и флаг)
func cleanTranslationName(_ rawName: String) -> String {
    var name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { return "По умолчанию" }
    
    // 1. Убираем громоздкие сцен-теги релиза (2160p, WEB-DL, BDRip и т.д.)
    if let regex = try? NSRegularExpression(pattern: "(?i)[a-z0-9._-]{3,}(?:2160p|1080p|720p|480p|internal|web-dl|web-dlrip|bdrip|bluray|hdr10|hdr|dv|hevc|x264|x265|spacehd\\d*)[a-z0-9._-]*", options: []) {
        let range = NSRange(location: 0, length: name.utf16.count)
        name = regex.stringByReplacingMatches(in: name, options: [], range: range, withTemplate: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // 1b. Убираем аудио-кодеки, каналы и битрейты (DD 51 @ 448 kbps, AC3 5.1 @ 640 kbps, AAC 2.0 и т.д.)
    name = name.replacingOccurrences(of: "(?i)\\b(?:AC3|E-AC3|EAC3|DDP|DD|DTS-HD|DTS|TrueHD|AAC|FLAC|MP3|PCM|LPCM)\\s*(?:5[.]?1|7[.]?1|2[.]?0|51)?(?:\\s*@\\s*\\d+\\s*(?:kbps|kbit|кбит/с|кб/с)?)?", with: "", options: .regularExpression)
    name = name.replacingOccurrences(of: "(?i)@\\s*\\d+\\s*(?:kbps|kbit|кбит/с|кб/с)?", with: "", options: .regularExpression)
    name = name.replacingOccurrences(of: "(?i)\\b\\d+\\s*(?:kbps|kbit|кбит/с|кб/с)\\b", with: "", options: .regularExpression)
    name = name.replacingOccurrences(of: "(?i)\\b(?:Blu-ray(?:\\s*CEE)?|BDRip|WEB-DL|HDTV|Line)\\b", with: "", options: .regularExpression)
    name = name.replacingOccurrences(of: "(?i)\\b(?:5[.]?1|7[.]?1|2[.]?0)\\b", with: "", options: .regularExpression)
    
    // 2. Субтитры
    if name.localizedCaseInsensitiveContains("субтитр") || name.localizedCaseInsensitiveContains("subtitle") {
        return "💬 \(name)"
    }
    
    // 3. Динамическое извлечение языка из тегов вида (Russian), (English), [Ukrainian] или префиксов
    struct LangInfo {
        let flag: String
        let defaultName: String
        let patterns: [String]
    }
    
    let knownLanguages: [LangInfo] = [
        LangInfo(flag: "🇷🇺", defaultName: "Русский", patterns: ["russian", "русский", "рус", "ru"]),
        LangInfo(flag: "🇺🇸", defaultName: "Оригинал", patterns: ["original", "оригинальный", "оригинал", "english", "английский", "англ", "eng", "usa", "en"]),
        LangInfo(flag: "🇺🇦", defaultName: "Украинский", patterns: ["ukrainian", "украинский", "укр", "ukr", "uk"]),
        LangInfo(flag: "🇯🇵", defaultName: "Японский", patterns: ["japanese", "японский", "япон", "jap", "ja"]),
        LangInfo(flag: "🇰🇷", defaultName: "Корейский", patterns: ["korean", "корейский", "корей", "kor", "ko"]),
        LangInfo(flag: "🇨🇳", defaultName: "Китайский", patterns: ["chinese", "китайский", "китай", "chi", "zh"]),
        LangInfo(flag: "🇰🇿", defaultName: "Казахский", patterns: ["kazakh", "казахский", "казах", "kaz", "kz"]),
        LangInfo(flag: "🇬🇪", defaultName: "Грузинский", patterns: ["georgian", "грузинский", "грузин", "geo", "ka"]),
        LangInfo(flag: "🇫🇷", defaultName: "Французский", patterns: ["french", "французский", "француз", "fra", "fr"]),
        LangInfo(flag: "🇩🇪", defaultName: "Немецкий", patterns: ["german", "немецкий", "немец", "ger", "de"]),
        LangInfo(flag: "🇪🇸", defaultName: "Испанский", patterns: ["spanish", "испанский", "испан", "spa", "es"]),
        LangInfo(flag: "🇮🇹", defaultName: "Итальянский", patterns: ["italian", "итальянский", "итальян", "ita", "it"]),
        LangInfo(flag: "🇹🇷", defaultName: "Турецкий", patterns: ["turkish", "турецкий", "турец", "tur", "tr"])
    ]
    
    var detectedFlag: String?
    var detectedDefaultName: String = "Русский"
    var cleanRemainder = name
    
    // Ищем соответствие языку
    for lang in knownLanguages {
        for pattern in lang.patterns {
            // Проверяем формат (Language) или [Language]
            let parenPattern = "(?i)[\\(\\[]\\s*\(pattern)\\s*[\\)\\]]"
            if let regex = try? NSRegularExpression(pattern: parenPattern, options: []) {
                let range = NSRange(location: 0, length: cleanRemainder.utf16.count)
                if regex.firstMatch(in: cleanRemainder, options: [], range: range) != nil {
                    detectedFlag = lang.flag
                    detectedDefaultName = lang.defaultName
                    cleanRemainder = regex.stringByReplacingMatches(in: cleanRemainder, options: [], range: range, withTemplate: " ")
                    break
                }
            }
            
            // Проверяем формат в начале строки "Language: ..." или "Language ..."
            let prefixPattern = "(?i)^\(pattern)[:\\s-]+"
            if let regex = try? NSRegularExpression(pattern: prefixPattern, options: []) {
                let range = NSRange(location: 0, length: cleanRemainder.utf16.count)
                if regex.firstMatch(in: cleanRemainder, options: [], range: range) != nil {
                    detectedFlag = lang.flag
                    detectedDefaultName = lang.defaultName
                    cleanRemainder = regex.stringByReplacingMatches(in: cleanRemainder, options: [], range: range, withTemplate: " ")
                    break
                }
            }
            
            // Если вся строка это просто название языка (например "English", "Оригинальный")
            if cleanRemainder.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == pattern {
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
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    
    // Очищаем тире и префиксы вида "Многоголосый - " при наличии названия студии
    cleanRemainder = cleanRemainder
        .replacingOccurrences(of: "\\s*[–—-]\\s*", with: " - ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)

    if let dashRange = cleanRemainder.range(of: " - ") {
        let prefix = String(cleanRemainder[..<dashRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        let suffix = String(cleanRemainder[dashRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        let lowerPrefix = prefix.lowercased()
        if lowerPrefix.contains("многоголос") || lowerPrefix.contains("дубл") || lowerPrefix.contains("двухголос") || lowerPrefix.contains("закадр") || lowerPrefix.contains("проф") || lowerPrefix.contains("люб") {
            if !suffix.isEmpty {
                cleanRemainder = suffix
            }
        }
    } else {
        let prefixPattern = "(?i)^(?:профессиональный\\s+|проф[.]\\s+|любительский\\s+|люб[.]\\s+)?(?:многоголосый|двухголосый|одноголосый|закадровый|дублированный|дубляж)[:\\s-]+(.+)$"
        if let regex = try? NSRegularExpression(pattern: prefixPattern, options: []) {
            let range = NSRange(location: 0, length: cleanRemainder.utf16.count)
            if let match = regex.firstMatch(in: cleanRemainder, options: [], range: range),
               let groupRange = Range(match.range(at: 1), in: cleanRemainder) {
                let studioPart = String(cleanRemainder[groupRange]).trimmingCharacters(in: .whitespaces)
                if !studioPart.isEmpty {
                    cleanRemainder = studioPart
                }
            }
        }
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



/// Возвращает уникальное понятное название для озвучки с учётом её индекса в общем списке
func displayTranslationName(_ rawName: String, at indexInAll: Int, in allRawNames: [String]) -> String {
    let cleaned = cleanTranslationName(rawName)
    
    // Посчитаем, сколько раз данное очищенное название встречается во ВСЁМ списке
    let totalDuplicates = allRawNames.filter { cleanTranslationName($0) == cleaned }.count
    
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
