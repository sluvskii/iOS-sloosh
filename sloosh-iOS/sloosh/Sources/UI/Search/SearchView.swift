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
            Group {
                if viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if viewModel.history.isEmpty {
                        SearchEmptyState(
                            icon: "magnifyingglass",
                            title: "Начните поиск",
                            subtitle: "Ищите фильмы и сериалы по названию"
                        )
                    } else {
                        List {
                            Section("Недавние запросы") {
                                ForEach(viewModel.history, id: \.self) { query in
                                    HStack(spacing: 12) {
                                        Image(systemName: "clock.arrow.circlepath")
                                            .foregroundColor(.secondary)

                                        Button {
                                            viewModel.selectHistory(query)
                                        } label: {
                                            Text(query)
                                                .foregroundColor(.primary)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .buttonStyle(.plain)

                                        Button {
                                            viewModel.removeHistory(query)
                                        } label: {
                                            Image(systemName: "xmark")
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundColor(.secondary)
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
                } else if viewModel.isLoading && viewModel.results.isEmpty {
                    ProgressView("Ищем...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.error, viewModel.results.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.system(size: 42))
                            .foregroundColor(.secondary)
                        Text(error)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                        Button("Повторить") {
                            Task {
                                await viewModel.retry()
                            }
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
                    ScrollView {
                        let spacing: CGFloat = cardDensity == .compact ? 8 : 16
                        let padding: CGFloat = cardDensity == .compact ? 12 : 16
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
                                            
                                            NavigationLink(destination: DetailsView(movieId: movie.id, navigationTransitionID: nil, navigationTransitionNamespace: nil)) {
                                                Label("Подробнее", systemImage: "info.circle")
                                            }
                                        }
                                        .tint(nil)
                                    }
                                    .onAppear {
                                        if movie.id == viewModel.results.last?.id {
                                            Task {
                                                await viewModel.loadNextPage()
                                            }
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

                        // Pagination buttons removed in favor of infinite scroll
                    }
                    .refreshable {
                        await viewModel.performSearch(reset: true)
                    }
                }
            }
            .navigationTitle("Поиск")
            .searchable(text: $viewModel.searchQuery, prompt: "Фильмы и сериалы...")
            .sheet(item: $viewModel.directPlaybackMovie) { movie in
                let kpId = movie.externalIds?.kp ?? Int(movie.id) ?? 0
                HomeDirectPlayWrapper(
                    kpId: kpId,
                    title: movie.title ?? movie.name ?? movie.originalTitle ?? ""
                ) { config in
                    viewModel.directPlaybackMovie = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        viewModel.playerConfig = config
                    }
                }
            }
            .fullScreenCover(item: $viewModel.playerConfig) { config in
                PlayerView(
                    iframeUrl: config.iframeUrl,
                    fallbackTitle: config.title,
                    kpId: config.kpId,
                    season: config.season,
                    episode: config.episode,
                    selectedVoiceover: config.voiceover,
                    directStreamUrl: config.streamUrl,
                    voices: config.voices,
                    subtitles: config.subtitles,
                    initialQuality: config.quality,
                    seriesResult: config.seriesResult
                )
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.history.isEmpty {
                        Button("Очистить") {
                            viewModel.clearHistory()
                        }
                    }
                    Button {
                        showFilters = true
                    } label: {
                        Image(systemName: viewModel.filters.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                            .foregroundColor(viewModel.filters.isEmpty ? .primary : Color.slooshAccent)
                    }
                }
            }
            .sheet(isPresented: $showFilters) {
                SearchFilterSheet(filters: $viewModel.filters)
            }
        }
    }
}

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
    @Published var playerConfig: PlayerConfig? = nil

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

    func selectHistory(_ query: String) {
        searchQuery = query
    }

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

    func setPage(_ newPage: Int) async {
        let clamped = max(1, min(newPage, max(totalPages, 1)))
        guard clamped != page else { return }
        page = clamped
        await performSearch(reset: true, saveHistory: false)
    }

    func retry() async {
        await performSearch(reset: results.isEmpty, saveHistory: false)
    }

    func performSearch(reset: Bool, saveHistory: Bool = true) async {
        searchTask?.cancel()

        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
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
                    if page == 1 {
                        results = []
                    }
                } else {
                    isAppending = true
                }
                error = nil

                let response = try await MoviesRepository.shared.searchMoviesResponse(query: trimmedQuery, page: page, filters: filters)
                if !Task.isCancelled {
                    let rawResults = response.results ?? []
                    // Filter invalid items like Android does
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
                        let uniqueItems = newResults.filter { !existing.contains($0.id) }
                        results.append(contentsOf: uniqueItems)
                    }

                    if saveHistory && !newResults.isEmpty && page == 1 {
                        updateHistory(with: trimmedQuery)
                    }
                }
            } catch {
                if !Task.isCancelled {
                    self.error = "Ошибка поиска: \(error.localizedDescription)"
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
