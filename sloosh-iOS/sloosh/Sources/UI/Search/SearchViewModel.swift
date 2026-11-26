import Foundation
import Combine

/// All mutations and the generation check are on one actor. Cancellation alone
/// is insufficient: transports are allowed to complete after cancellation.
@MainActor
final class SearchViewModel: ObservableObject {
    typealias Loader = (String, Int, SearchFilters) async throws -> MediaResponse

    @Published var searchQuery = ""
    @Published var searchFilters = SearchFilters()
    @Published private(set) var results: [MediaDto] = []
    @Published private(set) var history: [String] = []
    @Published private(set) var discoveryMovies: [MediaDto] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isAppending = false
    @Published private(set) var error: String?
    @Published private(set) var isInvalidRequest = false
    @Published private(set) var page = 0
    @Published private(set) var totalPages = 1
    @Published private(set) var resolvedQuery: String?
    @Published private(set) var nextCursor: String?
    @Published private(set) var sortScope: String?
    @Published private(set) var correctionReason: String?
    @Published private(set) var originalQuery: String?
    @Published private(set) var insufficientMetadata = 0
    @Published private(set) var serverSuggestions: [CatalogSearchSuggestion] = []
    @Published var suggestionDestination: CatalogSearchDestination?
    @Published var directPlaybackMovie: MediaDto?
    @Published var playerConfig: PlayerConfig?

    private struct Request: Equatable {
        let query: String
        let filters: SearchFilters
    }
    typealias CursorLoader = (String, Int, SearchFilters, String?) async throws -> MediaResponse
    typealias SuggestionsLoader = (String) async throws -> [CatalogSearchSuggestion]
    private let diagnostic: (String) -> Void
    private var observedCards: [MediaDto] = []
    @Published private(set) var recoveredExactTitle = false
    private let cursorLoader: CursorLoader?
    private let suggestionsLoader: SuggestionsLoader?
    private var suggestionsTask: Task<Void, Never>?
    private var suggestionFetchTask: Task<[CatalogSearchSuggestion], Error>?
    private var suggestionFetchQuery = ""
    private var suggestionFetchGeneration = 0
    private var suggestionFetchDate = Date.distantPast
    private var suggestionGeneration = 0
    private let loader: Loader
    private let defaults: UserDefaults
    private let historyKey: String
    private let debounceNanoseconds: UInt64
    private var task: Task<Void, Never>?
    private var generation = 0
    private var observedRequest: Request?
    private var activeFilters: SearchFilters = SearchFilters()
    private var cancellables = Set<AnyCancellable>()

    init(defaults: UserDefaults = .standard, historyScope: String, debounceNanoseconds: UInt64 = 300_000_000,
         cursorLoader: CursorLoader? = nil, suggestionsLoader: SuggestionsLoader? = nil,
         diagnostic: @escaping (String) -> Void = { _ in },
         loadPage: @escaping Loader) {
        self.diagnostic = diagnostic
        self.cursorLoader = cursorLoader
        self.suggestionsLoader = suggestionsLoader
        self.loader = loadPage
        self.defaults = defaults
        self.historyKey = "catalog_search_history_v2_\(historyScope)"
        self.debounceNanoseconds = debounceNanoseconds
        let stored = defaults.stringArray(forKey: historyKey) ?? []
        var seen = Set<String>()
        history = stored.map(CatalogSearchQuery.text).filter {
            !$0.isEmpty && seen.insert(CatalogSearchQuery.key($0)).inserted
        }.prefix(20).map { $0 }
        Publishers.CombineLatest($searchQuery, $searchFilters)
            .sink { [weak self] query, filters in
                guard let self else { return }
                let request = Request(query: CatalogSearchQuery.text(query), filters: filters.normalized)
                guard request != self.observedRequest else { return }
                self.refreshSuggestions(request.query)
                self.observedRequest = request
                // Invalidate immediately, BEFORE debounce, so an older response
                // can never flash under a newly typed query or new filter chip.
                self.start(request: request, reset: true, delayed: true)
            }
            .store(in: &cancellables)
    }

