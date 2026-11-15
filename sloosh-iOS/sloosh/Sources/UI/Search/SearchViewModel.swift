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
    @Published private(set) var discoveryTitles: [String] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isAppending = false
    @Published private(set) var error: String?
    @Published private(set) var page = 0
    @Published private(set) var totalPages = 1
    @Published private(set) var resolvedQuery: String?
    @Published var directPlaybackMovie: MediaDto?
    @Published var playerConfig: PlayerConfig?

    private struct Request: Equatable {
        let query: String
        let filters: SearchFilters
    }
    private let loader: Loader
    private let defaults: UserDefaults
    private let historyKey: String
    private let debounceNanoseconds: UInt64
    private var task: Task<Void, Never>?
    private var generation = 0
    private var observedRequest: Request?
    private var cancellables = Set<AnyCancellable>()

    init(defaults: UserDefaults = .standard, historyScope: String, debounceNanoseconds: UInt64 = 300_000_000,
         loadPage: @escaping Loader) {
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
                self.observedRequest = request
                // Invalidate immediately, BEFORE debounce, so an older response
                // can never flash under a newly typed query or new filter chip.
                self.start(request: request, reset: true, delayed: true)
            }
            .store(in: &cancellables)
    }

    deinit { task?.cancel() }

    var isDiscovery: Bool { CatalogSearchQuery.text(searchQuery).isEmpty && searchFilters.normalized.isEmpty }
    var hasMore: Bool { !isDiscovery && page > 0 && page < totalPages }
    var suggestions: [String] {
        CatalogSearchQuery.suggestions(for: searchQuery,
                                       candidates: history + results.flatMap { [$0.title, $0.name, $0.originalTitle].compactMap { $0 } } + discoveryTitles)
    }
    var usesLocalSorting: Bool { !CatalogSearchQuery.text(searchQuery).isEmpty && searchFilters.order != nil }

    func setDiscoveryTitles(_ titles: [String]) {
        discoveryTitles = Array(titles.prefix(30))
    }

    func selectHistory(_ query: String) { searchQuery = query }

    func rememberCurrentQuery() {
        let query = CatalogSearchQuery.text(searchQuery)
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
            results = []; page = 0; totalPages = 1; resolvedQuery = nil
            isAppending = false
        } else if isLoading || isAppending { return task }
        error = nil
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
        let loader = self.loader
        task = Task { [weak self] in
            do {
                if delay > 0 { try await Task.sleep(nanoseconds: delay) }
                try Task.checkCancellation()
                var query = frozenQuery
                var nextPage = firstPage
                var response = try await loader(query, nextPage, request.filters)
                try Task.checkCancellation()
                if reset, request.filters.isEmpty, response.allItems.isEmpty, response.effectiveTotalPages <= 1 {
                    for alternative in CatalogSearchQuery.alternatives(request.query) {
                        let alternativeResponse = try await loader(alternative, 1, request.filters)
                        try Task.checkCancellation()
                        if !alternativeResponse.allItems.isEmpty {
                            query = alternative
                            response = alternativeResponse
                            break
                        }
                    }
                }
                // Local filters can produce empty pages while later pages match.
                // Scan a bounded window, then expose an explicit Continue action.
                var scanned = 1
                while response.allItems.isEmpty && nextPage < min(500, response.effectiveTotalPages) && scanned < 4 {
                    nextPage += 1; scanned += 1
                    response = try await loader(query, nextPage, request.filters)
                    try Task.checkCancellation()
                }
                guard let self, self.generation == token else { return }
                self.results = CatalogSearchPolicy.merge(reset ? [] : self.results, response.allItems, order: request.filters.order)
                self.page = nextPage
                self.totalPages = max(nextPage, min(500, response.effectiveTotalPages))
                self.resolvedQuery = query == request.query ? nil : query
                self.isLoading = false; self.isAppending = false
            } catch {
                guard !Task.isCancelled, let self, self.generation == token else { return }
                // Cursor advances ONLY on success. Retry repeats the failed page,
                // retaining all already displayed items and selected filters.
                self.error = (error as? LocalizedError)?.errorDescription
                    ?? "Не удалось загрузить результаты. Проверьте подключение и повторите попытку."
                self.isLoading = false; self.isAppending = false
            }
        }
        return task
    }

    private func persistHistory() { defaults.set(history, forKey: historyKey) }
}
