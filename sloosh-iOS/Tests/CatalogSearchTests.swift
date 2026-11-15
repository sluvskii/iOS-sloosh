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
        check(CatalogSearchPolicy.matches(anime, filters: SearchFilters(type: "ANIME", genres: "аниме")), "Japanese animation is recognized without an anime name tag")
        check(!CatalogSearchPolicy.matches(anime, filters: SearchFilters(type: "CARTOON")), "Animation and anime categories remain distinct")
        let unknown = MediaDto(originalId: .string("kp_10"), title: "Нет метаданных")
        for filters in [SearchFilters(ratingFrom: 1), SearchFilters(yearFrom: 2020), SearchFilters(genres: "комедия"), SearchFilters(countries: "Россия"), SearchFilters(type: "TV_SERIES")] {
            check(!CatalogSearchPolicy.matches(unknown, filters: filters), "Missing search metadata cannot prove a selected constraint")
            check(CatalogSearchPolicy.matches(unknown, filters: filters, serverFiltered: true), "Server-filtered browse pages may omit filter metadata")
        }
        check(!CatalogSearchPolicy.matches(film, filters: SearchFilters(yearFrom: 2030), serverFiltered: true), "Known contradictory metadata is rejected even on browse pages")
        let normalized = SearchFilters(type: "movie", ratingFrom: 12, ratingTo: -1, yearFrom: 2026, yearTo: 1900, genres: "комедия,драма").normalized
        check(normalized.type == "FILM" && normalized.ratingFrom == 0 && normalized.ratingTo == 10 && normalized.yearFrom == 1900 && normalized.yearTo == 2026, "Normalize API type and malformed ranges")
        let encoded = CatalogSearchRequest.discoveryItems(filters: SearchFilters(ratingFrom: 7.5, yearFrom: 1900, yearTo: 2028, genres: "комедия,драма", countries: "США"), page: 0)
        let params = Dictionary(uniqueKeysWithValues: encoded.map { ($0.name, $0.value ?? "") })
        check(params["page"] == "1" && params["ratingFrom"] == "7.5" && params["yearTo"] == "2028", "Transport uses locale-independent decimals and both bounds")
        var components = URLComponents(string: "https://example.com/search")!
        components.queryItems = [URLQueryItem(name: "query", value: CatalogSearchQuery.text("Любовь & смерть + жизнь"))]
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
        let source = try String(contentsOfFile: "sloosh/Sources/Data/Repositories/MoviesRepository.swift", encoding: .utf8)
        check(!source.contains("filteredResults = rawResults") && !source.contains("filteredResults = studioItems"), "Repository never restores unfiltered data when filters eliminate a page")
        print("PASS: \(count) production catalog search policy/state/transport-contract checks")
    }
}
