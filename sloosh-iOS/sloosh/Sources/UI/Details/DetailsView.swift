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

                        AsyncImage(url: URL(string: details.displayBackdropUrl ?? details.displayPosterUrl ?? "")) { phase in
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
                                    await viewModel.fetchSources(kpId: kpId, title: details.title ?? details.name ?? "")
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
        .sheet(item: $viewModel.sourceResultWrapper) { wrapper in
            if wrapper.mode == .alloha, let result = wrapper.allohaResult {
                SourceSelectionView(result: result) { iframeUrl in
                    selectedIframeUrl = iframeUrl
                    showPlayer = true
                }
                .presentationDetents([.medium, .large])
            } else if wrapper.mode == .collaps {
                let isSerial = wrapper.collapsSeasons != nil && !(wrapper.collapsSeasons?.isEmpty ?? true)
                CollapsSelectionView(
                    result: wrapper.collapsSeasons ?? [],
                    movieResult: wrapper.collapsMovie,
                    isSerial: isSerial,
                    title: viewModel.details?.title ?? viewModel.details?.name ?? "",
                    onPlay: { url in
                        // Collaps returns direct HLS/MPD urls
                        selectedIframeUrl = url // we use this state variable for the URL
                        showPlayer = true
                    }
                )
                .presentationDetents([.medium, .large])
            } else {
                Text("Нет доступных источников")
            }
        }
        .fullScreenCover(isPresented: $showPlayer) {
            if let url = selectedIframeUrl, let details = viewModel.details {
                let mode = SourceManager.shared.currentMode
                if mode == .alloha {
                    PlayerView(iframeUrl: url, fallbackTitle: details.title ?? details.name ?? "")
                } else {
                    PlayerView(directVideoUrl: url, fallbackTitle: details.title ?? details.name ?? "")
                }
            }
        }
    }
}

// Обертка для Identifiable, чтобы использовать в .sheet(item:)
struct SourceResultWrapper: Identifiable {
    let id = UUID()
    let mode: SourceMode
    var allohaResult: AllohaApiResult?
    var collapsSeasons: [CollapsSeason]?
    var collapsMovie: CollapsMovie?
}

@MainActor
class DetailsViewModel: ObservableObject {
    @Published var details: MediaDetailsDto?
    @Published var isLoading = true
    
    @Published var isFetchingSources = false
    @Published var sourceResultWrapper: SourceResultWrapper?
    
    func loadDetails(id: String) async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            details = try await MoviesRepository.shared.getDetails(id: id)
        } catch {
            print("Error loading details: \(error)")
        }
    }
    
    func fetchSources(kpId: Int, title: String) async {
        isFetchingSources = true
        defer { isFetchingSources = false }
        
        let mode = SourceManager.shared.currentMode
        do {
            switch mode {
            case .alloha:
                let result = try await AllohaRepository.shared.fetchByKpId(kpId: kpId)
                self.sourceResultWrapper = SourceResultWrapper(mode: .alloha, allohaResult: result)
            case .collaps:
                let seasons = try await CollapsRepository.shared.getSeasonsByKpId(kpId: kpId)
                if seasons.isEmpty {
                    let movie = try await CollapsRepository.shared.getMovieByKpId(kpId: kpId)
                    self.sourceResultWrapper = SourceResultWrapper(mode: .collaps, collapsMovie: movie)
                } else {
                    self.sourceResultWrapper = SourceResultWrapper(mode: .collaps, collapsSeasons: seasons)
                }
            }
        } catch {
            print("Error fetching sources: \(error)")
        }
    }
}
