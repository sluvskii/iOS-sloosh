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
}

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()

    var body: some View {
        NavigationStack {
            let categoryBinding = Binding<HomeCategory?>(
                get: { viewModel.selectedCategory },
                set: { if let val = $0 { viewModel.selectedCategory = val } }
            )

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(HomeCategory.allCases, id: \.self) { category in
                        HomeCategoryContentView(viewModel: viewModel, category: category)
                            .containerRelativeFrame(.horizontal)
                            .id(category)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: categoryBinding)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: viewModel.selectedCategory)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("sloosh")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.accentColor, .accentColor.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                ToolbarItem(placement: .principal) {
                    HomeCategorySegmentedPicker(selectedCategory: $viewModel.selectedCategory)
                        .scaleEffect(0.9) // Делаем панель чуть меньше (тоньше), чтобы не было обрезки
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HomeFilterMenu(selectedFilter: $viewModel.selectedFilter)
                }
            }
            .task {
                await viewModel.applyCurrentSelection(force: true)
            }
            .onChange(of: viewModel.selectedCategory) { _, _ in
                Task {
                    await viewModel.applyCurrentSelection()
                }
            }
            .onChange(of: viewModel.selectedFilter) { _, _ in
                Task {
                    await viewModel.applyCurrentSelection()
                }
            }
        }
    }
}

struct HomeCategoryContentView: View {
    @ObservedObject var viewModel: HomeViewModel
    let category: HomeCategory
    
    let columns = [
        GridItem(.adaptive(minimum: 105), spacing: 16)
    ]

    var body: some View {
        let key = HomeCacheKey(category: category, filter: viewModel.selectedFilter)
        let items = viewModel.cachedItems[key] ?? []
        let isLoading = viewModel.isLoading[key] ?? false
        let isLoadingMore = viewModel.isLoadingMore[key] ?? false

        ScrollView {
            if isLoading {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(0..<12, id: \.self) { _ in
                        MoviePosterCardPlaceholder()
                    }
                }
                .padding(16)
            } else if items.isEmpty {
                HomeEmptyState(
                    category: category,
                    filter: viewModel.selectedFilter
                )
                .frame(maxWidth: .infinity, minHeight: 300)
                .padding(.horizontal, 20)
            } else {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(items) { movie in
                        NavigationLink(destination: DetailsView(movieId: movie.id)) {
                            MoviePosterCard(movie: movie)
                        }
                        .buttonStyle(.plain)
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
        .scrollIndicators(.hidden)
    }
}

private struct HomeCategorySegmentedPicker: View {
    @Binding var selectedCategory: HomeCategory

    var body: some View {
        Picker("Категория", selection: $selectedCategory) {
            ForEach(HomeCategory.allCases, id: \.self) { category in
                Text(category.segmentedTitle)
                    .tag(category)
            }
        }
        .pickerStyle(.segmented)
    }
}

private struct HomeFilterMenu: View {
    @Binding var selectedFilter: HomeFilter

    var body: some View {
        Menu {
            Picker("Сортировка", selection: $selectedFilter) {
                ForEach(HomeFilter.allCases) { filter in
                    Text(filter.title)
                        .tag(filter)
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Color(UIColor.label))
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
                .font(.system(size: 22, weight: .bold))

            Text("Попробуйте выбрать другую вкладку или сменить фильтрацию с `\(filter.title)` на другой режим.")
                .font(.system(size: 15, weight: .medium))
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

struct RemotePosterView: View {
    let url: URL?
    
    @State private var image: UIImage?
    @State private var isLoading = false
    @State private var hasError = false
    
    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(2/3, contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 4)
            } else if isLoading {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .aspectRatio(2/3, contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shimmer()
            } else {
                FallbackPosterView()
            }
        }
        .task(id: url) {
            guard let url = url, image == nil else {
                if url == nil {
                    isLoading = false
                    hasError = true
                }
                return
            }
            
            isLoading = true
            hasError = false
            
            do {
                let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)
                let (data, _) = try await URLSession.shared.data(for: request)
                if let uiImg = UIImage(data: data) {
                    self.image = uiImg
                } else {
                    self.hasError = true
                }
            } catch {
                if !Task.isCancelled {
                    self.hasError = true
                }
            }
            
            isLoading = false
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
                            .foregroundColor(Color(UIColor { traitCollection in
                                if traitCollection.userInterfaceStyle == .dark {
                                    return UIColor(red: 0.70, green: 1.0, blue: 0.0, alpha: 1.0)
                                } else {
                                    return UIColor(red: 0.45, green: 0.80, blue: 0.0, alpha: 1.0)
                                }
                            }))
                            .font(.system(size: 10))
                        Text(String(format: "%.1f", rating))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

struct FallbackPosterView: View {
    var body: some View {
        Rectangle()
            .fill(.regularMaterial)
            .aspectRatio(2/3, contentMode: .fill)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                Image(systemName: "film.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.gray.opacity(0.5))
            )
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

    func applyCurrentSelection(force: Bool = false) async {
        let key = HomeCacheKey(category: selectedCategory, filter: selectedFilter)

        if force {
            cachedItems[key] = []
            cachedPages[key] = 1
            cachedCanLoadMore[key] = true
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
