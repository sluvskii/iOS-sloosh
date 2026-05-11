import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    if viewModel.isLoading {
                        ProgressView("Загрузка...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.top, 100)
                    } else {
                        MovieSection(title: "Популярные", movies: viewModel.popularMovies)
                        MovieSection(title: "Высокий рейтинг", movies: viewModel.topMovies)
                        MovieSection(title: "Топ сериалы", movies: viewModel.topTv)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("NeoMovies")
            .background(Color(UIColor.systemGroupedBackground))
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
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(movies) { movie in
                        NavigationLink(destination: DetailsView(movieId: movie.id)) {
                            MoviePosterCard(movie: movie)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 10)
            }
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
                        .fill(Color.gray.opacity(0.1))
                        .frame(width: 140, height: 210)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 140, height: 210)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        // Native Liquid Glass effect matching SlooshIOS Theme
                        .overlay(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.25), radius: 15, x: 0, y: 10)
                case .failure:
                    Rectangle()
                        .fill(.regularMaterial)
                        .frame(width: 140, height: 210)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .overlay(
                            Image(systemName: "film.fill")
                                .font(.system(size: 30))
                                .foregroundColor(.gray.opacity(0.5))
                        )
                @unknown default:
                    EmptyView()
                }
            }
            
            Text(movie.displayTitle)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(width: 140, alignment: .leading)
            
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
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
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
