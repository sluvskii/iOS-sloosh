import SwiftUI

struct DetailsView: View {
    let movieId: String
    @StateObject private var viewModel = DetailsViewModel()
    
    @State private var showPlayer = false
    @State private var selectedIframeUrl: String? = nil
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if viewModel.isLoading {
                    ProgressView("Загрузка...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 100)
                } else if let details = viewModel.details {
                    // Stretchy Backdrop
                    GeometryReader { geometry in
                        let minY = geometry.frame(in: .global).minY
                        let isScrollingDown = minY > 0
                        let height = isScrollingDown ? 450 + minY : 450
                        let offset = isScrollingDown ? -minY : 0

                        AsyncImage(url: URL(string: details.backdropUrl ?? details.posterUrl ?? "")) { phase in
                            if let image = phase.image {
                                image.resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: geometry.size.width, height: height)
                                    .clipped()
                            } else {
                                Rectangle().fill(Color.gray.opacity(0.2))
                                    .frame(width: geometry.size.width, height: height)
                            }
                        }
                        .offset(y: offset)
                        .overlay(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    .clear,
                                    .clear,
                                    Color(UIColor.systemBackground).opacity(0.6),
                                    Color(UIColor.systemBackground)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .offset(y: offset)
                        )
                    }
                    .frame(height: 450)
                    
                    VStack(alignment: .center, spacing: 12) {
                        Text(details.title ?? details.name ?? "Без названия")
                            .font(.system(size: 34, weight: .heavy, design: .rounded))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        // Metadata Row
                        HStack(spacing: 8) {
                            if let rating = details.rating, rating > 0 {
                                HStack(spacing: 4) {
                                    Image(systemName: "star.fill")
                                        .foregroundColor(.orange)
                                    Text(String(format: "%.1f", rating))
                                        .bold()
                                }
                            }
                            
                            if details.rating != nil, details.rating! > 0, details.releaseDate != nil {
                                Text("·").foregroundColor(.secondary)
                            }
                            
                            if let year = details.releaseDate?.prefix(4) {
                                Text(String(year))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .font(.system(size: 15, weight: .medium))
                        
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
                                        .progressViewStyle(CircularProgressViewStyle(tint: Color(UIColor.systemBackground)))
                                        .padding(.trailing, 8)
                                } else {
                                    Image(systemName: "play.fill")
                                }
                                Text(viewModel.isFetchingSources ? "Загрузка..." : "Смотреть")
                                    .font(.system(size: 18, weight: .bold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.primary)
                            .foregroundColor(Color(UIColor.systemBackground))
                            .clipShape(Capsule())
                        }
                        .disabled(viewModel.isFetchingSources)
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                        
                        Text(details.description ?? "Описание отсутствует.")
                            .font(.system(size: 16, weight: .regular, design: .rounded))
                            .foregroundColor(.secondary)
                            .lineSpacing(4)
                            .padding(.top, 24)
                            .padding(.horizontal)
                    }
                    .offset(y: -80)
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
