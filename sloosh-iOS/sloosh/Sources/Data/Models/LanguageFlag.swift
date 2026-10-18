import SwiftUI
import UIKit

/// Круглые флаги стран и служебные значки для озвучек и субтитров.
enum LanguageFlag: String, CaseIterable, Hashable {
    case ru = "Flag-RU"
    case ua = "Flag-UA"
    case us = "Flag-US"
    case kz = "Flag-KZ"
    case by = "Flag-BY"
    case gb = "Flag-GB"
    case jp = "Flag-JP"
    case kr = "Flag-KR"
    case cn = "Flag-CN"
    case fr = "Flag-FR"
    case de = "Flag-DE"
    case tr = "Flag-TR"
    case ge = "Flag-GE"
    case es = "Flag-ES"
    case it = "Flag-IT"
    case subtitles = "Flag-Subtitles"

    var assetName: String { rawValue }

    var hasAsset: Bool {
        UIImage(named: assetName) != nil
    }

    /// Определяет флаг языка по тексту перевода или эмодзи
    static func detect(from text: String) -> LanguageFlag {
        let lower = text.lowercased()

        // 1. Субтитры
        if lower.contains("субтитр") || lower.contains("subtitle") || text.contains("💬") {
            return .subtitles
        }

        // 2. По эмодзи флагов
        if text.contains("🇷🇺") { return .ru }
        if text.contains("🇺🇦") { return .ua }
        if text.contains("🇺🇸") { return .us }
        if text.contains("🇰🇿") { return .kz }
        if text.contains("🇧🇾") { return .by }
        if text.contains("🇬🇧") { return .gb }
        if text.contains("🇯🇵") { return .jp }
        if text.contains("🇰🇷") { return .kr }
        if text.contains("🇨🇳") { return .cn }
        if text.contains("🇫🇷") { return .fr }
        if text.contains("🇩🇪") { return .de }
        if text.contains("🇹🇷") { return .tr }
        if text.contains("🇬🇪") { return .ge }
        if text.contains("🇪🇸") { return .es }
        if text.contains("🇮🇹") { return .it }

        // 3. По ключевым словам
        if lower.contains("украин") || lower.contains("ukrain") || lower.contains("укр") {
            return .ua
        }
        if lower.contains("казах") || lower.contains("kazakh") || lower.contains("каз") {
            return .kz
        }
        if lower.contains("белорус") || lower.contains("belarus") || lower.contains("бел") {
            return .by
        }
        if lower.contains("оригинал") || lower.contains("original") || lower.contains("english") || lower.contains("английск") || lower.contains("англ") || lower.contains("usa") {
            return .us
        }
        if lower.contains("япон") || lower.contains("japan") || lower.contains("аниме") {
            return .jp
        }
        if lower.contains("корей") || lower.contains("korean") {
            return .kr
        }
        if lower.contains("китай") || lower.contains("chinese") {
            return .cn
        }
        if lower.contains("француз") || lower.contains("french") {
            return .fr
        }
        if lower.contains("немец") || lower.contains("german") {
            return .de
        }
        if lower.contains("турец") || lower.contains("turkish") {
            return .tr
        }
        if lower.contains("грузин") || lower.contains("georgian") {
            return .ge
        }
        if lower.contains("испан") || lower.contains("spanish") {
            return .es
        }
        if lower.contains("итальян") || lower.contains("italian") {
            return .it
        }

        // По умолчанию для отечественных переводов и озвучек
        return .ru
    }

    /// Аккуратно удаляет эмодзи флага в начале строки, не трогая само название
    static func stripLeadingEmoji(from text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespaces)
        let emojis = ["🇷🇺", "🇺🇸", "🇺🇦", "🇬🇧", "🇰🇿", "🇧🇾", "🇯🇵", "🇰🇷", "🇨🇳", "🇫🇷", "🇩🇪", "🇹🇷", "🇬🇪", "🇪🇸", "🇮🇹", "💬"]
        for emoji in emojis {
            if s.hasPrefix(emoji) {
                s = String(s.dropFirst(emoji.count)).trimmingCharacters(in: .whitespaces)
                break
            }
        }
        return s
    }
}
