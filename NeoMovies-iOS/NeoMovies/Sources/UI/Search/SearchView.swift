import SwiftUI

struct SearchView: View {
    @StateObject private var viewModel = SearchViewModel()
    
    var body: some View {
        NavigationStack {
            List(viewModel.results) { movie in
                NavigationLink(destination: DetailsView(movieId: movie.id)) {
                    HStack {
                        AsyncImage(url: URL(string: movie.displayPosterUrl ?? "")) { phase in
                            if let image = phase.image {
                                image.resizable().aspectRatio(contentMode: .fill).frame(width: 50, height: 75).cornerRadius(4)
                            } else {
                                Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 50, height: 75).cornerRadius(4)
                            }
                        }
                        
                        VStack(alignment: .leading) {
                            Text(movie.displayTitle)
                                .font(.headline)
                            if let year = movie.year?.stringValue {
                                Text(year)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Search")
            .searchable(text: $viewModel.searchQuery, prompt: "Search movies and TV shows...")
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