    deinit { task?.cancel(); suggestionsTask?.cancel(); suggestionFetchTask?.cancel() }

    var isDiscovery: Bool { CatalogSearchQuery.text(searchQuery).isEmpty && searchFilters.normalized.isEmpty }
    var hasMore: Bool { !isDiscovery && page > 0 && (nextCursor != nil || page < totalPages) }
    var catalogSuggestions: [CatalogSearchSuggestion] {
        let local = (Array(results.prefix(60)) + discoveryMovies + observedCards).map { CatalogSearchSuggestion(movie: $0) }
        return CatalogSearchSuggestion.catalogHits(serverSuggestions + local, query: searchQuery)
    }

    /// Text completions are explicitly labeled as history, never film matches.
    var historySuggestions: [String] {
        CatalogSearchQuery.suggestions(for: searchQuery, candidates: history)
    }
    var usesLocalSorting: Bool { !CatalogSearchQuery.text(searchQuery).isEmpty && searchFilters.order != nil || sortScope == "window" }

    func setDiscoveryMovies(_ movies: [MediaDto]) {
        discoveryMovies = Array(CatalogSearchPolicy.merge([], movies, order: nil).filter { CatalogSearchDestination($0) != nil }.prefix(30))
        rememberCards(discoveryMovies)
    }

    func openSuggestion(_ movie: MediaDto) {
        guard let destination = CatalogSearchDestination(movie) else { return }
        rememberTitle(movie.displayTitle)
        // Opening a known project is navigation, NOT query completion. Do not
        // mutate searchQuery, start a search or replace an existing result page.
        suggestionDestination = destination
        diagnostic("[CatalogSearch] open_suggestion typed=true")
    }

    func selectHistory(_ query: String) { searchQuery = query }

    func rememberCurrentQuery() { rememberTitle(searchQuery) }

    func rememberTitle(_ title: String) {
        let query = CatalogSearchQuery.text(title)
        guard !query.isEmpty else { return }
        let key = CatalogSearchQuery.key(query)
        history = Array(([query] + history.filter { CatalogSearchQuery.key($0) != key }).prefix(20))
        persistHistory()
    }

    func removeHistory(_ query: String) {
        history.removeAll { $0 == query }
        persistHistory()
    }

    func clearHistory() { history = []; persistHistory() }

    func submit() async {
        rememberCurrentQuery()
        await performSearch(reset: true)
    }

    func performSearch(reset: Bool, saveHistory: Bool = false) async {
        if saveHistory { rememberCurrentQuery() }
        let request = Request(query: CatalogSearchQuery.text(searchQuery), filters: searchFilters.normalized)
        observedRequest = request
        start(request: request, reset: reset, delayed: false)
        await task?.value
    }

    func loadNextPage() async {
        guard hasMore, !isLoading, !isAppending else { return }
        await performSearch(reset: false)
    }

    func retry() async {
        if page == 0 { await performSearch(reset: true) }
        else { await loadNextPage() }
    }

