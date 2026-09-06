import SwiftUI
import Combine

struct SearchView: View {
    @StateObject private var viewModel = SearchViewModel()
    @State private var pendingPlayerConfig: PlayerConfig? = nil
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
                    SearchDiscoveryView(viewModel: viewModel)
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
                                            
                                            NavigationLink(destination: DetailsView(movieId: movie.id, navigationTransitionID: nil, navigationTransitionNamespace: nil).navigationBarBackButtonHidden(true)) {
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
                    }
                    .refreshable {
                        await viewModel.performSearch(reset: true)
                    }
                }
            }
            .navigationTitle("Поиск")
            .searchable(text: $viewModel.searchQuery, prompt: "Фильмы и сериалы...")
            .sheet(item: $viewModel.directPlaybackMovie, onDismiss: {
                if let pending = pendingPlayerConfig {
                    pendingPlayerConfig = nil
                    DispatchQueue.main.async {
                        viewModel.playerConfig = pending
                    }
                }
            }) { movie in
                HomeDirectPlayWrapper(
                    movieId: movie.id,
                    fallbackTitle: movie.title ?? movie.name ?? movie.originalTitle ?? "",
                    initialKpId: movie.externalIds?.kp
                ) { config in
                    pendingPlayerConfig = config
                    viewModel.directPlaybackMovie = nil
                }
            }
            .fullScreenCover(item: $viewModel.playerConfig, onDismiss: {
                viewModel.playerConfig = nil
            }) { config in
                PlayerView(config: config)
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.history.isEmpty {
                        Button("Очистить") {
                            viewModel.clearHistory()
                        }
                    }
                }
            }
        }
    }
}

struct SearchDiscoveryView: View {
    @ObservedObject var viewModel: SearchViewModel

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                // 1. History
                if !viewModel.history.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Недавние запросы")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.secondary)
                            Spacer()
                            Button("Очистить") {
                                viewModel.clearHistory()
                            }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.slooshAccent)
                        }
                        .padding(.horizontal, 16)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(viewModel.history, id: \.self) { query in
                                    HStack(spacing: 8) {
                                        Button {
                                            viewModel.selectHistory(query)
                                        } label: {
                                            Text(query)
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundColor(.primary)
                                        }
                                        .buttonStyle(.plain)
                                        
                                        Button {
                                            viewModel.removeHistory(query)
                                        } label: {
                                            Image(systemName: "xmark")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundColor(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .glassEffect(.regular.interactive(), in: Capsule())
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                }

                // 2. Studios and Networks
                VStack(alignment: .leading, spacing: 14) {
                    Text("Студии и стриминги")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 16)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHGrid(rows: [GridItem(.fixed(48)), GridItem(.fixed(48))], spacing: 10) {
                            ForEach(StudioBrand.all) { brand in
                                NavigationLink(destination: StudioCatalogView(studioId: brand.id, studioName: brand.name)) {
                                    HStack(spacing: 10) {
                                        Image(systemName: brand.systemIcon)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(brand.accentColor)
                                            .frame(width: 22, height: 22)
                                        
                                        Text(brand.name)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(.primary)
                                    }
                                    .padding(.horizontal, 14)
                                    .frame(height: 48)
                                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                
                // 3. Quick hint when history is empty
                if viewModel.history.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "sparkle.magnifyingglass")
                            .font(.system(size: 34))
                            .foregroundColor(.secondary.opacity(0.6))
                            .padding(.bottom, 2)
                        Text("Быстрый поиск")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                        Text("Ищите фильмы, сериалы или выбирайте студии выше")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 28)
                    .padding(.horizontal, 24)
                }
            }
            .padding(.vertical, 16)
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

                let response = try await MoviesRepository.shared.searchMoviesResponse(query: trimmedQuery, page: page)
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
