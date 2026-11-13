import Foundation

@main
struct TierListPolicyTests {
    static func main() {
        var count = 0
        func check(_ condition: Bool, _ description: String) {
            precondition(condition, description)
            count += 1
        }

        // MARK: Декод списка из RTDB-документа

        let document: [String: Any] = [
            "title": "Все фильмы MCU",
            "authorId": "usr_abc",
            "authorName": "Кина Царь",
            "createdAtMs": 1_000,
            "updatedAtMs": 2_000,
            "rows": [
                ["id": "r1", "label": "S", "colorHex": "FF7F7F", "items": [
                    ["mediaId": "movie_559", "mediaType": "movie", "title": "Человек-паук 3", "year": 2007, "posterUrl": "https://x/p.jpg"]
                ]],
                ["id": "r2", "label": "A", "colorHex": "FFBF7F", "items": [
                    ["mediaId": "movie_1726", "title": "Железный человек"],
                    ["title": "битый айтем без id"] // должен быть пропущен
                ]]
            ],
            "unranked": [
                ["mediaId": "movie_299534", "mediaType": "movie", "title": "Мстители: Финал", "year": 2019]
            ]
        ]
        let list = TierList.decode(id: "list1", document: document)
        check(list != nil, "Valid document decodes")
        check(list?.rows.count == 2, "Two tier rows decoded")
        check(list?.rows[0].items.count == 1, "Row S has one item")
        check(list?.rows[1].items.count == 1, "Broken item skipped, valid item kept")
        check(list?.unranked.count == 1, "Unranked pool decoded")
        check(list?.rows[0].items[0].detailsId == "movie_559", "Typed mediaId preserved")

        // Битые документы не декодируются
        check(TierList.decode(id: "x", document: ["title": "Только заголовок"]) == nil, "Document without author rejected")
        check(TierList.decode(id: "x", document: ["authorId": "usr"]) == nil, "Document without title rejected")
        check(TierList.decode(id: "x", document: ["title": "T", "authorId": "u", "rows": []]) == nil, "Document without rows rejected")

        // MARK: publishDocument roundtrip

        let published = list!.publishDocument
        let restored = TierList.decode(id: "list1", document: published)
        check(restored?.title == list?.title, "Roundtrip preserves title")
        check(restored?.rows[0].items[0].posterUrl == "https://x/p.jpg", "Roundtrip preserves poster")
        check(restored?.rows[1].items[0].year == nil, "Optional year omitted cleanly")

        // MARK: Ранжинг

        func makeList(id: String, likes: Int?, views: Int?, ageHours: Double) -> TierList {
            TierList(
                id: id, title: "T", subtitle: nil,
                authorId: "u", authorName: "A", authorTag: nil, authorAvatar: nil,
                createdAtMs: Int64(1_790_000_000_000 - ageHours * 3_600_000),
                updatedAtMs: 0,
                rows: TierRow.defaultRows(), unranked: [],
                templateId: nil, likesCount: likes, viewsCount: views, isDraft: nil
            )
        }
        let nowMs: Int64 = 1_790_000_000_000
        let hot = makeList(id: "hot", likes: 50, views: 500, ageHours: 2)
        let fresh = makeList(id: "fresh", likes: 0, views: 0, ageHours: 1)
        let stale = makeList(id: "stale", likes: 3, views: 20, ageHours: 700)

        let ranked = TierListRanking.rank([stale, hot, fresh], nowMs: nowMs)
        check(ranked[0].id == "hot", "Engagement winner ranks first")
        check(TierListRanking.score(hot, nowMs: nowMs) > TierListRanking.score(stale, nowMs: nowMs), "Hot beats stale")
        check(TierListRanking.score(fresh, nowMs: nowMs) > TierListRanking.score(stale, nowMs: nowMs), "Freshness beats tiny engagement")

        // MARK: Шаблоны

        let template = TierTemplate.decode(id: "mcu", document: [
            "title": "MCU",
            "items": (1...6).map { ["mediaId": "movie_\($0)", "title": "Film \($0)", "posterUrl": "https://x/\($0).jpg"] }
        ])
        check(template != nil && template?.items.count == 6, "Template with 6 items decodes")
        check(template?.coverPosterUrls.count == 4, "Cover collage capped at 4 posters")
        check(TierTemplate.decode(id: "x", document: [
            "title": "Too small",
            "items": [["mediaId": "movie_1", "title": "One"]]
        ]) == nil, "Template with fewer than 4 items rejected")

        // MARK: Черновики и флаги

        var draft = makeList(id: "draft_x", likes: nil, views: nil, ageHours: 1)
        draft.isDraft = true
        check(draft.isDraftList, "Draft flag readable")
        let draftDoc = draft.publishDocument
        check((draftDoc["isDraft"] as? Bool) == nil, "Draft flag not published to RTDB")
        check((draftDoc["title"] as? String) == "T", "Draft title published")

        // MARK: Перемещение и граничные индексы

        var testRows = TierRow.defaultRows()
        check(!testRows.isEmpty, "Default rows present")
        check(testRows.first?.label == "S", "Top row is S")

        let sampleItem = TierListItem(mediaId: "movie_123", mediaType: "movie", title: "Test Movie", year: 2024, posterUrl: nil)
        var poolItems: [TierListItem] = [sampleItem]

        // Симуляция безопасного переноса из пула в верхний тир
        let safeTargetIndex = max(0, min(100, testRows[0].items.count))
        testRows[0].items.insert(sampleItem, at: safeTargetIndex)
        poolItems.removeAll { $0.mediaId == sampleItem.mediaId }

        check(testRows[0].items.count == 1, "Item inserted into Row S")
        check(poolItems.isEmpty, "Item removed from pool")
        check(testRows[0].items[0].mediaId == "movie_123", "Item identity preserved")

        print("tier-list-policy: \(count) checks passed")
    }
}
