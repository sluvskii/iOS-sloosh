import SwiftUI
import Combine

struct SearchView: View {
    @StateObject private var viewModel = SearchViewModel(
        historyScope: AuthRepository.shared.currentUser?.id ?? "guest",
        cursorLoader: { query, page, filters, cursor in
            try await MoviesRepository.shared.searchMoviesResponse(query: query, page: page, filters: filters, cursor: cursor)
        },
        suggestionsLoader: { query in try await MoviesApi.shared.searchSuggestions(query: query) },
        diagnostic: { AppDiagnostics.shared.log($0) },
        loadPage: { query, page, filters in
            try await MoviesRepository.shared.searchMoviesResponse(query: query, page: page, filters: filters)
        }
    )
    @ObservedObject private var mediaOverrides = MediaOverridesRepository.shared
    @State private var pendingPlayerConfig: PlayerConfig? = nil
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
                if viewModel.isDiscovery {
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
                        if viewModel.isInvalidRequest {
                            Button("Изменить фильтры") { showFilters = true }
                        } else {
                        Button("Повторить") {
                            Task {
                                await viewModel.retry()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.slooshAccent)
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.results.isEmpty {
                    VStack(spacing: 16) {
                        SearchEmptyState(
                            icon: "magnifyingglass",
                            title: viewModel.hasMore ? "В этой части каталога совпадений нет" : "Ничего не найдено",
                            subtitle: viewModel.searchFilters.isEmpty ? "Проверьте название или выберите подсказку" : "Попробуйте убрать часть фильтров — они не сбрасываются автоматически"
                        )
                        if viewModel.hasMore {
                            Button("Продолжить поиск") { Task { await viewModel.loadNextPage() } }
                                .disabled(viewModel.isAppending)
                        }
                        if !viewModel.searchFilters.isEmpty {
                            Button("Сбросить фильтры") { viewModel.searchFilters = SearchFilters() }
                        }
                        if viewModel.isAppending { ProgressView() }
                    }
                } else {
                    ScrollView {
                        let spacing: CGFloat = cardDensity == .compact ? 8 : 16
                        let padding: CGFloat = cardDensity == .compact ? 12 : 16
                        LazyVGrid(columns: columns, spacing: spacing) {
                            ForEach(viewModel.results, id: \.artworkIdentifier) { movie in
                                MovieDetailsNavigationLink(movie: movie, navigationTransition: navigationTransition)
                                    .contextMenu {
                                        Group {
                                            Button {
                                                viewModel.directPlaybackMovie = movie
                                            } label: {
                                                Label("Смотреть", systemImage: "play.fill")
                                            }
                                            
                                            NavigationLink(destination: DetailsView(movieId: movie.id, mediaType: movie.type, navigationTransitionID: nil, navigationTransitionNamespace: nil).navigationBarBackButtonHidden(true)) {
                                                Label("Подробнее", systemImage: "info.circle")
                                            }
                                        }
                                        .tint(nil)
                                    }
                                    .simultaneousGesture(TapGesture().onEnded { viewModel.rememberCurrentQuery() })
                                    .onAppear {
                                        if movie.artworkIdentifier == viewModel.results.last?.artworkIdentifier {
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
                        paginationFooter
                            .padding(.horizontal, 16)
                            .padding(.bottom, 20)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .scrollEdgeEffectStyle(.soft, for: .bottom)
                    .refreshable {
                        await viewModel.performSearch(reset: true)
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $viewModel.searchQuery, prompt: "Название, оригинальное название…")
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .searchSuggestions {
                if !viewModel.serverSuggestions.isEmpty {
                    ForEach(viewModel.serverSuggestions) { suggestion in
                        if let movie = suggestion.movie {
                            NavigationLink(destination: DetailsView(movieId: movie.id, mediaType: movie.type, navigationTransitionID: nil, navigationTransitionNamespace: nil).navigationBarBackButtonHidden(true)) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(movie.displayTitle)
                                    Text([movie.year?.stringValue, movie.type == "tv" ? "Сериал" : "Фильм"].compactMap { $0 }.joined(separator: " · "))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .simultaneousGesture(TapGesture().onEnded { viewModel.rememberTitle(movie.displayTitle) })
                        } else {
                            Label(suggestion.title, systemImage: "magnifyingglass")
                                .searchCompletion(suggestion.title)
                        }
                    }
                } else {
                    ForEach(viewModel.suggestions, id: \.self) { suggestion in
                        Label(suggestion, systemImage: "magnifyingglass")
                            .searchCompletion(suggestion)
                    }
                }
            }
            .onSubmit(of: .search) { Task { await viewModel.submit() } }
            .safeAreaInset(edge: .top, spacing: 0) { searchContext }
            .task {
                if let items = try? await MoviesRepository.shared.getPopularMovies(page: 1) {
                    viewModel.setDiscoveryTitles(items.map(\.displayTitle))
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Поиск")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showFilters = true
                    } label: {
                        Image(systemName: viewModel.searchFilters.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                            .font(.system(size: 19))
                            .foregroundColor(.primary)
                            .glassForeground()
                    }
                }
            }
            .sheet(isPresented: $showFilters) {
                SearchFilterSheet(filters: $viewModel.searchFilters, context: .search)
            }
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
                    .preferredColorScheme(.dark)
                    .environment(\.colorScheme, .dark)
            }
        }
    }
    @ViewBuilder
    private var searchContext: some View {
        if !viewModel.isDiscovery {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if !viewModel.searchFilters.isEmpty {
                        Button { showFilters = true } label: {
                            Label("Фильтры: \(viewModel.searchFilters.activeCount)", systemImage: "line.3.horizontal.decrease")
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .glassEffect(.regular.interactive(), in: .capsule)
                        }
                        .buttonStyle(.plain)
                        Button("Сбросить") { viewModel.searchFilters = SearchFilters() }
                            .font(.subheadline)
                    }
                    Spacer()
                    if !viewModel.isLoading, !viewModel.results.isEmpty {
                        Text("Показано: \(viewModel.results.count)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !viewModel.searchFilters.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(CatalogSearchFilter.allCases) { field in
                                if let label = field.label(in: viewModel.searchFilters) {
                                    Button {
                                        viewModel.searchFilters = field.removing(from: viewModel.searchFilters)
                                    } label: {
                                        HStack(spacing: 6) {
                                            Text(label).lineLimit(1)
                                            Image(systemName: "xmark").font(.caption2.weight(.semibold))
                                        }
                                        .font(.caption.weight(.medium))
                                        .padding(.horizontal, 10).padding(.vertical, 7)
                                        .glassEffect(.regular.interactive(), in: .capsule)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Убрать фильтр: \(label)")
                                }
                            }
                        }
                    }
                }
                if viewModel.recoveredExactTitle {
                    Text("Найдено по точному названию").font(.caption).foregroundStyle(.secondary)
                }
                if let query = viewModel.resolvedQuery {
                    Text("Результаты для «\(query)»")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .accessibilityLabel("Уточнённый запрос: \(query)")
                }
                if let raw = viewModel.originalQuery, viewModel.resolvedQuery != nil {
                    Text("Исходный запрос: «\(raw)»").font(.caption).foregroundStyle(.secondary)
                }
                if let reason = viewModel.correctionReason {
                    Text(reason).font(.caption).foregroundStyle(.secondary)
                }
                if viewModel.insufficientMetadata > 0 {
                    Text("Часть карточек скрыта: недостаточно данных для проверки фильтров")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if viewModel.usesLocalSorting {
                    Text("Сортировка по загруженным результатам")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private var paginationFooter: some View {
        if let error = viewModel.error {
            VStack(spacing: 10) {
                Text(error).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if viewModel.isInvalidRequest {
                    Button("Обновить поиск") { Task { await viewModel.performSearch(reset: true) } }
                } else {
                    Button("Повторить загрузку") { Task { await viewModel.retry() } }
                }
            }
        } else if viewModel.hasMore && !viewModel.isAppending {
            Button("Показать ещё") { Task { await viewModel.loadNextPage() } }
        }
    }
}

struct SearchDiscoveryView: View {
    @ObservedObject var viewModel: SearchViewModel

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                FlowLayout(spacing: 8) {
                    Button("Фильмы") { viewModel.searchFilters = SearchFilters(type: "FILM") }
                    Button("Сериалы") { viewModel.searchFilters = SearchFilters(type: "TV_SERIES") }
                    Button("Новинки") {
                        viewModel.searchFilters = SearchFilters(order: "YEAR", yearFrom: Calendar.current.component(.year, from: Date()))
                    }
                }
                .buttonStyle(.bordered)
                .tint(.primary)
                .padding(.horizontal, 16)

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
                        
                        FlowLayout(spacing: 8) {
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
                                    .accessibilityLabel("Удалить запрос «\(query)» из истории")
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .glassEffect(.regular.interactive(), in: Capsule())
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }

                // 2. Popular Genres
                VStack(alignment: .leading, spacing: 14) {
                    Text("Жанры")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 16)
                    
                    FlowLayout(spacing: 8) {
                        ForEach([
                            "Боевик", "Комедия", "Драма", "Фантастика", "Триллер",
                            "Ужасы", "Детектив", "Мелодрама", "Приключения", "Фэнтези",
                            "Мультфильм", "Криминал", "Семейный", "Аниме"
                        ], id: \.self) { genre in
                            Button {
                                viewModel.searchFilters = SearchFilters(genres: genre.lowercased())
                            } label: {
                                Text(genre)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.primary)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 9)
                                    .glassEffect(.regular.interactive(), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                // 3. Studios and Networks
                VStack(alignment: .leading, spacing: 14) {
                    Text("Студии и стриминги")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 16)
                    
                    FlowLayout(spacing: 8) {
                        ForEach(StudioBrand.all) { brand in
                            Button {
                                viewModel.searchFilters = SearchFilters(studio: brand.id)
                            } label: {
                                Text(brand.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.primary)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 9)
                                    .glassEffect(.regular.interactive(), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
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
