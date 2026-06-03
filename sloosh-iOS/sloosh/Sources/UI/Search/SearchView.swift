import SwiftUI

struct SearchView: View {
    @StateObject private var viewModel = SearchViewModel()

    private let columns = [
        GridItem(.adaptive(minimum: 120), spacing: 16)
    ]

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
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(viewModel.results) { movie in
                                NavigationLink(destination: DetailsView(movieId: movie.id)) {
                                    MoviePosterCard(movie: movie)
                                }
                                .buttonStyle(.plain)
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
                        .padding(16)

                        if viewModel.totalPages > 1 {
                            HStack(spacing: 12) {
                                Button("Назад") {
                                    Task {
                                        await viewModel.setPage(viewModel.page - 1)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(viewModel.page <= 1 || viewModel.isAppending || viewModel.isLoading)

                                Text("\(viewModel.page) / \(viewModel.totalPages)")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.secondary)

                                Button("Далее") {
                                    Task {
                                        await viewModel.setPage(viewModel.page + 1)
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(Color.slooshAccent)
                                .disabled(viewModel.page >= viewModel.totalPages || viewModel.isAppending || viewModel.isLoading)
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 24)
                        }
                    }
                }
            }
            .navigationTitle("Поиск")
            .searchable(text: $viewModel.searchQuery, prompt: "Фильмы и сериалы...")
            .onChange(of: viewModel.searchQuery) { _, newValue in
                Task {
                    await viewModel.setQuery(newValue)
                }
            }
            .toolbar {
                if viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.history.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Очистить") {
                            viewModel.clearHistory()
                        }
                    }
                }
            }
        }
    }
}

struct SearchEmptyState: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 42))
                .foregroundColor(.secondary)
            Text(title)
                .font(.system(size: 22, weight: .bold))
            Text(subtitle)
                .font(.system(size: 15, weight: .medium))
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private let historyKey = "search_history"
    private let maxHistory = 5
    private var searchTask: Task<Void, Never>?

    init() {
        loadHistory()
    }

    func setQuery(_ value: String) async {
        page = 1
        await performSearch(reset: true)
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
                if reset {
                    try await Task.sleep(nanoseconds: 300_000_000)
                }
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
