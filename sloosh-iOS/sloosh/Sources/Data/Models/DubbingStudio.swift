import SwiftUI
import UIKit

/// Популярные российские студии озвучки и дубляжа.
/// Поддерживает автоматическое распознавание из сырых названий балансеров и отображение брендовых логотипов.
enum DubbingStudio: String, CaseIterable, Identifiable, Hashable {
    case redHeadSound = "rhs"
    case hdRezka = "hdrezka"
    case flarrowFilms = "flarrowfilms"
    case tvShows = "tvshows"
    case alexFilm = "alexfilm"
    case ruDub = "rudub"
    case coldFilm = "coldfilm"
    case lostFilm = "lostfilm"
    case kubikVKube = "kubik"
    case daronMoneyStudio = "dms"
    case jaskier = "jaskier"
    case newStudio = "newstudio"
    case leProduction = "leproduction"

    var id: String { rawValue }

    /// Каноническое отображаемое название студии
    var title: String {
        switch self {
        case .redHeadSound: return "Red Head Sound"
        case .hdRezka: return "HDRezka Studio"
        case .flarrowFilms: return "Flarrow Films"
        case .tvShows: return "TVShows"
        case .alexFilm: return "AlexFilm"
        case .ruDub: return "RuDub"
        case .coldFilm: return "ColdFilm"
        case .lostFilm: return "LostFilm"
        case .kubikVKube: return "Кубик в кубе"
        case .daronMoneyStudio: return "Dragon Money Studio"
        case .jaskier: return "Jaskier"
        case .newStudio: return "NewStudio"
        case .leProduction: return "LE-Production"
        }
    }

    /// Имя ассета в Assets.xcassets
    var assetName: String {
        switch self {
        case .redHeadSound: return "Studio-RHS"
        case .hdRezka: return "Studio-HDRezka"
        case .flarrowFilms: return "Studio-FlarrowFilms"
        case .tvShows: return "Studio-TVShows"
        case .alexFilm: return "Studio-AlexFilm"
        case .ruDub: return "Studio-RuDub"
        case .coldFilm: return "Studio-ColdFilm"
        case .lostFilm: return "Studio-LostFilm"
        case .kubikVKube: return "Studio-Kubik"
        case .daronMoneyStudio: return "Studio-DMS"
        case .jaskier: return "Studio-Jaskier"
        case .newStudio: return "Studio-NewStudio"
        case .leProduction: return "Studio-LE"
        }
    }

    /// Проверяет наличие файла логотипа в бандле приложения
    var hasAsset: Bool {
        UIImage(named: assetName) != nil
    }

    /// Ключевые слова и паттерны для обнаружения студии в названии дорожки
    var searchKeywords: [String] {
        switch self {
        case .redHeadSound:
            return ["red head sound", "redheadsound", "ред хед саунд", "редхед", "rhs", "рхс"]
        case .hdRezka:
            return ["hdrezka", "hd-rezka", "rezka", "хдрезка", "хд резка", "резка"]
        case .flarrowFilms:
            return ["flarrow films", "flarrowfilms", "flarrow", "флэрроу филмс", "флэрроу", "флероу"]
        case .tvShows:
            return ["tvshows", "tv shows", "tv-shows", "твшоус", "тв шоу", "твшоу"]
        case .alexFilm:
            return ["alexfilm", "alex film", "alex-film", "алексфильм", "алекс фильм", "alex"]
        case .ruDub:
            return ["rudub", "ru dub", "ru-dub", "рудаб", "ру даб"]
        case .coldFilm:
            return ["coldfilm", "cold film", "cold-film", "колдфильм", "колд фильм", "cold"]
        case .lostFilm:
            return ["lostfilm", "lost film", "lost-film", "лостфильм", "лост фильм", "lost"]
        case .kubikVKube:
            return ["кубик в кубе", "кубик в кубе (18+)", "кубики", "kubik v kube", "kubik-v-kube", "kubik"]
        case .daronMoneyStudio:
            return ["daron money studio", "daron money", "dragon money studio", "dragon money", "daron", "dragon", "dms", "дарон мани", "драгон мани", "дарон", "драгон"]
        case .jaskier:
            return ["jaskier", "яскъ", "яск", "яскьер", "яскиер", "жаскьер"]
        case .newStudio:
            return ["newstudio", "new studio", "new-studio", "ньюстудио", "нью студио", "нью-студио", "newstudio tv"]
        case .leProduction:
            return ["le-production", "le - production", "le production", "leproduction", "l.e. production", "l.e.production", "ле-продакшн", "ле продакшн", "лепродакшн", "ле продакшен", "ле-продакшен", "le-prod", "le prod"]
        }
    }

    /// Интеллектуальное определение студии дубляжа по сырому или очищенному названию перевода
    static func detect(from name: String) -> DubbingStudio? {
        let lower = name.lowercased()
        
        // 1. Проверяем прямые совпадения с ключевыми словами
        for studio in Self.allCases {
            for keyword in studio.searchKeywords {
                // Если ключевое слово короткое (rhs, dms, rezka), проверяем границы слов
                if keyword.count <= 4 {
                    let pattern = "(?i)(^|[\\s(\\[_-])\(NSRegularExpression.escapedPattern(for: keyword))([\\s)\\]_.,:!?-]|$)"
                    if (try? NSRegularExpression(pattern: pattern).firstMatch(in: lower, range: NSRange(location: 0, length: lower.utf16.count))) != nil {
                        return studio
                    }
                } else if lower.contains(keyword) {
                    return studio
                }
            }
        }
        return nil
    }

    /// Очищает эмодзи в начале названия, сохраняя само название целиком без обрезки
    func cleanChipTitle(from displayName: String) -> String {
        LanguageFlag.stripLeadingEmoji(from: displayName)
    }
}
