import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if viewModel.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        MovieSection(title: "Popular Movies", movies: viewModel.popularMovies)
                        MovieSection(title: "Top Rated Movies", movies: viewModel.topMovies)
                        MovieSection(title: "Top TV Shows", movies: viewModel.topTv)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("NeoMovies")
            .task {
                await viewModel.loadData()
            }
        }
    }
}

struct MovieSection: View {
    let title: String
    let movies: [MediaDto]
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.title2)
                .bold()
                .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(movies) { movie in
                        NavigationLink(destination: DetailsView(movieId: movie.id)) {
                            MoviePosterCard(movie: movie)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

struct MoviePosterCard: View {
    let movie: MediaDto
    
    var body: some View {
        VStack {
            AsyncImage(url: URL(string: movie.displayPosterUrl ?? "")) { phase in
                switch phase {
                case .empty:
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 120, height: 180)
                        .cornerRadius(8)
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 120, height: 180)
                        .cornerRadius(8)
                case .failure:
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 120, height: 180)
                        .cornerRadius(8)
                        .overlay(
                            Image(systemName: "film")
                                .foregroundColor(.gray)
                        )
                @unknown default:
                    EmptyView()
                }
            }
            
            Text(movie.displayTitle)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 120)
        }
    }
}

@MainActor
class HomeViewModel: ObservableObject {
    @Published var popularMovies: [MediaDto] = []
    @Published var topMovies: [MediaDto] = []
    @Published var topTv: [MediaDto] = []
    @Published var isLoading = true
    
    func loadData() async {
        isLoading = true
        defer { isLoading = false }
        
        async let pop = MoviesRepository.shared.getPopularMovies()
        async let topM = MoviesRepository.shared.getTopMovies()
        async let topT = MoviesRepository.shared.getTopTv()
        
        do {
            popularMovies = try await pop
            topMovies = try await topM
            topTv = try await topT
        } catch {
            print("Failed to load home data: \(error)")
        }
    }
}
