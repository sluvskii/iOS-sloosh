import SwiftUI

@MainActor
final class StudioCatalogViewModel: ObservableObject {
    let studioId: String
    let studioName: String
    
    @Published var items: [MediaDto] = []
    @Published var isLoading = false
    @Published var isAppending = false
    @Published var currentPage = 1
    @Published var totalPages = 1
    @Published var directPlaybackMovie: MediaDto? = nil
    @Published var playerConfig: PlayerConfig? = nil
    
    init(studioId: String, studioName: String) {
        self.studioId = studioId
        self.studioName = studioName
        Task {
            await loadInitial()
        }
    }
    
    func loadInitial(force: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        currentPage = 1
        
        do {
            let result = try await MoviesRepository.shared.getCollection(id: studioId, page: 1)
            self.items = result.items
            self.totalPages = result.totalPages
        } catch {
            self.items = []
        }
        
        isLoading = false
    }
    
    func loadNextPage() async {
        guard !isLoading, !isAppending, currentPage < totalPages else { return }
        isAppending = true
        let nextPage = currentPage + 1
        
        do {
            let result = try await MoviesRepository.shared.getCollection(id: studioId, page: nextPage)
            let newItems = result.items.filter { newItem in
                !self.items.contains { $0.id == newItem.id }
            }
            self.items.append(contentsOf: newItems)
            self.currentPage = nextPage
            self.totalPages = result.totalPages
        } catch {
            // End of pages or network error
        }
        
        isAppending = false
    }
}

struct StudioCatalogView: View {
    let studioId: String
    let studioName: String
    @StateObject private var viewModel: StudioCatalogViewModel
    @State private var pendingPlayerConfig: PlayerConfig? = nil
    @Namespace private var navigationTransition
    @AppStorage("cardDensity") private var cardDensity: CardDensity = .regular
    @Environment(\.dismiss) private var dismiss

    init(studioId: String, studioName: String) {
        self.studioId = studioId
        self.studioName = studioName
        _viewModel = StateObject(wrappedValue: StudioCatalogViewModel(studioId: studioId, studioName: studioName))
    }

    private var brand: StudioBrand? {
        StudioBrand.find(by: studioId) ?? StudioBrand.find(by: studioName)
    }

    private var columns: [GridItem] {
        let spacing: CGFloat = cardDensity == .compact ? 8 : 16
        let minWidth: CGFloat = cardDensity == .compact ? 95 : 105
        return [GridItem(.adaptive(minimum: minWidth), spacing: spacing)]
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if viewModel.isLoading && viewModel.items.isEmpty {
                    let spacing: CGFloat = cardDensity == .compact ? 8 : 16
                    let padding: CGFloat = cardDensity == .compact ? 12 : 16
                    LazyVGrid(columns: columns, spacing: spacing) {
                        ForEach(0..<9, id: \.self) { _ in
                            MoviePosterCardPlaceholder()
                        }
                    }
                    .padding(padding)
                } else if viewModel.items.isEmpty {
                    AppEmptyStateView(
                        icon: "film.stack",
                        title: "Ничего не найдено",
                        description: "В каталоге студии «\(studioName)» пока нет доступных релизов"
                    )
                    .padding(.top, 60)
                } else {
                    let spacing: CGFloat = cardDensity == .compact ? 8 : 16
                    let padding: CGFloat = cardDensity == .compact ? 12 : 16
                    LazyVGrid(columns: columns, spacing: spacing) {
                        ForEach(viewModel.items) { movie in
                            MovieDetailsNavigationLink(movie: movie, navigationTransition: navigationTransition, studio: brand)
                                .contextMenu {
                                    Group {
                                        Button {
                                            viewModel.directPlaybackMovie = movie
                                        } label: {
                                            Label("Смотреть", systemImage: "play.fill")
                                        }
                                        
                                        NavigationLink(destination: DetailsView(movieId: movie.id, navigationTransitionID: nil, navigationTransitionNamespace: nil, initialStudio: brand).navigationBarBackButtonHidden(true)) {
                                            Label("Подробнее", systemImage: "info.circle")
                                        }
                                    }
                                    .tint(nil)
                                }
                                .onAppear {
                                    if movie.id == viewModel.items.last?.id {
                                        Task {
                                            await viewModel.loadNextPage()
                                        }
                                    }
                                }
                        }

                        if viewModel.isAppending {
                            ForEach(0..<3, id: \.self) { _ in
                                MoviePosterCardPlaceholder()
                            }
                        }
                    }
                    .padding(padding)
                }
            }
        }
        .navigationTitle(studioName)
        .navigationBarTitleDisplayMode(.large)
        .fullWidthSwipeBack()
        .sheet(item: $viewModel.directPlaybackMovie, onDismiss: {
            if let pending = pendingPlayerConfig {
                pendingPlayerConfig = nil
                DispatchQueue.main.async {
                    viewModel.playerConfig = pending
                }
            }
        }) { movie in
            HomeDirectPlayWrapper(
                movieId: movie.id,
                fallbackTitle: movie.title ?? movie.name ?? movie.originalTitle ?? "",
                initialKpId: movie.externalIds?.kp
            ) { config in
                pendingPlayerConfig = config
                viewModel.directPlaybackMovie = nil
            }
        }
        .fullScreenCover(item: $viewModel.playerConfig) { config in
            PlayerView(config: config)
        }
    }
}
