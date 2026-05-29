import SwiftUI

struct RemoteBackdropView: View {
    let url: URL?
    let width: CGFloat
    let height: CGFloat
    
    @State private var image: UIImage?
    @State private var isLoading = false
    
    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height)
                    .clipped()
            } else {
                Rectangle().fill(Color.gray.opacity(0.2))
                    .frame(width: width, height: height)
                    .shimmer()
            }
        }
        .task(id: url) {
            guard let url = url, image == nil else { return }
            isLoading = true
            do {
                let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)
                let (data, _) = try await URLSession.shared.data(for: request)
                if let uiImg = UIImage(data: data) {
                    self.image = uiImg
                }
            } catch {
                // Ignore error, just keep placeholder
            }
            isLoading = false
        }
    }
}

struct DetailsView: View {
    let movieId: String
    @StateObject private var viewModel = DetailsViewModel()
    
    @State private var showPlayer = false
    @State private var showSourceSheet = false
    @State private var selectedIframeUrl: String? = nil
    @State private var selectedDirectVideoUrl: String? = nil
    @State private var showDownloadAlert = false
    @State private var sourceSheetMode: SourceMode?
    @State private var sourceSheetTitle = ""
    @State private var sourceFetchTask: Task<Void, Never>?
    @State private var sourceSheetDetent: PresentationDetent = .medium
    @Namespace private var transition
    
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

                        RemoteBackdropView(
                            url: URL(string: details.displayBackdropUrl ?? details.displayPosterUrl ?? ""),
                            width: geometry.size.width,
                            height: height
                        )
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
                            .font(.system(size: 34, weight: .heavy))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        if let originalTitle = details.originalTitle, !originalTitle.isEmpty, originalTitle != (details.title ?? details.name) {
                            Text(originalTitle)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                                .padding(.top, -8)
                        }

                        DetailsPrimaryMetadataRow(details: details)
                        
                        // Play Button
                        Button(action: {
                            guard let kpId = details.externalIds?.kp else { return }
                            
                            sourceSheetMode = SourceManager.shared.currentMode
                            sourceSheetTitle = details.title ?? details.name ?? ""
                            sourceSheetDetent = .medium
                            viewModel.resetSourceSheet()
                            showSourceSheet = true
                            
                            sourceFetchTask?.cancel()
                            sourceFetchTask = Task {
                                await viewModel.fetchSources(kpId: kpId, title: sourceSheetTitle)
                            }
                        }) {
                            HStack {
                                Image(systemName: "play.fill")
                                Text(viewModel.isResolvingAllohaPlayback ? "Подготовка..." : "Смотреть")
                                    .font(.system(size: 17, weight: .semibold))
                            }
                            .padding(.vertical, 14)
                            .padding(.horizontal, 48)
                            .foregroundStyle(Color(UIColor.systemBackground))
                        }
                        .background(Color.primary)
                        .clipShape(Capsule())
                        .matchedTransitionSource(id: "playBtn", in: transition)
                        .disabled(viewModel.isResolvingAllohaPlayback)
                        .buttonStyle(.plain)
                        .padding(.top, 16)

