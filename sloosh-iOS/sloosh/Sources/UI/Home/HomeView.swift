import SwiftUI
import UIKit

enum HomeCategory: String, CaseIterable {
    case all = "Все"
    case movies = "Фильмы"
    case tvShows = "Сериалы"
    case cartoons = "Мультфильмы"

    var title: String { rawValue }

    var segmentedTitle: String {
        switch self {
        case .all:
            return "Все"
        case .movies:
            return "Фильмы"
        case .tvShows:
            return "Сериалы"
        case .cartoons:
            return "Мульты"
        }
    }
}

enum HomeFilter: String, CaseIterable, Identifiable {
    case popular = "Смотрят сейчас"
    case topRated = "По рейтингу"

    var id: String { rawValue }

    var title: String { rawValue }
    
    var icon: String {
        switch self {
        case .popular: return "flame"
        case .topRated: return "star"
        }
    }
}

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @Namespace private var navigationTransition
    @State private var isFilterCollapsed = false

    var body: some View {
        NavigationStack {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(HomeCategory.allCases, id: \.self) { category in
                        HomeCategoryContentView(
                            viewModel: viewModel,
                            category: category,
                            navigationTransition: navigationTransition,
                            isFilterCollapsed: $isFilterCollapsed
                        )
                        .containerRelativeFrame(.horizontal)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: Binding(
                get: { viewModel.selectedCategory },
                set: { newValue in
                    if let newValue = newValue {
                        viewModel.selectedCategory = newValue
                    }
                }
            ))
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                HomeCategoryTextTabs(
                    selectedCategory: $viewModel.selectedCategory,
                    selectedFilter: $viewModel.selectedFilter,
                    isFilterCollapsed: $isFilterCollapsed
                )
                .padding(.top, 4)
                .padding(.bottom, 2) // Уменьшенный отступ до контента
                // Уменьшен tintOpacity, чтобы через блюр пробивались цвета постеров.
                // Это необходимо, чтобы наш Vibrant-текст мог их впитывать!
                .background(
                    VariableBlurView(tintOpacity: 0.75)
                        .padding(.bottom, -30) // Увеличиваем длину размытия вниз, но не так сильно
                        .ignoresSafeArea(edges: .top)
                )
            }
            .task {
                await viewModel.applyCurrentSelection()
            }
            .onChange(of: viewModel.selectedCategory) { _, _ in
                isFilterCollapsed = false
                Task { await viewModel.applyCurrentSelection() }
            }
            .onChange(of: viewModel.selectedFilter) { _, _ in
                isFilterCollapsed = false
                Task { await viewModel.applyCurrentSelection() }
            }
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
        }
    }
}

class ScrollDebouncer {
    var lastStateChangeTime: Date = Date.distantPast
    let debounceInterval: TimeInterval = 0.4 // Matches animation duration
}

struct HomeCategoryContentView: View {
    @ObservedObject var viewModel: HomeViewModel
    let category: HomeCategory
    let navigationTransition: Namespace.ID
    @Binding var isFilterCollapsed: Bool

    @State private var debouncer = ScrollDebouncer()
    @AppStorage("cardDensity") private var cardDensity: CardDensity = .regular

    private var columns: [GridItem] {
        let spacing: CGFloat = cardDensity == .compact ? 8 : 16
        let minWidth: CGFloat = cardDensity == .compact ? 95 : 105
        return [GridItem(.adaptive(minimum: minWidth), spacing: spacing)]
    }

