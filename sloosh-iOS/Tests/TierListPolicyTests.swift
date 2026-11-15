import Foundation

@main
struct TierListPolicyTests {
    @MainActor
    static func main() async throws {
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

        // The production move reducer, not a hand-written simulation.
        let second = TierListItem(mediaId: "tv_123", mediaType: "tv", title: "Series", year: nil, posterUrl: nil)
        var actualRows = [TierRow(id: "s", label: "S", colorHex: "FF0000", items: [sampleItem, second]), TierRow(id: "a", label: "A", colorHex: "00FF00", items: [])]
        var actualPool: [TierListItem] = []
        TierBoardPolicy.move(sampleItem.mediaId, to: "s", at: 1, rows: &actualRows, unranked: &actualPool)
        check(actualRows[0].items.map(\.mediaId) == [second.mediaId, sampleItem.mediaId], "Same-row forward insertion uses post-removal index")
        TierBoardPolicy.move(sampleItem.mediaId, to: "a", at: 900, rows: &actualRows, unranked: &actualPool)
        check(actualRows[1].items == [sampleItem] && actualRows[0].items == [second], "Empty row accepts movie without losing equal-number TV")
        TierBoardPolicy.move(sampleItem.mediaId, to: TierBoardPolicy.pool, at: -5, rows: &actualRows, unranked: &actualPool)
        check(actualPool == [sampleItem] && actualRows[1].items.isEmpty, "Empty pool is a real destination")
        let before = actualRows
        TierBoardPolicy.move(second.mediaId, to: "deleted-row", at: 0, rows: &actualRows, unranked: &actualPool)
        check(actualRows == before && actualPool == [sampleItem], "Deleted/invalid destination is a no-op")
        for index in -5...10 {
            TierBoardPolicy.move(second.mediaId, to: "s", at: index, rows: &actualRows, unranked: &actualPool)
            check((actualRows.flatMap(\.items) + actualPool).count == 2, "Repeated boundary moves never duplicate/lose items")
        }
        check(TierBoardPolicy.validationMessage(title: "  ", subtitle: nil, rows: actualRows, items: actualPool) != nil, "Reject whitespace title")
        check(TierBoardPolicy.validationMessage(title: String(repeating: "я", count: 121), subtitle: nil, rows: actualRows, items: actualPool) != nil, "Check Firebase title limit before network")
        check(TierBoardPolicy.validationMessage(title: "Test", subtitle: nil, rows: actualRows, items: []) != nil, "Reject empty publication")
        check(TierBoardPolicy.validationMessage(title: "Test", subtitle: nil, rows: actualRows, items: [sampleItem, sampleItem]) != nil, "Reject duplicates")
        check(TierBoardPolicy.validationMessage(title: "Test", subtitle: nil, rows: actualRows, items: [sampleItem, second]) == nil, "Typed movie and series are independent")

        let suite = "sloosh.tier.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var alice = draft; alice.authorId = "alice"; alice.id = "draft_alice"
        var bob = draft; bob.authorId = "bob"; bob.id = "draft_bob"
        var guest = draft; guest.authorId = ""; guest.id = "draft_guest"
        defaults.set(try! JSONEncoder().encode([alice, bob, guest]), forKey: "sloosh_tier_drafts_v1")
        let aliceStore = TierDraftStore(defaults: defaults, userId: "alice")
        let bobStore = TierDraftStore(defaults: defaults, userId: "bob")
        check(aliceStore.load().map(\.id) == [alice.id], "Migrate only proven owner drafts")
        check(bobStore.load().map(\.id) == [bob.id], "Other account keeps its work")
        check(TierDraftStore(defaults: defaults, userId: nil).load().map(\.id) == [guest.id], "Guest drafts are not adopted by a logged-in user")
        aliceStore.save(bob)
        check(aliceStore.load().count == 1, "An old editor cannot save into a different account")
        alice.title = "Edited"; aliceStore.save(alice)
        check(aliceStore.load().first?.title == "Edited", "Update replaces draft instead of duplicating")
        aliceStore.delete(id: alice.id)
        check(aliceStore.load().isEmpty && bobStore.load().count == 1, "Deletion cannot resurrect legacy draft or delete another account")
        for i in 0..<25 { alice.id = "draft_\(i)"; aliceStore.save(alice) }
        check(aliceStore.load().count == 25, "Never silently delete draft 21 and older")

        // Autosave decisions use the production state machine and actual store.
        let autosaveStore = TierDraftStore(defaults: defaults, userId: "autosave")
        for pool in [[TierListItem](), template!.items] {
            let initial = TierEditorSnapshot(title: "Мой тир-лист", subtitle: "", rows: TierRow.defaultRows(), unranked: pool)
            var state = TierDraftAutosaveState(initial: initial, wasStored: false)
            for _ in 0..<3 {
                check(state.action(for: initial, didPublish: false) == .none,
                      "Opening, backgrounding and leaving untouched blank/template editors never save a draft")
            }
            var changed = initial
            changed.title = "Мой рейтинг"
            check(state.action(for: changed, didPublish: false) == .save, "A real title edit starts autosave")
            var saved = draft
            saved.authorId = "autosave"; saved.id = "draft_autosave"
            saved.title = changed.title; saved.rows = changed.rows; saved.unranked = changed.unranked
            autosaveStore.save(saved)
            check(autosaveStore.load().count == 1, "Edited work remains recoverable")
            check(state.action(for: changed, didPublish: false) == .none, "Lifecycle callbacks do not rewrite unchanged work")
            check(state.action(for: initial, didPublish: false) == .delete, "Undoing all edits removes only the new session draft")
            autosaveStore.delete(id: saved.id)
            check(autosaveStore.load().isEmpty, "No phantom draft remains after undo to the initial state")
            check(state.action(for: initial, didPublish: false) == .none, "Repeated exit after undo stays a no-op")
            check(state.action(for: changed, didPublish: true) == .none, "Publication cannot resurrect a deleted draft")
            check(state.action(for: changed, didPublish: false) == .save, "Editing again after undo resumes autosave")

            for edited in [
                TierEditorSnapshot(title: initial.title, subtitle: "Описание", rows: initial.rows, unranked: pool),
                TierEditorSnapshot(title: initial.title, subtitle: "", rows: Array(initial.rows.reversed()), unranked: pool),
                TierEditorSnapshot(title: initial.title, subtitle: "", rows: initial.rows, unranked: pool + [sampleItem])
            ] {
                var freshState = TierDraftAutosaveState(initial: initial, wasStored: false)
                check(freshState.action(for: edited, didPublish: false) == .save, "Description, row and film edits are saved")
            }
            var existing = TierDraftAutosaveState(initial: initial, wasStored: true)
            check(existing.action(for: initial, didPublish: false) == .none, "Opening an existing draft does not rewrite it")
            check(existing.action(for: changed, didPublish: false) == .save, "Existing draft edits still save")
            check(existing.action(for: initial, didPublish: false) == .save, "Undo after autosave restores an existing draft, never deletes it")
            check(existing.action(for: initial, didPublish: false) == .none, "Restored existing draft does not save repeatedly")
        }

        // A local checkpoint preserves BOTH committed template edits and pending
        // picks across view/process reconstruction; it is never a server write.
        let adminStore = AdminTierTemplateSessionStore(defaults: defaults, userId: "alice")
        let otherAdminStore = AdminTierTemplateSessionStore(defaults: defaults, userId: "bob")
        var adminSession = AdminTierTemplateSession(original: template!)
        check(!adminSession.hasUnsavedWork, "An unchanged template has no unsaved work")
        adminSession.value.title = "Локальное название"
        adminSession.showPicker = true
        adminSession.picker.searchText = "Тест"
        adminSession.picker.collection = TierPickerCollection(id: "collection_1", name: "Подборка")
        adminSession.picker.selected = [sampleItem, second, sampleItem, template!.items[0]]
        adminStore.save(adminSession)
        let reopenedStore = AdminTierTemplateSessionStore(defaults: defaults, userId: "alice")
        var recovered = reopenedStore.load()!
        check(recovered == adminSession, "Reconstruction restores session identity, template, picker visibility, query, collection and ordered pending selections")
        check(recovered.original == template, "Recovery retains the original server version for conflict checks")
        check(recovered.value.items == template!.items, "Unconfirmed picks never leak into the template")
        check(otherAdminStore.load() == nil, "Another account cannot restore this admin session")
        recovered.addSelectedItems()
        check(recovered.value.items == template!.items + [sampleItem, second], "Confirm adds pending items once in selection order, filtering typed duplicates")
        check(recovered.picker == TierItemPickerDraft() && !recovered.showPicker, "Confirm clears only pending picks and closes picker")
        reopenedStore.save(recovered)
        check(reopenedStore.load()?.value == recovered.value, "Confirmed but unpublished template edits also survive restart")
        reopenedStore.clear()
        check(reopenedStore.load() == nil, "Explicit save/discard clears recovery instead of reopening a ghost session")
        var pendingOnly = AdminTierTemplateSession(original: nil)
        check(!pendingOnly.hasUnsavedWork && !pendingOnly.hasTemplateChanges, "Opening a blank admin editor alone is not an edit")
        pendingOnly.picker.selected = [sampleItem]
        check(pendingOnly.hasUnsavedWork && !pendingOnly.hasTemplateChanges, "Pending picks count as recoverable work, not committed template changes")
        pendingOnly.picker = TierItemPickerDraft()
        check(!pendingOnly.hasUnsavedWork, "Explicit picker cancel discards pending picks")
        let guestAdminStore = AdminTierTemplateSessionStore(defaults: defaults, userId: "")
        guestAdminStore.save(adminSession)
        check(guestAdminStore.load() == nil, "Admin recovery is never saved for a signed-out guest")
        defaults.set(Data("broken".utf8), forKey: "sloosh_admin_tier_session_v1_alice")
        check(adminStore.load() == nil, "Corrupt local recovery does not crash the admin panel")
        adminStore.clear()

        let appUI = try String(contentsOfFile: "sloosh/Sources/UI/Home/ContentView.swift", encoding: .utf8)
        check(appUI.contains(".id(authRepo.currentUser?.id)"), "Tab content identity is account-scoped, not driven by cosmetic avatar/settings refresh")
        check(!appUI.contains("\\(avatarVersion)"), "Avatar refresh must not recreate the entire tab tree and dismiss editors")

        // Source-level UI contract, not a gesture/pixel test: keep the exact
        // system API used before the polish pass and never chain a popup to it.
        let galleryUI = try String(contentsOfFile: "sloosh/Sources/UI/TierLists/TierListsHomeView.swift", encoding: .utf8)
        let adminUI = try String(contentsOfFile: "sloosh/Sources/UI/Admin/AdminTierTemplatesView.swift", encoding: .utf8)
            .components(separatedBy: "private struct AdminTierTemplateEditor")[0]
        check(galleryUI.components(separatedBy: ".buttonStyle(.plain)").count - 1 == 4,
              "Draft, published, template and popular row buttons must not tint their text with the brand accent")
        check(adminUI.contains(".buttonStyle(.plain)"), "Admin template row buttons must keep neutral text")
        for source in [galleryUI, adminUI] {
            check(source.contains(".swipeActions(edge: .trailing)"), "Restore the historical system swipeActions API")
            check(source.contains("Button(role: .destructive)") && source.contains(".tint(.red)"), "Keep native destructive actions red")
            check(!source.contains(".confirmationDialog("), "Swipe removal must not open a second popover")
            check(!source.contains("allowsFullSwipe: false"), "Do not restrict native full swipe")
        }

        let networkChecks = try await TierListRepositoryTests.run()
        print("tier-list-repository: \(networkChecks) production-transport checks passed")
        print("tier-list-policy: \(count) checks passed")
    }
}
