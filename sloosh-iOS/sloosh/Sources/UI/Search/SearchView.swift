import SwiftUI
import UIKit
import Combine

private enum SearchScreenState: Equatable {
    case discovery
    case skeleton
    case error
    case empty
    case results
}

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
    @State private var isSearchPresented = false
    @State private var scrollOffset: CGFloat = 0
    @Namespace private var navigationTransition
    @AppStorage("cardDensity") private var cardDensity: CardDensity = .regular

    private var hasSearchContextChrome: Bool {
        !viewModel.isDiscovery && (!viewModel.searchFilters.isEmpty || viewModel.resolvedQuery != nil)
    }

    private var topBlurOpacity: Double {
        min(1.0, Double(max(0, scrollOffset) / 28.0))
    }

    private var columns: [GridItem] {
        let spacing: CGFloat = cardDensity == .compact ? 8 : 16
        let minWidth: CGFloat = cardDensity == .compact ? 95 : 105
        return [GridItem(.adaptive(minimum: minWidth), spacing: spacing)]
    }

    private var screenState: SearchScreenState {
        if viewModel.isDiscovery { return .discovery }
        if viewModel.isLoading && viewModel.results.isEmpty { return .skeleton }
        if viewModel.error != nil && viewModel.results.isEmpty { return .error }
        if viewModel.results.isEmpty { return .empty }
        return .results
    }

    var body: some View {
        NavigationStack {
            ZStack {
                switch screenState {
                case .discovery:
                    SearchDiscoveryView(
                        viewModel: viewModel,
                        navigationTransition: navigationTransition,
                        scrollOffset: $scrollOffset
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.99)))

                case .skeleton:
                    skeletonGrid
                        .transition(.opacity)

                case .error:
                    errorView
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))

                case .empty:
                    emptyView
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))

                case .results:
                    resultsGrid
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .top) {
                if !hasSearchContextChrome {
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                        .background(
                            VariableBlurView(tintColor: Color(UIColor.systemBackground), tintOpacity: 0.92)
                                .ignoresSafeArea(edges: .top)
                        )
                        .opacity(topBlurOpacity)
                        .animation(.easeInOut(duration: 0.2), value: topBlurOpacity)
                        .allowsHitTesting(false)
                }
            }
            .animation(.spring(response: 0.34, dampingFraction: 0.88), value: screenState)
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: viewModel.searchFilters)
            .onChange(of: screenState) { _, _ in
                scrollOffset = 0
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $viewModel.searchQuery, isPresented: $isSearchPresented, prompt: "Фильмы и сериалы")
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .onSubmit(of: .search) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                isSearchPresented = false
                Task { await viewModel.submit() }
            }
            .navigationDestination(item: $viewModel.suggestionDestination) { destination in
                DetailsView(movieId: destination.movieId, mediaType: destination.mediaType, navigationTransitionID: nil, navigationTransitionNamespace: nil)
                    .navigationBarBackButtonHidden(true)
            }
            .safeAreaInset(edge: .top, spacing: 0) { searchContext }
            .task {
                guard viewModel.discoveryMovies.isEmpty else { return }
                viewModel.setDiscoveryLoading(true)
                if let trending = try? await MoviesRepository.shared.getTrending(page: 1), !trending.isEmpty {
                    viewModel.setDiscoveryMovies(trending)
                } else if let popular = try? await MoviesRepository.shared.getPopularMovies(page: 1) {
                    viewModel.setDiscoveryMovies(popular)
                } else {
                    viewModel.setDiscoveryLoading(false)
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Поиск")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 10) {
                        if viewModel.isLoading && !viewModel.results.isEmpty {
                            ProgressView()
                                .controlSize(.small)
                                .transition(.scale.combined(with: .opacity))
                        }

                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            showFilters = true
                        } label: {
                            let hasFilters = !viewModel.searchFilters.isEmpty
                            Image(systemName: hasFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(hasFilters ? Color.slooshAccent : Color.primary)
                                .glassForeground(isEnabled: GlassForegroundAppearance.shouldBlend(tint: hasFilters ? Color.slooshAccent : .primary))
                        }
                        .accessibilityLabel("Фильтры")
                    }
                    .animation(.easeInOut(duration: 0.2), value: viewModel.isLoading)
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

    // MARK: - Substates

    private var skeletonGrid: some View {
        ScrollView(showsIndicators: false) {
            let spacing: CGFloat = cardDensity == .compact ? 8 : 16
            let padding: CGFloat = cardDensity == .compact ? 12 : 16
            LazyVGrid(columns: columns, spacing: spacing) {
                ForEach(0..<12, id: \.self) { _ in
                    MoviePosterCardPlaceholder()
                }
            }
            .padding(padding)
        }
        .scrollDisabled(true)
        .scrollEdgeEffectStyle(.soft, for: .all)
    }

    private var resultsGrid: some View {
        ScrollView {
            let spacing: CGFloat = cardDensity == .compact ? 8 : 16
            let padding: CGFloat = cardDensity == .compact ? 12 : 16
            LazyVGrid(columns: columns, spacing: spacing) {
                ForEach(Array(viewModel.results.enumerated()), id: \.element.artworkIdentifier) { index, movie in
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
                            let threshold = max(0, viewModel.results.count - 4)
                            if index >= threshold {
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
            .opacity(viewModel.isLoading ? 0.65 : 1.0)
            .animation(.easeInOut(duration: 0.18), value: viewModel.isLoading)

            paginationFooter
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollEdgeEffectStyle(.soft, for: .all)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, newOffset in
            scrollOffset = newOffset
        }
        .refreshable {
            await viewModel.performSearch(reset: true)
        }
    }

    private var errorView: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(.secondary)
            Text(viewModel.error ?? "Не удалось загрузить результаты")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 280)
            if viewModel.isInvalidRequest {
                Button("Изменить фильтры") { showFilters = true }
                    .buttonStyle(.bordered)
                    .tint(Color.slooshAccent)
            } else {
                Button("Повторить") {
                    Task { await viewModel.retry() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.slooshAccent)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            SearchEmptyState(
                icon: "magnifyingglass",
                title: "Ничего не найдено",
                subtitle: viewModel.searchFilters.isEmpty
                    ? "Проверьте написание названия или попробуйте другое слово"
                    : "Попробуйте изменить или сбросить выбранные фильтры"
            )
            if !viewModel.searchFilters.isEmpty {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        viewModel.searchFilters = SearchFilters()
                    }
                } label: {
                    Text("Сбросить фильтры")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .glassForeground()
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .glassEffect(.regular.interactive(), in: Capsule())
                }
                .buttonStyle(.glassPress)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var searchContext: some View {
        let hasFilters = !viewModel.searchFilters.isEmpty
        let hasCorrection = viewModel.resolvedQuery != nil
        if !viewModel.isDiscovery && (hasFilters || hasCorrection) {
            VStack(alignment: .leading, spacing: 2) {
                if hasFilters {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(CatalogSearchFilter.allCases) { field in
                                if let label = field.label(in: viewModel.searchFilters) {
                                    Button {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                            viewModel.searchFilters = field.removing(from: viewModel.searchFilters)
                                        }
                                    } label: {
                                        HStack(spacing: 5) {
                                            Text(label)
                                                .lineLimit(1)
                                            Image(systemName: "xmark")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundStyle(.secondary)
                                        }
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.primary)
                                        .glassForeground()
                                        .padding(.horizontal, 11)
                                        .padding(.vertical, 6)
                                        .contentShape(.capsule)
                                        .glassEffect(.regular.interactive(), in: .capsule)
                                    }
                                    .buttonStyle(.glassPress)
                                    .accessibilityLabel("Убрать фильтр: \(label)")
                                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                                }
                            }

                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                                    viewModel.searchFilters = SearchFilters()
                                }
                            } label: {
                                Text("Сбросить")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color.slooshAccent)
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 6)
                                    .contentShape(.capsule)
                                    .glassEffect(.regular.interactive(), in: .capsule)
                            }
                            .buttonStyle(.glassPress)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                    }
                    .scrollClipDisabled()
                }

                if let resolved = viewModel.resolvedQuery {
                    Text("Показано для «\(resolved)»")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.top, hasFilters ? 0 : 4)
                        .accessibilityLabel("Уточнённый запрос: \(resolved)")
                }
            }
            .padding(.top, 0)
            .padding(.bottom, 6)
            .background(
                VariableBlurView(tintColor: Color(UIColor.systemBackground), tintOpacity: 0.95)
                    .padding(.bottom, -24)
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)
            )
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var paginationFooter: some View {
        if let error = viewModel.error {
            VStack(spacing: 10) {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Повторить загрузку") {
                    Task { await viewModel.retry() }
                }
                .buttonStyle(.bordered)
                .tint(Color.slooshAccent)
            }
            .padding(.top, 8)
        } else if viewModel.hasMore && !viewModel.isAppending {
            Button {
                Task { await viewModel.loadNextPage() }
            } label: {
                Text("Показать ещё")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .glassForeground()
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .glassEffect(.regular.interactive(), in: Capsule())
            }
            .buttonStyle(.glassPress)
            .padding(.top, 6)
        }
    }
}