    var body: some View {
        let key = HomeCacheKey(category: category, filter: viewModel.selectedFilter)
        let items = viewModel.cachedItems[key]
        let isLoading = viewModel.isLoading[key] ?? false
        let isLoadingMore = viewModel.isLoadingMore[key] ?? false

        ScrollViewReader { proxy in
            ScrollView {
                let spacing: CGFloat = cardDensity == .compact ? 8 : 16
                let padding: CGFloat = cardDensity == .compact ? 12 : 16

                // Invisible anchor used to scroll-to-top on tab switch
                Color.clear.frame(height: 0).id("home-scroll-top")

                if isLoading || items == nil {
                    LazyVGrid(columns: columns, spacing: spacing) {
                        ForEach(0..<12, id: \.self) { _ in
                            MoviePosterCardPlaceholder()
                        }
                    }
                    .padding(.horizontal, padding)
                    .padding(.bottom, padding)
                } else if let items = items, items.isEmpty {
                    HomeEmptyState(
                        category: category,
                        filter: viewModel.selectedFilter
                    )
                    .frame(maxWidth: .infinity, minHeight: 300)
                    .padding(.horizontal, 20)
                } else if let items = items {
                    LazyVGrid(columns: columns, spacing: spacing) {
                        ForEach(items) { movie in
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
                                if movie.id == items.last?.id {
                                    Task { await viewModel.loadData(for: category) }
                                }
                            }
                        }

                        if isLoadingMore {
                            ForEach(0..<3, id: \.self) { _ in
                                MoviePosterCardPlaceholder()
                            }
                        }
                    }
                    .padding(.horizontal, padding)
                    .padding(.bottom, padding)
                }
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { oldOffset, newOffset in
                let now = Date()
                guard now.timeIntervalSince(debouncer.lastStateChangeTime) > debouncer.debounceInterval else { return }
                let delta = newOffset - oldOffset
                if newOffset <= 0 {
                    if isFilterCollapsed {
                        isFilterCollapsed = false
                        debouncer.lastStateChangeTime = now
                    }
                } else if delta > 8 {
                    if !isFilterCollapsed {
                        isFilterCollapsed = true
                        debouncer.lastStateChangeTime = now
                    }
                } else if delta < -8 {
                    if isFilterCollapsed {
                        isFilterCollapsed = false
                        debouncer.lastStateChangeTime = now
                    }
                }
            }
            .scrollIndicators(.hidden)
            .refreshable {
                await viewModel.applyCurrentSelection(force: true)
            }
        }
    }
}

struct MovieDetailsNavigationLink<Label: View>: View {
    let movieId: String
    let transitionID: String
    let navigationTransition: Namespace.ID
    @ViewBuilder let label: () -> Label

    init(movieId: String, transitionID: String? = nil, navigationTransition: Namespace.ID, @ViewBuilder label: @escaping () -> Label) {
        self.movieId = movieId
        self.transitionID = transitionID ?? "movie-card-\(movieId)"
        self.navigationTransition = navigationTransition
        self.label = label
    }

    init(movie: MediaDto, navigationTransition: Namespace.ID) where Label == MoviePosterCard {
        self.init(movieId: movie.id, navigationTransition: navigationTransition) {
            MoviePosterCard(movie: movie)
        }
    }

    var body: some View {
        NavigationLink(
            destination: DetailsView(
                movieId: movieId,
                navigationTransitionID: transitionID,
                navigationTransitionNamespace: navigationTransition
            )
        ) {
            label()
                .matchedTransitionSource(id: transitionID, in: navigationTransition)
        }
        .buttonStyle(.plain)
    }
}

private struct TabScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

