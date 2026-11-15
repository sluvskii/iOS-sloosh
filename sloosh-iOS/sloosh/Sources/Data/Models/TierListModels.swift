import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

/// Один фильм внутри тир-листа. mediaId — типизированный идентификатор
/// («movie_123» / «tv_456»), открывает DetailsView через существующую навигацию.
/// posterUrl фиксируется в момент добавления (абсолютный w500 из MediaDto) —
/// рендер доски и экспорт работают без N×1 запросов деталей.
struct TierListItem: Codable, Hashable, Identifiable {
    var mediaId: String
    var mediaType: String
    var title: String
    var year: Int?
    var posterUrl: String?

    var id: String { mediaId }
    var detailsId: String { mediaId }
}

/// Строка уровня (S/A/B/C/D…) с цветным чипом.
struct TierRow: Codable, Hashable, Identifiable {
    var id: String
    var label: String
    var colorHex: String
    var items: [TierListItem]

    var color: Color {
        #if canImport(UIKit)
        Color(UIColor(hex: colorHex) ?? .systemGray)
        #else
        Color.clear
        #endif
    }

    static func defaultRows() -> [TierRow] {
        let defaults: [(String, String)] = [
            ("S", "FF7F7F"), ("A", "FFBF7F"), ("B", "FFDF7F"),
            ("C", "FFFF7F"), ("D", "BFFF7F")
        ]
        return defaults.map { label, hex in
            TierRow(id: UUID().uuidString, label: label, colorHex: hex, items: [])
        }
    }
}

/// Публичный тир-лист. likesCount/viewsCount — счётчики в узле (пишутся
/// guard-проверкой существования содержимого, паттерн ClipsRepository);
/// сами лайки лежат в отдельном поддереве tier_lists_likes/{id}/{uid}.
struct TierList: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var subtitle: String?
    var authorId: String
    var authorName: String
    var authorTag: String?
    var authorAvatar: String?
    var createdAtMs: Int64
    var updatedAtMs: Int64
    var rows: [TierRow]
    var unranked: [TierListItem]
    var templateId: String?
    var likesCount: Int?
    var viewsCount: Int?
    /// Локальный флаг черновика: черновики живут только в UserDefaults и не публикуются.
    var isDraft: Bool?

    var isDraftList: Bool { isDraft ?? false }
    var allItems: [TierListItem] { rows.flatMap(\.items) + unranked }
    var itemsCount: Int { allItems.count }

    var dateText: String {
        let date = Date(timeIntervalSince1970: TimeInterval(createdAtMs / 1000))
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMMM yyyy"
        formatter.locale = Locale(identifier: "ru_RU")
        return formatter.string(from: date)
    }

    /// Кодировка для RTDB: черновые поля не публикуются.
    var publishDocument: [String: Any] {
        var document: [String: Any] = [
            "title": title,
            "authorId": authorId,
            "authorName": authorName,
            "createdAtMs": createdAtMs,
            "updatedAtMs": updatedAtMs,
            "rows": rows.map { row -> [String: Any] in
                [
                    "id": row.id,
                    "label": row.label,
                    "colorHex": row.colorHex,
                    "items": row.items.map { item -> [String: Any] in
                        var dict: [String: Any] = [
                            "mediaId": item.mediaId,
                            "mediaType": item.mediaType,
                            "title": item.title
                        ]
                        if let year = item.year { dict["year"] = year }
                        if let posterUrl = item.posterUrl { dict["posterUrl"] = posterUrl }
                        return dict
                    }
                ]
            },
            "unranked": unranked.map { item -> [String: Any] in
                var dict: [String: Any] = [
                    "mediaId": item.mediaId,
                    "mediaType": item.mediaType,
                    "title": item.title
                ]
                if let year = item.year { dict["year"] = year }
                if let posterUrl = item.posterUrl { dict["posterUrl"] = posterUrl }
                return dict
            }
        ]
        if let subtitle = subtitle, !subtitle.isEmpty { document["subtitle"] = subtitle }
        if let authorTag = authorTag, !authorTag.isEmpty { document["authorTag"] = authorTag }
        if let authorAvatar = authorAvatar { document["authorAvatar"] = authorAvatar }
        if let templateId = templateId { document["templateId"] = templateId }
        if let likesCount = likesCount { document["likesCount"] = likesCount }
        if let viewsCount = viewsCount { document["viewsCount"] = viewsCount }
        return document
    }

    /// Восстановление из RTDB-документа (толерантно: битые строки/айтемы пропускаются).
    static func decode(id: String, document: [String: Any]) -> TierList? {
        guard let title = document["title"] as? String, !title.isEmpty,
              let authorId = document["authorId"] as? String, !authorId.isEmpty else { return nil }

        func decodeItems(_ raw: Any?) -> [TierListItem] {
            guard let array = raw as? [[String: Any]] else { return [] }
            return array.compactMap { entry in
                guard let mediaId = entry["mediaId"] as? String, !mediaId.isEmpty,
                      let itemTitle = entry["title"] as? String else { return nil }
                return TierListItem(
                    mediaId: mediaId,
                    mediaType: entry["mediaType"] as? String ?? "movie",
                    title: itemTitle,
                    year: entry["year"] as? Int,
                    posterUrl: entry["posterUrl"] as? String
                )
            }
        }

        let rows: [TierRow] = (document["rows"] as? [[String: Any]] ?? []).compactMap { raw in
            guard let label = raw["label"] as? String, !label.isEmpty else { return nil }
            return TierRow(
                id: raw["id"] as? String ?? UUID().uuidString,
                label: label,
                colorHex: raw["colorHex"] as? String ?? "FF7F7F",
                items: decodeItems(raw["items"])
            )
        }
        if rows.isEmpty { return nil }

        let createdAt = (document["createdAtMs"] as? NSNumber)?.int64Value
            ?? Int64((document["createdAtMs"] as? Double) ?? 0)
        let updatedAt = (document["updatedAtMs"] as? NSNumber)?.int64Value
            ?? Int64((document["updatedAtMs"] as? Double) ?? 0)

        return TierList(
            id: id,
            title: title,
            subtitle: document["subtitle"] as? String,
            authorId: authorId,
            authorName: document["authorName"] as? String ?? "Пользователь",
            authorTag: document["authorTag"] as? String,
            authorAvatar: document["authorAvatar"] as? String,
            createdAtMs: createdAt,
            updatedAtMs: updatedAt,
            rows: rows,
            unranked: decodeItems(document["unranked"]),
            templateId: document["templateId"] as? String,
            likesCount: (document["likesCount"] as? NSNumber)?.intValue,
            viewsCount: (document["viewsCount"] as? NSNumber)?.intValue,
            isDraft: nil
        )
    }
}