// MARK: - Discovery Showcase

struct SearchDiscoveryView: View {
    @ObservedObject var viewModel: SearchViewModel
    let navigationTransition: Namespace.ID
    @Binding var scrollOffset: CGFloat

    private struct GenreTile: Identifiable {
        let name: String
        let icon: String
        var id: String { name }
    }

    private let genreTiles: [GenreTile] = [
        GenreTile(name: "Боевик", icon: "bolt.fill"),
        GenreTile(name: "Комедия", icon: "face.smiling.fill"),
        GenreTile(name: "Драма", icon: "theatermasks.fill"),
        GenreTile(name: "Фантастика", icon: "sparkles"),
        GenreTile(name: "Триллер", icon: "eye.fill"),
        GenreTile(name: "Ужасы", icon: "moon.stars.fill"),
        GenreTile(name: "Детектив", icon: "magnifyingglass"),
        GenreTile(name: "Мелодрама", icon: "heart.fill"),
        GenreTile(name: "Приключения", icon: "map.fill"),
        GenreTile(name: "Фэнтези", icon: "wand.and.stars"),
        GenreTile(name: "Мультфильм", icon: "paintpalette.fill"),
        GenreTile(name: "Криминал", icon: "flame.fill"),
        GenreTile(name: "Семейный", icon: "figure.2.and.child.holdinghands"),
        GenreTile(name: "Аниме", icon: "star.fill")
    ]