private struct HomeCategoryTextTabs: View {
    @Binding var selectedCategory: HomeCategory
    @Binding var selectedFilter: HomeFilter
    @Binding var isFilterCollapsed: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .headline) private var titleSize: CGFloat = 28 // Увеличенный размер шрифта

    private let titleHeight: CGFloat = 36 // Увеличена высота под новый размер

    private var tabSpacing: CGFloat {
        horizontalSizeClass == .regular ? 20 : 16
    }

    private var edgeContentInset: CGFloat {
        horizontalSizeClass == .regular ? 18 : 16
    }

    private var tabScrollAnimation: Animation {
        .spring(response: 0.35, dampingFraction: 0.75, blendDuration: 0.1)
    }

    private func layeredText(
        _ text: String,
        size: CGFloat,
        weight: Font.Weight,
        isSelected: Bool
    ) -> some View {
        let isDark = colorScheme == .dark
        
        // Для активного таба непрозрачность выше (0.9/0.8), для неактивного ниже (0.45/0.4)
        let opacity = isSelected ? (isDark ? 0.9 : 0.8) : (isDark ? 0.45 : 0.4)
        let color = isDark ? Color.white.opacity(opacity) : Color.black.opacity(opacity)
        
        // Для темной темы .plusLighter (сложение), для светлой .plusDarker (умножение)
        let blendMode: BlendMode = isDark ? .plusLighter : .plusDarker
        
        return Text(text)
            .font(.system(size: size, weight: weight))
            .tracking(-0.8)
            .foregroundStyle(color)
            .blendMode(blendMode)
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: tabSpacing) {
                    ForEach(Array(HomeCategory.allCases.enumerated()), id: \.element) { index, category in
                        let isSelected = selectedCategory == category
                        let isFirst = index == 0
                        let isLast = index == HomeCategory.allCases.count - 1

                        Button {
                            withAnimation(tabScrollAnimation) {
                                isFilterCollapsed = false

                                guard !isSelected else { return }
                                selectedCategory = category
                            }
                        } label: {
                            layeredText(
                                category.segmentedTitle,
                                size: titleSize,
                                weight: isSelected ? .bold : .semibold,
                                isSelected: isSelected
                            )
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(height: titleHeight, alignment: .center)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(TabScaleButtonStyle())
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .id(category)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        .accessibilityHint("Нажмите для перехода. Удерживайте для выбора фильтра.")
                        .padding(.leading, isFirst ? edgeContentInset : 0)
                        .padding(.trailing, isLast ? edgeContentInset : 0)
                        .contextMenu {
                            ForEach(HomeFilter.allCases) { filter in
                                Button {
                                    withAnimation(tabScrollAnimation) {
                                        isFilterCollapsed = false
                                        selectedCategory = category
                                        selectedFilter = filter
                                    }
                                } label: {
                                    if selectedCategory == category && selectedFilter == filter {
                                        Label(filter.title, systemImage: "checkmark")
                                    } else {
                                        Label(filter.title, systemImage: filter.icon)
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .scrollTargetLayout()
            }
            .frame(height: titleHeight + 4, alignment: .topLeading)
            .scrollClipDisabled()
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .animation(tabScrollAnimation, value: selectedCategory)
            .animation(tabScrollAnimation, value: isFilterCollapsed)
            .onAppear {
                scrollProxy.scrollTo(selectedCategory, anchor: .center)
            }
            .onChange(of: selectedCategory) { _, newCategory in
                withAnimation(tabScrollAnimation) {
                    scrollProxy.scrollTo(newCategory, anchor: .center)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selectedCategory)
        .sensoryFeedback(.selection, trigger: selectedFilter)
    }
}

private struct HomeEmptyState: View {
    let category: HomeCategory
    let filter: HomeFilter

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "film.stack")
                .font(.system(size: 44))
                .foregroundColor(.secondary)

            Text("Ничего не найдено")
                .font(.system(size: 22, weight: .bold))

            Text("Попробуйте выбрать другую вкладку или сменить фильтрацию с `\(filter.title)` на другой режим.")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .glassEffect(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

struct RemotePosterView<Overlay: View>: View {
    let url: URL?
    var cornerRadius: CGFloat = 12
    @Binding var isLoading: Bool
    let overlay: () -> Overlay
    
    init(url: URL?, cornerRadius: CGFloat = 12, isLoading: Binding<Bool> = .constant(false), @ViewBuilder overlay: @escaping () -> Overlay) {
        self.url = url
        self.cornerRadius = cornerRadius
        self._isLoading = isLoading
        self.overlay = overlay
    }
    
    var body: some View {
        AsyncCachedImage(url: url, isExternalLoading: $isLoading) {
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .aspectRatio(2/3, contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .shimmer()
        } content: { image in
            Image(uiImage: image)
                .resizable()
                .aspectRatio(2/3, contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } fallback: {
            FallbackPosterView(cornerRadius: cornerRadius)
        }
        .overlay {
            overlay()
        }
    }
}

extension RemotePosterView where Overlay == EmptyView {
    init(url: URL?, cornerRadius: CGFloat = 12, isLoading: Binding<Bool> = .constant(false)) {
        self.url = url
        self.cornerRadius = cornerRadius
        self._isLoading = isLoading
        self.overlay = { EmptyView() }
    }
}

struct MoviePosterCard: View {
    let movie: MediaDto
    @AppStorage("cardStyle") private var cardStyle: CardStyle = .classic

    var body: some View {
        switch cardStyle {
        case .classic:
            classicBody
        case .overlay:
            overlayBody
        }
    }

    private var classicBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            let url = URL(string: movie.displayPosterUrl ?? "")
            
            ZStack(alignment: .topLeading) {
                RemotePosterView(url: url)
                
                if let rating = movie.rating, rating > 0 {
                    Text(String(format: "%.1f", rating))
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(Color.rating(rating))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .padding(8)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(movie.displayTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .tracking(-0.3)
                    .allowsTightening(true)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
                    .foregroundColor(.primary)

                let yearStr = movie.year?.stringValue
                let genreStr = movie.genres?.first?.name?.capitalized
                
                if let y = yearStr, let g = genreStr {
                    Text("\(y) • \(g)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else if let y = yearStr {
                    Text(y)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else if let g = genreStr {
                    Text(g)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else {
                    Text(" ")
                        .font(.system(size: 12))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 2)
        }
    }

    private var overlayBody: some View {
        RemotePosterView(url: URL(string: movie.displayPosterUrl ?? ""), cornerRadius: 16) {
            ZStack(alignment: .bottomLeading) {
                // Progressive blur at the bottom of the card
                Rectangle()
                    .fill(.regularMaterial)
                    .padding(.horizontal, -2)
                    .padding(.bottom, -2)
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.3),
                                .init(color: .black, location: 0.9)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // Metadata inside the poster
                VStack(alignment: .leading, spacing: 1) {
                    Text(movie.displayTitle)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(movie.displayTitle.contains(" ") ? 2 : 1)
                        .tracking(-0.3)
                        .allowsTightening(true)
                        .multilineTextAlignment(.leading)
                    
                    let yearStr = movie.year?.stringValue
                    let genreStr = movie.genres?.first?.name?.capitalized
                    
                    if let y = yearStr, let g = genreStr {
                        Text("\(y) • \(g)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    } else if let y = yearStr {
                        Text(y)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    } else if let g = genreStr {
                        Text(g)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
                
                // Rating overlay on top-left of the poster
                if let rating = movie.rating, rating > 0 {
                    VStack {
                        HStack {
                            Text(String(format: "%.1f", rating))
                                .font(.system(size: 12, weight: .heavy))
                                .foregroundColor(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 3)
                                .background(Color.rating(rating))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .padding(8)
                            Spacer()
                        }
                        Spacer()
                    }
                }
            }
            .environment(\.colorScheme, .dark)
        }
        .aspectRatio(2/3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct FallbackPosterView: View {
    var cornerRadius: CGFloat = 12
    
    var body: some View {
        ZStack {
            Color.clear
            Image(systemName: "film.fill")
                .font(.system(size: 30))
                .foregroundColor(.secondary.opacity(0.65))
        }
        .aspectRatio(2/3, contentMode: .fill)
        .glassEffect(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct MoviePosterCardPlaceholder: View {
    @AppStorage("cardStyle") private var cardStyle: CardStyle = .classic
    
    var body: some View {
        switch cardStyle {
        case .classic:
            VStack(alignment: .leading, spacing: 8) {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .aspectRatio(2/3, contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shimmer()
                
                VStack(alignment: .leading, spacing: 4) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 14)
                        .cornerRadius(4)
                        .shimmer()
                        
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 50, height: 14)
                        .cornerRadius(4)
                        .shimmer()
                }
            }
        case .overlay:
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .aspectRatio(2/3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shimmer()
        }
    }
}

struct HomeCacheKey: Hashable {
    let category: HomeCategory
    let filter: HomeFilter
}

@MainActor
class HomeViewModel: ObservableObject {
    @Published var selectedCategory: HomeCategory = .all
    @Published var selectedFilter: HomeFilter = .popular
    
    @Published var cachedItems: [HomeCacheKey: [MediaDto]] = [:]
    @Published var isLoading: [HomeCacheKey: Bool] = [:]
    @Published var isLoadingMore: [HomeCacheKey: Bool] = [:]
    
    @Published var directPlaybackMovie: MediaDto? = nil
    @Published var playerConfig: PlayerConfig? = nil

    private var cachedPages: [HomeCacheKey: Int] = [:]
    private var cachedCanLoadMore: [HomeCacheKey: Bool] = [:]
    private var hasPerformedInitialLoad = false

    func applyCurrentSelection(force: Bool = false) async {
        let key = HomeCacheKey(category: selectedCategory, filter: selectedFilter)

        if force {
            cachedItems[key] = nil
            cachedPages[key] = 1
            cachedCanLoadMore[key] = true
        } else if !hasPerformedInitialLoad {
            hasPerformedInitialLoad = true
        } else if let cached = cachedItems[key], !cached.isEmpty {
            return
        }

        await loadData(for: selectedCategory)
    }

    func loadData(for category: HomeCategory? = nil) async {
        let cat = category ?? selectedCategory
        let key = HomeCacheKey(category: cat, filter: selectedFilter)

        let currentCanLoadMore = cachedCanLoadMore[key] ?? true
        guard currentCanLoadMore else { return }

        let isCurrentlyLoading = isLoading[key] ?? false
        let isCurrentlyLoadingMore = isLoadingMore[key] ?? false
        guard !isCurrentlyLoading, !isCurrentlyLoadingMore else { return }

        let existingItems = cachedItems[key] ?? []
        if existingItems.isEmpty {
            isLoading[key] = true
        } else {
            isLoadingMore[key] = true
        }

        defer {
            isLoading[key] = false
            isLoadingMore[key] = false
        }

        do {
            var newItems: [MediaDto] = []
            var pagesFetched = 0
            var page = cachedPages[key] ?? 1
            var canLoad = currentCanLoadMore

            while newItems.isEmpty && pagesFetched < 3 && canLoad {
                let fetched = try await fetchPage(page, category: cat, filter: selectedFilter)
                if fetched.isEmpty {
                    canLoad = false
                    break
                }

                let validFetched = filterValidItems(fetched)
                newItems.append(contentsOf: filterItemsForSelectedCategory(validFetched, category: cat))

                page += 1
                pagesFetched += 1
            }

            let currentItems = cachedItems[key] ?? []
            let existingIds = Set(currentItems.map { $0.id })
            let uniqueNewItems = newItems.filter { !existingIds.contains($0.id) }

            cachedItems[key] = currentItems + uniqueNewItems
            cachedPages[key] = page
            cachedCanLoadMore[key] = canLoad
        } catch {
            print("Failed to load category data: \(error)")
        }
    }

    private func fetchPage(_ page: Int, category: HomeCategory, filter: HomeFilter) async throws -> [MediaDto] {
        let baseItems: [MediaDto]

        switch filter {
        case .popular:
            baseItems = try await MoviesRepository.shared.getPopularMovies(page: page)
        case .topRated:
            switch category {
            case .tvShows:
                baseItems = try await MoviesRepository.shared.getTopTv(page: page)
            case .movies, .cartoons:
                baseItems = try await MoviesRepository.shared.getTopMovies(page: page)
            case .all:
                async let topMovies = MoviesRepository.shared.getTopMovies(page: page)
                async let topTv = MoviesRepository.shared.getTopTv(page: page)
                baseItems = try await (topMovies + topTv)
                    .sorted { ($0.rating ?? 0) > ($1.rating ?? 0) }
            }
        }

        return baseItems
    }

    private func filterValidItems(_ items: [MediaDto]) -> [MediaDto] {
        return items.filter { item in
            let poster = item.posterUrl ?? item.poster_path ?? ""
            let hasPoster = !poster.isEmpty && !poster.lowercased().contains("no-poster")
            let hasTitle = !(item.title ?? item.name ?? "").isEmpty
            let hasRating = (item.rating ?? 0) > 0.0
            
            return hasPoster && hasTitle && hasRating
        }
    }

    private func filterItemsForSelectedCategory(_ items: [MediaDto], category: HomeCategory) -> [MediaDto] {
        switch category {
        case .all:
            return items
        case .movies:
            return items.filter { $0.type == "movie" && !isCartoon($0) }
        case .tvShows:
            return items.filter { $0.type == "tv" && !isCartoon($0) }
        case .cartoons:
            return items.filter { isCartoon($0) }
        }
    }

}
