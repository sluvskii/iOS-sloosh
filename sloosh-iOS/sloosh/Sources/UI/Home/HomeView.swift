import SwiftUI
import UIKit

enum HomeCategory: String, CaseIterable {
    case all = "Все"
    case movies = "Фильмы"
    case tvShows = "Сериалы"
    case cartoons = "Мультфильмы"

    var title: String { rawValue }
}

enum HomeFilter: String, CaseIterable, Identifiable {
    case popular = "Популярное"
    case latest = "Свежие"
    case topRated = "По рейтингу"

    var id: String { rawValue }

    var title: String { rawValue }

    var systemImage: String {
        switch self {
        case .popular:
            return "flame.fill"
        case .latest:
            return "sparkles"
        case .topRated:
            return "star.fill"
        }
    }
}

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @Namespace private var topPanelNamespace

    let columns = [
        GridItem(.adaptive(minimum: 105), spacing: 16)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                if viewModel.isLoading {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(0..<12, id: \.self) { _ in
                            MoviePosterCardPlaceholder()
                        }
                    }
                    .padding(16)
                } else if viewModel.items.isEmpty {
                    HomeEmptyState(
                        category: viewModel.selectedCategory,
                        filter: viewModel.selectedFilter
                    )
                    .frame(maxWidth: .infinity, minHeight: 300)
                    .padding(.horizontal, 20)
                } else {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(viewModel.items) { movie in
                            NavigationLink(destination: DetailsView(movieId: movie.id)) {
                                MoviePosterCard(movie: movie)
                            }
                            .buttonStyle(.plain)
                            .onAppear {
                                if movie.id == viewModel.items.last?.id {
                                    Task {
                                        await viewModel.loadData()
                                    }
                                }
                            }
                        }

                        if viewModel.isLoadingMore {
                            ForEach(0..<3, id: \.self) { _ in
                                MoviePosterCardPlaceholder()
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .scrollIndicators(.hidden)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HomeCategoryToolbarStrip(
                        selectedCategory: $viewModel.selectedCategory,
                        namespace: topPanelNamespace
                    )
                }

                ToolbarItem(placement: .topBarTrailing) {
                    HomeFilterMenu(selectedFilter: $viewModel.selectedFilter)
                }
            }
            .background(Color(UIColor.systemBackground))
            .task {
                await viewModel.applyCurrentSelection(force: true)
            }
            .onChange(of: viewModel.selectedCategory) { _, newCategory in
                Task {
                    await viewModel.applyCurrentSelection()
                }
            }
            .onChange(of: viewModel.selectedFilter) { _, newFilter in
                Task {
                    await viewModel.applyCurrentSelection()
                }
            }
        }
    }
}

