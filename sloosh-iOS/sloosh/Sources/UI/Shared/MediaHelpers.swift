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

/// Очищает и красиво форматирует названия озвучек (убирает тех. релиз-теги типа INTERNAL2160pWEB-DL, добавляет флаги стран)
func cleanTranslationName(_ rawName: String) -> String {
    var name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { return "🇷🇺 По умолчанию" }
    
    // Если уже начинается с эмодзи-флага, возвращаем как есть
    if name.unicodeScalars.first?.properties.isEmoji == true && name.count > 2 {
        return name
    }
    
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
    
    // 3. Распознавание нерусских языков и назначение флагов
    let nonRussianLanguages: [(keywords: [String], flag: String, defaultName: String)] = [
        (["english", "английский", "original", "оригинал", "eng", "usa"], "🇺🇸", "Английский"),
        (["ukrainian", "украинский", "укр", "ukr"], "🇺🇦", "Украинский"),
        (["kazakh", "казахский", "каз", "kz"], "🇰🇿", "Казахский"),
        (["georgian", "грузинский", "груз"], "🇬🇪", "Грузинский"),
        (["japanese", "японский", "яп"], "🇯🇵", "Японский"),
        (["korean", "корейский", "кор"], "🇰🇷", "Корейский"),
        (["chinese", "китайский", "кит"], "🇨🇳", "Китайский"),
        (["french", "французский", "фр"], "🇫🇷", "Французский"),
        (["german", "немецкий", "нем"], "🇩🇪", "Немецкий"),
        (["spanish", "испанский", "исп"], "🇪🇸", "Испанский"),
        (["italian", "итальянский", "ит"], "🇮🇹", "Итальянский"),
        (["turkish", "турецкий", "тур"], "🇹🇷", "Турецкий")
    ]
    
    for item in nonRussianLanguages {
        for kw in item.keywords {
            if lower == kw || lower.hasPrefix(kw + " ") || lower.contains(" " + kw) {
                if lower == kw || lower == "оригинал" || lower == "original" || lower == "english" || lower == "английский" {
                    return "\(item.flag) \(item.defaultName)"
                }
                let cleanWithoutPrefix = name.replacingOccurrences(of: "(?i)^" + kw + "\\s*", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
                let finalTitle = cleanWithoutPrefix.isEmpty ? item.defaultName : cleanWithoutPrefix
                return "\(item.flag) \(finalTitle)"
            }
        }
    }
    
    // 4. Для всех русских озвучек (Дубляж, HDRezka, Red Head Sound, LostFilm, Многоголосый и т.д.) добавляем флаг РФ 🇷🇺
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
