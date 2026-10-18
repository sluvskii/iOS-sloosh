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
        case .daronMoneyStudio: return "Daron Money Studio"
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
            return ["alexfilm", "alex film", "alex-film", "алексфильм", "алекс фильм"]
        case .ruDub:
            return ["rudub", "ru dub", "ru-dub", "рудаб", "ру даб"]
        case .coldFilm:
            return ["coldfilm", "cold film", "cold-film", "колдфильм", "колд фильм"]
        case .lostFilm:
            return ["lostfilm", "lost film", "lost-film", "лостфильм", "лост фильм"]
        case .kubikVKube:
            return ["кубик в кубе", "кубик в кубе (18+)", "кубики", "kubik v kube", "kubik-v-kube", "kubik"]
        case .daronMoneyStudio:
            return ["daron money studio", "daron money", "daron", "dms", "дарон мани", "дарон"]
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

    /// Форматирует название для отображения в плашке рядом с логотипом (убирая дублирующийся флаг РФ)
    func cleanChipTitle(from displayName: String) -> String {
        var title = displayName
        // Убираем флаг России "🇷🇺 ", так как брендовый логотип уже идентифицирует российскую студию
        if title.hasPrefix("🇷🇺 ") {
            title = String(title.dropFirst(4)).trimmingCharacters(in: .whitespaces)
        } else if title.hasPrefix("🇷🇺") {
            title = String(title.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }
        return title
    }
}
