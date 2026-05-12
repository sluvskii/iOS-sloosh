import SwiftUI

struct DetailsView: View {
    let movieId: String
    @StateObject private var viewModel = DetailsViewModel()
    
    @State private var showPlayer = false
    @State private var selectedIframeUrl: String? = nil
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if viewModel.isLoading {
                    ProgressView("Загрузка...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 100)
                } else if let details = viewModel.details {
                    // Backdrop
                    AsyncImage(url: URL(string: details.backdropUrl ?? details.posterUrl ?? "")) { phase in
                        if let image = phase.image {
                            image.resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(height: 300)
                                .clipped()
                                .overlay(
                                    LinearGradient(gradient: Gradient(colors: [.clear, Color(UIColor.systemBackground)]), startPoint: .top, endPoint: .bottom)
                                )
                        } else {
                            Rectangle().fill(Color.gray.opacity(0.2)).frame(height: 300)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text(details.title ?? details.name ?? "Без названия")
                            .font(.system(size: 28, weight: .heavy, design: .rounded))
                        
                        HStack(spacing: 12) {
                            if let rating = details.rating, rating > 0 {
                                HStack(spacing: 4) {
                                    Image(systemName: "star.fill")
                                        .foregroundColor(.orange)
                                    Text(String(format: "%.1f", rating))
                                        .bold()
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.orange.opacity(0.2))
                                .cornerRadius(8)
                            }
                            
                            if let year = details.releaseDate?.prefix(4) {
                                Text(String(year))
                                    .font(.subheadline)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.gray.opacity(0.2))
                                    .cornerRadius(8)
                            }
                        }
                        
                        Text(details.description ?? "Описание отсутствует.")
                            .font(.system(size: 16, weight: .regular, design: .rounded))
                            .foregroundColor(.secondary)
                            .lineSpacing(4)
                        
                        // Play Button
                        Button(action: {
                            Task {
                                if let kpId = details.externalIds?.kp {
                                    await viewModel.fetchAllohaSources(kpId: kpId)
                                }
                            }
                        }) {
                            HStack {
                                if viewModel.isFetchingSources {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .padding(.trailing, 8)
                                } else {
                                    Image(systemName: "play.fill")
                                }
                                Text(viewModel.isFetchingSources ? "Загрузка..." : "Смотреть")
                                    .font(.system(size: 16, weight: .bold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.neoAccent)
                            .foregroundColor(.white)
                            .cornerRadius(16)
                        }
                        .disabled(viewModel.isFetchingSources)
                        .padding(.top, 16)
                    }
                    .padding(.horizontal)
                    .offset(y: -40)
                } else {
                    Text("Не удалось загрузить данные.")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 100)
                }
            }
        }
        .edgesIgnoringSafeArea(.top)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadDetails(id: movieId)
        }
        .sheet(item: $viewModel.alohaResultWrapper) { wrapper in
            SourceSelectionView(result: wrapper.result) { iframeUrl in
                selectedIframeUrl = iframeUrl
                showPlayer = true
            }
            .presentationDetents([.medium, .large])
        }
        .fullScreenCover(isPresented: $showPlayer) {
            if let iframeUrl = selectedIframeUrl, let details = viewModel.details {
                PlayerView(iframeUrl: iframeUrl, fallbackTitle: details.title ?? details.name ?? "")
            }
        }
    }
}

// Обертка для Identifiable, чтобы использовать в .sheet(item:)
struct AllohaResultWrapper: Identifiable {
    let id = UUID()
    let result: AllohaApiResult
}

@MainActor
class DetailsViewModel: ObservableObject {
    @Published var details: MediaDetailsDto?
    @Published var isLoading = true
    
    @Published var isFetchingSources = false
    @Published var alohaResultWrapper: AllohaResultWrapper?
    
    func loadDetails(id: String) async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            details = try await MoviesRepository.shared.getDetails(id: id)
        } catch {
            print("Error loading details: \(error)")
        }
    }
    
    func fetchAllohaSources(kpId: Int) async {
        isFetchingSources = true
        defer { isFetchingSources = false }
        
        do {
            let result = try await AllohaRepository.shared.fetchByKpId(kpId: kpId)
            self.alohaResultWrapper = AllohaResultWrapper(result: result)
        } catch {
            print("Error fetching Alloha sources: \(error)")
        }
    }
}
