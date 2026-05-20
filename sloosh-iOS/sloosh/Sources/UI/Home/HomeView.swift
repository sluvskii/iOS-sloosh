import SwiftUI

enum HomeCategory: String, CaseIterable {
    case all = "Все"
    case movies = "Фильмы"
    case tvShows = "Сериалы"
}

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    
    let columns = [
        GridItem(.adaptive(minimum: 105), spacing: 16)
    ]
    
    var body: some View {
        NavigationStack {
            // Infinite Grid
            ScrollView {
                if viewModel.isLoading {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(0..<12, id: \.self) { _ in
                            MoviePosterCardPlaceholder()
                        }
                    }
                    .padding(16)
                    .padding(.top, 8)
                } else if viewModel.items.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "film")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        Text("Ничего не найдено")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 300)
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
                    .padding(.top, 8)
                }
            }
            .safeAreaInset(edge: .top) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        ForEach(HomeCategory.allCases, id: \.self) { category in
                            NavBarTab(
                                title: category.rawValue,
                                isSelected: viewModel.selectedCategory == category
                            ) {
                                Task {
                                    await viewModel.selectCategory(category)
                                }
                            }
                        }
                    }
                    .padding(.top, 8)
                }
                .background(.ultraThinMaterial)
                .overlay(
                    Rectangle()
                        .frame(height: 0.5)
                        .foregroundColor(Color.primary.opacity(0.1)),
                    alignment: .bottom
                )
            }
            .navigationTitle("")
            .navigationBarHidden(true)
            .background(Color(UIColor.systemBackground))
            .task {
                await viewModel.selectCategory(.all)
            }
        }
    }
}

struct CategoryPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.primary : Color(UIColor.secondarySystemBackground))
                .foregroundColor(isSelected ? Color(UIColor.systemBackground) : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct NavBarTab: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 16, weight: isSelected ? .bold : .medium, design: .rounded))
                    .foregroundColor(isSelected ? .primary : .secondary)
                
                Rectangle()
                    .fill(isSelected ? Color.primary : Color.clear)
                    .frame(height: 3)
                    .cornerRadius(1.5)
                    .padding(.horizontal, 16)
            }
            .padding(.top, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
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
    @Published var items: [MediaDto] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    
    private var currentPage = 1
    private var canLoadMore = true
    
    private var cachedItems: [HomeCategory: [MediaDto]] = [:]
    private var cachedPages: [HomeCategory: Int] = [:]
    private var cachedCanLoadMore: [HomeCategory: Bool] = [:]
    
    func selectCategory(_ category: HomeCategory) async {
        if selectedCategory == category && !items.isEmpty {
            return
        }
        
        selectedCategory = category
        
        if let cached = cachedItems[category], !cached.isEmpty {
            items = cached
            currentPage = cachedPages[category] ?? 1
            canLoadMore = cachedCanLoadMore[category] ?? true
            return
        }
        
        items = []
        currentPage = 1
        canLoadMore = true
        await loadData()
    }
    
    func loadData() async {
        guard canLoadMore, !isLoading, !isLoadingMore else { return }
        
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
            
            // To ensure we get enough items for filtered categories, we might fetch multiple pages
            while newItems.isEmpty && pagesFetched < 3 && canLoadMore {
                let fetched = try await fetchPage(currentPage)
                if fetched.isEmpty {
                    canLoadMore = false
                    break
                }
                
                switch selectedCategory {
                case .all:
                    newItems.append(contentsOf: fetched)
                case .movies:
                    newItems.append(contentsOf: fetched.filter { $0.type == "movie" })
                case .tvShows:
                    newItems.append(contentsOf: fetched.filter { $0.type == "tv" })
                }
                
                currentPage += 1
                pagesFetched += 1
            }
            
            let existingIds = Set(items.map { $0.id })
            let uniqueNewItems = newItems.filter { !existingIds.contains($0.id) }
            
            items.append(contentsOf: uniqueNewItems)
            
            cachedItems[selectedCategory] = items
            cachedPages[selectedCategory] = currentPage
            cachedCanLoadMore[selectedCategory] = canLoadMore
            
        } catch {
            print("Failed to load category data: \(error)")
        }
    }
    
    private func fetchPage(_ page: Int) async throws -> [MediaDto] {
        switch selectedCategory {
        case .all, .movies, .tvShows:
            return try await MoviesRepository.shared.getPopularMovies(page: page)
        }
    }
}