                        DetailsInfoSection(details: details)
                            .padding(.top, 20)
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
        .ignoresSafeArea(edges: .top)
        .overlay {
            if viewModel.isResolvingAllohaPlayback {
                ZStack {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()

                    VStack(spacing: 14) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                        Text("Подготавливаем поток...")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                    .glassEffect(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(id: "details") {
            ToolbarItem(id: "favorite", placement: .topBarTrailing) {
                Button {
                    viewModel.toggleFavorite()
                } label: {
                    Image(systemName: viewModel.isFavorite ? "heart.fill" : "heart")
                        .foregroundColor(.primary)
                }
                .disabled(viewModel.details == nil)
            }
            
            ToolbarItem(id: "download", placement: .topBarTrailing) {
                Button {
                    showDownloadAlert = true
                } label: {
                    Image(systemName: "arrow.down.circle")
                        .foregroundColor(.primary)
                }
                .disabled(viewModel.details == nil)
            }
        }
        .alert("В разработке", isPresented: $showDownloadAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Функция скачивания появится в будущих обновлениях.")
        }
        .alert(
            "Не удалось открыть видео",
            isPresented: Binding(
                get: { viewModel.playbackErrorMessage != nil },
                set: { if !$0 { viewModel.playbackErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                viewModel.playbackErrorMessage = nil
            }
        } message: {
            Text(viewModel.playbackErrorMessage ?? "Попробуйте еще раз.")
        }
        .task {
            await viewModel.loadDetails(id: movieId)
        }
        .sheet(isPresented: $showSourceSheet, onDismiss: {
            sourceFetchTask?.cancel()
            sourceFetchTask = nil
            sourceSheetDetent = .medium
            sourceSheetMode = nil
            sourceSheetTitle = ""
            viewModel.resetSourceSheet()
        }) {
            ZStack {
                if viewModel.isFetchingSources, let sourceSheetMode {
                    SourceSelectionLoadingView(
                        title: sourceSheetTitle,
                        mode: sourceSheetMode
                    )
                } else if let wrapper = viewModel.sourceResultWrapper,
                          wrapper.mode == .alloha,
                          let result = wrapper.allohaResult {
                    SourceSelectionView(result: result) { translation in
                        viewModel.resolveAllohaPlayback(iframeUrl: translation.iframeUrl, translationName: translation.name)
                    }
                } else if let wrapper = viewModel.sourceResultWrapper, wrapper.mode == .collaps {
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
                } else {
                    SourceSelectionEmptyView(title: sourceSheetTitle)
                }
            }
            .presentationDetents([.medium, .large], selection: $sourceSheetDetent)
            .navigationTransition(.zoom(sourceID: "playBtn", in: transition))
        }
        .onChange(of: viewModel.allohaPlaybackUrl) { resolvedUrl in
            guard let resolvedUrl else { return }
            showSourceSheet = false
            selectedDirectVideoUrl = resolvedUrl
            selectedIframeUrl = nil
            showPlayer = true
        }
        .onChange(of: viewModel.isResolvingAllohaPlayback) { isResolving in
            if isResolving {
                showSourceSheet = false
            }
        }
        .fullScreenCover(isPresented: $showPlayer, onDismiss: {
            selectedIframeUrl = nil
            selectedDirectVideoUrl = nil
            viewModel.cleanupAllohaSession()
        }) {
            if let details = viewModel.details {
                let mode = SourceManager.shared.currentMode
                if mode == .alloha {
                    if let directUrl = selectedDirectVideoUrl {
                        PlayerView(directVideoUrl: directUrl, fallbackTitle: details.title ?? details.name ?? "")
                    } else if let iframeUrl = selectedIframeUrl {
                        PlayerView(iframeUrl: iframeUrl, fallbackTitle: details.title ?? details.name ?? "")
                    } else {
                        Text("Видео не найдено")
                    }
                } else if let directUrl = selectedIframeUrl {
                    PlayerView(directVideoUrl: directUrl, fallbackTitle: details.title ?? details.name ?? "")
                } else if let directUrl = selectedDirectVideoUrl {
                    PlayerView(directVideoUrl: directUrl, fallbackTitle: details.title ?? details.name ?? "")
                } else {
                    Text("Видео не найдено")
                }
            }
        }
    }
}

private struct SourceSelectionLoadingView: View {
    let title: String
    let mode: SourceMode

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    SourceSelectionSkeletonSection(title: "Озвучка", chipWidths: [84, 112, 96, 104])

                    if mode == .alloha || mode == .collaps {
                        SourceSelectionSkeletonSection(title: "Сезон", chipWidths: [88, 88, 88])
                        SourceSelectionSkeletonSection(title: "Серия", chipWidths: [84, 84, 84, 84])
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentMargins(.horizontal, 20, for: .scrollContent)
            .contentMargins(.top, 16, for: .scrollContent)
            .contentMargins(.bottom, 28, for: .scrollContent)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }
}

private struct SourceSelectionSkeletonSection: View {
    let title: String
    let chipWidths: [CGFloat]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.primary)

            FlowLayout(spacing: 10) {
                ForEach(Array(chipWidths.enumerated()), id: \.offset) { _, width in
                    Capsule()
                        .fill(Color(UIColor.secondarySystemFill))
                        .frame(width: width, height: 34)
                }
            }
        }
        .shimmer()
    }
}

private struct SourceSelectionEmptyView: View {
    let title: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.bubble")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text("Не удалось получить источники")
                    .font(.system(size: 20, weight: .bold))

                Text("Попробуйте закрыть окно и нажать `Смотреть` еще раз.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }
}

private struct DetailsPrimaryMetadataRow: View {
    let details: MediaDetailsDto

    private func ratingColor(for rating: Double) -> Color {
        switch rating {
        case 7.5...10.0: return .green
        case 5.0..<7.5: return .yellow
        case 0.1..<5.0: return .red
        default: return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            if let rating = details.rating, rating > 0 {
                Label(String(format: "%.1f", rating), systemImage: "star.fill")
                    .foregroundColor(ratingColor(for: rating))
            }

            if let year = details.releaseDate?.prefix(4), !year.isEmpty {
                Text(String(year))
            }

            if let country = details.country, !country.isEmpty {
                Text(country)
            }

            if let duration = details.duration, duration > 0 {
                Text("\(duration) мин")
            }
        }
        .font(.system(size: 15, weight: .semibold))
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal)
    }
}

private struct DetailsInfoSection: View {
    let details: MediaDetailsDto

    private var genres: [String] {
        details.genres?
            .compactMap { $0.name?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !genres.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Жанры")
                        .font(.system(size: 18, weight: .bold))

                    FlowLayout(spacing: 8) {
                        ForEach(genres, id: \.self) { genre in
                            Text(genre)
                                .font(.system(size: 14, weight: .semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .glassEffect(in: Capsule())
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Описание")
                    .font(.system(size: 18, weight: .bold))

                Text(details.description ?? "Описание отсутствует.")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.secondary)
                    .lineSpacing(4)
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
    @Published var isResolvingAllohaPlayback = false
    @Published var sourceResultWrapper: SourceResultWrapper?
    @Published var allohaPlaybackUrl: String?
    @Published var playbackErrorMessage: String?
    
    @Published var isFavorite: Bool = false

    private var allohaSessionManager: AllohaSessionManager?
    private var allohaTimeoutTask: Task<Void, Never>?
    private let allohaTranslationPreferenceKey = "alloha_last_translation_name"

    func resetSourceSheet() {
        sourceResultWrapper = nil
    }
    
    func loadDetails(id: String) async {
        if details != nil && (details?.id == id || details?.sourceId == id || details?.externalIds?.kp?.description == id.replacingOccurrences(of: "kp_", with: "")) {
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            details = try await MoviesRepository.shared.getDetails(id: id)
            checkFavoriteStatus()
        } catch {
            print("Error loading details: \(error)")
        }
    }
    
    func checkFavoriteStatus() {
        guard let details = details else { return }
        guard let (mediaId, mediaType) = favoriteKey(for: details) else { return }
        
        isFavorite = FavoritesRepository.shared.isFavorite(mediaId: mediaId, mediaType: mediaType)
    }
    
    func toggleFavorite() {
        guard let details = details else { return }
        guard let (mediaId, mediaType) = favoriteKey(for: details) else { return }
        
        if isFavorite {
            FavoritesRepository.shared.removeFromFavorites(mediaId: mediaId, mediaType: mediaType)
        } else {
            FavoritesRepository.shared.addToFavorites(
                mediaId: mediaId,
                mediaType: mediaType,
                title: details.title ?? details.name,
                posterUrl: details.posterUrl ?? details.backdropUrl
            )
        }
        isFavorite.toggle()
    }
    
    private func favoriteKey(for details: MediaDetailsDto) -> (String, String)? {
        // Use KP ID if available, otherwise ID
        let mediaId = details.externalIds?.kp?.description ?? details.id ?? details.sourceId
        guard let validId = mediaId, !validId.isEmpty else { return nil }
        
        let type = (details.type?.lowercased() == "tv" || details.type?.lowercased() == "series") ? "tv" : "movie"
        return (validId.replacingOccurrences(of: "kp_", with: ""), type)
    }
    
    func fetchSources(kpId: Int, title: String) async {
        sourceResultWrapper = nil
        isFetchingSources = true
        defer { isFetchingSources = false }
        
        let mode = SourceManager.shared.currentMode
        do {
            switch mode {
            case .alloha:
                let result = try await AllohaRepository.shared.fetchByKpId(kpId: kpId)
                if let movie = result.movie,
                   let translation = preferredAllohaTranslation(from: movie) {
                    resolveAllohaPlayback(iframeUrl: translation.iframeUrl, translationName: translation.name)
                } else {
                    self.sourceResultWrapper = SourceResultWrapper(mode: .alloha, allohaResult: result)
                }
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

    func resolveAllohaPlayback(iframeUrl: String, translationName: String? = nil) {
        cleanupAllohaSession()

        if let translationName, !translationName.isEmpty {
            UserDefaults.standard.set(translationName, forKey: allohaTranslationPreferenceKey)
        }

        isResolvingAllohaPlayback = true
        playbackErrorMessage = nil
        allohaPlaybackUrl = nil

        let sessionManager = AllohaSessionManager()
        allohaSessionManager = sessionManager

        sessionManager.onStreamReady = { [weak self] _, _ in
            guard let self = self else { return }
            self.allohaTimeoutTask?.cancel()
            self.isResolvingAllohaPlayback = false
            self.allohaPlaybackUrl = HlsProxyServer.shared.fixedMasterUrl
        }

        sessionManager.onError = { [weak self] error in
            guard let self = self else { return }
            self.allohaTimeoutTask?.cancel()
            self.cleanupAllohaSession()
            self.playbackErrorMessage = error
        }

        allohaTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 55_000_000_000)
            guard let self = self,
                  !Task.isCancelled,
                  self.isResolvingAllohaPlayback else { return }
            self.cleanupAllohaSession()
            self.playbackErrorMessage = "Источник не ответил вовремя."
        }

        sessionManager.startSession(iframeUrl: iframeUrl)
    }

    func cleanupAllohaSession() {
        allohaTimeoutTask?.cancel()
        allohaTimeoutTask = nil
        allohaSessionManager?.release()
        allohaSessionManager = nil
        isResolvingAllohaPlayback = false
        HlsProxyServer.shared.stop()
    }

    private func preferredAllohaTranslation(from movie: AllohaMovie) -> AllohaTranslation? {
        let savedName = UserDefaults.standard.string(forKey: allohaTranslationPreferenceKey)
        return movie.translations.first(where: { $0.name == savedName }) ?? movie.translations.first
    }
}
