import Foundation

// UI-only dependency; production search state/DTOs/policies are compiled below.
struct PlayerConfig: Identifiable { let id = UUID() }

@main
struct CatalogSearchTests {
    @MainActor
    static func main() async throws {
        var count = 0
        func check(_ value: Bool, _ message: String) { precondition(value, message); count += 1 }
        func waitUntil(_ condition: () -> Bool) async {
            for _ in 0..<10_000 {
                if condition() { return }
                await Task.yield()
            }
            preconditionFailure("Search test did not reach the expected state")
        }
        let suite = "sloosh.search.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let film = MediaDto(originalId: .string("42"), title: "Ёлки", year: .int(2026), rating: 7.5,
                            type: "movie", genres: [GenreDto(id: "35", name: "Comedy")], countries: ["RU"])
        let series = MediaDto(originalId: .string("42"), title: "Сериал", originalTitle: "Series", year: .int(2025),
                              rating: 8, type: "tv", genres: [GenreDto(id: "18", name: "Drama")], countries: ["US"])
        let anime = MediaDto(originalId: .string("movie_2"), title: "Аниме", type: "movie",
                             genres: [GenreDto(id: "16", name: nil)], countries: ["JP"])
        check(CatalogSearchQuery.text("  Ёлки\n \t2026 ") == "Ёлки 2026", "Normalize repeated whitespace, preserve readable query")
        check(CatalogSearchQuery.key("ЁЛКИ—2026!") == CatalogSearchQuery.key("елки 2026"), "Case, punctuation and ё/е comparison")
        check(CatalogSearchQuery.text(String(repeating: "я", count: 10_000)).count == 200, "Bound untrusted query length")
        check(CatalogSearchQuery.alternatives("ghbdtn").contains("привет"), "Recover Russian text typed on Latin keyboard")
        check(CatalogSearchQuery.alternatives("руддщ").contains("hello"), "Recover Latin text typed on Russian keyboard")
        check(CatalogSearchQuery.alternatives("я").isEmpty && CatalogSearchQuery.alternatives("film фильм").isEmpty, "Do not transform short or mixed-script titles blindly")
        check(CatalogSearchQuery.alternatives("matrix").count <= 2, "Fallback budget is bounded")
        check(CatalogSearchQuery.editDistance("матрица", "матирца") == 1, "Adjacent transposition counts as one typo")
        check(CatalogSearchQuery.suggestions(for: "матирца", candidates: ["Матрица", "Совсем другое"]) == ["Матрица"], "Typo-aware suggestions from observed titles")
        check(CatalogSearchQuery.suggestions(for: "ел", candidates: ["Ёлки", "ЁЛКИ", "Елена"]) == ["Ёлки", "Елена"], "Suggestions deduplicate normalized titles, retain stable order")
        check(CatalogSearchPolicy.merge([], [film], order: nil).count == 1, "Posterless releases remain searchable")
        check(CatalogSearchPolicy.merge([], [MediaDto(originalId: .string("7"), originalTitle: "Only original")], order: nil).count == 1, "Original-title-only records remain searchable")
        check(CatalogSearchPolicy.merge([], [MediaDto(originalId: .string("7"), title: " \n")], order: nil).isEmpty, "Malformed untitled records are rejected")
        check(CatalogSearchPolicy.merge([film], [series, film, series], order: nil).count == 2, "Same-number film and series survive typed deduplication, including duplicates within one page")
        check(CatalogSearchPolicy.matches(film, filters: SearchFilters(type: "FILM", ratingFrom: 7.5, ratingTo: 7.5, yearFrom: 2026, yearTo: 2026, genres: "комедия", countries: "Россия")), "Inclusive bounds and RU/EN/numeric metadata aliases")
        check(!CatalogSearchPolicy.matches(film, filters: SearchFilters(type: "TV_SERIES")), "Wrong content type is never restored as a fallback")
        check(!CatalogSearchPolicy.matches(film, filters: SearchFilters(genres: "драма,комедия")), "All selected genres must match")
        check(CatalogSearchPolicy.matches(film, filters: SearchFilters(countries: "США,Россия")), "Any selected country may match")
        let namedGenre = MediaDto(originalId: .string("movie_9"), title: "Комедия", type: "movie", genres: [GenreDto(id: "16", name: "Комедия")])
        check(CatalogSearchPolicy.matches(namedGenre, filters: SearchFilters(type: "FILM", genres: "комедия")), "Named genre wins over a conflicting legacy numeric namespace")
        let china = MediaDto(originalId: .string("movie_10"), title: "Фильм", countries: ["China"])
        check(!CatalogSearchPolicy.matches(china, filters: SearchFilters(countries: "Индия")), "Country matching cannot confuse India IN with a substring of China")
        check(CatalogSearchPolicy.matches(anime, filters: SearchFilters(type: "ANIME", genres: "аниме")), "Japanese animation is recognized without an anime name tag")
        check(!CatalogSearchPolicy.matches(anime, filters: SearchFilters(type: "CARTOON")), "Animation and anime categories remain distinct")
        let sparseAnimation = MediaDto(originalId: .string("movie_3"), title: "Без жанров", type: "movie")
        check(CatalogSearchPolicy.matches(sparseAnimation, filters: SearchFilters(type: "CARTOON"), serverFiltered: true), "Base movie type cannot disprove server animation scope when genre metadata is omitted")
        check(!CatalogSearchPolicy.matches(sparseAnimation, filters: SearchFilters(type: "CARTOON")), "Unfiltered title results still need animation evidence")
        check(MediaDto(title: " ", originalTitle: "Original").displayTitle == "Original", "Blank translated title must not hide a valid original title in cards")
        let unknown = MediaDto(originalId: .string("kp_10"), title: "Нет метаданных")
        for filters in [SearchFilters(ratingFrom: 1), SearchFilters(yearFrom: 2020), SearchFilters(genres: "комедия"), SearchFilters(countries: "Россия"), SearchFilters(type: "TV_SERIES")] {
            check(!CatalogSearchPolicy.matches(unknown, filters: filters), "Missing search metadata cannot prove a selected constraint")
            check(CatalogSearchPolicy.matches(unknown, filters: filters, serverFiltered: true), "Server-filtered browse pages may omit filter metadata")
        }
        check(!CatalogSearchPolicy.matches(film, filters: SearchFilters(yearFrom: 2030), serverFiltered: true), "Known contradictory metadata is rejected even on browse pages")
        let normalized = SearchFilters(type: "movie", ratingFrom: 12, ratingTo: -1, yearFrom: 2026, yearTo: 1900, genres: "комедия,драма").normalized
        check(normalized.type == "FILM" && normalized.ratingFrom == 0 && normalized.ratingTo == 10 && normalized.yearFrom == 1900 && normalized.yearTo == 2026, "Normalize API type and malformed ranges")
        let chipFilters = SearchFilters(type: "FILM", ratingFrom: 7, yearFrom: 2026, yearTo: 2026, genres: "комедия", countries: "Россия")
        check(CatalogSearchFilter.year.label(in: chipFilters) == "2026", "Exact year is visible as a single-year constraint")
        let withoutYear = CatalogSearchFilter.year.removing(from: chipFilters)
        check(withoutYear.yearFrom == nil && withoutYear.yearTo == nil && withoutYear.type == "FILM" && withoutYear.ratingFrom == 7,
              "Removing a filter chip clears both bounds but preserves unrelated constraints")
        let encoded = CatalogSearchRequest.discoveryItems(filters: SearchFilters(ratingFrom: 7.5, yearFrom: 1900, yearTo: 2028, genres: "комедия,драма", countries: "США"), page: 0)
        let params = Dictionary(uniqueKeysWithValues: encoded.map { ($0.name, $0.value ?? "") })
        check(params["page"] == "1" && params["ratingFrom"] == "7.5" && params["yearTo"] == "2028", "Transport uses locale-independent decimals and both bounds")
        var components = URLComponents(string: "https://example.com/search")!
        components.percentEncodedQuery = CatalogSearchRequest.encodedQuery([URLQueryItem(name: "query", value: CatalogSearchQuery.text("Любовь & смерть + жизнь"))])
        check(components.percentEncodedQuery?.contains("%2B") == true && components.percentEncodedQuery?.contains("+") == false,
              "Literal plus is escaped for form-style server query parsers")
        check(URLComponents(url: components.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "Любовь & смерть + жизнь", "Reserved punctuation round-trips without corrupting the query")

        // Delayed transport deliberately ignores cancellation to test generation fencing.
        var pending: [String: CheckedContinuation<MediaResponse, Error>] = [:]
        let race = SearchViewModel(defaults: defaults, historyScope: "race", debounceNanoseconds: 0) { query, _, _ in
            try await withCheckedThrowingContinuation { pending[query] = $0 }
        }
        race.searchQuery = "old"
        await waitUntil { pending["old"] != nil }
        race.searchQuery = "new"
        await waitUntil { pending["new"] != nil }
        pending.removeValue(forKey: "new")!.resume(returning: MediaResponse(results: [series], pages: 1))
        await waitUntil { !race.isLoading }
        pending.removeValue(forKey: "old")!.resume(returning: MediaResponse(results: [film], pages: 9))
        for _ in 0..<20 { await Task.yield() }
        check(race.results.first?.artworkIdentifier == series.artworkIdentifier && race.totalPages == 1, "Late old responses cannot overwrite a newer query, flags or pagination")
        check(race.history.isEmpty, "Typing never records intermediate queries in history")
        race.rememberCurrentQuery()
        check(race.history == ["new"], "Opening/confirming explicitly records the query")
        race.searchQuery = ""
        check(race.results.isEmpty && !race.isLoading && !race.isAppending, "Clearing query invalidates results synchronously before debounce")

        var filteredPending: [String: CheckedContinuation<MediaResponse, Error>] = [:]
        let filterRace = SearchViewModel(defaults: defaults, historyScope: "filterRace", debounceNanoseconds: 0) { _, _, filters in
            try await withCheckedThrowingContinuation { filteredPending[filters.type ?? "all"] = $0 }
        }
        filterRace.searchQuery = "same"
        await waitUntil { filteredPending["all"] != nil }
        filterRace.searchFilters = SearchFilters(type: "TV_SERIES")
        await waitUntil { filteredPending["TV_SERIES"] != nil }
        filteredPending.removeValue(forKey: "TV_SERIES")!.resume(returning: MediaResponse(results: [series], pages: 1))
        await waitUntil { !filterRace.isLoading }
        filteredPending.removeValue(forKey: "all")!.resume(throwing: URLError(.timedOut))
        for _ in 0..<20 { await Task.yield() }
        check(filterRace.results.first?.artworkIdentifier == series.artworkIdentifier && filterRace.error == nil,
              "Late errors from old filters cannot erase filtered results or display a stale failure")
        filterRace.searchQuery = "pending"
        await waitUntil { filteredPending["TV_SERIES"] != nil }
        filterRace.searchQuery = ""; filterRace.searchFilters = SearchFilters()
        filteredPending.removeValue(forKey: "TV_SERIES")!.resume(returning: MediaResponse(results: [series], pages: 1))
        for _ in 0..<20 { await Task.yield() }
        check(filterRace.isDiscovery && filterRace.results.isEmpty && filterRace.error == nil,
              "Clearing all inputs fences an in-flight completion and returns to discovery")

        var requestedPages: [Int] = []
        var failPageTwo = true
        let paging = SearchViewModel(defaults: defaults, historyScope: "paging", debounceNanoseconds: 0) { _, page, _ in
            requestedPages.append(page)
            if page == 2 && failPageTwo { throw URLError(.notConnectedToInternet) }
            return MediaResponse(results: page == 1 ? [film] : [series, series], pages: 2)
        }
        paging.searchQuery = "Рейтинг"
        await paging.performSearch(reset: true)
        await paging.loadNextPage()
        check(paging.page == 1 && paging.error != nil && paging.results.count == 1, "A failed append retains content and cursor")
        failPageTwo = false
        await paging.retry()
        check(requestedPages == [1, 2, 2] && paging.page == 2 && paging.results.count == 2 && paging.error == nil, "Retry repeats failed page, never skips it or duplicates items")
        check(!paging.hasMore && !paging.isAppending, "Last page stops pagination")

        var scanned: [Int] = []
        let sparse = SearchViewModel(defaults: defaults, historyScope: "sparse", debounceNanoseconds: 0) { _, page, _ in
            scanned.append(page)
            return MediaResponse(results: page == 5 ? [film] : [], pages: 10)
        }
        sparse.searchFilters = SearchFilters(yearFrom: 2026)
        await sparse.performSearch(reset: true)
        check(scanned == [1, 2, 3, 4] && sparse.page == 4 && sparse.hasMore && sparse.results.isEmpty, "Bound empty-page scanning and retain explicit continuation")
        await sparse.loadNextPage()
        check(sparse.results.count == 1 && sparse.page == 5, "A matching title beyond the first empty pages is reachable")

        var queries: [String] = []
        let fallback = SearchViewModel(defaults: defaults, historyScope: "fallback", debounceNanoseconds: 0) { query, page, _ in
            queries.append(query)
            return MediaResponse(results: query == "привет" ? [film] : [], pages: query == "привет" ? 2 : 1)
        }
        fallback.searchQuery = "ghbdtn"
        await fallback.performSearch(reset: true)
        check(fallback.resolvedQuery == "привет" && fallback.results.count == 1, "Successful keyboard recovery is disclosed, original input retained")
        await fallback.loadNextPage()
        check(queries == ["ghbdtn", "привет", "привет"], "Pagination freezes the resolved query, never mixes spelling variants")
        var errors = 0
        let failing = SearchViewModel(defaults: defaults, historyScope: "fail", debounceNanoseconds: 0) { _, _, _ in
            errors += 1; throw URLError(.timedOut)
        }
        failing.searchQuery = "ghbdtn"
        await failing.performSearch(reset: true)
        check(errors == 1 && failing.error != nil && !failing.isLoading, "Network failure is not mistaken for an empty result or retried as a typo")

        var debounceCalls = 0
        let debounced = SearchViewModel(defaults: defaults, historyScope: "history", debounceNanoseconds: 60_000_000_000) { _, _, _ in
            debounceCalls += 1; return MediaResponse(results: [film], pages: 1)
        }
        for query in ["м", "ма", "мат", "матрица"] { debounced.searchQuery = query }
        for _ in 0..<10 { await Task.yield() }
        check(debounceCalls == 0 && debounced.history.isEmpty, "Debounce suppresses keystroke requests and history spam")
        await debounced.submit()
        check(debounceCalls == 1 && debounced.history == ["матрица"], "Submit bypasses debounce exactly once and commits history")
        for i in 0..<25 { debounced.searchQuery = "Запрос \(i)"; debounced.rememberCurrentQuery() }
        debounced.searchQuery = ""
        check(debounced.history.count == 20, "Bound and persist recent history")
        let other = SearchViewModel(defaults: defaults, historyScope: "other", loadPage: { _, _, _ in MediaResponse() })
        check(other.history.isEmpty, "Search history is account-isolated")
        debounced.clearHistory()
        check(defaults.stringArray(forKey: "catalog_search_history_v2_history") == [], "History deletion is durable")
        check(CatalogSearchPolicy.merge([film], [series], order: "RATING").first?.artworkIdentifier == series.artworkIdentifier, "Rating sorting is stable over all loaded pages")
        let titleItems = CatalogSearchRequest.items(query: "Матрица", filters: SearchFilters(type: "FILM", order: "RATING", yearTo: 2026, countries: "Россия", studio: "company:1"), page: 1)
        check(!titleItems.contains { $0.name == "order" || $0.name == "studio" }, "Title request never sends unsupported order or studio")
        check(titleItems.contains { $0.name == "countries" } && titleItems.contains { $0.name == "yearTo" }, "Title request sends structural filters to server")
        let cursorItems = CatalogSearchRequest.items(query: "", filters: SearchFilters(type: "ANIME"), page: 9, cursor: "a+b=/")
        check(cursorItems.contains { $0.name == "cursor" && $0.value == "a+b=/" } && !cursorItems.contains { $0.name == "page" }, "Cursor replaces page without dropping filters")
        let modern = try JSONDecoder().decode(MediaResponse.self, from: Data(#"{"results":[],"nextCursor":"next+1","query":{"raw":"матирца","resolved":"матрица","corrected":true,"correction":{"reason":"Опечатка"}},"meta":{"contractVersion":"2026-11-16","sortScope":"window","globalSort":false,"insufficientMetadata":2},"futureField":true}"#.utf8))
        check(modern.nextCursor == "next+1" && modern.meta?.sortScope == "window" && modern.query?.correction?.reason == "Опечатка", "Additive server search metadata decodes alongside unknown future fields")
        var cursorRequests: [String?] = []
        var failCursor = true
        let modernPaging = SearchViewModel(defaults: defaults, historyScope: "modernPaging", debounceNanoseconds: 0,
            cursorLoader: { _, _, _, cursor in
                cursorRequests.append(cursor)
                if cursor != nil && failCursor { throw URLError(.timedOut) }
                return MediaResponse(results: cursor == nil ? [film] : [series], pages: 2,
                    nextCursor: cursor == nil ? "next+1" : nil, meta: modern.meta)
            }, loadPage: { _, _, _ in throw CatalogSearchError.invalidResponse })
        modernPaging.searchFilters = SearchFilters(type: "ANIME", order: "RATING")
        await modernPaging.performSearch(reset: true)
        check(modernPaging.usesLocalSorting && modernPaging.nextCursor == "next+1", "Window scope disclosure comes from server metadata")
        await modernPaging.loadNextPage()
        check(modernPaging.page == 1 && modernPaging.nextCursor == "next+1", "Failed append retains opaque cursor")
        failCursor = false
        await modernPaging.retry()
        check(cursorRequests.count == 3 && cursorRequests[0] == nil && cursorRequests[1] == "next+1" && cursorRequests[2] == "next+1", "Cursor retry repeats exact continuation")
        check(modernPaging.results.map(\.artworkIdentifier) == [film.artworkIdentifier, series.artworkIdentifier], "Discovery keeps server order rather than reranking by client rating")
        var modernQueries: [String] = []
        let correctedSearch = SearchViewModel(defaults: defaults, historyScope: "modernCorrection", debounceNanoseconds: 0) { query, page, _ in
            modernQueries.append(query)
            return MediaResponse(results: page == 1 ? [film] : [series], pages: 2, query: page == 1 ? modern.query : nil, meta: modern.meta)
        }
        correctedSearch.searchQuery = "матирца"
        await correctedSearch.performSearch(reset: true)
        await correctedSearch.loadNextPage()
        check(modernQueries == ["матирца", "матрица"] && correctedSearch.originalQuery == "матирца" && correctedSearch.correctionReason == "Опечатка", "Server correction freezes resolved paging and retains original/reason on append")
        var noDoubleCorrectionCalls = 0
        let noDoubleCorrection = SearchViewModel(defaults: defaults, historyScope: "noDoubleCorrection", debounceNanoseconds: 0) { _, _, _ in
            noDoubleCorrectionCalls += 1
            return MediaResponse(results: [], pages: 1, query: modern.query, meta: modern.meta)
        }
        noDoubleCorrection.searchQuery = "ghbdtn"
        await noDoubleCorrection.performSearch(reset: true)
        check(noDoubleCorrectionCalls == 1, "Modern server responses never trigger a second local correction")
        let invalidSearch = SearchViewModel(defaults: defaults, historyScope: "invalidSearch", debounceNanoseconds: 0) { _, _, _ in
            throw CatalogServerError(code: "unknown_country", message: "technical internal details")
        }
        invalidSearch.searchQuery = "Фильм"
        await invalidSearch.performSearch(reset: true)
        check(invalidSearch.isInvalidRequest && invalidSearch.error?.contains("страну") == true, "Invalid parameter is an actionable error, not empty results or leaked diagnostics")
        var pendingSuggestions: [String: CheckedContinuation<[String], Error>] = [:]
        let suggested = SearchViewModel(defaults: defaults, historyScope: "suggestions", debounceNanoseconds: 0,
            suggestionsLoader: { query in
                try await withCheckedThrowingContinuation { pendingSuggestions[query] = $0 }
            }, loadPage: { _, _, _ in MediaResponse(results: [], pages: 1, meta: modern.meta) })
        suggested.searchQuery = "old suggestion"
        try await Task.sleep(nanoseconds: 350_000_000)
        await waitUntil { pendingSuggestions["old suggestion"] != nil }
        suggested.searchQuery = "new suggestion"
        try await Task.sleep(nanoseconds: 350_000_000)
        await waitUntil { pendingSuggestions["new suggestion"] != nil }
        pendingSuggestions.removeValue(forKey: "new suggestion")!.resume(returning: ["Новая подсказка", "Новая подсказка"])
        await waitUntil { !suggested.serverSuggestions.isEmpty }
        pendingSuggestions.removeValue(forKey: "old suggestion")!.resume(returning: ["Устаревшая подсказка"])
        for _ in 0..<20 { await Task.yield() }
        check(suggested.suggestions == ["Новая подсказка"], "Server suggestions deduplicate and fence stale completions")
        suggested.searchQuery = ""
        check(suggested.serverSuggestions.isEmpty, "Clearing input synchronously clears server suggestions")
        let source = try String(contentsOfFile: "sloosh/Sources/Data/Repositories/MoviesRepository.swift", encoding: .utf8)
        check(!source.contains("filteredResults = rawResults") && !source.contains("filteredResults = studioItems"), "Repository never restores unfiltered data when filters eliminate a page")
        let homeSource = try String(contentsOfFile: "sloosh/Sources/UI/Home/HomeView.swift", encoding: .utf8)
        check(homeSource.contains("if key.searchFilters.isEmpty, (cachedItems[key]"), "Home network recovery cannot show unfiltered cached shelves under selected filters")
        check(homeSource.contains("filter: key.filter, searchFilters: key.searchFilters"), "Home uses the captured filter snapshot instead of mutable selection state")
        print("PASS: \(count) production catalog search policy/state/transport-contract checks")
    }
}
