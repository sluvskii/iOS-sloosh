import SwiftUI
import UIKit

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
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HomeCategorySegmentedControl(selection: $viewModel.selectedCategory)
                        .frame(maxWidth: 260)
                }
            }
            .background(Color(UIColor.systemBackground))
            .task {
                await viewModel.selectCategory(.all)
            }
            .onChange(of: viewModel.selectedCategory) { _, newCategory in
                Task {
                    await viewModel.selectCategory(newCategory)
                }
            }
        }
    }
}

struct HomeCategorySegmentedControl: UIViewRepresentable {
    @Binding var selection: HomeCategory

    func makeUIView(context: Context) -> UISegmentedControl {
        let control = UISegmentedControl(items: HomeCategory.allCases.map(\.rawValue))
        control.selectedSegmentIndex = HomeCategory.allCases.firstIndex(of: selection) ?? 0
        control.apportionsSegmentWidthsByContent = true
        control.addTarget(
            context.coordinator,
            action: #selector(Coordinator.valueChanged(_:)),
            for: .valueChanged
        )
        return control
    }

    func updateUIView(_ uiView: UISegmentedControl, context: Context) {
        let selectedIndex = HomeCategory.allCases.firstIndex(of: selection) ?? 0
        if uiView.selectedSegmentIndex != selectedIndex {
            uiView.selectedSegmentIndex = selectedIndex
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    final class Coordinator: NSObject {
        private let selection: Binding<HomeCategory>

        init(selection: Binding<HomeCategory>) {
            self.selection = selection
        }

        @objc func valueChanged(_ sender: UISegmentedControl) {
            let categories = HomeCategory.allCases
            guard categories.indices.contains(sender.selectedSegmentIndex) else { return }
            selection.wrappedValue = categories[sender.selectedSegmentIndex]
        }
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
    
    private var loadedCategory: HomeCategory?
    
    private var currentPage = 1
    private var canLoadMore = true
    
    private var cachedItems: [HomeCategory: [MediaDto]] = [:]
    private var cachedPages: [HomeCategory: Int] = [:]
    private var cachedCanLoadMore: [HomeCategory: Bool] = [:]
    
    func selectCategory(_ category: HomeCategory) async {
        if loadedCategory == category && !items.isEmpty {
            selectedCategory = category
            return
        }
        
        selectedCategory = category
        
        if let cached = cachedItems[category], !cached.isEmpty {
            items = cached
            currentPage = cachedPages[category] ?? 1
            canLoadMore = cachedCanLoadMore[category] ?? true
            loadedCategory = category
            return
        }
        
        items = []
        currentPage = 1
        canLoadMore = true
        await loadData()
        loadedCategory = category
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
