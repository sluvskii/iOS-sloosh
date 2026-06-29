import SwiftUI

// MARK: - Rating Color

extension Color {
    /// Цвет рейтинга: зелёный ≥7.5, жёлтый 5–7.5, красный <5.
    static func rating(_ value: Double) -> Color {
        switch value {
        case 7.5...10.0: return .green
        case 5.0..<7.5:  return .yellow
        case 0.1..<5.0:  return .red
        default:         return .secondary
        }
    }
}

// MARK: - Cartoon Detection

/// Определяет, является ли медиа мультфильмом/анимацией по жанрам и названию.
func isCartoon(_ item: MediaDto) -> Bool {
    let genreNames = item.genres?
        .compactMap { $0.name?.lowercased() }
        .joined(separator: " ") ?? ""

    let haystack = [
        genreNames,
        item.displayTitle.lowercased(),
        item.originalTitle?.lowercased() ?? ""
    ].joined(separator: " ")

    return haystack.contains("мульт")
        || haystack.contains("анимац")
        || haystack.contains("animation")
        || haystack.contains("anime")
}

/// Облегчённая версия для случаев, когда жанры недоступны (например, FavoriteDto).
func isCartoonByTitle(_ title: String?) -> Bool {
    guard let t = title?.lowercased() else { return false }
    return t.contains("мульт") || t.contains("анимац") || t.contains("animation") || t.contains("anime")
}
