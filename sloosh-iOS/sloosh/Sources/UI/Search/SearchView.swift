import SwiftUI
import Combine

struct SearchView: View {
    @StateObject private var viewModel = SearchViewModel()
    @State private var showFilters = false
    @Namespace private var navigationTransition
    @AppStorage("cardDensity") private var cardDensity: CardDensity = .regular

    private var columns: [GridItem] {
        let spacing: CGFloat = cardDensity == .compact ? 8 : 16
        let minWidth: CGFloat = cardDensity == .compact ? 95 : 105
        return [GridItem(.adaptive(minimum: minWidth), spacing: spacing)]
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                // Main content
                contentArea
                    // top padding для floating search bar
                    .padding(.top, 60)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaBar(edge: .top) {
                floatingSearchBar
            }
            .sheet(item: $viewModel.directPlaybackMovie) { movie in
                HomeDirectPlayWrapper(
                    movieId: movie.id,
                    fallbackTitle: movie.title ?? movie.name ?? movie.originalTitle ?? "",
                    initialKpId: movie.externalIds?.kp
                )
            }
            .sheet(isPresented: $showFilters) {
                SearchFilterSheet(filters: $viewModel.filters)
            }
        }
    }

    // MARK: — Floating search bar

    private var floatingSearchBar: some View {
        HStack(spacing: 10) {
            // Search icon
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)

            // Text field
            TextField("Фильмы и сериалы...", text: $viewModel.searchQuery)
                .font(.system(size: 16))
                .autocorrectionDisabled()
                .submitLabel(.search)

            // Clear / Filters
            if !viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    viewModel.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }

            // History clear button
            if viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.history.isEmpty {
                Button("Очистить") {
                    viewModel.clearHistory()
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.slooshAccent)
                .transition(.opacity)
            }

            // Filters
            Button {
                showFilters = true
            } label: {
                Image(systemName: viewModel.filters.isEmpty
                      ? "line.3.horizontal.decrease.circle"
                      : "line.3.horizontal.decrease.circle.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(viewModel.filters.isEmpty ? .secondary : Color.slooshAccent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .glassEffect(.regular.interactive(), in: Capsule())
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: viewModel.searchQuery.isEmpty)
    }

    // MARK: — Content area

    @ViewBuilder
    private var contentArea: some View {
        let trimmed = viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            if viewModel.history.isEmpty {
                SearchEmptyState(
                    icon: "magnifyingglass",
                    title: "Начните поиск",
                    subtitle: "Ищите фильмы и сериалы по названию"
                )
            } else {
                historyList
            }
        } else if viewModel.isLoading && viewModel.results.isEmpty {
            ProgressView("Ищем...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.error, viewModel.results.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 42))
                    .foregroundStyle(.secondary)
                Text(error)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Повторить") {
                    Task { await viewModel.retry() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.slooshAccent)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.results.isEmpty {
            SearchEmptyState(
                icon: "film",
                title: "Ничего не найдено",
                subtitle: "Попробуйте изменить запрос"
            )
        } else {
            resultsGrid
        }
    }

    // MARK: — History list

    private var historyList: some View {
        List {
            Section("Недавние запросы") {
                ForEach(viewModel.history, id: \.self) { query in
                    HStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(.secondary)

                        Button {
                            viewModel.selectHistory(query)
                        } label: {
                            Text(query)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)

                        Button {
                            viewModel.removeHistory(query)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 24, height: 24)
                                .glassEffect(in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: — Results grid

    private var resultsGrid: some View {
        let spacing: CGFloat = cardDensity == .compact ? 8 : 16
        let padding: CGFloat = cardDensity == .compact ? 12 : 16

        return ScrollView {
            LazyVGrid(columns: columns, spacing: spacing) {
                ForEach(viewModel.results) { movie in
                    MovieDetailsNavigationLink(movie: movie, navigationTransition: navigationTransition)
                        .contextMenu {
                            Group {
                                Button {
                                    viewModel.directPlaybackMovie = movie
                                } label: {
                                    Label("Смотреть", systemImage: "play.fill")
                                }

                                NavigationLink(destination: DetailsView(
                                    movieId: movie.id,
                                    navigationTransitionID: nil,
                                    navigationTransitionNamespace: nil
                                )) {
                                    Label("Подробнее", systemImage: "info.circle")
                                }
                            }
                            .tint(nil)
                        }
                        .onAppear {
                            if movie.id == viewModel.results.last?.id {
                                Task { await viewModel.loadNextPage() }
                            }
                        }
                }

                if viewModel.isAppending {
                    ForEach(0..<3, id: \.self) { _ in
                        MoviePosterCardPlaceholder()
                    }
                }
            }
            .padding(padding)
        }
        .refreshable {
            await viewModel.performSearch(reset: true)
        }
    }
}

// MARK: — Empty state

struct SearchEmptyState: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        AppEmptyStateView(
            icon: icon,
            title: title,
            description: subtitle
        )
    }
}

// MARK: — ViewModel

@MainActor
class SearchViewModel: ObservableObject {
    @Published var searchQuery = ""
    @Published var filters = SearchFilters()
    @Published var results: [MediaDto] = []
    @Published var history: [String] = []
    @Published var isLoading = false
    @Published var isAppending = false
    @Published var error: String?
    @Published var page = 1
    @Published var totalPages = 1
    @Published var directPlaybackMovie: MediaDto? = nil

    private let historyKey = "search_history"
    private let maxHistory = 5
    private var searchTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init() {
        loadHistory()

        $searchQuery
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self = self else { return }
                Task {
                    self.page = 1
                    await self.performSearch(reset: true)
                }
            }
            .store(in: &cancellables)

        $filters
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self = self else { return }
                Task {
                    self.page = 1
                    await self.performSearch(reset: true)
                }
            }
            .store(in: &cancellables)
    }

    func selectHistory(_ query: String) { searchQuery = query }

    func removeHistory(_ query: String) {
        history.removeAll { $0 == query }
        persistHistory()
    }

    func clearHistory() {
        history = []
        persistHistory()
    }

    func loadNextPage() async {
        guard !isLoading, !isAppending, page < totalPages else { return }
        page += 1
        await performSearch(reset: false)
    }

    func retry() async {
        await performSearch(reset: results.isEmpty, saveHistory: false)
    }

    func performSearch(reset: Bool, saveHistory: Bool = true) async {
        searchTask?.cancel()

        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            error = nil
            isLoading = false
            isAppending = false
            totalPages = 1
            page = 1
            return
        }

        searchTask = Task {
            do {
                if Task.isCancelled { return }

                if reset {
                    isLoading = true
                    if page == 1 { results = [] }
                } else {
                    isAppending = true
                }
                error = nil

                let response = try await MoviesRepository.shared.searchMoviesResponse(
                    query: trimmed, page: page, filters: filters
                )
                if !Task.isCancelled {
                    let rawResults = response.results ?? []
                    let newResults = rawResults.filter { item in
                        let poster = item.posterUrl ?? item.poster_path ?? ""
                        let hasPoster = !poster.isEmpty && !poster.lowercased().contains("no-poster")
                        let hasTitle = !(item.title ?? item.name ?? "").isEmpty
                        let hasRating = (item.rating ?? 0) > 0.0
                        return hasPoster && hasTitle && hasRating
                    }

                    totalPages = max(response.effectiveTotalPages, 1)
                    if page <= 1 || reset {
                        results = newResults
                    } else {
                        let existing = Set(results.map(\.id))
                        let unique = newResults.filter { !existing.contains($0.id) }
                        results.append(contentsOf: unique)
                    }

                    if saveHistory && !newResults.isEmpty && page == 1 {
                        updateHistory(with: trimmed)
                    }
                }
            } catch {
                if !Task.isCancelled {
                    if let localized = error as? LocalizedError, let desc = localized.errorDescription {
                        self.error = desc
                    } else {
                        self.error = "Нет подключения к интернету"
                    }
                }
            }

            if !Task.isCancelled {
                isLoading = false
                isAppending = false
            }
        }
    }

    private func loadHistory() {
        let raw = UserDefaults.standard.string(forKey: historyKey) ?? ""
        history = raw
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func updateHistory(with query: String) {
        history = ([query] + history.filter { $0 != query }).prefix(maxHistory).map { $0 }
        persistHistory()
    }

    private func persistHistory() {
        UserDefaults.standard.set(history.joined(separator: "\n"), forKey: historyKey)
    }
}