/// Ранжинг для вкладки «Популярные»: вовлечённость (лайки×2 + просмотры×0.2)
/// плюс затухание свежести. Чистая логика — покрывается CI-тестами без UIKit.
enum TierListRanking {
    static func score(_ list: TierList, nowMs: Int64) -> Double {
        let engagement = Double(list.likesCount ?? 0) * 2 + Double(list.viewsCount ?? 0) * 0.2
        let ageHours = max(0.5, Double(nowMs - list.createdAtMs) / 3_600_000)
        let freshness = max(0.0, 100.0 - ageHours * 1.2)
        return engagement + freshness
    }

    static func rank(_ lists: [TierList], nowMs: Int64) -> [TierList] {
        lists.sorted { a, b in
            let scoreA = score(a, nowMs: nowMs)
            let scoreB = score(b, nowMs: nowMs)
            if abs(scoreA - scoreB) > 0.001 { return scoreA > scoreB }
            if a.createdAtMs != b.createdAtMs { return a.createdAtMs > b.createdAtMs }
            return a.id > b.id
        }
    }
}

/// пишется только админами (правила), импортируется JSON-файлом в консоль.
/// Редакторский шаблон для галереи «Шаблоны». Живёт в RTDB `tier_templates`,
/// пишется только админами (правила), импортируется JSON-файлом в консоль.
struct TierTemplate: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var subtitle: String?
    var priority: Int?
    var items: [TierListItem]

    var validationMessage: String? {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Добавьте название шаблона" }
        if title.count > 120 { return "Название — не больше 120 символов" }
        if (subtitle?.count ?? 0) > 300 { return "Описание — не больше 300 символов" }
        if items.count < 4 { return "Добавьте хотя бы четыре фильма или сериала" }
        if Set(items.map(\.mediaId)).count != items.count { return "Уберите повторяющиеся фильмы" }
        return nil
    }

    var publishDocument: [String: Any] {
        var result: [String: Any] = ["title": title, "priority": priority ?? 0]
        if let subtitle, !subtitle.isEmpty { result["subtitle"] = subtitle }
        result["items"] = items.map { item -> [String: Any] in
            var value: [String: Any] = ["mediaId": item.mediaId, "mediaType": item.mediaType, "title": item.title]
            if let year = item.year { value["year"] = year }
            if let url = item.posterUrl { value["posterUrl"] = url }
            return value
        }
        return result
    }

    var coverPosterUrls: [String] {
        Array(items.prefix(4).compactMap(\.posterUrl))
    }

    static func decode(id: String, document: [String: Any]) -> TierTemplate? {
        guard let title = document["title"] as? String, !title.isEmpty else { return nil }
        let items: [TierListItem] = (document["items"] as? [[String: Any]] ?? []).compactMap { entry in
            guard let mediaId = entry["mediaId"] as? String, !mediaId.isEmpty,
                  let itemTitle = entry["title"] as? String else { return nil }
            return TierListItem(
                mediaId: mediaId,
                mediaType: entry["mediaType"] as? String ?? "movie",
                title: itemTitle,
                year: entry["year"] as? Int,
                posterUrl: entry["posterUrl"] as? String
            )
        }
        guard items.count >= 4 else { return nil }
        return TierTemplate(
            id: id,
            title: title,
            subtitle: document["subtitle"] as? String,
            priority: (document["priority"] as? NSNumber)?.intValue,
            items: items
        )
    }
}

