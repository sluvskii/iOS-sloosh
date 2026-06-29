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

    @State private var scrollPosition: HomeCategory?

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
                        .id(category)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $scrollPosition)
            .safeAreaBar(edge: .top, spacing: 0) {
                HomeCategoryTextTabs(
                    selectedCategory: $viewModel.selectedCategory,
                    selectedFilter: $viewModel.selectedFilter,
                    isFilterCollapsed: $isFilterCollapsed
                )
                .padding(.top, 4)
                .padding(.bottom, 2)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .toolbar(.hidden, for: .navigationBar)
            .task {
                scrollPosition = viewModel.selectedCategory
                await viewModel.applyCurrentSelection()
            }
            .onChange(of: scrollPosition) { _, newCategory in
                if let newCategory, newCategory != viewModel.selectedCategory {
                    viewModel.selectedCategory = newCategory
                }
            }
            .onChange(of: viewModel.selectedCategory) { _, newCategory in
                if scrollPosition != newCategory {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        scrollPosition = newCategory
                    }
                }
                isFilterCollapsed = false
                Task {
                    await viewModel.applyCurrentSelection()
                }
            }
            .onChange(of: viewModel.selectedFilter) { _, _ in
                isFilterCollapsed = false
                Task {
                    await viewModel.applyCurrentSelection()
                }
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
    
    let columns = [
        GridItem(.adaptive(minimum: 105), spacing: 16)
    ]

    var body: some View {
        let key = HomeCacheKey(category: category, filter: viewModel.selectedFilter)
        let items = viewModel.cachedItems[key]
        let isLoading = viewModel.isLoading[key] ?? false
        let isLoadingMore = viewModel.isLoadingMore[key] ?? false

        ScrollView {
            if isLoading || items == nil {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(0..<12, id: \.self) { _ in
                        MoviePosterCardPlaceholder()
                    }
                }
                .padding(16)
            } else if let items = items, items.isEmpty {
                HomeEmptyState(
                    category: category,
                    filter: viewModel.selectedFilter
                )
                .frame(maxWidth: .infinity, minHeight: 300)
                .padding(.horizontal, 20)
            } else if let items = items {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(items) { movie in
                        MovieDetailsNavigationLink(movie: movie, navigationTransition: navigationTransition)
                        .onAppear {
                            if movie.id == items.last?.id {
                                Task {
                                    await viewModel.loadData(for: category)
                                }
                            }
                        }
                    }

                    if isLoadingMore {
                        ForEach(0..<3, id: \.self) { _ in
                            MoviePosterCardPlaceholder()
                        }
                    }
                }
                .padding(16)
            }
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { oldOffset, newOffset in
            let now = Date()
            guard now.timeIntervalSince(debouncer.lastStateChangeTime) > debouncer.debounceInterval else {
                return
            }
            
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
    @ScaledMetric(relativeTo: .headline) private var titleSize: CGFloat = 25

    private let titleHeight: CGFloat = 31

    private var visibleFilterHeight: CGFloat {
        0
    }

    private var tabHeight: CGFloat {
        titleHeight + visibleFilterHeight
    }

    private var tabSpacing: CGFloat {
        horizontalSizeClass == .regular ? 28 : 22
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
        baseColor: Color
    ) -> some View {
        return Text(text)
            .font(.system(size: size, weight: weight))
            .foregroundStyle(baseColor)
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
                                baseColor: isSelected ? .primary : .secondary
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
            .frame(height: tabHeight, alignment: .topLeading)
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

struct RemotePosterView: View {
    let url: URL?
    
    var body: some View {
        AsyncCachedImage(url: url) {
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .aspectRatio(2/3, contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shimmer()
        } content: { image in
            Image(uiImage: image)
                .resizable()
                .aspectRatio(2/3, contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } fallback: {
            FallbackPosterView()
        }
    }
}

struct MoviePosterCard: View {
    let movie: MediaDto

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let url = URL(string: movie.displayPosterUrl ?? "")
            RemotePosterView(url: url)

            VStack(alignment: .leading, spacing: 4) {
                Text(movie.displayTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let rating = movie.rating, rating > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .foregroundColor(.rating(rating))
                            .font(.system(size: 10))
                        Text(String(format: "%.1f", rating))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.rating(rating))
                    }
                }
            }
        }
    }
}

struct FallbackPosterView: View {
    var body: some View {
        ZStack {
            Color.clear
            Image(systemName: "film.fill")
                .font(.system(size: 30))
                .foregroundColor(.secondary.opacity(0.65))
        }
        .aspectRatio(2/3, contentMode: .fill)
        .glassEffect(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct MoviePosterCardPlaceholder: View {
    var body: some View {
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