private struct HomeCategoryToolbarStrip: View {
    @Binding var selectedCategory: HomeCategory
    let namespace: Namespace.ID

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(HomeCategory.allCases, id: \.self) { category in
                    let isSelected = selectedCategory == category

                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                            selectedCategory = category
                        }
                    } label: {
                        Text(category.title)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(isSelected ? Color.black : Color.primary)
                            .lineLimit(1)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background {
                                ZStack {
                                    if isSelected {
                                        Capsule()
                                            .fill(Color.slooshAccent)
                                            .matchedGeometryEffect(id: "home-category-pill", in: namespace)
                                    } else {
                                        Capsule()
                                            .fill(.clear)
                                    }
                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: 320)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct HomeFilterMenu: View {
    @Binding var selectedFilter: HomeFilter

    var body: some View {
        Menu {
            Picker("Сортировка", selection: $selectedFilter) {
                ForEach(HomeFilter.allCases) { filter in
                    Label(filter.title, systemImage: filter.systemImage)
                        .tag(filter)
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
        }
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
                .font(.system(size: 22, weight: .bold, design: .rounded))

            Text("Попробуйте выбрать другую вкладку или сменить фильтрацию с `\(filter.title)` на другой режим.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

struct MoviePosterCard: View {
    let movie: MediaDto
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AsyncImage(url: URL(string: movie.displayPosterUrl ?? "")) { phase in
                switch phase {
                case .empty:
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .aspectRatio(2/3, contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shimmer()
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(2/3, contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        // Native Liquid Glass effect matching SlooshIOS Theme
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 4)
                case .failure:
                    Rectangle()
                        .fill(.regularMaterial)
                        .aspectRatio(2/3, contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            Image(systemName: "film.fill")
                                .font(.system(size: 30))
                                .foregroundColor(.gray.opacity(0.5))
                        )
                @unknown default:
                    EmptyView()
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(movie.displayTitle)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                if let rating = movie.rating, rating > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .foregroundColor(Color(UIColor { traitCollection in
                                if traitCollection.userInterfaceStyle == .dark {
                                    return UIColor(red: 0.70, green: 1.0, blue: 0.0, alpha: 1.0)
                                } else {
                                    return UIColor(red: 0.45, green: 0.80, blue: 0.0, alpha: 1.0)
                                }
                            }))
                            .font(.system(size: 10))
                        Text(String(format: "%.1f", rating))
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
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

@MainActor
class HomeViewModel: ObservableObject {
    @Published var selectedCategory: HomeCategory = .all
    @Published var selectedFilter: HomeFilter = .popular
    @Published var items: [MediaDto] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false

    private var loadedKey: HomeCacheKey?

    private var currentPage = 1
    private var canLoadMore = true

    private var cachedItems: [HomeCacheKey: [MediaDto]] = [:]
    private var cachedPages: [HomeCacheKey: Int] = [:]
    private var cachedCanLoadMore: [HomeCacheKey: Bool] = [:]

    func applyCurrentSelection(force: Bool = false) async {
        let key = HomeCacheKey(category: selectedCategory, filter: selectedFilter)

        if !force, loadedKey == key && !items.isEmpty {
            return
        }

        if !force, let cached = cachedItems[key], !cached.isEmpty {
            items = cached
            currentPage = cachedPages[key] ?? 1
            canLoadMore = cachedCanLoadMore[key] ?? true
            loadedKey = key
            return
        }

        items = []
        currentPage = 1
        canLoadMore = true
        await loadData()
        loadedKey = key
    }

    func loadData() async {
        guard canLoadMore, !isLoading, !isLoadingMore else { return }

        let cacheKey = HomeCacheKey(category: selectedCategory, filter: selectedFilter)

        if items.isEmpty {
            isLoading = true
        } else {
            isLoadingMore = true
        }

        defer {
            isLoading = false
            isLoadingMore = false
        }

        do {
            var newItems: [MediaDto] = []
            var pagesFetched = 0

            while newItems.isEmpty && pagesFetched < 3 && canLoadMore {
                let fetched = try await fetchPage(currentPage)
                if fetched.isEmpty {
                    canLoadMore = false
                    break
                }

                newItems.append(contentsOf: filterItemsForSelectedCategory(fetched))

                currentPage += 1
                pagesFetched += 1
            }

            let existingIds = Set(items.map { $0.id })
            let uniqueNewItems = newItems.filter { !existingIds.contains($0.id) }

            items.append(contentsOf: uniqueNewItems)

            cachedItems[cacheKey] = items
            cachedPages[cacheKey] = currentPage
            cachedCanLoadMore[cacheKey] = canLoadMore
        } catch {
            print("Failed to load category data: \(error)")
        }
    }

    private func fetchPage(_ page: Int) async throws -> [MediaDto] {
        let baseItems: [MediaDto]

        switch selectedFilter {
        case .popular:
            baseItems = try await MoviesRepository.shared.getPopularMovies(page: page)
        case .latest:
            let popular = try await MoviesRepository.shared.getPopularMovies(page: page)
            baseItems = popular.sorted { lhs, rhs in
                let leftYear = extractedYear(from: lhs)
                let rightYear = extractedYear(from: rhs)
                if leftYear == rightYear {
                    return (lhs.rating ?? 0) > (rhs.rating ?? 0)
                }
                return leftYear > rightYear
            }
        case .topRated:
            switch selectedCategory {
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

    private func filterItemsForSelectedCategory(_ items: [MediaDto]) -> [MediaDto] {
        switch selectedCategory {
        case .all:
            return items
        case .movies:
            return items.filter { $0.type == "movie" && !isCartoon($0) }
        case .tvShows:
            return items.filter { $0.type == "tv" && !isCartoon($0) }
        case .cartoons:
            return items.filter(isCartoon)
        }
    }

    private func isCartoon(_ item: MediaDto) -> Bool {
        let genreNames = item.genres?
            .compactMap { $0.name?.lowercased() }
            .joined(separator: " ") ?? ""

        let haystack = [
            genreNames,
            item.displayTitle.lowercased(),
            item.originalTitle?.lowercased() ?? ""
        ].joined(separator: " ")

        return haystack.contains("мульт")
            || haystack.contains("анимац")
            || haystack.contains("animation")
            || haystack.contains("anime")
    }

    private func extractedYear(from item: MediaDto) -> Int {
        let raw = item.year?.stringValue ?? ""
        return Int(raw.prefix(4)) ?? 0
    }
}

private struct HomeCacheKey: Hashable {
    let category: HomeCategory
    let filter: HomeFilter
}