    @discardableResult
    private func start(request: Request, reset: Bool, delayed: Bool) -> Task<Void, Never>? {
        if reset {
            generation += 1
            task?.cancel()
            let filtersChanged = request.filters != activeFilters
            let preserveResultsWhileTyping = delayed && !request.query.isEmpty && !filtersChanged && !results.isEmpty
            activeFilters = request.filters
            if !preserveResultsWhileTyping {
                results = []
                resolvedQuery = nil
                recoveredExactTitle = false
                nextCursor = nil
                sortScope = nil
                correctionReason = nil
                originalQuery = nil
                insufficientMetadata = 0
            }
            page = 0; totalPages = 1
            isAppending = false
        } else if isLoading || isAppending { return task }
        error = nil
        isInvalidRequest = false
        guard !request.query.isEmpty || !request.filters.isEmpty else {
            isLoading = false; isAppending = false
            task = nil
            return nil
        }
        let token = generation
        if reset { isLoading = true } else { isAppending = true }
        let firstPage = reset ? 1 : page + 1
        let frozenQuery = resolvedQuery ?? request.query
        let delay = delayed ? debounceNanoseconds : 0
        let legacyLoader = self.loader
        let cursorLoader = self.cursorLoader
        let initialCursor = reset ? nil : nextCursor
        let diagnostic = self.diagnostic
        let suggestionsLoader = self.suggestionsLoader
        let knownCards = observedCards
        diagnostic("[CatalogSearch] start generation=\(token) chars=\(request.query.count) filters=\(request.filters.activeCount) page=\(firstPage) cursor=\(initialCursor != nil)")
        let loader: CursorLoader = { query, page, filters, cursor in
            if let cursorLoader { return try await cursorLoader(query, page, filters, cursor) }
            return try await legacyLoader(query, page, filters)
        }
        task = Task { [weak self] in
            do {
                if delay > 0 { try await Task.sleep(nanoseconds: delay) }
                try Task.checkCancellation()
                var query = frozenQuery
                var nextPage = firstPage
                var cursor = initialCursor
                var response = try await loader(query, nextPage, request.filters, cursor)
                var queryInfo = response.query
                if response.query?.corrected == true, let resolved = response.query?.resolved { query = resolved }
                try Task.checkCancellation()
                if reset, response.meta?.contractVersion == nil, response.query?.corrected != true, request.filters.isEmpty, response.allItems.isEmpty, response.effectiveTotalPages <= 1 {
                    for alternative in CatalogSearchQuery.alternatives(request.query) {
                        let alternativeResponse = try await loader(alternative, 1, request.filters, nil)
                        try Task.checkCancellation()
                        if !alternativeResponse.allItems.isEmpty {
                            query = alternative
                            response = alternativeResponse
                            break
                        }
                    }
                }
                // A suggestion dictionary can know a real typed title which the
                // upstream text endpoint fails to return for its full spelling.
                // Reconcile ONLY exact identities, after a terminal successful
                // empty answer, without filters, correction, or extra pages.
                var recovered = false
                if reset, !request.query.isEmpty, request.filters.isEmpty,
                   response.query?.corrected != true, response.allItems.isEmpty,
                   response.nextCursor == nil, response.effectiveTotalPages <= 1 {
                    var exact = CatalogExactTitleRecovery.matches(request.query, in: knownCards)
                    if exact.isEmpty, let suggestionsLoader {
                        do {
                            guard let self else { return }
                            let suggestions = try await self.fetchSuggestions(request.query, using: suggestionsLoader)
                            try Task.checkCancellation()
                            exact = CatalogExactTitleRecovery.matches(request.query, in: suggestions.compactMap(\.movie))
                        } catch {
                            try Task.checkCancellation()
                            // Suggestion failure cannot change a successful empty
                            // title answer into an invented match or a spelling retry.
                            diagnostic("[CatalogSearch] exact_recovery suggestions_unavailable generation=\(token)")
                        }
                    }
                    if !exact.isEmpty {
                        response = MediaResponse(page: 1, results: exact, pages: 1)
                        recovered = true
                    }
                }
                // Server post-filtering can leave empty pages with later matches.
                // Scan a bounded window, then expose an explicit Continue action.
                var scanned = 1
                while response.allItems.isEmpty && nextPage < 500 && (response.nextCursor != nil || nextPage < response.effectiveTotalPages) && scanned < 4 {
                    nextPage += 1; scanned += 1
                    cursor = response.nextCursor
                    response = try await loader(query, nextPage, request.filters, cursor)
                    if queryInfo == nil { queryInfo = response.query }
                    try Task.checkCancellation()
                }
                guard let self, self.generation == token else { return }
                self.results = CatalogSearchPolicy.merge(reset ? [] : self.results, response.allItems, order: request.query.isEmpty ? nil : request.filters.order)
                self.rememberCards(response.allItems)
                if reset { self.recoveredExactTitle = recovered }
                diagnostic("[CatalogSearch] applied generation=\(token) received=\(response.allItems.count) displayed=\(self.results.count) page=\(nextPage) exact_recovery=\(recovered) corrected=\(queryInfo?.corrected == true)")
                self.nextCursor = response.nextCursor
                self.sortScope = response.meta?.sortScope
                if reset || queryInfo?.corrected == true {
                    self.correctionReason = queryInfo?.correction?.reason
                    self.originalQuery = queryInfo?.raw
                }
                self.insufficientMetadata = response.meta?.insufficientMetadata ?? 0
                self.page = nextPage
                self.totalPages = max(nextPage, min(500, response.effectiveTotalPages))
                self.resolvedQuery = query == request.query ? nil : query
                self.isLoading = false; self.isAppending = false
            } catch {
                guard !Task.isCancelled, let self, self.generation == token else { return }
                // Cursor advances ONLY on success. Retry repeats the failed page,
                // retaining all already displayed items and selected filters.
                diagnostic("[CatalogSearch] failure generation=\(token) invalid_request=\(error is CatalogServerError)")
                self.isInvalidRequest = error is CatalogServerError
                self.error = (error as? LocalizedError)?.errorDescription
                    ?? "Не удалось загрузить результаты. Проверьте подключение и повторите попытку."
                self.isLoading = false; self.isAppending = false
            }
        }
        return task
    }

