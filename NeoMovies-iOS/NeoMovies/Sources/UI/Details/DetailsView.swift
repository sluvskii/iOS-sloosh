import SwiftUI

struct DetailsView: View {
    let movieId: String
    @StateObject private var viewModel = DetailsViewModel()
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let details = viewModel.details {
                    // Backdrop
                    AsyncImage(url: URL(string: details.backdropUrl ?? "")) { phase in
                        if let image = phase.image {
                            image.resizable().aspectRatio(contentMode: .fit)
                        } else {
                            Rectangle().fill(Color.gray.opacity(0.3)).frame(height: 200)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(details.title ?? details.name ?? "Unknown")
                            .font(.title)
                            .bold()
                        
                        if let rating = details.rating {
                            HStack {
                                Image(systemName: "star.fill")
                                    .foregroundColor(.yellow)
                                Text(String(format: "%.1f", rating))
                            }
                        }
                        
                        Text(details.description ?? "No description available.")
                            .font(.body)
                        
                        // Play Button
                        NavigationLink(destination: PlayerView(movieId: movieId, videoUrl: "sample_url")) {
                            HStack {
                                Image(systemName: "play.fill")
                                Text("Watch")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        .padding(.top)
                    }
                    .padding()
                } else {
                    Text("Failed to load details.")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadDetails(id: movieId)
        }
    }
}

@MainActor
class DetailsViewModel: ObservableObject {
    @Published var details: MediaDetailsDto?
    @Published var isLoading = true
    
    func loadDetails(id: String) async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            details = try await MoviesRepository.shared.getDetails(id: id)
        } catch {
            print("Error loading details: \(error)")
        }
    }
}
