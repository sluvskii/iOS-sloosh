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
}

// MARK: - Cartoon Detection

/// Определяет, является ли медиа мультфильмом/анимацией по жанрам и названию.
func isCartoon(_ item: MediaDto) -> Bool {
    let genreIds = item.genres?.compactMap { $0.id?.lowercased() } ?? []
    let genreNames = item.genres?.compactMap { $0.name?.lowercased() } ?? []
    
    // Strict checking against API genres to prevent false positives (like "Мультиверс" movie)
    return genreIds.contains("мультфильм") || genreIds.contains("аниме") ||
           genreNames.contains("мультфильм") || genreNames.contains("аниме")
}

/// Облегчённая версия для случаев, когда жанры недоступны (например, FavoriteDto).
func isCartoonByTitle(_ title: String?) -> Bool {
    guard let t = title?.lowercased() else { return false }
    // More strict checking by splitting words to avoid "мультиверс" triggering
    let words = t.components(separatedBy: .punctuationCharacters.union(.whitespaces))
    return words.contains("мультфильм") || words.contains("мультфильмы") || words.contains("аниме")
}

// MARK: - Translation Name Sanitization

/// Очищает и красиво форматирует названия озвучек (убирает тех. релиз-теги типа INTERNAL2160pWEB-DL, переводит языковые имена)
func cleanTranslationName(_ rawName: String) -> String {
    var name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { return "По умолчанию" }
    
    // 1. Убираем громоздкие сцен-теги релиза
    if let regex = try? NSRegularExpression(pattern: "(?i)[a-z0-9._-]{3,}(?:2160p|1080p|720p|480p|internal|web-dl|web-dlrip|bdrip|bluray|hdr10|hdr|dv|hevc|x264|x265|spacehd\\d*)[a-z0-9._-]*", options: []) {
        let range = NSRange(location: 0, length: name.utf16.count)
        name = regex.stringByReplacingMatches(in: name, options: [], range: range, withTemplate: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // 2. Нормализуем скобки и трубы в чистые пробелы для аккуратного разбора
    name = name
        .replacingOccurrences(of: "(", with: " ")
        .replacingOccurrences(of: ")", with: " ")
        .replacingOccurrences(of: "[", with: " ")
        .replacingOccurrences(of: "]", with: " ")
        .replacingOccurrences(of: "|", with: " ")
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    
    if name.isEmpty {
        name = rawName.components(separatedBy: " ").first ?? rawName
    }
    
    let lower = name.lowercased()
    
    // 3. Распознавание конкретных иностранных языков (включая оригиналы аниме, дорам и европейского кино)
    if lower.contains("japanese") || lower.contains("япон") || lower == "jap" || lower == "яп" {
        let clean = name.replacingOccurrences(of: "(?i)^(japanese|японский|яп|jap)\\s*", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "🇯🇵 Японский" : "🇯🇵 \(clean)"
    }
    if lower.contains("korean") || lower.contains("корей") || lower == "kor" || lower == "кор" {
        let clean = name.replacingOccurrences(of: "(?i)^(korean|корейский|кор|kor)\\s*", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "🇰🇷 Корейский" : "🇰🇷 \(clean)"
    }
    if lower.contains("chinese") || lower.contains("китай") || lower == "chi" || lower == "кит" {
        let clean = name.replacingOccurrences(of: "(?i)^(chinese|китайский|кит|chi)\\s*", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "🇨🇳 Китайский" : "🇨🇳 \(clean)"
    }
    if lower.contains("ukrainian") || lower.contains("украин") || lower == "укр" || lower == "ukr" {
        let clean = name.replacingOccurrences(of: "(?i)^(ukrainian|украинский|укр|ukr)\\s*", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "🇺🇦 Украинский" : "🇺🇦 \(clean)"
    }
    if lower.contains("kazakh") || lower.contains("казах") || lower == "каз" || lower == "kz" {
        let clean = name.replacingOccurrences(of: "(?i)^(kazakh|казахский|каз|kz)\\s*", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "🇰🇿 Казахский" : "🇰🇿 \(clean)"
    }
    if lower.contains("georgian") || lower.contains("грузин") || lower == "geo" {
        let clean = name.replacingOccurrences(of: "(?i)^(georgian|грузинский|geo)\\s*", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "🇬🇪 Грузинский" : "🇬🇪 \(clean)"
    }
    if lower.contains("french") || lower.contains("француз") || lower == "fra" || lower == "фр" {
        let clean = name.replacingOccurrences(of: "(?i)^(french|французский|фр|fra)\\s*", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "🇫🇷 Французский" : "🇫🇷 \(clean)"
    }
    if lower.contains("german") || lower.contains("немец") || lower == "ger" || lower == "нем" {
        let clean = name.replacingOccurrences(of: "(?i)^(german|немецкий|нем|ger)\\s*", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "🇩🇪 Немецкий" : "🇩🇪 \(clean)"
    }
    if lower.contains("spanish") || lower.contains("испан") || lower == "spa" || lower == "исп" {
        let clean = name.replacingOccurrences(of: "(?i)^(spanish|испанский|исп|spa)\\s*", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "🇪🇸 Испанский" : "🇪🇸 \(clean)"
    }
    if lower.contains("italian") || lower.contains("итальян") || lower == "ita" || lower == "ит" {
        let clean = name.replacingOccurrences(of: "(?i)^(italian|итальянский|ит|ita)\\s*", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "🇮🇹 Итальянский" : "🇮🇹 \(clean)"
    }
    if lower.contains("turkish") || lower.contains("турец") || lower == "tur" || lower == "тур" {
        let clean = name.replacingOccurrences(of: "(?i)^(turkish|турецкий|тур|tur)\\s*", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "🇹🇷 Турецкий" : "🇹🇷 \(clean)"
    }
    
    // 4. Английский / Оригинал (Original, Оригинал, English, Английский, ENG, USA, UK)
    if lower.contains("original") || lower.contains("оригинал") || lower.contains("english") || lower.contains("английск") || lower == "eng" || lower == "usa" || lower.hasPrefix("eng ") || lower.hasSuffix(" eng") || lower.contains(" eng ") {
        if lower.contains("english") || lower.contains("английск") {
            let clean = name.replacingOccurrences(of: "(?i)^(english|английский)\\s*", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
            return clean.isEmpty ? "🇺🇸 Английский" : "🇺🇸 \(clean)"
        }
        let clean = name.replacingOccurrences(of: "(?i)^(original|оригинал|оригинальная дорожка|eng|usa)\\s*", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "🇺🇸 Оригинал" : "🇺🇸 \(clean)"
    }
    
    // 5. Субтитры
    if lower.contains("субтитр") || lower.contains("subtitle") {
        return "💬 \(name)"
    }
    
    // 6. Для всех русских озвучек и студий (Дубляж, HDrezka, Red Head Sound, AlexFilm, LostFilm, Кубик в Кубе, Flarrow Films, TVShows, NewComers, Newstudio и т.д.)
    var cleanRus = name
    for rusPrefix in ["Russian", "Русский", "русский", "russian", "RU", "ru"] {
        if cleanRus.hasPrefix(rusPrefix) {
            cleanRus = cleanRus.dropFirst(rusPrefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    if cleanRus.isEmpty {
        cleanRus = "Русский"
    }
    
    return "🇷🇺 \(cleanRus)"
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