/// Shared by the live board and tests. Indices refer to the destination AFTER
/// removing the lifted item. Invalid/deleted destinations never lose a movie.
enum TierBoardPolicy {
    static let pool = "__pool__"
    static func move(_ mediaId: String, to destination: String, at index: Int,
                     rows: inout [TierRow], unranked: inout [TierListItem]) {
        guard destination == pool || rows.contains(where: { $0.id == destination }),
              let item = (rows.flatMap(\.items) + unranked).first(where: { $0.mediaId == mediaId }) else { return }
        for i in rows.indices { rows[i].items.removeAll { $0.mediaId == mediaId } }
        unranked.removeAll { $0.mediaId == mediaId }
        if destination == pool {
            unranked.insert(item, at: max(0, min(index, unranked.count)))
        } else if let i = rows.firstIndex(where: { $0.id == destination }) {
            rows[i].items.insert(item, at: max(0, min(index, rows[i].items.count)))
        }
    }

    static func validationMessage(title: String, subtitle: String?, rows: [TierRow], items: [TierListItem]) -> String? {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Добавьте название" }
        if title.count > 120 { return "Название — не больше 120 символов" }
        if (subtitle?.count ?? 0) > 300 { return "Описание — не больше 300 символов" }
        if rows.isEmpty { return "Добавьте хотя бы один уровень" }
        if items.isEmpty { return "Добавьте хотя бы один фильм или сериал" }
        if Set(items.map(\.mediaId)).count != items.count { return "Уберите повторяющиеся фильмы" }
        return nil
    }

    static func draftKey(userId: String?) -> String { "sloosh_tier_drafts_v2_\(userId ?? "guest")" }
    static func belongsToAccount(_ list: TierList, userId: String?) -> Bool {
        list.authorId == (userId ?? "")
    }
}

struct TierEditorSnapshot: Equatable {
    var title: String
    var subtitle: String
    var rows: [TierRow]
    var unranked: [TierListItem]
}

/// Opening an editor is not an edit. Track persisted content separately from
/// the opening snapshot so undo works even after a debounced save has fired.
struct TierDraftAutosaveState {
    enum Action: Equatable { case none, save, delete }

    private let initial: TierEditorSnapshot
    private let wasStored: Bool
    private var persisted: TierEditorSnapshot?

    init(initial: TierEditorSnapshot, wasStored: Bool) {
        self.initial = initial
        self.wasStored = wasStored
        self.persisted = wasStored ? initial : nil
    }

    mutating func action(for snapshot: TierEditorSnapshot, didPublish: Bool) -> Action {
        guard !didPublish else { return .none }
        if !wasStored && snapshot == initial {
            guard persisted != nil else { return .none }
            persisted = nil
            return .delete
        }
        guard snapshot != persisted else { return .none }
        persisted = snapshot
        return .save
    }
}

/// Account-isolated persistence, including a conservative migration: unowned
/// legacy drafts remain guest drafts, never silently attached to a signed-in UID.
struct TierDraftStore {
    let defaults: UserDefaults
    let userId: String?
    private var key: String { TierBoardPolicy.draftKey(userId: userId) }

    func load() -> [TierList] {
        if defaults.data(forKey: key) == nil,
           let old = defaults.data(forKey: "sloosh_tier_drafts_v1"),
           let legacy = try? JSONDecoder().decode([TierList].self, from: old) {
            write(legacy.filter { TierBoardPolicy.belongsToAccount($0, userId: userId) })
        }
        guard let data = defaults.data(forKey: key), let lists = try? JSONDecoder().decode([TierList].self, from: data) else { return [] }
        return lists.filter { TierBoardPolicy.belongsToAccount($0, userId: userId) }.sorted { $0.updatedAtMs > $1.updatedAtMs }
    }
    func save(_ list: TierList) {
        guard TierBoardPolicy.belongsToAccount(list, userId: userId) else { return }
        var lists = load().filter { $0.id != list.id }
        var copy = list
        copy.isDraft = true
        copy.updatedAtMs = Int64(Date().timeIntervalSince1970 * 1000)
        lists.insert(copy, at: 0)
        // Never silently discard older work to enforce a UI limit.
        write(lists)
    }
    func delete(id: String) { write(load().filter { $0.id != id }) }
    private func write(_ lists: [TierList]) {
        if let data = try? JSONEncoder().encode(lists) { defaults.set(data, forKey: key) }
    }
}
