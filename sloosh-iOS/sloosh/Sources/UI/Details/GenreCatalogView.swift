import SwiftUI

struct GenreCatalogView: View {
    let genre: String
    @StateObject private var viewModel: GenreCatalogViewModel
    @State private var pendingPlayerConfig: PlayerConfig? = nil
    @Namespace private var navigationTransition
    @AppStorage("cardDensity") private var cardDensity: CardDensity = .regular
    @Environment(\.dismiss) private var dismiss

    init(genre: String) {
        self.genre = genre
        _viewModel = StateObject(wrappedValue: GenreCatalogViewModel(genre: genre))
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
                        icon: "film",
                        title: "Ничего не найдено",
                        description: "В категории «\(genre.capitalized)» пока нет доступных фильмов"
                    )
                    .padding(.top, 60)
                } else {
                    let spacing: CGFloat = cardDensity == .compact ? 8 : 16
                    let padding: CGFloat = cardDensity == .compact ? 12 : 16
                    LazyVGrid(columns: columns, spacing: spacing) {
                        ForEach(viewModel.items) { movie in
                            MovieDetailsNavigationLink(movie: movie, navigationTransition: navigationTransition)
                                .contextMenu {
                                    Group {
                                        Button {
                                            viewModel.directPlaybackMovie = movie
                                        } label: {
                                            Label("Смотреть", systemImage: "play.fill")
                                        }
                                        
                                        NavigationLink(destination: DetailsView(movieId: movie.id, navigationTransitionID: nil, navigationTransitionNamespace: nil)) {
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
        .refreshable {
            await viewModel.loadInitial(force: true)
        }
        .navigationTitle(genre.capitalized)
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
        .fullScreenCover(item: $viewModel.playerConfig, onDismiss: {
            viewModel.playerConfig = nil
        }) { config in
            PlayerView(
                iframeUrl: config.iframeUrl,
                fallbackTitle: config.title,
                kpId: config.kpId,
                season: config.season,
                episode: config.episode,
                selectedVoiceover: config.voiceover,
                directStreamUrl: config.streamUrl,
                voices: config.voices,
                subtitles: config.subtitles,
                initialQuality: config.quality,
                seriesResult: config.seriesResult
            )
        }
        .task {
            if viewModel.items.isEmpty {
                await viewModel.loadInitial()
            }
        }
    }
}

@MainActor
class GenreCatalogViewModel: ObservableObject {
    let genre: String
    @Published var items: [MediaDto] = []
    @Published var isLoading = false
    @Published var isAppending = false
    @Published var canLoadMore = true
    @Published var directPlaybackMovie: MediaDto? = nil
    @Published var playerConfig: PlayerConfig? = nil

    private var page = 1

    init(genre: String) {
        self.genre = genre
    }

    func loadInitial(force: Bool = false) async {
        guard !isLoading else { return }
        if force {
            page = 1
            canLoadMore = true
            items = []
        }
        isLoading = true
        defer { isLoading = false }

        do {
            let filters = SearchFilters(genres: genre)
            let response = try await MoviesRepository.shared.searchMoviesResponse(query: "", page: 1, filters: filters)
            let valid = filterValidItems(response.results ?? [])
            items = valid
            page = 1
            canLoadMore = !(response.results ?? []).isEmpty
        } catch {
            print("Failed to load genre catalog: \(error)")
        }
    }

    func loadNextPage() async {
        guard !isLoading, !isAppending, canLoadMore else { return }
        isAppending = true
        defer { isAppending = false }

        let nextPage = page + 1
        do {
            let filters = SearchFilters(genres: genre)
            let response = try await MoviesRepository.shared.searchMoviesResponse(query: "", page: nextPage, filters: filters)
            let raw = response.results ?? []
            if raw.isEmpty {
                canLoadMore = false
                return
            }
            let valid = filterValidItems(raw)
            let existing = Set(items.map(\.id))
            let unique = valid.filter { !existing.contains($0.id) }
            items.append(contentsOf: unique)
            page = nextPage
        } catch {
            print("Failed to load next page of genre catalog: \(error)")
        }
    }

    private func filterValidItems(_ items: [MediaDto]) -> [MediaDto] {
        return items.filter { item in
            let poster = item.posterUrl ?? item.poster_path ?? ""
            let hasPoster = !poster.isEmpty && !poster.lowercased().contains("no-poster")
            let hasTitle = !(item.title ?? item.name ?? "").isEmpty
            let hasRating = (item.rating ?? 0) > 0.0
            return hasPoster && hasTitle && hasRating
        }
    }
}