    private func refreshSuggestions(_ query: String) {
        suggestionGeneration += 1
        let token = suggestionGeneration
        suggestionsTask?.cancel()
        if query != suggestionFetchQuery {
            suggestionFetchTask?.cancel()
            suggestionFetchGeneration += 1
            suggestionFetchTask = nil
            suggestionFetchQuery = query
        }
        serverSuggestions = []
        guard CatalogSearchQuery.text(query).count >= 2, let suggestionsLoader else { return }
        suggestionsTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 300_000_000)
                try Task.checkCancellation()
                guard let self else { return }
                let suggestions = try await self.fetchSuggestions(query, using: suggestionsLoader)
                try Task.checkCancellation()
                guard self.suggestionGeneration == token else { return }
                self.serverSuggestions = Array(CatalogSearchSuggestion.unique(suggestions).filter {
                    $0.movie.flatMap(CatalogSearchDestination.init) != nil
                }.prefix(8))
                self.rememberCards(self.serverSuggestions.compactMap(\.movie))
                self.diagnostic("[CatalogSearch] suggestions generation=\(token) chars=\(query.count) count=\(self.serverSuggestions.count) typed=\(self.serverSuggestions.filter { $0.movie != nil }.count)")
            } catch {
                // Suggestions never block typing/search. Local history remains available.
                guard !Task.isCancelled, let self, self.suggestionGeneration == token else { return }
                self.serverSuggestions = []
            }
        }
    }

    private func fetchSuggestions(_ query: String, using loader: @escaping SuggestionsLoader) async throws -> [CatalogSearchSuggestion] {
        try Task.checkCancellation()
        if query == suggestionFetchQuery, let pending = suggestionFetchTask,
           Date().timeIntervalSince(suggestionFetchDate) < 30 {
            return try await pending.value
        }
        suggestionFetchQuery = query
        suggestionFetchDate = Date()
        suggestionFetchGeneration += 1
        let token = suggestionFetchGeneration
        let pending = Task { try await loader(query) }
        suggestionFetchTask = pending
        do { return try await pending.value }
        catch {
            if suggestionFetchGeneration == token { suggestionFetchTask = nil }
            throw error
        }
    }

    private func rememberCards(_ cards: [MediaDto]) {
        // Session/account-local and bounded. A new search can match an observed
        // full title without depending on which server isolate receives it next.
        observedCards = Array(CatalogSearchPolicy.merge(cards, observedCards, order: nil).prefix(120))
    }

    private func persistHistory() { defaults.set(history, forKey: historyKey) }
}