    private let tileColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                // 1. Recent queries (single horizontal row, never a wall of pills)
                if !viewModel.history.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Недавние")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.primary)
                            Spacer()
                            Button("Очистить") {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                                    viewModel.clearHistory()
                                }
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.slooshAccent)
                        }
                        .padding(.horizontal, 16)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(viewModel.history, id: \.self) { query in
                                    HStack(spacing: 7) {
                                        Button {
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                            viewModel.selectHistory(query)
                                        } label: {
                                            HStack(spacing: 6) {
                                                Image(systemName: "clock")
                                                    .font(.system(size: 12, weight: .semibold))
                                                    .foregroundStyle(.secondary)
                                                Text(query)
                                                    .font(.system(size: 14, weight: .medium))
                                                    .foregroundStyle(.primary)
                                                    .lineLimit(1)
                                            }
                                        }
                                        .buttonStyle(.glassPress)

                                        Button {
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                                viewModel.removeHistory(query)
                                            }
                                        } label: {
                                            Image(systemName: "xmark")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundStyle(.secondary)
                                                .padding(2)
                                        }
                                        .buttonStyle(.glassPress)
                                        .accessibilityLabel("Удалить запрос «\(query)» из истории")
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .contentShape(Capsule())
                                    .glassEffect(.regular.interactive(), in: Capsule())
                                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        }
                        .scrollClipDisabled()
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // 2. Trending Cinema Carousel
                if viewModel.isDiscoveryLoading || !viewModel.discoveryMovies.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Сейчас в тренде")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 16)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 12) {
                                if viewModel.discoveryMovies.isEmpty {
                                    ForEach(0..<5, id: \.self) { _ in
                                        MoviePosterCardPlaceholder()
                                            .frame(width: 122)
                                    }
                                } else {
                                    ForEach(viewModel.discoveryMovies.prefix(15), id: \.artworkIdentifier) { movie in
                                        MovieDetailsNavigationLink(movie: movie, navigationTransition: navigationTransition)
                                            .frame(width: 122)
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
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                        }
                        .scrollClipDisabled()
                    }
                }

                // 3. Genres 2-Column Cinema Tiles
                VStack(alignment: .leading, spacing: 8) {
                    Text("Жанры")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 16)

                    LazyVGrid(columns: tileColumns, spacing: 10) {
                        ForEach(genreTiles) { tile in
                            NavigationLink(destination: GenreCatalogView(genre: tile.name)) {
                                HStack(spacing: 8) {
                                    Image(systemName: tile.icon)
                                        .font(.system(size: 13.5, weight: .semibold))
                                        .foregroundStyle(Color.slooshAccent)
                                        .frame(width: 28, height: 28)
                                        .background(Color.slooshAccent.opacity(0.14), in: Circle())

                                    Text(tile.name)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.84)
                                        .allowsTightening(true)

                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.glassPress)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }

                // 4. Studios and Streaming Services Horizontal Rail
                VStack(alignment: .leading, spacing: 4) {
                    Text("Студии и стриминги")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 16)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(StudioBrand.all) { brand in
                                NavigationLink(destination: StudioCatalogView(studioId: brand.id, studioName: brand.name)) {
                                    HStack(spacing: 9) {
                                        Image(systemName: brand.isNetwork ? "play.tv.fill" : "film.stack.fill")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(Color.slooshAccent)

                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(brand.name)
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundStyle(.primary)
                                                .lineLimit(1)
                                            Text(brand.isNetwork ? "Стриминг" : "Студия")
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 11)
                                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                                .buttonStyle(.glassPress)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .scrollClipDisabled()
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollEdgeEffectStyle(.soft, for: .all)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, newOffset in
            scrollOffset = newOffset
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
