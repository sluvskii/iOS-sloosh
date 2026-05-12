import SwiftUI

struct SearchView: View {
    @StateObject private var viewModel = SearchViewModel()
    
    var body: some View {
        NavigationStack {
            List(viewModel.results) { movie in
                NavigationLink(destination: DetailsView(movieId: movie.id)) {
                    HStack(spacing: 16) {
                        AsyncImage(url: URL(string: movie.displayPosterUrl ?? "")) { phase in
                            if let image = phase.image {
                                image.resizable().aspectRatio(contentMode: .fill).frame(width: 60, height: 90).cornerRadius(8)
                                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                            } else {
                                Rectangle().fill(Color.gray.opacity(0.2)).frame(width: 60, height: 90).cornerRadius(8)
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text(movie.displayTitle)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            
                            HStack {
                                if let year = movie.year?.stringValue {
                                    Text(year)
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .foregroundColor(.secondary)
                                }
                                
                                if let rating = movie.rating, rating > 0 {
                                    HStack(spacing: 2) {
                                        Image(systemName: "star.fill")
                                            .foregroundColor(.orange)
                                            .font(.system(size: 10))
                                        Text(String(format: "%.1f", rating))
                                            .font(.system(size: 12, weight: .bold, design: .rounded))
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.leading, 4)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Поиск")
            .searchable(text: $viewModel.searchQuery, prompt: "Фильмы и сериалы...")
            .onChange(of: viewModel.searchQuery) { newValue in
                Task {
                    await viewModel.performSearch()
                }
            }
        }
    }
}

@MainActor
class SearchViewModel: ObservableObject {
    @Published var searchQuery = ""
    @Published var results: [MediaDto] = []
    
    private var searchTask: Task<Void, Never>?
    
    func performSearch() async {
        searchTask?.cancel()
        
        guard !searchQuery.isEmpty else {
            results = []
            return
        }
        
        searchTask = Task {
            do {
                // Debounce
                try await Task.sleep(nanoseconds: 500_000_000)
                if Task.isCancelled { return }
                
                let searchResults = try await MoviesRepository.shared.searchMovies(query: searchQuery)
                if !Task.isCancelled {
                    self.results = searchResults
                }
            } catch {
                print("Search error: \(error)")
            }
        }
    }
}
