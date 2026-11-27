import SwiftUI
import UIKit

enum HomeCategory: String, CaseIterable {
    case all = "Все"
    case movies = "Фильмы"
    case tvShows = "Сериалы"
    case cartoons = "Мультфильмы"
    case anime = "Аниме"

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
        case .anime:
            return "Аниме"
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

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @ObservedObject private var deepLinkManager = DeepLinkManager.shared
    @ObservedObject private var mediaOverrides = MediaOverridesRepository.shared
    @Namespace private var navigationTransition
    @State private var pendingPlayerConfig: PlayerConfig? = nil
    @State private var requestedCategory: HomeCategory? = nil
    @State private var headerCategory: HomeCategory? = nil

    var body: some View {
        NavigationStack {
            HomeCategoryContentView(
                viewModel: viewModel,
                navigationTransition: navigationTransition,
                requestedCategory: $requestedCategory,
                headerCategory: $headerCategory
            )
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        ForEach(HomeFilter.allCases) { filter in
                            Button {
                                guard viewModel.selectedFilter != filter else { return }
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                                    viewModel.selectedFilter = filter
                                }
                            } label: {
                                if viewModel.selectedFilter == filter {
                                    Label(filter.title, systemImage: "checkmark")
                                } else {
                                    Label(filter.title, systemImage: filter.icon)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    .tint(.primary)
                    .accessibilityLabel("Сортировка: \(viewModel.selectedFilter.title)")
                }

                ToolbarItem(placement: .principal) {
                    Menu {
                        ForEach(HomeCategory.allCases, id: \.self) { category in
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                requestedCategory = category
                            } label: {
                                if viewModel.selectedCategory == category {
                                    Label(category.title, systemImage: "checkmark")
                                } else {
                                    Text(category.title)
                                }
                            }
                        }
                    } label: {
                        let displayedCategory = headerCategory ?? viewModel.selectedCategory
                        VStack(spacing: 1) {
                            HStack(spacing: 4) {
                                Text(displayedCategory.title)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .contentTransition(.numericText())
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.secondary)
                            }
                            Text(viewModel.selectedFilter.title)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .contentTransition(.numericText())
                        }
                        .fixedSize()
                        .padding(.horizontal, 10)
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .tint(.primary)
                    .accessibilityLabel("Категория: \((headerCategory ?? viewModel.selectedCategory).title), сортировка: \(viewModel.selectedFilter.title)")
                }
                .sharedBackgroundVisibility(.hidden)

                ToolbarItem(placement: .topBarTrailing) {
                    let hasFilters = !viewModel.searchFilters.isEmpty
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        viewModel.showFilters = true
                    } label: {
                        Image(systemName: hasFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(hasFilters ? Color.slooshAccent : Color.primary)
                            .glassForeground(isEnabled: GlassForegroundAppearance.shouldBlend(tint: hasFilters ? Color.slooshAccent : .primary))
                    }
                    .tint(hasFilters ? Color.slooshAccent : .primary)
                    .accessibilityLabel("Фильтры")
                }
            }
            .task {
                await viewModel.applyCurrentSelection()
            }
            .onChange(of: viewModel.selectedCategory) { _, _ in
                headerCategory = nil
                Task { await viewModel.applyCurrentSelection() }
            }
            .onChange(of: viewModel.selectedFilter) { _, _ in
                Task { await viewModel.applyCurrentSelection() }
            }
            .onChange(of: viewModel.searchFilters) { _, _ in
                Task { await viewModel.applyCurrentSelection(force: true) }
            }
            .sheet(isPresented: $viewModel.showFilters) {
                SearchFilterSheet(filters: $viewModel.searchFilters, context: .home)
            }
            .navigationDestination(item: Binding<DeepLinkMovie?>(
                get: {
                    deepLinkManager.targetMovieId.map { DeepLinkMovie(id: $0) }
                },
                set: { newValue in
                    deepLinkManager.targetMovieId = newValue?.id
                }
            )) { item in
                DetailsView(
                    movieId: item.id,
                    navigationTransitionID: nil,
                    navigationTransitionNamespace: nil
                )
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
                    mediaType: movie.type,
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
}

private struct HomeCategoryGridView: View, Equatable {
    let category: HomeCategory
    let filter: HomeFilter
    let items: [MediaDto]?
    let isLoading: Bool
    let isLoadingMore: Bool
    let cardDensity: CardDensity
    let spacing: CGFloat
    let padding: CGFloat
    let navigationTransition: Namespace.ID
    let onDirectPlay: (MediaDto) -> Void
    let onLoadMore: (HomeCategory) -> Void

    private let itemIds: [String]

    init(
        category: HomeCategory,
        filter: HomeFilter,
        items: [MediaDto]?,
        isLoading: Bool,
        isLoadingMore: Bool,
        cardDensity: CardDensity,
        spacing: CGFloat,
        padding: CGFloat,
        navigationTransition: Namespace.ID,
        onDirectPlay: @escaping (MediaDto) -> Void,
        onLoadMore: @escaping (HomeCategory) -> Void
    ) {
        self.category = category
        self.filter = filter
        self.items = items
        self.isLoading = isLoading
        self.isLoadingMore = isLoadingMore
        self.cardDensity = cardDensity
        self.spacing = spacing
        self.padding = padding
        self.navigationTransition = navigationTransition
        self.onDirectPlay = onDirectPlay
        self.onLoadMore = onLoadMore
        self.itemIds = items?.map(\.artworkIdentifier) ?? []
    }

    static func == (lhs: HomeCategoryGridView, rhs: HomeCategoryGridView) -> Bool {
        lhs.category == rhs.category &&
        lhs.filter == rhs.filter &&
        lhs.isLoading == rhs.isLoading &&
        lhs.isLoadingMore == rhs.isLoadingMore &&
        lhs.cardDensity == rhs.cardDensity &&
        lhs.spacing == rhs.spacing &&
        lhs.padding == rhs.padding &&
        lhs.itemIds == rhs.itemIds
    }

    private var columns: [GridItem] {
        let minWidth: CGFloat = cardDensity == .compact ? 95 : 105
        return [GridItem(.adaptive(minimum: minWidth), spacing: spacing)]
    }

    var body: some View {
        Group {
            if let items = items, !items.isEmpty {
                LazyVGrid(columns: columns, spacing: spacing) {
                    ForEach(items, id: \.artworkIdentifier) { movie in
                        MovieDetailsNavigationLink(movie: movie, navigationTransition: navigationTransition)
                            .contextMenu {
                                Group {
                                    Button {
                                        onDirectPlay(movie)
                                    } label: {
                                        Label("Смотреть", systemImage: "play.fill")
                                    }
                                    NavigationLink(destination: DetailsView(movieId: movie.id, mediaType: movie.type, navigationTransitionID: nil, navigationTransitionNamespace: nil)) {
                                        Label("Подробнее", systemImage: "info.circle")
                                    }
                                }
                                .tint(nil)
                            }
                            .onAppear {
                                if movie.id == items.last?.id {
                                    onLoadMore(category)
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
            } else if isLoading || items == nil {
                LazyVGrid(columns: columns, spacing: spacing) {
                    ForEach(0..<12, id: \.self) { _ in
                        MoviePosterCardPlaceholder()
                    }
                }
                .padding(.horizontal, padding)
                .padding(.bottom, padding)
            } else {
                HomeEmptyState(
                    category: category,
                    filter: filter
                )
                .padding(.top, 72)
                .padding(.bottom, 48)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct HomeGalleryStageView: View {
    @ObservedObject var viewModel: HomeViewModel
    let navigationTransition: Namespace.ID
    let cardDensity: CardDensity
    let spacing: CGFloat
    let padding: CGFloat
    let extraTopBleedMargin: CGFloat
    let metrics: HorizontalGalleryMetricsBox<HomeCategory>
    let scrollProxy: ScrollViewProxy
    @Binding var requestedCategory: HomeCategory?
    @Binding var headerCategory: HomeCategory?

    @StateObject private var swipe = HorizontalGallerySwipeController<HomeCategory>()

    private func preloadIfNeeded(_ cat: HomeCategory?) {
        guard let cat else { return }
        let key = HomeCacheKey(category: cat, filter: viewModel.selectedFilter, searchFilters: viewModel.searchFilters)
        guard viewModel.cachedItems[key] == nil, !(viewModel.isLoading[key] ?? false) else { return }
        Task { await viewModel.loadData(for: cat, force: false, prefetchAdjacent: false) }
    }

    var body: some View {
        let all = HomeCategory.allCases
        let activeCategory = viewModel.selectedCategory
        let pageWidth = max(1, metrics.width)
        let fullPageHeight = max(UIScreen.main.bounds.height, metrics.fullHeight)
        let stepStride = pageWidth + HorizontalGallerySwipeController<HomeCategory>.pageGap
        let offset = swipe.effectiveOffset(current: activeCategory, in: all, pageWidth: pageWidth)

        ZStack(alignment: .topLeading) {
            ForEach(swipe.visibleCategories(current: activeCategory, in: all), id: \.self) { cat in
                let isActive = cat == activeCategory
                let key = HomeCacheKey(category: cat, filter: viewModel.selectedFilter, searchFilters: viewModel.searchFilters)
                let items = viewModel.cachedItems[key]
                let hasContent = !(items?.isEmpty ?? false)
                let rawSavedY = isActive ? 0 : (metrics.savedScrollOffsets[cat] ?? 0)
                let savedY = hasContent ? rawSavedY : 0
                let topBleed = metrics.topBleed(isActive: isActive, savedY: savedY, extraTopMargin: extraTopBleedMargin)
                let delta = max(0, savedY - topBleed)
                let xPos = isActive ? offset : (offset + (swipe.slideDirection > 0 ? stepStride : -stepStride))
                let yPos = isActive ? 0 : (metrics.topOffset - topBleed)
                let clipHeight: CGFloat? = isActive ? nil : (fullPageHeight + topBleed)

                EquatableView(
                    content: HomeCategoryGridView(
                        category: cat,
                        filter: viewModel.selectedFilter,
                        items: items,
                        isLoading: viewModel.isLoading[key] ?? false,
                        isLoadingMore: isActive && (viewModel.isLoadingMore[key] ?? false),
                        cardDensity: cardDensity,
                        spacing: spacing,
                        padding: padding,
                        navigationTransition: navigationTransition,
                        onDirectPlay: { movie in
                            viewModel.directPlaybackMovie = movie
                        },
                        onLoadMore: { targetCat in
                            Task { await viewModel.loadData(for: targetCat) }
                        }
                    )
                )
                .padding(.top, isActive ? 0 : -delta)
                .frame(width: pageWidth, height: clipHeight, alignment: .top)
                .clipped()
                .horizontalGalleryIncomingTopFade(
                    isActive: isActive,
                    outgoingTopOffset: metrics.topOffset,
                    topBleed: topBleed
                )
                .allowsHitTesting(isActive)
                .offset(x: xPos, y: yPos)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: viewModel.selectedFilter)
        .background(
            HorizontalGallerySwipeAttachment(
                isLocked: swipe.isAnimatingSnap,
                onChanged: { translationX in
                    swipe.handlePanChanged(
                        translationX,
                        current: viewModel.selectedCategory,
                        in: all,
                        pageWidth: pageWidth,
                        preloadIfNeeded: preloadIfNeeded,
                        onPreviewCandidate: { candidate, tx in
                            if let candidate, abs(tx) > pageWidth * 0.42 {
                                if headerCategory != candidate {
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                                        headerCategory = candidate
                                    }
                                }
                            } else if headerCategory != nil {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                                    headerCategory = nil
                                }
                            }
                        }
                    )
                },
                onEnded: { translationX, velocityX, didFinish in
                    swipe.handlePanEnded(
                        translationX,
                        velocityX: velocityX,
                        didFinish: didFinish,
                        metrics: metrics,
                        current: viewModel.selectedCategory,
                        in: all,
                        pageWidth: pageWidth,
                        preloadIfNeeded: preloadIfNeeded,
                        onPrepareCommitHeader: { target in
                            if headerCategory != target {
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                                    headerCategory = target
                                }
                            }
                        },
                        onPrepareCancelHeader: {
                            if headerCategory != nil {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                                    headerCategory = nil
                                }
                            }
                        },
                        isStillCurrent: { target in
                            viewModel.selectedCategory == target
                        },
                        onCommitState: { target in
                            headerCategory = nil
                            viewModel.selectedCategory = target
                        }
                    )
                },
                onScrollViewFound: { sv in
                    if swipe.attachedScrollView !== sv {
                        swipe.attachedScrollView = sv
                    }
                },
                onWindowDismiss: {
                    if swipe.dragOffset != 0 || swipe.slideDirection != 0 || swipe.isAnimatingSnap {
                        swipe.resetImmediately {
                            headerCategory = nil
                        }
                    }
                }
            )
        )
        .onChange(of: requestedCategory) { _, target in
            guard let target else { return }
            requestedCategory = nil
            swipe.handleRequestedCategoryChange(
                to: target,
                metrics: metrics,
                current: viewModel.selectedCategory,
                in: all,
                scrollToTop: {
                    withAnimation(.easeOut(duration: 0.24)) {
                        scrollProxy.scrollTo("home-scroll-top", anchor: .top)
                    }
                },
                preloadIfNeeded: preloadIfNeeded,
                onPrepareCommitHeader: { next in
                    if headerCategory != next {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                            headerCategory = next
                        }
                    }
                },
                isStillCurrent: { next in
                    viewModel.selectedCategory == next
                },
                onCommitState: { next in
                    headerCategory = nil
                    viewModel.selectedCategory = next
                }
            )
        }
    }
}

struct HomeCategoryContentView: View {
    @ObservedObject var viewModel: HomeViewModel
    let navigationTransition: Namespace.ID
    @Binding var requestedCategory: HomeCategory?
    @Binding var headerCategory: HomeCategory?

    @AppStorage("cardDensity") private var cardDensity: CardDensity = .regular
    @State private var metrics = HorizontalGalleryMetricsBox<HomeCategory>()

    var body: some View {
        let category = viewModel.selectedCategory

        ScrollViewReader { proxy in
            ScrollView {
                let spacing: CGFloat = cardDensity == .compact ? 8 : 16
                let padding: CGFloat = cardDensity == .compact ? 12 : 16

                // Invisible anchor used to scroll-to-top on sort/filter switch
                Color.clear.frame(height: 0).id("home-scroll-top")

                VStack(alignment: .leading, spacing: 12) {
                    if !viewModel.searchFilters.isEmpty {
                        HomeActiveFiltersStrip(searchFilters: $viewModel.searchFilters)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    HomeGalleryStageView(
                        viewModel: viewModel,
                        navigationTransition: navigationTransition,
                        cardDensity: cardDensity,
                        spacing: spacing,
                        padding: padding,
                        extraTopBleedMargin: viewModel.searchFilters.isEmpty ? 10 : 58,
                        metrics: metrics,
                        scrollProxy: proxy,
                        requestedCategory: $requestedCategory,
                        headerCategory: $headerCategory
                    )
                }
                .padding(.top, 8)
                .padding(.bottom, 16)
                .animation(.spring(response: 0.32, dampingFraction: 0.85), value: viewModel.searchFilters.isEmpty)
            }
            .onScrollGeometryChange(for: HorizontalGalleryScrollMetrics.self) { geometry in
                HorizontalGalleryScrollMetrics.from(geometry)
            } action: { _, newMetrics in
                metrics.apply(newMetrics)
            }
            .scrollIndicators(.hidden)
            .scrollEdgeEffectStyle(.soft, for: .all)
            .refreshable {
                await viewModel.refresh(category: category)
            }
            .onChange(of: viewModel.selectedFilter) { _, _ in
                metrics.savedScrollOffsets.removeAll()
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("home-scroll-top", anchor: .top)
                }
            }
            .onChange(of: viewModel.searchFilters) { _, _ in
                metrics.savedScrollOffsets.removeAll()
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("home-scroll-top", anchor: .top)
                }
            }
        }
    }
}

struct MovieDetailsNavigationLink<Label: View>: View {
    let movieId: String
    let mediaType: String?
    let transitionID: String
    let navigationTransition: Namespace.ID
    let studio: StudioBrand?
    @ViewBuilder let label: () -> Label

    init(movieId: String, mediaType: String? = nil, transitionID: String? = nil, navigationTransition: Namespace.ID, studio: StudioBrand? = nil, @ViewBuilder label: @escaping () -> Label) {
        self.movieId = movieId
        self.mediaType = mediaType
        self.transitionID = transitionID ?? "movie-card-\(CatalogArtworkIdentity(id: movieId, type: mediaType)?.requestId ?? movieId)"
        self.navigationTransition = navigationTransition
        self.studio = studio
        self.label = label
    }

    init(movie: MediaDto, navigationTransition: Namespace.ID, studio: StudioBrand? = nil, refreshArtwork: Bool = false) where Label == MoviePosterCard {
        self.init(movieId: movie.id, mediaType: movie.type, navigationTransition: navigationTransition, studio: studio) {
            MoviePosterCard(movie: movie, refreshArtwork: refreshArtwork)
        }
    }

    var body: some View {
        NavigationLink(
            destination: DetailsView(
                movieId: movieId,
                mediaType: mediaType,
                navigationTransitionID: transitionID,
                navigationTransitionNamespace: navigationTransition,
                initialStudio: studio
            )
        ) {
            label()
                .matchedTransitionSource(id: transitionID, in: navigationTransition)
        }
        .buttonStyle(.cardPress)
    }
}

private struct HomeActiveFiltersStrip: View {
    @Binding var searchFilters: SearchFilters

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CatalogSearchFilter.allCases) { field in
                    if let label = field.label(in: searchFilters) {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                searchFilters = field.removing(from: searchFilters)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(label)
                                    .lineLimit(1)
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.slooshAccent)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .contentShape(.capsule)
                            .glassEffect(.regular.interactive(), in: .capsule)
                        }
                        .buttonStyle(.glassPress)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .scrollClipDisabled()
    }
}

private struct HomeEmptyState: View {
    let category: HomeCategory
    let filter: HomeFilter

    var body: some View {
        AppEmptyStateView(
            icon: "film.stack",
            title: "Ничего не найдено",
            description: "Попробуйте выбрать другую вкладку или сменить режим сортировки."
        )
    }
}

struct RemotePosterView<Overlay: View>: View {
    let url: URL?
    var fallbackUrl: URL? = nil
    var cornerRadius: CGFloat = 12
    @Binding var isLoading: Bool
    let overlay: () -> Overlay
    
    init(url: URL?, fallbackUrl: URL? = nil, cornerRadius: CGFloat = 12, isLoading: Binding<Bool> = .constant(false), @ViewBuilder overlay: @escaping () -> Overlay) {
        self.url = url
        self.fallbackUrl = fallbackUrl
        self.cornerRadius = cornerRadius
        self._isLoading = isLoading
        self.overlay = overlay
    }
    
    var body: some View {
        AsyncCachedImage(url: url, fallbackUrl: fallbackUrl, isExternalLoading: $isLoading) {
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
        .overlay(alignment: .bottomLeading) {
            overlay()
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

extension RemotePosterView where Overlay == EmptyView {
    init(url: URL?, fallbackUrl: URL? = nil, cornerRadius: CGFloat = 12, isLoading: Binding<Bool> = .constant(false)) {
        self.url = url
        self.fallbackUrl = fallbackUrl
        self.cornerRadius = cornerRadius
        self._isLoading = isLoading
        self.overlay = { EmptyView() }
    }
}

struct MoviePosterCard: View {
    let movie: MediaDto
    var refreshArtwork = false
    @ObservedObject private var mediaOverrides = MediaOverridesRepository.shared
    @AppStorage("cardStyle") private var cardStyle: CardStyle = .classic
    @AppStorage("posterQuality") private var posterQuality: PosterQuality = .high
    @AppStorage("useLogosInCatalog") private var useLogosInCatalog: Bool = false
    @AppStorage("showCatalogMetadata") private var showCatalogMetadata = true

    @State private var fetchedPoster: (identity: CatalogArtworkIdentity, artwork: CatalogLogoRepository.Artwork)?
    @State private var artworkRevision = 0
    private var artworkIdentity: CatalogArtworkIdentity? {
        CatalogArtworkIdentity(id: movie.originalId?.stringValue, type: movie.type)
    }
    private var posterURL: URL? {
        let remote = fetchedPoster.flatMap { $0.identity == artworkIdentity ? $0.artwork : nil }
        let curated = mediaOverrides.catalogOverride(id: movie.originalId?.stringValue, type: movie.type, kpId: movie.externalIds?.kp)
        let selected = useLogosInCatalog
            ? (curated?.artworkURL(curated?.textlessPosterUrl) ?? curated?.artworkURL(curated?.posterUrl))
            : curated?.artworkURL(curated?.posterUrl)
        let ordinary = (refreshArtwork ? remote?.poster : nil) ?? movie.displayPosterUrl(forLogoMode: false)
        let value = selected ?? (useLogosInCatalog ? (movie.displayTextlessPosterUrl() ?? remote?.textlessPoster ?? ordinary) : ordinary)
        return value.flatMap(URL.init(string:))
    }

    private var fallbackPosterURL: URL? {
        let remote = fetchedPoster.flatMap { $0.identity == artworkIdentity ? $0.artwork.poster : nil }
        let ordinary = (refreshArtwork ? remote : nil) ?? movie.displayPosterUrl(forLogoMode: false)
        let fallback = ordinary.flatMap(URL.init(string:))
        return fallback == posterURL ? nil : fallback
    }

    var body: some View {
        Group {
            switch cardStyle {
            case .classic: classicBody
            case .overlay: overlayBody
            }
        }
        .task(id: "\(useLogosInCatalog)|\(artworkIdentity?.requestId ?? movie.identifier)|\(artworkRevision)") {
            fetchedPoster = nil
            guard refreshArtwork || (useLogosInCatalog && movie.displayTextlessPosterUrl() == nil),
                  let identity = artworkIdentity else { return }
            let artwork = await CatalogLogoRepository.shared.artwork(for: identity)
            guard !Task.isCancelled else { return }
            fetchedPoster = (identity, artwork)
        }
        .onReceive(NotificationCenter.default.publisher(for: .mediaArtworkOverridesDidChange)) { _ in
            fetchedPoster = nil
            artworkRevision += 1
        }
    }

    private var classicBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            let url = posterURL
            
            ZStack(alignment: .topLeading) {
                RemotePosterView(url: url, fallbackUrl: fallbackPosterURL)
                
                if movie.isUnreleased {
                    Text("Скоро")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .padding(8)
                } else if movie.effectiveRating > 0 {
                    Text(String(format: "%.1f", movie.effectiveRating))
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(Color.rating(movie.effectiveRating))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .padding(8)
                }
            }

            MovieCardCaptionView(
                movie: movie, isOverlay: false,
                useLogos: useLogosInCatalog, showsMetadata: showCatalogMetadata
            )
            .padding(.horizontal, 4)
            .padding(.bottom, 2)
        }
    }

    private var overlayBody: some View {
        RemotePosterView(url: posterURL, fallbackUrl: fallbackPosterURL, cornerRadius: 12) {
            ZStack(alignment: .bottomLeading) {
                // Progressive blur with dark tint at the bottom of the poster
                VariableBlurView(
                    maxBlurRadius: 4.5,
                    direction: .blurredBottomClearTop,
                    tintColor: .black,
                    tintOpacity: 0.82,
                    style: .dark,
                    haloIntensity: 0
                )
                .frame(height: 60)
                .frame(maxWidth: .infinity, alignment: .bottom)
                .allowsHitTesting(false)
                
                // Metadata inside the poster
                MovieCardCaptionView(
                    movie: movie, isOverlay: true,
                    useLogos: useLogosInCatalog, showsMetadata: showCatalogMetadata
                )
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .overlay(alignment: .topLeading) {
            if movie.isUnreleased {
                Text("Скоро")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .padding(8)
            } else if movie.effectiveRating > 0 {
                Text(String(format: "%.1f", movie.effectiveRating))
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(Color.rating(movie.effectiveRating))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(8)
            }
        }
        .aspectRatio(2/3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct MovieCardCaptionView: View {
    let movie: MediaDto
    let isOverlay: Bool
    let useLogos: Bool
    let showsMetadata: Bool
    @ScaledMetric(relativeTo: .caption) private var scale: CGFloat = 1

    private var metadata: String? {
        CatalogCaptionLayout.metadataText(year: movie.displayYear, genre: movie.genres?.first?.name?.capitalized)
    }

    var body: some View {
        let layout = CatalogCaptionLayout(isOverlay: isOverlay, showsMetadata: showsMetadata, scale: scale)
        VStack(alignment: .leading, spacing: layout.spacing) {
            MovieCardTitleOrLogoView(movie: movie, isOverlay: isOverlay, useLogos: useLogos, showsMetadata: showsMetadata)
            if showsMetadata {
                Text(metadata ?? " ")
                    .font(.system(size: (isOverlay ? 10 : 12) * scale, weight: isOverlay ? .semibold : .regular))
                    .foregroundStyle(isOverlay ? Color.white.opacity(0.65) : Color.secondary)
                    .blendMode(isOverlay ? .plusLighter : .normal)
                    .lineLimit(1)
                    .frame(height: layout.metadataHeight, alignment: .leading)
                    .accessibilityHidden(metadata == nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: layout.totalHeight, alignment: .leading)
    }
}

struct MovieCardTitleOrLogoView: View {
    let movie: MediaDto
    let isOverlay: Bool
    let useLogos: Bool
    var showsMetadata = true
    @ScaledMetric(relativeTo: .caption) private var captionScale: CGFloat = 1
    private var layout: CatalogCaptionLayout {
        CatalogCaptionLayout(isOverlay: isOverlay, showsMetadata: showsMetadata, scale: captionScale)
    }
    @State private var artworkRevision = 0
    @State private var fetchedLogo: (identity: CatalogArtworkIdentity, url: String)?
    private var artworkIdentity: CatalogArtworkIdentity? {
        CatalogArtworkIdentity(id: movie.originalId?.stringValue, type: movie.type)
    }
    private var logoURL: URL? {
        let remote = fetchedLogo.flatMap { $0.identity == artworkIdentity ? $0.url : nil }
        guard let value = movie.displayLogoUrl(isCompact: true) ?? remote else { return nil }
        return URL(string: adjustLogoUrl(urlStr: value, targetSize: "w300"))
    }
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Group {
            if useLogos, let logoUrl = logoURL {
                AsyncCachedImage(url: logoUrl) {
                    titleText
                        .opacity(0.85)
                } content: { uiImg in
                    GeometryReader { geometry in
                        let size = layout.fittedLogoSize(imageSize: uiImg.size, availableWidth: geometry.size.width)
                        Image(uiImage: uiImg)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: size.width, height: size.height)
                            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
                            .shadow(color: Color.black.opacity(isOverlay ? 0.6 : (colorScheme == .light ? 0.25 : 0.45)), radius: 1, x: 0, y: 1)
                    }
                    .accessibilityLabel(movie.displayTitle)
                } fallback: {
                    titleText
                }
                .frame(height: layout.titleAreaHeight, alignment: .leading)
                .id("\(movie.identifier)|\(logoUrl.absoluteString)")
            } else {
                titleText
                    .frame(height: layout.titleAreaHeight, alignment: .leading)
            }
        }
        .task(id: "\(useLogos)|\(artworkIdentity?.requestId ?? movie.identifier)|\(artworkRevision)") {
            fetchedLogo = nil
            guard useLogos, let identity = artworkIdentity, movie.displayLogoUrl(isCompact: true) == nil else { return }
            let url = await CatalogLogoRepository.shared.logo(for: identity)
            guard !Task.isCancelled, artworkIdentity == identity, let url else { return }
            fetchedLogo = (identity, url)
        }
        .onReceive(NotificationCenter.default.publisher(for: .mediaArtworkOverridesDidChange)) { _ in
            fetchedLogo = nil
            artworkRevision += 1
        }
    }

    private var titleText: some View {
        Group {
            if CatalogFallbackTitleStyle.isEnabled(showsMetadata: showsMetadata) {
                CatalogFallbackLogoTitle(title: movie.displayTitle, isOverlay: isOverlay, scale: captionScale)
            } else if isOverlay {
                Text(movie.displayTitle)
                    .font(.system(size: 13 * captionScale, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.95))
                    .blendMode(.plusLighter)
                    .lineLimit(layout.titleLineLimit)
                    .tracking(-0.3)
                    .allowsTightening(true)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
            } else {
                Text(movie.displayTitle)
                    .font(.system(size: 14 * captionScale, weight: .semibold))
                    .lineLimit(layout.titleLineLimit)
                    .tracking(-0.3)
                    .allowsTightening(true)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
                    .foregroundColor(.primary)
            }
        }
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
    @AppStorage("useLogosInCatalog") private var useLogosInCatalog: Bool = false
    @AppStorage("showCatalogMetadata") private var showCatalogMetadata = true
    
    var body: some View {
        switch cardStyle {
        case .classic:
            VStack(alignment: .leading, spacing: 8) {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .aspectRatio(2/3, contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shimmer()
                
                CatalogCaptionSkeleton(isOverlay: false, useLogos: useLogosInCatalog, showsMetadata: showCatalogMetadata)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 2)
                    .shimmer()
            }
        case .overlay:
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .aspectRatio(2/3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shimmer()
        }
    }
}

struct HomeCacheKey: Hashable {
    let category: HomeCategory
    let filter: HomeFilter
    let searchFilters: SearchFilters
}

enum FeedPhase: Equatable {
    case original
    case searchFallback
}

struct InfiniteCursor: Equatable {
    var phase: FeedPhase
    var page: Int
}

@MainActor
class HomeViewModel: ObservableObject {
    @Published var selectedCategory: HomeCategory = .all
    @Published var selectedFilter: HomeFilter = .popular
    @Published var searchFilters = SearchFilters()
    @Published var showFilters = false
    
    @Published var cachedItems: [HomeCacheKey: [MediaDto]] = [:]
    @Published var isLoading: [HomeCacheKey: Bool] = [:]
    @Published var isLoadingMore: [HomeCacheKey: Bool] = [:]
    
    @Published var directPlaybackMovie: MediaDto? = nil
    @Published var playerConfig: PlayerConfig? = nil

    private var cachedCursors: [HomeCacheKey: InfiniteCursor] = [:]
    private var cachedCanLoadMore: [HomeCacheKey: Bool] = [:]
    private var hasPerformedInitialLoad = false
    private var prefetchTask: Task<Void, Never>? = nil

    func applyCurrentSelection(force: Bool = false) async {
        let key = HomeCacheKey(category: selectedCategory, filter: selectedFilter, searchFilters: searchFilters)

        if force {
            cachedCursors[key] = nil
            cachedCanLoadMore[key] = true
        } else if !hasPerformedInitialLoad {
            hasPerformedInitialLoad = true
        } else if let cached = cachedItems[key], !cached.isEmpty {
            return
        }

        await loadData(for: selectedCategory, force: force)
    }

    func refresh(category: HomeCategory) async {
        let key = HomeCacheKey(category: category, filter: selectedFilter, searchFilters: searchFilters)
        cachedCursors[key] = nil
        cachedCanLoadMore[key] = true
        async let configSync: Void = MoviesApi.shared.loadRemoteConfig()
        async let dataLoad: Void = loadData(for: category, force: true)
        _ = await (configSync, dataLoad)
    }
    
    private func initialCursor(for key: HomeCacheKey) -> InfiniteCursor {
        if key.searchFilters.isEmpty {
            return InfiniteCursor(phase: .original, page: 1)
        } else {
            return InfiniteCursor(phase: .searchFallback, page: 1)
        }
    }

    private func advanceCursor(_ cursor: inout InfiniteCursor, key: HomeCacheKey) -> Bool {
        if cursor.phase == .original {
            cursor.phase = .searchFallback
            cursor.page = 1
            return true
        } else {
            return false
        }
    }

    func loadData(for category: HomeCategory? = nil, force: Bool = false, prefetchAdjacent: Bool = true) async {
        let cat = category ?? selectedCategory
        let key = HomeCacheKey(category: cat, filter: selectedFilter, searchFilters: searchFilters)

        let currentCanLoadMore = cachedCanLoadMore[key] ?? true
        guard currentCanLoadMore || force else { return }

        let isCurrentlyLoading = isLoading[key] ?? false
        let isCurrentlyLoadingMore = isLoadingMore[key] ?? false
        if !force {
            guard !isCurrentlyLoading, !isCurrentlyLoadingMore else { return }
        } else {
            guard !isCurrentlyLoading else { return }
        }

        let existingItems = cachedItems[key] ?? []
        if existingItems.isEmpty {
            isLoading[key] = true
        } else if !force {
            isLoadingMore[key] = true
        }

        defer {
            isLoading[key] = false
            isLoadingMore[key] = false
        }

        do {
            var newItems: [MediaDto] = []
            var cursor = (force ? nil : cachedCursors[key]) ?? initialCursor(for: key)
            var canLoad = force ? true : currentCanLoadMore

            while newItems.isEmpty && canLoad {
                let fetched = try await fetchPage(cursor, category: cat, filter: key.filter, searchFilters: key.searchFilters, force: force && cursor.page == 1)
                
                if fetched.isEmpty {
                    if !advanceCursor(&cursor, key: key) {
                        canLoad = false
                        break
                    }
                    continue
                }

                let validFetched = filterValidItems(fetched)
                newItems.append(contentsOf: filterItemsForSelectedCategory(validFetched, category: cat))

                cursor.page += 1
            }

            if force {
                cachedItems[key] = newItems
            } else {
                let currentItems = cachedItems[key] ?? []
                let existingIds = Set(currentItems.map { $0.id })
                let uniqueNewItems = newItems.filter { !existingIds.contains($0.id) }
                var merged = currentItems + uniqueNewItems
                if key.searchFilters.order == "YEAR" {
                    merged.sort { a, b in
                        let yearA = a.effectiveYear ?? 0
                        let yearB = b.effectiveYear ?? 0
                        if yearA != yearB { return yearA > yearB }
                        let dateA = a.releaseDate ?? ""
                        let dateB = b.releaseDate ?? ""
                        if !dateA.isEmpty && !dateB.isEmpty && dateA != dateB { return dateA > dateB }
                        return a.effectiveRating > b.effectiveRating
                    }
                } else if key.searchFilters.order == "RATING" {
                    merged.sort { a, b in
                        let ratingA = a.effectiveRating
                        let ratingB = b.effectiveRating
                        if ratingA != ratingB { return ratingA > ratingB }
                        return (a.effectiveYear ?? 0) > (b.effectiveYear ?? 0)
                    }
                }
                cachedItems[key] = merged
            }
            cachedCursors[key] = cursor
            cachedCanLoadMore[key] = canLoad

            if prefetchAdjacent {
                prefetchTask?.cancel()
                prefetchTask = Task(priority: .utility) { [weak self] in
                    await self?.prefetchAdjacentCategories(currentCategory: cat)
                }
            }
        } catch {
            print("Failed to load category data: \(error)")
            if key.searchFilters.isEmpty, (cachedItems[key] == nil || cachedItems[key]?.isEmpty == true), let fallback = await loadFallbackFromDisk(for: cat) {
                cachedItems[key] = fallback
            }
        }
    }

    private func loadFallbackFromDisk(for category: HomeCategory) async -> [MediaDto]? {
        let repo = MoviesRepository.shared
        switch category {
        case .all:
            if selectedFilter == .topRated {
                if let top = try? await repo.getTopMovies(page: 1, force: false), !top.isEmpty {
                    return top.filter { !isTalkShowOrReality($0) }
                }
                if let trending = try? await repo.getTrending(page: 1, force: false) {
                    return trending.filter { !isTalkShowOrReality($0) }
                }
                return nil
            } else {
                if let trending = try? await repo.getTrending(page: 1, force: false), !trending.isEmpty {
                    return trending.filter { !isTalkShowOrReality($0) }
                }
                if let popular = try? await repo.getPopularMovies(page: 1, force: false) {
                    return popular.filter { !isTalkShowOrReality($0) }
                }
                return nil
            }
        case .movies:
            if selectedFilter == .topRated {
                return try? await repo.getTopMovies(page: 1, force: false)
            } else {
                return try? await repo.getPopularMovies(page: 1, force: false)
            }
        case .tvShows:
            if let tv = try? await repo.getTopTv(page: 1, force: false) {
                return tv.filter { !isTalkShowOrReality($0) }
            }
            return nil
        case .cartoons:
            return try? await repo.getCartoons(page: 1, force: false)
        case .anime:
            if selectedFilter == .topRated {
                return try? await repo.getTopAnime(page: 1, force: false)
            } else {
                return try? await repo.getPopularAnime(page: 1, force: false)
            }
        }
    }

    private func prefetchAdjacentCategories(currentCategory: HomeCategory) async {
        let all = HomeCategory.allCases
        guard let currentIndex = all.firstIndex(of: currentCategory) else { return }

        var ordered: [HomeCategory] = []
        for delta in 1..<all.count {
            if currentIndex + delta < all.count { ordered.append(all[currentIndex + delta]) }
            if currentIndex - delta >= 0 { ordered.append(all[currentIndex - delta]) }
        }
        let targets = searchFilters.isEmpty ? ordered : Array(ordered.prefix(2))

        for cat in targets {
            if Task.isCancelled { break }
            let key = HomeCacheKey(category: cat, filter: selectedFilter, searchFilters: searchFilters)
            if cachedItems[key] == nil, !(isLoading[key] ?? false) {
                await loadData(for: cat, force: false, prefetchAdjacent: false)
            }
            if Task.isCancelled { break }
            if let items = cachedItems[key], !items.isEmpty {
                let urls = items.prefix(15).compactMap { $0.displayPosterUrl(forLogoMode: false).flatMap(URL.init(string:)) }
                ImageCache.prefetch(urls: urls)
            }
        }
    }

    private func fetchPage(_ cursor: InfiniteCursor, category: HomeCategory, filter: HomeFilter, searchFilters: SearchFilters, force: Bool = false) async throws -> [MediaDto] {
        if cursor.phase == .original {
            switch category {
            case .all:
                switch filter {
                case .popular:
                    async let trendingTask = MoviesRepository.shared.getTrending(page: cursor.page, force: force)
                    async let popularMoviesTask = MoviesRepository.shared.getPopularMovies(page: cursor.page, force: force)
                    async let popularTvTask = MoviesRepository.shared.getPopularTv(page: cursor.page, force: force)
                    async let cartoonsTask = MoviesRepository.shared.getCartoons(page: cursor.page, force: force)
                    async let animeTask = MoviesRepository.shared.getPopularAnime(page: cursor.page, force: force)

                    let trending = (try? await trendingTask) ?? []
                    let popularMovies = (try? await popularMoviesTask) ?? []
                    let popularTv = (try? await popularTvTask) ?? []
                    let cartoons = (try? await cartoonsTask) ?? []
                    let anime = (try? await animeTask) ?? []

                    let trendingMovies = trending.filter { $0.isMovieType && !isCartoon($0) }
                    let trendingTv = trending.filter { $0.isTvType && !isCartoon($0) && !isTalkShowOrReality($0) }
                    let trendingCartoons = trending.filter { isCartoon($0) && !isAnime($0) }
                    let trendingAnime = trending.filter { isAnime($0) }

                    let combinedMovies = interleaveLists(primary: trendingMovies, secondary: popularMovies.filter { $0.isMovieType && !isCartoon($0) })
                    let combinedTv = interleaveLists(primary: trendingTv, secondary: popularTv.filter { $0.isTvType && !isCartoon($0) && !isTalkShowOrReality($0) })
                    let combinedCartoons = interleaveLists(primary: trendingCartoons, secondary: cartoons.filter { isCartoon($0) && !isAnime($0) })
                    let combinedAnime = interleaveLists(primary: trendingAnime, secondary: anime.filter { isAnime($0) })

                    let balanced = interleaveBalancedMedia(
                        movies: combinedMovies,
                        tv: combinedTv,
                        cartoons: combinedCartoons,
                        anime: combinedAnime
                    )

                    if balanced.isEmpty {
                        return try await MoviesRepository.shared.getPopularMovies(page: cursor.page, force: force)
                    } else {
                        return balanced
                    }
                case .topRated:
                    async let moviesTask = MoviesRepository.shared.getTopMovies(page: cursor.page, force: force)
                    async let tvTask = MoviesRepository.shared.getTopTv(page: cursor.page, force: force)
                    async let cartoonsTask = MoviesRepository.shared.getCartoons(page: cursor.page, force: force)
                    async let animeTask = MoviesRepository.shared.getTopAnime(page: cursor.page, force: force)

                    let movies = (try? await moviesTask) ?? []
                    let tv = (try? await tvTask) ?? []
                    let cartoons = (try? await cartoonsTask) ?? []
                    let anime = (try? await animeTask) ?? []

                    let filteredTv = tv.filter { $0.isTvType && !isCartoon($0) && !isTalkShowOrReality($0) }
                    let balanced = interleaveBalancedMedia(
                        movies: movies.filter { $0.isMovieType && !isCartoon($0) },
                        tv: filteredTv,
                        cartoons: cartoons.filter { isCartoon($0) && !isAnime($0) },
                        anime: anime.filter { isAnime($0) }
                    )
                    if balanced.isEmpty {
                        return try await MoviesRepository.shared.getTopMovies(page: cursor.page, force: force)
                    } else {
                        return balanced
                    }
                }
            case .movies:
                switch filter {
                case .popular:
                    return try await MoviesRepository.shared.getPopularMovies(page: cursor.page, force: force)
                case .topRated:
                    return try await MoviesRepository.shared.getTopMovies(page: cursor.page, force: force)
                }
            case .tvShows:
                switch filter {
                case .popular:
                    let raw = try await MoviesRepository.shared.getPopularTv(page: cursor.page, force: force)
                    return raw.filter { !isTalkShowOrReality($0) }
                case .topRated:
                    let raw = try await MoviesRepository.shared.getTopTv(page: cursor.page, force: force)
                    return raw.filter { !isTalkShowOrReality($0) }
                }
            case .cartoons:
                return try await MoviesRepository.shared.getCartoons(page: cursor.page, force: force)
            case .anime:
                switch filter {
                case .popular:
                    return try await MoviesRepository.shared.getPopularAnime(page: cursor.page, force: force)
                case .topRated:
                    return try await MoviesRepository.shared.getTopAnime(page: cursor.page, force: force)
                }
            }
        } else {
            var mergedFilters = searchFilters
            
            if mergedFilters.order == nil {
                mergedFilters.order = filter == .popular ? "NUM_VOTE" : "RATING"
            }
            
            if mergedFilters.type == nil {
                switch category {
                case .movies:
                    mergedFilters.type = "FILM"
                case .tvShows:
                    mergedFilters.type = "TV_SERIES"
                case .cartoons:
                    mergedFilters.type = "CARTOON"
                case .anime:
                    mergedFilters.type = "ANIME"
                case .all:
                    break
                }
            }
            
            let response = try await MoviesRepository.shared.searchMoviesResponse(query: "", page: cursor.page, filters: mergedFilters)
            return response.results ?? []
        }
    }

    private func interleaveLists(primary: [MediaDto], secondary: [MediaDto]) -> [MediaDto] {
        var result: [MediaDto] = []
        var seen = Set<String>()
        var p = 0
        var s = 0
        while p < primary.count || s < secondary.count {
            if p < primary.count {
                let item = primary[p]
                p += 1
                if !item.id.isEmpty && !seen.contains(item.id) {
                    seen.insert(item.id)
                    result.append(item)
                }
            }
            if s < secondary.count {
                let item = secondary[s]
                s += 1
                if !item.id.isEmpty && !seen.contains(item.id) {
                    seen.insert(item.id)
                    result.append(item)
                }
            }
        }
        return result
    }

    private func interleaveBalancedMedia(
        movies: [MediaDto],
        tv: [MediaDto],
        cartoons: [MediaDto],
        anime: [MediaDto]
    ) -> [MediaDto] {
        var result: [MediaDto] = []
        var seenIds = Set<String>()
        var itemsSinceLastAnime = 10

        func canAppend(_ item: MediaDto) -> Bool {
            let id = item.id
            if id.isEmpty || seenIds.contains(id) { return false }
            if isTalkShowOrReality(item) { return false }
            if isAnime(item) {
                // Строгий баланс: между аниме должно быть минимум 4 фильма или сериала,
                // чтобы вкладка "Все" не переполнялась аниме.
                if itemsSinceLastAnime < 4 {
                    return false
                }
            }
            return true
        }

        func appendItem(_ item: MediaDto) {
            seenIds.insert(item.id)
            result.append(item)
            if isAnime(item) {
                itemsSinceLastAnime = 0
            } else {
                itemsSinceLastAnime += 1
            }
        }

        var mIdx = 0
        var tIdx = 0
        var cIdx = 0
        var aIdx = 0

        let maxTotal = movies.count + tv.count + cartoons.count + anime.count
        var step = 0

        while (mIdx < movies.count || tIdx < tv.count || cIdx < cartoons.count || aIdx < anime.count) && step < maxTotal {
            step += 1

            // 1. Фильм
            while mIdx < movies.count {
                let item = movies[mIdx]
                mIdx += 1
                if canAppend(item) {
                    appendItem(item)
                    break
                }
            }

            // 2. Сериал
            while tIdx < tv.count {
                let item = tv[tIdx]
                tIdx += 1
                if canAppend(item) {
                    appendItem(item)
                    break
                }
            }

            // 3. Фильм
            while mIdx < movies.count {
                let item = movies[mIdx]
                mIdx += 1
                if canAppend(item) {
                    appendItem(item)
                    break
                }
            }

            // 4. Сериал
            while tIdx < tv.count {
                let item = tv[tIdx]
                tIdx += 1
                if canAppend(item) {
                    appendItem(item)
                    break
                }
            }

            // 5. Поочерёдно мультфильм или аниме
            if step % 2 == 1 {
                var added = false
                while cIdx < cartoons.count {
                    let item = cartoons[cIdx]
                    cIdx += 1
                    if canAppend(item) {
                        appendItem(item)
                        added = true
                        break
                    }
                }
                if !added {
                    while aIdx < anime.count {
                        let item = anime[aIdx]
                        aIdx += 1
                        if canAppend(item) {
                            appendItem(item)
                            break
                        }
                    }
                }
            } else {
                var added = false
                while aIdx < anime.count {
                    let item = anime[aIdx]
                    aIdx += 1
                    if canAppend(item) {
                        appendItem(item)
                        added = true
                        break
                    }
                }
                if !added {
                    while cIdx < cartoons.count {
                        let item = cartoons[cIdx]
                        cIdx += 1
                        if canAppend(item) {
                            appendItem(item)
                            break
                        }
                    }
                }
            }
        }

        return result
    }

    private func filterValidItems(_ items: [MediaDto]) -> [MediaDto] {
        return items.filter { item in
            let poster = item.displayPosterUrl ?? item.poster ?? item.posterUrl ?? item.poster_path ?? ""
            let hasPoster = !poster.isEmpty && !poster.lowercased().contains("no-poster")
            let title = (item.title ?? item.name ?? item.originalTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let hasTitle = !title.isEmpty
            let rating = item.effectiveRating
            let hasValidRating = rating >= 0.0
            
            return (hasPoster || item.isUnreleased) && hasTitle && hasValidRating
        }
    }

    private func filterItemsForSelectedCategory(_ items: [MediaDto], category: HomeCategory) -> [MediaDto] {
        switch category {
        case .all:
            return items.filter { !isTalkShowOrReality($0) }
        case .anime:
            return items
        case .movies:
            return items.filter { $0.isMovieType && !isCartoon($0) }
        case .tvShows:
            return items.filter { $0.isTvType && !isCartoon($0) && !isTalkShowOrReality($0) }
        case .cartoons:
            return items.filter { isCartoon($0) && !isAnime($0) }
        }
    }

}
