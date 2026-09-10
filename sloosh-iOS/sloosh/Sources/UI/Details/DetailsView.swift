import SwiftUI
import Photos

struct RemoteBackdropView: View {
    let url: URL?
    let fallbackUrl: URL?
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        AsyncCachedImage(url: url, fallbackUrl: fallbackUrl) {
            Rectangle().fill(Color.gray.opacity(0.2))
                .frame(width: width, height: height)
                .shimmer()
        } content: { image in
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: width, height: height)
                .clipped()
        } fallback: {
            Rectangle().fill(Color.gray.opacity(0.2))
                .frame(width: width, height: height)
        }
        .mask(
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .black.opacity(0.4), location: 0.06),
                    .init(color: .black.opacity(0.85), location: 0.12),
                    .init(color: .black, location: 0.18),
                    .init(color: .black, location: 0.35),
                    .init(color: .black.opacity(0.8), location: 0.50),
                    .init(color: .black.opacity(0.45), location: 0.68),
                    .init(color: .black.opacity(0.2), location: 0.82),
                    .init(color: .black.opacity(0.06), location: 0.93),
                    .init(color: .clear, location: 1.0)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

struct RemoteLogoView: View {
    let url: URL?
    let fallbackTitle: String
    var alignment: Alignment = .center
    var isTopBar: Bool = false
    
    var body: some View {
        AsyncCachedImage(url: url) {
            Text(fallbackTitle)
                .font(.system(size: isTopBar ? 17 : 32, weight: isTopBar ? .bold : .heavy))
                .lineLimit(isTopBar ? 1 : 2)
                .multilineTextAlignment(alignment == .leading ? .leading : .center)
                .padding(.horizontal, alignment == .center ? (isTopBar ? 0 : 16) : 0)
                .shimmer()
                .frame(maxWidth: .infinity, alignment: alignment)
        } content: { image in
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: isTopBar ? nil : 280, maxHeight: isTopBar ? 32 : 110, alignment: alignment)
                .padding(.horizontal, alignment == .center ? (isTopBar ? 0 : 16) : 0)
                .shadow(color: .black.opacity(isTopBar ? 0.0 : 0.3), radius: 8, x: 0, y: 4)
        } fallback: {
            Text(fallbackTitle)
                .font(.system(size: isTopBar ? 17 : 32, weight: isTopBar ? .bold : .heavy))
                .lineLimit(isTopBar ? 1 : 2)
                .multilineTextAlignment(alignment == .leading ? .leading : .center)
                .padding(.horizontal, alignment == .center ? (isTopBar ? 0 : 16) : 0)
                .frame(maxWidth: .infinity, alignment: alignment)
                .foregroundStyle(Color.white)
                .shadow(color: .black.opacity(0.8), radius: 6, x: 0, y: 3)
        }
    }
}

struct DetailsView: View {
    let movieId: String
    let mediaType: String?
    let navigationTransitionID: String?
    let navigationTransitionNamespace: Namespace.ID?
    let initialStudio: StudioBrand?
    @StateObject private var viewModel = DetailsViewModel()
    
    init(
        movieId: String,
        mediaType: String? = nil,
        navigationTransitionID: String? = nil,
        navigationTransitionNamespace: Namespace.ID? = nil,
        initialStudio: StudioBrand? = nil
    ) {
        self.movieId = movieId
        self.mediaType = mediaType
        self.navigationTransitionID = navigationTransitionID
        self.navigationTransitionNamespace = navigationTransitionNamespace
        self.initialStudio = initialStudio
    }

    init(
        movieId: String,
        navigationTransitionID: String? = nil,
        navigationTransitionNamespace: Namespace.ID? = nil,
        initialStudio: StudioBrand? = nil
    ) {
        self.movieId = movieId
        self.mediaType = nil
        self.navigationTransitionID = navigationTransitionID
        self.navigationTransitionNamespace = navigationTransitionNamespace
        self.initialStudio = initialStudio
    }
    
    @State private var showPlayer = false
    @State private var pendingPlayerLaunch = false
    @State private var showSourceSheet = false
    @State private var selectedIframeUrl: String? = nil
    @State private var sourceSheetTitle = ""
    @State private var sourceFetchTask: Task<Void, Never>?
    @State private var sourceSheetDetent: PresentationDetent = .medium
    @State private var sourceSheetMode: SourceSelectionMode = .play
    @Namespace private var transition
    @State private var sourceSheetSourceID: String = "playBtn"
    
    @State private var playerKpId: Int?
    @State private var playerTmdbId: Int?
    @State private var playerMediaKey: String?
    @State private var playerSeason: Int?
    @State private var playerEpisode: Int?
    @State private var playerVoiceover: String?
    @State private var playerStreamUrl: String?
    @State private var playerVoices: [String] = []
    @State private var playerSubtitles: [PlaybackSubtitle] = []
    @State private var playerQuality: VideoQualityPreference? = nil
    @State private var playerSeriesResult: AllohaApiResult?
    @State private var favoriteBounce = false
    @State private var movieToDelete: DownloadItem? = nil
    @State private var showDeleteMovieAlert = false
    @State private var showShareToFriendSheet = false
    @State private var directPlaybackMovie: MediaDto? = nil
    @State private var pendingDirectPlayerConfig: PlayerConfig? = nil
    @State private var directPlaybackTitle: String? = nil
    @State private var selectedTrailer: TrailerVideoDto? = nil

    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dismiss) private var dismiss

    @State private var dominantBackdropColor: UIColor? = nil
    @State private var dominantPosterColor: UIColor? = nil

    @AppStorage("hasSeenSourceSelectionTooltip") private var hasSeenSourceSelectionTooltip = false
    @AppStorage("showOriginalTitle") private var showOriginalTitle = true
    @State private var showTooltip = false

    private var detailsBaseBackgroundColor: UIColor {
        UIColor.systemBackground.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
    }

    private var effectiveBackgroundColor: Color {
        let background = detailsBaseBackgroundColor
        if let dominant = dominantBackdropColor ?? dominantPosterColor {
            return Color(dominant.blended(with: background, fraction: 0.35))
        } else {
            return Color(background)
        }
    }

    private static var dominantColorCache: [String: UIColor] = [:]
    private static let dominantColorCacheLock = NSLock()

    private func fetchAverageColor(from url: URL?) async -> UIColor? {
        guard let url else { return nil }
        let key = url.absoluteString

        // 1. Проверяем кеш уже вычисленных цветов
        let cachedColor: UIColor? = Self.dominantColorCacheLock.withLock {
            Self.dominantColorCache[key]
        }
        if let cachedColor { return cachedColor }

        // 2. Проверяем наличие UIImage в оперативной памяти (мгновенно, без сети!)
        let effectiveUrl = ImageCache.resolveEffectiveUrl(url)
        if let ramImage = ImageCache.shared.image(forKey: key) ?? effectiveUrl.flatMap({ ImageCache.shared.image(forKey: $0.absoluteString) }) {
            if let avg = ramImage.averageColor {
                Self.dominantColorCacheLock.withLock {
                    Self.dominantColorCache[key] = avg
                }
                return avg
            }
        }

        // 3. Если изображения нет в памяти — загружаем из кеша URLSession
        return await Task.detached(priority: .userInitiated) {
            do {
                let targetUrl = effectiveUrl ?? url
                let request = URLRequest(url: targetUrl, cachePolicy: .returnCacheDataElseLoad)
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
                      let image = UIImage(data: data),
                      let avg = image.averageColor else {
                    return nil
                }
                Self.dominantColorCacheLock.withLock {
                    Self.dominantColorCache[key] = avg
                }
                return avg
            } catch {
                return nil
            }
        }.value
    }

    private func preloadDominantColor(for details: MediaDetailsDto) async {
        async let backdropColor = fetchAverageColor(from: URL(string: details.previewBackdropUrl ?? ""))
        async let posterColor = fetchAverageColor(from: URL(string: details.displayPosterUrl ?? ""))
        
        let (backdrop, poster) = await (backdropColor, posterColor)
        
        if Task.isCancelled { return }
        
        await MainActor.run {
            withAnimation(.easeInOut(duration: 0.25)) {
                self.dominantBackdropColor = backdrop
                self.dominantPosterColor = poster
            }
        }
    }
    
    @State private var isLogoAtTop: Bool = false
    @State private var isSavingImage: Bool = false
    @Namespace private var actorTransitionNamespace
    @Namespace private var crewTransitionNamespace
    
    var body: some View {
        ZStack {
            detailsContent
        }
            .optionalMovieNavigationTransition(
                sourceID: navigationTransitionID,
                in: navigationTransitionNamespace
            )
            .environment(\.colorScheme, .dark)
            .ignoresSafeArea(edges: .top)
            .hideNavigationBarWithRestore()
            .safeAreaInset(edge: .top, spacing: 0) {
                ZStack {
                    if let details = viewModel.details, isLogoAtTop {
                        RemoteLogoView(
                            url: URL(string: details.displayLogoUrl ?? ""),
                            fallbackTitle: details.title ?? details.originalTitle ?? "Без названия",
                            alignment: .center,
                            isTopBar: true
                        )
                        .frame(height: 32)
                        .padding(.horizontal, 68)
                        .transition(.blurFadeScale)
                    }
                    
                    HStack {
                        TelegramGlassIconButton(systemName: "chevron.left") {
                            dismiss()
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 0) {
                            // Кнопка «Избранное» (слева, как было изначально)
                            Button {
                                let generator = UIImpactFeedbackGenerator(style: .light)
                                generator.prepare()
                                generator.impactOccurred()
                                favoriteBounce.toggle()
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.5, blendDuration: 0.5)) {
                                    viewModel.toggleFavorite()
                                }
                            } label: {
                                Image(systemName: viewModel.isFavorite ? "heart.fill" : "heart")
                                    .font(.system(size: 21, weight: .medium))
                                    .foregroundStyle(.white)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(viewModel.details == nil)
                            .accessibilityLabel(viewModel.isFavorite ? "Убрать из избранного" : "Добавить в избранное")
                            .frame(width: 44, height: 44)

                            // Кнопка «Поделиться» (справа, растворяется с блюром)
                            Button {
                                let generator = UIImpactFeedbackGenerator(style: .medium)
                                generator.prepare()
                                generator.impactOccurred()
                                showShareToFriendSheet = true
                            } label: {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundStyle(.white)
                                    .frame(width: 44, height: 44)
                                    .blur(radius: isLogoAtTop ? 12 : 0)
                                    .opacity(isLogoAtTop ? 0 : 1)
                                    .scaleEffect(isLogoAtTop ? 0.4 : 1.0)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(viewModel.details == nil || isLogoAtTop)
                            .accessibilityLabel("Поделиться фильмом")
                            .frame(width: isLogoAtTop ? 0 : 44, height: 44)
                            .clipped()
                            .allowsHitTesting(!isLogoAtTop)
                        }
                        .padding(.horizontal, isLogoAtTop ? 0 : 2)
                        .frame(width: isLogoAtTop ? 44 : 92, height: 44)
                        .clipShape(Capsule())
                        .glassEffect(.regular.interactive(), in: .capsule)
                        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isLogoAtTop)
                    }

                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .background(
                    VariableBlurView(tintColor: effectiveBackgroundColor, tintOpacity: 1.0)
                        .padding(.bottom, -60)
                        .ignoresSafeArea(edges: .top)
                        .opacity(isLogoAtTop ? 1.0 : 0.0)
                        .animation(.easeInOut(duration: 0.25), value: isLogoAtTop)
                        .allowsHitTesting(false)
                )
            }
            .task {
                await viewModel.loadDetails(id: movieId, type: mediaType, studio: initialStudio)
            }
            .task(id: viewModel.details?.id) {
                guard let details = viewModel.details else { return }
                await preloadDominantColor(for: details)
            }
            .onAppear {
                if !hasSeenSourceSelectionTooltip {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        showTooltip = true
                    }
                }
            }
            .onChange(of: showTooltip) { _, newValue in
                if !newValue {
                    hasSeenSourceSelectionTooltip = true
                }
            }
            .sheet(isPresented: $showSourceSheet, onDismiss: {
                sourceFetchTask?.cancel()
                sourceFetchTask = nil
                sourceSheetDetent = .medium
                sourceSheetTitle = ""
                viewModel.resetSourceSheet()
                if pendingPlayerLaunch {
                    pendingPlayerLaunch = false
                    DispatchQueue.main.async {
                        showPlayer = true
                    }
                }
            }) {
                ZStack {
                    if let wrapper = viewModel.sourceResultWrapper,
                       let result = wrapper.allohaResult,
                       (!result.seasons.isEmpty || result.movie != nil) {
                        SourceSelectionView(mode: sourceSheetMode, result: result, kpId: wrapper.kpId, details: viewModel.details) { translation, season, episode, quality in
                            if sourceSheetMode == .play {
                                let effectiveKp = ((wrapper.kpId ?? 0) > 0 ? wrapper.kpId : nil)
                                    ?? viewModel.details?.ids?.kp
                                    ?? viewModel.details?.externalIds?.kp
                                let effectiveTmdb = viewModel.details?.externalIds?.tmdb
                                    ?? viewModel.details?.ids?.tmdb
                                    ?? Int(viewModel.details?.id ?? "")
                                let resolvedKey = (effectiveKp.flatMap { $0 > 0 ? "kp_\($0)" : nil }) ?? (viewModel.details?.id ?? "tmdb_\(effectiveTmdb ?? 0)")

                                playerKpId = effectiveKp
                                playerTmdbId = effectiveTmdb
                                playerMediaKey = resolvedKey
                                playerSeason = season
                                playerEpisode = episode
                                playerQuality = quality
                                playerSeriesResult = result
                                playerVoices = result.allTranslationNames
                                
                                selectedIframeUrl = translation.iframeUrl
                                playerVoiceover = translation.name
                                playerStreamUrl = translation.streamUrl
                                
                                pendingPlayerLaunch = true
                                showSourceSheet = false
                                viewModel.saveAllohaTranslation(translation.name)
                            } else {
                                if let details = viewModel.details {
                                    DownloadManager.shared.startDownload(
                                        details: details,
                                        season: season,
                                        episode: episode,
                                        translation: translation,
                                        preferredQuality: quality
                                    )
                                }
                                showSourceSheet = false
                            }
                        }
                    } else if viewModel.isFetchingSources || !viewModel.hasFinishedSourceFetch {
                        SourceSelectionLoadingView(
                            title: sourceSheetTitle
                        )
                    } else {
                        SourceSelectionEmptyView(title: sourceSheetTitle)
                    }
                }
                .presentationDetents([.medium, .large], selection: $sourceSheetDetent)
            }
            .fullScreenCover(isPresented: $showPlayer, onDismiss: {
                showPlayer = false
                AppDelegate.lockToPortrait()
                selectedIframeUrl = nil
                directPlaybackTitle = nil
                playerKpId = nil
                playerTmdbId = nil
                playerMediaKey = nil
                playerSeason = nil
                playerEpisode = nil
                playerVoiceover = nil
                playerStreamUrl = nil
                playerVoices = []
                playerSubtitles = []
                playerQuality = nil
                playerSeriesResult = nil
            }) {
                if let details = viewModel.details {
                    let fallbackTitle = directPlaybackTitle ?? details.title ?? details.originalTitle ?? ""
                    if let iframeUrl = selectedIframeUrl {
                        PlayerView(
                            iframeUrl: iframeUrl,
                            fallbackTitle: fallbackTitle,
                            kpId: playerKpId,
                            season: playerSeason,
                            episode: playerEpisode,
                            selectedVoiceover: playerVoiceover,
                            directStreamUrl: playerStreamUrl,
                            voices: playerVoices,
                            subtitles: playerSubtitles,
                            initialQuality: playerQuality,
                            seriesResult: playerSeriesResult,
                            mediaKey: playerMediaKey,
                            tmdbId: playerTmdbId,
                            posterUrl: details.displayPosterUrl,
                            backdropUrl: details.displayBackdropUrl ?? details.displayPosterUrl,
                            logoUrl: details.displayLogoUrl
                        )
                    } else if let streamUrl = playerStreamUrl {
                        PlayerView(
                            iframeUrl: "",
                            fallbackTitle: fallbackTitle,
                            kpId: playerKpId,
                            season: playerSeason,
                            episode: playerEpisode,
                            selectedVoiceover: playerVoiceover,
                            directStreamUrl: streamUrl,
                            voices: playerVoices,
                            subtitles: playerSubtitles,
                            initialQuality: playerQuality,
                            seriesResult: playerSeriesResult,
                            mediaKey: playerMediaKey,
                            tmdbId: playerTmdbId,
                            posterUrl: details.displayPosterUrl,
                            backdropUrl: details.displayBackdropUrl ?? details.displayPosterUrl,
                            logoUrl: details.displayLogoUrl
                        )
                    } else {
                        ZStack {
                            Color.black.ignoresSafeArea()
                            VStack(spacing: 20) {
                                Text("Видео не найдено")
                                    .foregroundColor(.white)
                                    .font(.headline)
                                Button("Закрыть") {
                                    showPlayer = false
                                }
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.white.opacity(0.2))
                                .cornerRadius(8)
                            }
                        }
                    }
                }
            }
        .alert("Удалить фильм?", isPresented: $showDeleteMovieAlert) {
            Button("Отмена", role: .cancel) {}
            Button("Удалить", role: .destructive) {
                if let movie = movieToDelete {
                    DownloadManager.shared.deleteDownload(id: movie.id)
                }
            }
        } message: {
            Text("Вы действительно хотите удалить этот фильм из памяти устройства?")
        }
        .sheet(isPresented: $showShareToFriendSheet) {
            if let details = viewModel.details {
                ShareToFriendSheet(movie: details)
            }
        }
        .sheet(item: $selectedTrailer) { trailer in
            TrailerPlayerSheetView(trailer: trailer)
        }
        .sheet(item: $directPlaybackMovie, onDismiss: {
            if let pending = pendingDirectPlayerConfig {
                pendingDirectPlayerConfig = nil
                DispatchQueue.main.async {
                    directPlaybackTitle = pending.title
                    selectedIframeUrl = pending.iframeUrl
                    playerKpId = pending.kpId
                    playerTmdbId = pending.tmdbId
                    playerMediaKey = pending.mediaKey
                    playerSeason = pending.season
                    playerEpisode = pending.episode
                    playerVoiceover = pending.voiceover
                    playerStreamUrl = pending.streamUrl
                    playerVoices = pending.voices
                    playerSubtitles = pending.subtitles
                    playerQuality = pending.quality
                    playerSeriesResult = pending.seriesResult
                    showPlayer = true
                }
            }
        }) { movie in
            HomeDirectPlayWrapper(
                movieId: movie.id,
                fallbackTitle: movie.title ?? movie.name ?? movie.originalTitle ?? "",
                initialKpId: movie.externalIds?.kp
            ) { config in
                pendingDirectPlayerConfig = config
                directPlaybackMovie = nil
            }
        }



        .preferredColorScheme(.dark)
    }



    private func handlePlayAction(details: MediaDetailsDto) {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()

        let kpId = details.ids?.kp ?? details.externalIds?.kp ?? 0
        let tmdbId = details.externalIds?.tmdb ?? details.ids?.tmdb ?? Int(details.id ?? "")
        guard kpId > 0 || (tmdbId ?? 0) > 0 else { return }

        sourceSheetSourceID = "playBtn"
        sourceSheetTitle = details.title ?? details.originalTitle ?? ""
        sourceSheetDetent = .medium
        sourceSheetMode = .play
        viewModel.prepareSourceSheet(kpId: kpId, tmdbId: tmdbId)
        showSourceSheet = true

        sourceFetchTask?.cancel()
        sourceFetchTask = Task {
            await viewModel.fetchSources(kpId: kpId, tmdbId: tmdbId, title: sourceSheetTitle)
        }
    }

    private func handleEpisodeSelection(details: MediaDetailsDto, season: Int, episode: Int) {
        let kpId = details.ids?.kp ?? details.externalIds?.kp ?? 0
        let tmdbId = details.externalIds?.tmdb ?? details.ids?.tmdb ?? Int(details.id ?? "")
        guard kpId > 0 || (tmdbId ?? 0) > 0 else { return }

        PlaybackProgressStore.shared.saveLastPlayed(
            kpId: kpId > 0 ? kpId : (tmdbId ?? 0),
            season: season,
            episode: episode
        )

        sourceSheetSourceID = "playBtn"
        sourceSheetTitle = details.title ?? details.originalTitle ?? ""
        sourceSheetDetent = .medium
        sourceSheetMode = .play
        viewModel.prepareSourceSheet(kpId: kpId, tmdbId: tmdbId)
        showSourceSheet = true

        sourceFetchTask?.cancel()
        sourceFetchTask = Task {
            await viewModel.fetchSources(kpId: kpId, tmdbId: tmdbId, title: sourceSheetTitle)
        }
    }

    @ViewBuilder
    private func playAndDownloadRow(for details: MediaDetailsDto) -> some View {
        if details.isUnreleased {
            unreleasedButton(for: details)
        } else {
            HStack(spacing: 8) {
                playButton(for: details)
                    .tooltip(text: "Нажмите для выбора перевода", isVisible: $showTooltip, isTailTop: false)
                downloadButton(for: details)
            }
        }
    }

    private func unreleasedButton(for details: MediaDetailsDto) -> some View {
        let labelText: String = {
            if let dateStr = details.formattedReleaseDate {
                return "Премьера: \(dateStr)"
            }
            return "Скоро в кино"
        }()
        
        return HStack(spacing: 8) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 17, weight: .semibold))
            Text(labelText)
                .font(.system(size: 16, weight: .bold))
        }
        .foregroundStyle(Color.primary.opacity(0.85))
        .padding(.horizontal, 22)
        .frame(height: 50)
        .glassEffect(.regular, in: .capsule)
        .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 3)
    }


    private var buttonAmbientTintColor: Color {
        if let dominant = dominantBackdropColor ?? dominantPosterColor {
            return Color(uiColor: dominant)
        } else {
            return effectiveBackgroundColor
        }
    }

    private func playButton(for details: MediaDetailsDto) -> some View {
        Button {
            handlePlayAction(details: details)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "play.fill")
                    .font(.system(size: 18, weight: .black))
                Text("Смотреть")
                    .font(.system(size: 19, weight: .heavy))
            }
            .foregroundStyle(Color.black)
            .padding(.horizontal, 26)
            .frame(height: 50)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.94))
            )
            .glassEffect(.regular.interactive(), in: .capsule)
            .shadow(color: Color.black.opacity(0.22), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.glassPress)
    }

    @ViewBuilder
    private func downloadButton(for details: MediaDetailsDto) -> some View {
        let kpId = details.ids?.kp ?? 0
        let item = DownloadManager.shared.getDownloadItem(kpId: kpId, season: nil, episode: nil)
        
        Button {
            handleDownloadAction(details: details, item: item)
        } label: {
            Group {
                if let item = item, item.status == .downloading {
                    ZStack {
                        Circle()
                            .stroke(Color.primary.opacity(0.15), lineWidth: 2)
                            .frame(width: 20, height: 20)
                        Circle()
                            .trim(from: 0.0, to: item.progress)
                            .stroke(Color.slooshAccent, lineWidth: 2)
                            .frame(width: 20, height: 20)
                            .rotationEffect(Angle(degrees: -90))
                        Image(systemName: "square.fill")
                            .font(.system(size: 6))
                    }
                } else if let item = item, item.status == .pending {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 22))
                        .foregroundColor(.primary)
                }
            }
            .foregroundStyle(.white)
            .frame(width: 50, height: 50)
            .glassEffect(.regular.interactive(), in: .circle)
            .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.glassPress)
    }

    private func handleDownloadAction(details: MediaDetailsDto, item: DownloadItem?) {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
        
        sourceSheetSourceID = "downloadBtn"
        
        if let item = item {
            switch item.status {
            case .downloading, .pending:
                DownloadManager.shared.pauseDownload(id: item.id)
            case .paused:
                DownloadManager.shared.resumeDownload(id: item.id)
            default:
                startDownloadWithPreferredTranslation(details: details, season: nil, episode: nil)
            }
        } else {
            startDownloadWithPreferredTranslation(details: details, season: nil, episode: nil)
        }
    }

    private func startDownloadWithPreferredTranslation(details: MediaDetailsDto, season: Int?, episode: Int?) {
        let kpId = details.ids?.kp ?? details.externalIds?.kp ?? 0
        let tmdbId = details.externalIds?.tmdb ?? details.ids?.tmdb ?? Int(details.id ?? "")
        guard kpId > 0 || (tmdbId ?? 0) > 0 else { return }
        
        sourceSheetTitle = details.title ?? details.originalTitle ?? ""
        sourceSheetDetent = .medium
        sourceSheetMode = .download
        viewModel.prepareSourceSheet(kpId: kpId, tmdbId: tmdbId)
        showSourceSheet = true

        sourceFetchTask?.cancel()
        sourceFetchTask = Task {
            await viewModel.fetchSources(kpId: kpId, tmdbId: tmdbId, title: sourceSheetTitle)
        }
    }

    private var detailsContent: some View {
        Group {
            if verticalSizeClass == .compact {
                landscapeDetailsContent
            } else {
                portraitDetailsContent
            }
        }
    }

    // MARK: - Image Saving & Sharing

    @MainActor
    private func saveImage(from urlString: String?, label: String) async {
        guard let urlString, let url = URL(string: urlString) else { return }
        isSavingImage = true
        defer { isSavingImage = false }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else {
                ToastManager.shared.show(title: "Не удалось загрузить \(label)", icon: "xmark.circle")
                return
            }
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                ToastManager.shared.show(title: "Нет доступа к Фото", icon: "lock")
                return
            }
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            ToastManager.shared.show(title: "Сохранено в Фото", icon: "checkmark.circle.fill")
        } catch {
            ToastManager.shared.show(title: "Ошибка: \(label) не сохранён", icon: "xmark.circle")
        }
    }

    private func shareImages(posterUrl: String?, backdropUrl: String?) {
        var items: [Any] = []
        if let str = backdropUrl, let url = URL(string: str),
           let data = URLCache.shared.cachedResponse(for: URLRequest(url: url))?.data,
           let img = UIImage(data: data) {
            items.append(img)
        } else if let str = posterUrl, let url = URL(string: str),
           let data = URLCache.shared.cachedResponse(for: URLRequest(url: url))?.data,
           let img = UIImage(data: data) {
            items.append(img)
        }
        if items.isEmpty {
            if let str = backdropUrl ?? posterUrl { items.append(str) }
        }
        guard !items.isEmpty else { return }

        let av = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first,
           let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
            var topVC = rootVC
            while let presented = topVC.presentedViewController { topVC = presented }
            av.popoverPresentationController?.sourceView = topVC.view
            topVC.present(av, animated: true)
        }
    }

    private var portraitDetailsContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                if viewModel.isLoading {
                    DetailsSkeletonView(backgroundColor: effectiveBackgroundColor)
                        .transition(.opacity)
                } else if let details = viewModel.details {
                    // Stretchy Backdrop
                    let baseHeight: CGFloat = 365
                    
                    GeometryReader { geometry in
                        let minY = geometry.frame(in: .global).minY
                        let isScrollingDown = minY > 0
                        let height = isScrollingDown ? baseHeight + minY : baseHeight
                        let offset = isScrollingDown ? -minY : 0

                        RemoteBackdropView(
                            url: URL(string: details.displayBackdropUrl ?? ""),
                            fallbackUrl: URL(string: details.displayPosterUrl ?? ""),
                            width: geometry.size.width,
                            height: height
                        )
                        .offset(y: offset)
                    }
                    .frame(height: baseHeight)
                    .contextMenu {
                        Button {
                            Task { await saveImage(from: details.displayBackdropUrl, label: "обложка") }
                        } label: {
                            Label("Сохранить обложку", systemImage: "photo.badge.arrow.down")
                        }
                        Button {
                            Task { await saveImage(from: details.displayPosterUrl, label: "постер") }
                        } label: {
                            Label("Сохранить постер", systemImage: "photo")
                        }
                        if details.displayLogoUrl != nil {
                            Button {
                                Task { await saveImage(from: details.displayLogoUrl, label: "логотип") }
                            } label: {
                                Label("Сохранить логотип", systemImage: "text.below.photo")
                            }
                        }
                        Divider()
                        Button {
                            shareImages(posterUrl: details.displayPosterUrl, backdropUrl: details.displayBackdropUrl)
                        } label: {
                            Label("Поделиться", systemImage: "square.and.arrow.up")
                        }
                    } preview: {
                        AsyncCachedImage(url: URL(string: details.displayBackdropUrl ?? ""),
                                         fallbackUrl: URL(string: details.displayPosterUrl ?? "")) {
                            Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 300, height: 200)
                        } content: { image in
                            Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
                                .frame(width: 300, height: 200).clipped()
                        } fallback: {
                            Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 300, height: 200)
                        }
                    }

                    VStack(alignment: .center, spacing: 12) {
                        ZStack {
                            RemoteLogoView(
                                url: URL(string: details.displayLogoUrl ?? ""),
                                fallbackTitle: details.title ?? details.originalTitle ?? "Без названия",
                                alignment: .center
                            )
                            .opacity(0)
                            .allowsHitTesting(false)
                            if !isLogoAtTop {
                                RemoteLogoView(
                                    url: URL(string: details.displayLogoUrl ?? ""),
                                    fallbackTitle: details.title ?? details.originalTitle ?? "Без названия",
                                    alignment: .center
                                )
                                .transition(.blurFadeScale)
                            }
                        }
                        .padding(.bottom, 8)
                        .background(
                            GeometryReader { geo in
                                Color.clear
                                    .onChange(of: geo.frame(in: .global).midY) { _, midY in
                                        let isAtTop = midY < 80
                                        if isLogoAtTop != isAtTop {
                                            withAnimation(.easeInOut(duration: 0.3)) {
                                                isLogoAtTop = isAtTop
                                            }
                                        }
                                    }
                                    .onAppear {
                                        isLogoAtTop = geo.frame(in: .global).midY < 80
                                    }
                            }
                        )

                        if showOriginalTitle, let originalTitle = details.originalTitle, !originalTitle.isEmpty, originalTitle != details.title {
                            Text(originalTitle)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                                .padding(.top, -8)
                        }

                        DetailsPrimaryMetadataRow(details: details, alignment: .center)

                        playAndDownloadRow(for: details)
                            .padding(.top, 8)
                            .padding(.bottom, -4)

                        DetailsInfoSection(details: details, backgroundColor: effectiveBackgroundColor, studio: initialStudio)
                            .padding(.top, 20)
                            .padding(.horizontal)

                        if let cast = details.cast, !cast.isEmpty {
                            ActorsSection(cast: cast, namespace: actorTransitionNamespace)
                                .padding(.top, 16)
                        }

                        if let crew = details.crew, !crew.isEmpty {
                            CrewSection(crew: crew, namespace: crewTransitionNamespace)
                                .padding(.top, 16)
                        }

                        if let trailers = details.trailers, !trailers.isEmpty {
                            TrailersSection(trailers: trailers) { trailer in
                                selectedTrailer = trailer
                            }
                            .padding(.top, 16)
                        }

                        if details.type == "tv" {
                            InlineEpisodesSection(viewModel: viewModel, details: details) { season, episode in
                                handleEpisodeSelection(details: details, season: season, episode: episode)
                            }
                            .padding(.top, 16)
                        }

                        if let collection = viewModel.movieCollection ?? details.collection {
                            FranchiseCollectionSection(collection: collection, onDirectPlay: { movie in
                                directPlaybackMovie = movie
                            })
                            .padding(.top, 16)
                        }

                        if let similar = details.similar, !similar.isEmpty {
                            SimilarMediaSection(
                                title: details.type == "tv" ? "Похожие сериалы" : "Похожие фильмы",
                                items: similar,
                                onDirectPlay: { movie in
                                    directPlaybackMovie = movie
                                }
                            )
                            .padding(.top, 16)
                        }

                        if let relatedStudio = viewModel.relatedStudio, let items = relatedStudio.items, !items.isEmpty {
                            RelatedStudioSection(response: relatedStudio, onDirectPlay: { movie in
                                directPlaybackMovie = movie
                            })
                            .padding(.top, 16)
                        }
                    }
                    .offset(y: -25)
                    .padding(.bottom, 28)
                    .transition(.opacity)
                } else {
                    Text("Не удалось загрузить данные.")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 100)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.35), value: viewModel.isLoading)
        }
        .scrollIndicators(.hidden)
        .background {
            effectiveBackgroundColor
                .animation(.easeInOut(duration: 0.4), value: effectiveBackgroundColor)
                .ignoresSafeArea()
        }
        .refreshable {
            await viewModel.loadDetails(id: movieId, type: mediaType, force: true, studio: initialStudio)
        }
    }

    private var landscapeDetailsContent: some View {
        GeometryReader { outerGeometry in
            ScrollView {
                VStack(spacing: 0) {
                    if viewModel.isLoading {
                        DetailsSkeletonView(backgroundColor: effectiveBackgroundColor)
                            .transition(.opacity)
                    } else if let details = viewModel.details {
                        let baseHeight: CGFloat = 280
                        
                        GeometryReader { geometry in
                            let minY = geometry.frame(in: .global).minY
                            let isScrollingDown = minY > 0
                            let height = isScrollingDown ? baseHeight + minY : baseHeight
                            let offset = isScrollingDown ? -minY : 0

                            RemoteBackdropView(
                                url: URL(string: details.displayBackdropUrl ?? ""),
                                fallbackUrl: URL(string: details.displayPosterUrl ?? ""),
                                width: geometry.size.width,
                                height: height
                            )
                            .offset(y: offset)
                        }
                        .frame(height: baseHeight)

                        VStack(spacing: 0) {
                            VStack(alignment: .center, spacing: 12) {
                                ZStack {
                                    RemoteLogoView(
                                        url: URL(string: details.displayLogoUrl ?? ""),
                                        fallbackTitle: details.title ?? details.originalTitle ?? "Без названия",
                                        alignment: .center
                                    )
                                    .opacity(0)
                                    .allowsHitTesting(false)
                                    if !isLogoAtTop {
                                        RemoteLogoView(
                                            url: URL(string: details.displayLogoUrl ?? ""),
                                            fallbackTitle: details.title ?? details.originalTitle ?? "Без названия",
                                            alignment: .center
                                        )
                                        .transition(.blurFadeScale)
                                    }
                                }
                                .padding(.bottom, 8)
                                .background(
                                    GeometryReader { geo in
                                        Color.clear
                                            .onChange(of: geo.frame(in: .global).midY) { _, midY in
                                                let isAtTop = midY < 80
                                                if isLogoAtTop != isAtTop {
                                                    withAnimation(.easeInOut(duration: 0.3)) {
                                                        isLogoAtTop = isAtTop
                                                    }
                                                }
                                            }
                                            .onAppear {
                                                isLogoAtTop = geo.frame(in: .global).midY < 80
                                            }
                                    }
                                )

                                if showOriginalTitle, let originalTitle = details.originalTitle, !originalTitle.isEmpty, originalTitle != details.title {
                                    Text(originalTitle)
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal)
                                        .padding(.top, -8)
                                }

                                DetailsPrimaryMetadataRow(details: details, alignment: .center)

                                playAndDownloadRow(for: details)
                                    .padding(.top, 8)
                                    .padding(.bottom, -4)

                                DetailsInfoSection(details: details, backgroundColor: effectiveBackgroundColor, studio: initialStudio)
                                    .padding(.top, 20)
                                    .padding(.horizontal)
                            }
                            .frame(maxWidth: 550)
                            .frame(maxWidth: .infinity, alignment: .center)

                            if let cast = details.cast, !cast.isEmpty {
                                ActorsSection(cast: cast, namespace: actorTransitionNamespace)
                                    .padding(.top, 16)
                            }

                            if let crew = details.crew, !crew.isEmpty {
                                CrewSection(crew: crew, namespace: crewTransitionNamespace)
                                    .padding(.top, 16)
                            }

                            if let trailers = details.trailers, !trailers.isEmpty {
                                TrailersSection(trailers: trailers) { trailer in
                                    selectedTrailer = trailer
                                }
                                .padding(.top, 16)
                            }

                            if details.type == "tv" {
                                let paddingVal = max(16, (outerGeometry.size.width - 550) / 2 + 16)
                                InlineEpisodesSection(
                                    viewModel: viewModel,
                                    details: details,
                                    horizontalPadding: paddingVal
                                ) { season, episode in
                                    handleEpisodeSelection(details: details, season: season, episode: episode)
                                }
                                .padding(.top, 16)
                            }

                            if let collection = viewModel.movieCollection ?? details.collection {
                                FranchiseCollectionSection(collection: collection, onDirectPlay: { movie in
                                    directPlaybackMovie = movie
                                })
                                .padding(.top, 16)
                            }

                            if let similar = details.similar, !similar.isEmpty {
                                SimilarMediaSection(
                                    title: details.type == "tv" ? "Похожие сериалы" : "Похожие фильмы",
                                    items: similar,
                                    onDirectPlay: { movie in
                                        directPlaybackMovie = movie
                                    }
                                )
                                .padding(.top, 16)
                            }

                            if let relatedStudio = viewModel.relatedStudio, let items = relatedStudio.items, !items.isEmpty {
                                RelatedStudioSection(response: relatedStudio, onDirectPlay: { movie in
                                    directPlaybackMovie = movie
                                })
                                .padding(.top, 16)
                            }
                        }
                        .offset(y: -60)
                        .padding(.bottom, 28)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .background {
                effectiveBackgroundColor
                    .animation(.easeInOut(duration: 0.4), value: effectiveBackgroundColor)
                    .ignoresSafeArea()
            }
            .refreshable {
                await viewModel.loadDetails(id: movieId, type: mediaType, force: true, studio: initialStudio)
            }
        }.ignoresSafeArea()
    }
}

private struct OptionalMovieNavigationTransitionModifier: ViewModifier {
    let sourceID: String?
    let namespace: Namespace.ID?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let sourceID, let namespace {
            content.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            content
        }
    }
}

private extension View {
    func optionalMovieNavigationTransition(sourceID: String?, in namespace: Namespace.ID?) -> some View {
        modifier(OptionalMovieNavigationTransitionModifier(sourceID: sourceID, namespace: namespace))
    }
}

private struct DetailsSkeletonView: View {
    let backgroundColor: Color
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    
    var body: some View {
        let baseHeight: CGFloat = verticalSizeClass == .compact ? 280 : 365
        
        VStack(spacing: 0) {
            // Backdrop
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(height: baseHeight)
                .shimmer()
                .mask(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: .black.opacity(0.4), location: 0.06),
                            .init(color: .black.opacity(0.85), location: 0.12),
                            .init(color: .black, location: 0.18),
                            .init(color: .black, location: 0.35),
                            .init(color: .black.opacity(0.8), location: 0.50),
                            .init(color: .black.opacity(0.45), location: 0.68),
                            .init(color: .black.opacity(0.2), location: 0.82),
                            .init(color: .black.opacity(0.06), location: 0.93),
                            .init(color: .clear, location: 1.0)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            
            VStack(alignment: .center, spacing: 12) {
                // Logo placeholder: replaced with a textual representation of loading to match RemoteLogoView
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 240, height: 40)
                    .cornerRadius(8)
                    .padding(.bottom, 8)
                    .shimmer()
                
                // Metadata row placeholder
                HStack(spacing: 16) {
                    ForEach(0..<4) { _ in
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 40, height: 16)
                            .cornerRadius(4)
                    }
                }
                .shimmer()
                .padding(.bottom, 4)
                
                // Play Button placeholder
                Capsule()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 180, height: 50)
                    .shimmer()
                    .padding(.top, 8)
                    .padding(.bottom, -4)
                
                // Info Section placeholder
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 80, height: 20)
                            .cornerRadius(4)
                        
                        HStack(spacing: 8) {
                            ForEach(0..<3) { i in
                                Capsule()
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(width: CGFloat(60 + i * 20), height: 32)
                            }
                        }
                    }
                    .shimmer()
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 100, height: 20)
                            .cornerRadius(4)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 16)
                                .cornerRadius(4)
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 16)
                                .cornerRadius(4)
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 16)
                                .cornerRadius(4)
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 200, height: 16)
                                .cornerRadius(4)
                        }
                    }
                    .shimmer()
                }
                .padding(.top, 20)
                .padding(.horizontal)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: verticalSizeClass == .compact ? 550 : .infinity)
            .frame(maxWidth: .infinity, alignment: .center)
            .offset(y: verticalSizeClass == .compact ? -50 : -25)
        }
    }
}



struct SourceSelectionLoadingView: View {
    let title: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    SourceSelectionSkeletonSection(title: "Озвучка", chipWidths: [84, 112, 96, 104])
                    SourceSelectionSkeletonSection(title: "Сезон", chipWidths: [88, 88, 88])
                    SourceSelectionSkeletonSection(title: "Серия", chipWidths: [84, 84, 84, 84])
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
                    .tint(.primary)
                    .buttonStyle(.plain)
                    .accessibilityLabel("Закрыть")
                }
            }
        }
        .presentationDragIndicator(.visible)
    }
}

struct SourceSelectionSkeletonSection: View {
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

struct SourceSelectionEmptyView: View {
    let title: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "film.stack")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text("Видео пока недоступно")
                    .font(.system(size: 20, weight: .bold))

                Text("Этот проект пока отсутствует в источниках стриминга или еще не вышел в релиз.")
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
                    .tint(.primary)
                    .buttonStyle(.plain)
                }
            }
        }
        .presentationDragIndicator(.visible)
    }
}

private struct DetailsPrimaryMetadataRow: View {
    let details: MediaDetailsDto
    var alignment: HorizontalAlignment = .center

    var body: some View {
        HStack(spacing: 8) {
            if let rating = details.ratings?.kp ?? details.ratings?.imdb ?? details.ratings?.tmdb, rating > 0 {
                Text(String(format: "%.1f", rating))
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(Color.rating(rating))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }

            if let ageRating = details.ageRating, !ageRating.isEmpty {
                Text(ageRating)
                    .fontWeight(.bold)
                    .foregroundColor(Color.ageRating(ageRating))
            }

            if let year = details.year, year > 0 {
                Text(String(year))
            }

            if let country = details.countries?.first, !country.isEmpty {
                Text(CountryLocalizer.format(country))
            }

            if let duration = details.duration, duration > 0 {
                Text("\(duration) мин")
            }
        }
        .font(.system(size: 15, weight: .semibold))
        .foregroundColor(.secondary)
        .multilineTextAlignment(alignment == .leading ? .leading : .center)
        .padding(.horizontal, alignment == .center ? 16 : 0)
        .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
    }
}

private struct DetailsInfoSection: View {
    let details: MediaDetailsDto
    let backgroundColor: Color
    var studio: StudioBrand? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var isDescriptionExpanded = false
    @State private var canExpand = false
    @State private var fullHeight: CGFloat = 0
    @State private var visibleHeight: CGFloat = 0

    private var genres: [String] {
        details.genres?
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
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
                            NavigationLink(destination: GenreCatalogView(genre: genre, mediaType: details.type)) {
                                HStack(spacing: 6) {
                                    Text(genre)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.primary)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .glassEffect(.regular.interactive(), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            let companies = details.productionCompanies ?? []
            let networks = details.networks ?? []
            if !companies.isEmpty || !networks.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(details.type == "tv" && !networks.isEmpty ? "Платформа" : "Студия")
                        .font(.system(size: 18, weight: .bold))

                    FlowLayout(spacing: 8) {
                        if !companies.isEmpty {
                            ForEach(companies) { company in
                                let brand = StudioBrand.find(by: company.name)
                                NavigationLink(destination: StudioCatalogView(studioId: brand?.id ?? String(company.id), studioName: company.name)) {
                                    Text(company.name)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.primary)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .glassEffect(.regular.interactive(), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        if !networks.isEmpty {
                            ForEach(networks) { net in
                                let brand = StudioBrand.find(by: net.name)
                                NavigationLink(destination: StudioCatalogView(studioId: brand?.id ?? String(net.id), studioName: net.name)) {
                                    Text(net.name)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.primary)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .glassEffect(.regular.interactive(), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            } else if let brand = details.identifiedStudio ?? studio {
                VStack(alignment: .leading, spacing: 10) {
                    Text(brand.isNetwork ? "Платформа" : "Студия")
                        .font(.system(size: 18, weight: .bold))

                    FlowLayout(spacing: 8) {
                        NavigationLink(destination: StudioCatalogView(studioId: brand.id, studioName: brand.name)) {
                            Text(brand.name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .glassEffect(.regular.interactive(), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            let budget = details.formattedBudget
            let revenue = details.formattedRevenue
            if budget != nil || revenue != nil {
                VStack(alignment: .leading, spacing: 10) {
                    Text(budget != nil && revenue != nil ? "Бюджет и сборы" : (budget != nil ? "Бюджет" : "Сборы"))
                        .font(.system(size: 18, weight: .bold))

                    HStack(spacing: 8) {
                        if let b = budget {
                            HStack(spacing: 4) {
                                Text("Бюджет:")
                                    .foregroundColor(.secondary)
                                Text(b)
                                    .fontWeight(.semibold)
                            }
                        }
                        if budget != nil && revenue != nil {
                            Text("•")
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                        if let r = revenue {
                            HStack(spacing: 4) {
                                Text("Сборы:")
                                    .foregroundColor(.secondary)
                                Text(r)
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                    .font(.system(size: 14))
                }
            }

            if let description = details.description, !description.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Описание")
                        .font(.system(size: 18, weight: .bold))

                    ZStack(alignment: .bottomLeading) {
                        Text(description)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(.primary.opacity(0.85))
                            .lineSpacing(4)
                            .lineLimit(isDescriptionExpanded ? nil : 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                GeometryReader { geo in
                                    Color.clear
                                        .onAppear {
                                            visibleHeight = geo.size.height
                                            checkTruncation()
                                        }
                                        .onChange(of: geo.size.height) { _, newHeight in
                                            visibleHeight = newHeight
                                            checkTruncation()
                                        }
                                }
                            )
                            .mask(
                                Group {
                                    if canExpand && !isDescriptionExpanded {
                                        LinearGradient(
                                            gradient: Gradient(stops: [
                                                .init(color: .black, location: 0.0),
                                                .init(color: .black, location: 0.4),
                                                .init(color: .clear, location: 1.0)
                                            ]),
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    } else {
                                        Color.black
                                    }
                                }
                            )
                    }
                    .background(
                        Text(description)
                            .font(.system(size: 15, weight: .regular))
                            .lineSpacing(4)
                            .lineLimit(nil)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .opacity(0)
                            .allowsHitTesting(false)
                            .background(
                                GeometryReader { geo in
                                    Color.clear
                                        .onAppear {
                                            fullHeight = geo.size.height
                                            checkTruncation()
                                        }
                                        .onChange(of: geo.size.height) { _, newHeight in
                                            fullHeight = newHeight
                                            checkTruncation()
                                        }
                                }
                            )
                    )
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isDescriptionExpanded)

                    if canExpand {
                        Button(action: {
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.prepare()
                            generator.impactOccurred()
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                isDescriptionExpanded.toggle()
                            }
                        }) {
                            HStack(spacing: 6) {
                                Text(isDescriptionExpanded ? "Свернуть" : "Читать далее")
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 11, weight: .heavy))
                                    .rotationEffect(.degrees(isDescriptionExpanded ? 180 : 0))
                            }
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .glassEffect(.regular.interactive(), in: .capsule)
                            .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, isDescriptionExpanded ? 12 : -28)
                        .zIndex(1)
                    }
                }
                .onChange(of: details.description) { _, _ in
                    isDescriptionExpanded = false
                    canExpand = false
                }
            }
        }
    }

    private func checkTruncation() {
        if !isDescriptionExpanded {
            canExpand = fullHeight > visibleHeight + 2
        }
    }
}

struct EpisodeDetailsSheetItem: Identifiable {
    let id = UUID()
    let movieId: String
    let season: Int
    let episode: Int
    let meta: TvEpisodeDetailsDto?
    let seasonEpisode: TvSeasonEpisodeDto?
    let fallbackTitle: String
    let isAvailable: Bool

    init(
        movieId: String,
        season: Int,
        episode: Int,
        meta: TvEpisodeDetailsDto? = nil,
        seasonEpisode: TvSeasonEpisodeDto? = nil,
        fallbackTitle: String = "Серия",
        isAvailable: Bool = true
    ) {
        self.movieId = movieId
        self.season = season
        self.episode = episode
        self.meta = meta
        self.seasonEpisode = seasonEpisode
        self.fallbackTitle = fallbackTitle
        self.isAvailable = isAvailable
    }
}

struct EpisodeDetailsSheet: View {
    let item: EpisodeDetailsSheetItem
    var details: MediaDetailsDto? = nil
    let onPlay: () -> Void
    let onWatchedToggle: (Bool) -> Void
    
    @State private var isWatched: Bool = false
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var downloadManager = DownloadManager.shared
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Still Image (Edge-to-edge)
                    let previewUrl: URL? = {
                        if let still = item.seasonEpisode?.stillPath ?? item.meta?.stillPath, !still.isEmpty {
                            if still.hasPrefix("http") {
                                return URL(string: still)
                            } else {
                                return URL(string: "https://api-sloosh.vercel.app/api/v1/images/tmdb/w500\(still)")
                            }
                        }
                        if let backdrop = details?.previewBackdropUrl ?? details?.displayBackdropUrl ?? details?.backdrop, !backdrop.isEmpty {
                            if backdrop.hasPrefix("http") {
                                return URL(string: backdrop)
                            } else {
                                return URL(string: "https://api-sloosh.vercel.app/api/v1/images/tmdb/w500\(backdrop)")
                            }
                        }
                        return nil
                    }()
                    
                    AsyncCachedImage(url: previewUrl) {
                        Rectangle()
                            .fill(Color.gray.opacity(0.15))
                            .aspectRatio(16/9, contentMode: .fill)
                            .shimmer()
                    } content: { image in
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } fallback: {
                        ZStack {
                            LinearGradient(
                                colors: [Color(white: 0.16), Color(white: 0.10)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            Image(systemName: item.isAvailable ? "play.circle.fill" : "calendar.badge.clock")
                                .font(.system(size: 36))
                                .foregroundColor(.white.opacity(0.35))
                        }
                        .aspectRatio(16/9, contentMode: .fill)
                    }
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16/9, contentMode: .fill)
                    .clipped()
                    
                    // Content
                    VStack(alignment: .leading, spacing: 14) {
                        // Title
                        let rawTitle = item.seasonEpisode?.name ?? item.meta?.name ?? (item.episode == 0 ? "Пилотная серия" : item.fallbackTitle)
                        let title: String = {
                            if item.episode == 0 {
                                return rawTitle
                            }
                            return rawTitle.hasPrefix("\(item.episode).") ? rawTitle : "\(item.episode). \(rawTitle)"
                        }()
                        Text(title)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.primary)
                        
                        // Metadata: Rating & Date
                        HStack(spacing: 12) {
                            let ratingVal: Double? = {
                                if let v = item.seasonEpisode?.voteAverage, v > 0 { return v }
                                if let v = item.meta?.ratings?.tmdb ?? item.meta?.ratings?.imdb, v > 0 { return v }
                                return nil
                            }()
                            if let rating = ratingVal {
                                Text(String(format: "%.1f", rating))
                                    .font(.system(size: 12, weight: .heavy))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 3)
                                    .background(Color.rating(rating))
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            } else if item.episode == 0 {
                                Text("Пилот")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.clear.glassEffect(in: RoundedRectangle(cornerRadius: 8, style: .continuous)))
                            }
                            
                            let airDate = item.seasonEpisode?.airDate ?? item.meta?.airDate ?? (item.episode == 0 ? (details?.releaseDate) : nil)
                            if let airDate = airDate, !airDate.isEmpty {
                                Text(formatAirDate(airDate))
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.secondary)
                            }

                            if let duration = item.seasonEpisode?.duration, duration > 0 {
                                Text("\(duration) мин")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.bottom, 2)
                        
                        // Description / Overview
                        let overview = item.seasonEpisode?.overview ?? item.meta?.overview ?? (item.episode == 0 ? (details?.description ?? "Пилотный выпуск сериала.") : nil)
                        if let overview = overview, !overview.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Описание серии")
                                    .font(.system(size: 16, weight: .bold))
                                
                                Text(overview)
                                    .font(.system(size: 15))
                                    .foregroundColor(.primary.opacity(0.85))
                                    .lineSpacing(4)
                            }
                        } else {
                            Text("Описание для этой серии отсутствует.")
                                .font(.system(size: 15))
                                .foregroundColor(.secondary)
                                .italic()
                        }
                        
                        // Bottom action: Play button or Release status
                        if item.isAvailable {
                            HStack(spacing: 12) {
                                Button(action: {
                                    dismiss()
                                    onPlay()
                                }) {
                                    HStack {
                                        Image(systemName: "play.fill")
                                        Text("Смотреть серию")
                                    }
                                    .font(.system(size: 17, weight: .bold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 4)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .buttonBorderShape(.capsule)
                                .tint(.primary)
                                .foregroundStyle(Color(UIColor.systemBackground))
                            }
                            .padding(.top, 8)
                        } else {
                            HStack(spacing: 12) {
                                Image(systemName: "calendar.badge.clock")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundColor(Color.slooshAccent)
                                
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Ожидается премьера")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.primary)
                                    
                                    let airDate = item.seasonEpisode?.airDate ?? item.meta?.airDate
                                    if let airDate = airDate, !airDate.isEmpty {
                                        Text("Дата выхода: \(formatAirDate(airDate))")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text("Дата выхода пока не объявлена")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(Color.clear.glassEffect(in: RoundedRectangle(cornerRadius: 16, style: .continuous)))
                            .padding(.top, 8)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("\(item.season) сезон, \(item.episode) серия")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.primary)
                    }
                    .tint(.primary)
                    .buttonStyle(.plain)
                }
                
                if item.isAvailable {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.prepare()
                            generator.impactOccurred()
                            isWatched.toggle()
                            onWatchedToggle(isWatched)
                        } label: {
                            Image(systemName: isWatched ? "checkmark.circle.fill" : "checkmark.circle")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(isWatched ? Color.slooshAccent : .primary)
                        }
                    }
                }
            }
        }
        .onAppear {
            guard item.isAvailable else { return }
            let root = item.movieId.hasPrefix("kp_") || item.movieId.hasPrefix("tmdb_") ? item.movieId : "kp_\(item.movieId)"
            let progressKey = "\(root)_s\(item.season)_e\(item.episode)"
            let progressFraction = PlaybackProgressStore.shared.normalizedProgress(mediaId: progressKey)
            isWatched = PlaybackProgressStore.shared.loadWatched(mediaId: progressKey) || (progressFraction ?? 0) >= 0.9
        }
    }
    
    private func formatAirDate(_ dateStr: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateStr) else { return dateStr }
        
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMMM yyyy"
        return formatter.string(from: date)
    }
    
    private func handleEpisodeDownload(kpId: Int, details: MediaDetailsDto, item: DownloadItem?) {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
        
        if let item = item {
            switch item.status {
            case .downloading, .pending:
                DownloadManager.shared.pauseDownload(id: item.id)
            case .paused:
                DownloadManager.shared.resumeDownload(id: item.id)
            case .failed:
                startDownload(kpId: kpId, details: details)
            case .completed:
                DownloadManager.shared.deleteDownload(id: item.id)
            }
        } else {
            startDownload(kpId: kpId, details: details)
        }
    }
    
    private func startDownload(kpId: Int, details: MediaDetailsDto) {
        Task {
            let title = details.title ?? details.originalTitle ?? ""
            let tmdbId = details.externalIds?.tmdb ?? details.ids?.tmdb ?? Int(details.id ?? "")
            await viewModel.fetchSources(kpId: kpId, tmdbId: tmdbId, title: title)
            guard let result = viewModel.sourceResultWrapper?.allohaResult else { return }
            
            let savedVoiceover = PlaybackProgressStore.shared.loadLastVoiceover(kpId: kpId, source: "alloha")
            let globalVoiceover = UserDefaults.standard.string(forKey: "alloha_last_translation_name")
            
            guard let seasonObj = result.seasons.first(where: { $0.season == item.season }),
                  let epObj = seasonObj.episodes.first(where: { $0.episode == item.episode }) else { return }
            
            let matching = epObj.translations.first(where: { allohaTranslationNamesMatch($0.name, savedVoiceover, exactOnly: true) })
            let globalMatching = epObj.translations.first(where: { allohaTranslationNamesMatch($0.name, globalVoiceover, exactOnly: false) })
            guard let translation = matching ?? globalMatching ?? epObj.translations.first else { return }
            
            let preferredQuality = VideoQualityPreference(rawValue: UserDefaults.standard.string(forKey: "preferredVideoQuality") ?? "Спрашивать каждый раз") ?? .ask
            DownloadManager.shared.startDownload(
                details: details,
                season: item.season,
                episode: item.episode,
                translation: translation,
                preferredQuality: preferredQuality
            )
        }
    }
}

struct EpisodeCellView: View {
    let movieId: String
    let season: Int
    let episode: Int
    let fallbackTitle: String
    var seasonEpisode: TvSeasonEpisodeDto? = nil
    var details: MediaDetailsDto? = nil
    var isAvailable: Bool = true
    let onPlayTap: () -> Void
    let onUpdate: () -> Void
    let onInfoTap: (TvEpisodeDetailsDto?, TvSeasonEpisodeDto?) -> Void
    
    @State private var meta: TvEpisodeDetailsDto?
    @State private var isLoading = false
    
    @State private var progressFractionState: Double?
    @State private var isWatchedState: Bool = false
    
    @ObservedObject private var downloadManager = DownloadManager.shared
    
    var previewUrl: URL? {
        if let still = seasonEpisode?.stillPath ?? meta?.stillPath, !still.isEmpty {
            if still.hasPrefix("http") {
                return URL(string: still)
            } else {
                return URL(string: "https://api-sloosh.vercel.app/api/v1/images/tmdb/w500\(still)")
            }
        }
        let backdrop = details?.previewBackdropUrl ?? details?.displayBackdropUrl ?? details?.backdrop
        if let backdrop = backdrop, !backdrop.isEmpty {
            if backdrop.hasPrefix("http") {
                return URL(string: backdrop)
            } else {
                return URL(string: "https://api-sloosh.vercel.app/api/v1/images/tmdb/w500\(backdrop)")
            }
        }
        return nil
    }
    
    private var progressKey: String {
        let root: String
        let effectiveDetails = details
        if let kp = effectiveDetails?.ids?.kp ?? effectiveDetails?.externalIds?.kp, kp > 0 {
            root = "kp_\(kp)"
        } else if movieId.hasPrefix("kp_") || movieId.hasPrefix("tmdb_") {
            root = movieId
        } else if let intVal = Int(movieId) {
            root = "kp_\(intVal)"
        } else {
            root = movieId
        }
        return "\(root)_s\(season)_e\(episode)"
    }
    
    private var isLastPlayed: Bool {
        let effectiveDetails = details
        let effectiveKp = effectiveDetails?.ids?.kp ?? effectiveDetails?.externalIds?.kp ?? (movieId.hasPrefix("kp_") ? Int(movieId.dropFirst(3)) : nil)
        let rootKey = effectiveKp.map { "kp_\($0)" } ?? (movieId.hasPrefix("tmdb_") ? movieId : "tmdb_\(movieId)")
        let lastSeason = PlaybackProgressStore.shared.loadLastSeason(mediaKey: rootKey) ?? (effectiveKp.flatMap { PlaybackProgressStore.shared.loadLastSeason(kpId: $0) })
        let lastEpisode = PlaybackProgressStore.shared.loadLastEpisode(mediaKey: rootKey) ?? (effectiveKp.flatMap { PlaybackProgressStore.shared.loadLastEpisode(kpId: $0) })
        return lastSeason == season && lastEpisode == episode
    }

    private func updateProgressState() {
        guard isAvailable else { return }
        progressFractionState = PlaybackProgressStore.shared.normalizedProgress(mediaId: progressKey)
        isWatchedState = PlaybackProgressStore.shared.loadWatched(mediaId: progressKey) || (progressFractionState ?? 0) >= 0.9
    }
    
    private func formatEpisodeAirDate(_ dateStr: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateStr) else { return dateStr }
        
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMMM yyyy"
        return formatter.string(from: date)
    }

    private func formatShortAirDate(_ dateStr: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateStr) else { return dateStr }
        
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                // Background Card
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(UIColor.tertiarySystemFill))
                    .frame(width: 160, height: 90)
                
                // Preview Image
                AsyncCachedImage(url: previewUrl) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 160, height: 90)
                        .shimmer()
                } content: { image in
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 160, height: 90)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .opacity(isAvailable ? 1.0 : 0.85)
                } fallback: {
                    ZStack {
                        LinearGradient(
                            colors: [Color(white: 0.16), Color(white: 0.10)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        Image(systemName: isAvailable ? "play.circle.fill" : "calendar.badge.clock")
                            .font(.system(size: 24))
                            .foregroundColor(.white.opacity(0.35))
                    }
                    .frame(width: 160, height: 90)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .animation(.easeInOut(duration: 0.25), value: previewUrl)
                
                // Dark gradient overlay
                VStack {
                    Spacer()
                    LinearGradient(
                        gradient: Gradient(colors: [.clear, .black.opacity(0.35)]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 24)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .allowsHitTesting(false)
                
                // Progress Bar (Bottom Aligned, only if available)
                if isAvailable, let progress = progressFractionState, progress > 0.02 {
                    VStack {
                        Spacer()
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(.white.opacity(0.2))
                                .frame(height: 3)
                            
                            Rectangle()
                                .fill(isWatchedState ? Color.gray : Color.slooshAccent)
                                .frame(width: 160 * CGFloat(progress), height: 3)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                
                // Rating overlay on top-left of the card (Unified with design system, only if available)
                if isAvailable {
                    let ratingVal: Double? = {
                        if let v = seasonEpisode?.voteAverage, v > 0 { return v }
                        if let v = meta?.ratings?.tmdb ?? meta?.ratings?.imdb, v > 0 { return v }
                        return nil
                    }()
                    if let rating = ratingVal {
                        VStack {
                            HStack {
                                Text(String(format: "%.1f", rating))
                                    .font(.system(size: 10, weight: .heavy))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 3)
                                    .background(Color.rating(rating))
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    .padding(6)
                                Spacer()
                            }
                            Spacer()
                        }
                    } else if episode == 0 {
                        VStack {
                            HStack {
                                Text("Пилот")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.clear.glassEffect(in: RoundedRectangle(cornerRadius: 6, style: .continuous)))
                                    .padding(6)
                                Spacer()
                            }
                            Spacer()
                        }
                    }
                } else {
                    // Unreleased badge on top-left of the card
                    VStack {
                        HStack {
                            HStack(spacing: 4) {
                                Image(systemName: "calendar")
                                    .font(.system(size: 9, weight: .semibold))
                                let rawDate = seasonEpisode?.airDate ?? meta?.airDate
                                Text(rawDate.map { formatShortAirDate($0) } ?? "Скоро")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.clear.glassEffect(in: RoundedRectangle(cornerRadius: 6, style: .continuous)))
                            .padding(6)
                            Spacer()
                        }
                        Spacer()
                    }
                }
                
                // Watched Checkmark Badge (Top-Right, only if available)
                if isAvailable && isWatchedState {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(Color.slooshAccent)
                                .shadow(color: .black.opacity(0.8), radius: 3, x: 0, y: 1)
                                .padding([.top, .trailing], 8)
                        }
                        Spacer()
                    }
                }
                
                // Download Badge (Top-Right, shifted left if watched is present, only if available)
                if isAvailable, let kpIdInt = Int(movieId) {
                    let downloadItem = downloadManager.getDownloadItem(kpId: kpIdInt, season: season, episode: episode)
                    if let dlItem = downloadItem {
                        VStack {
                            HStack {
                                Spacer()
                                if dlItem.status == .completed {
                                    Image(systemName: "arrow.down.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundColor(Color.slooshAccent)
                                        .shadow(color: .black.opacity(0.8), radius: 3, x: 0, y: 1)
                                        .padding([.top, .trailing], 8)
                                        .padding(.trailing, isWatchedState ? 20 : 0) // Shift left if checkmark is there
                                } else if dlItem.status == .downloading {
                                    ZStack {
                                        Circle()
                                            .stroke(Color.black.opacity(0.4), lineWidth: 1.5)
                                            .frame(width: 14, height: 14)
                                        Circle()
                                            .trim(from: 0.0, to: dlItem.progress)
                                            .stroke(Color.slooshAccent, lineWidth: 1.5)
                                            .frame(width: 14, height: 14)
                                            .rotationEffect(Angle(degrees: -90))
                                    }
                                    .shadow(color: .black.opacity(0.8), radius: 3, x: 0, y: 1)
                                    .padding([.top, .trailing], 8)
                                    .padding(.trailing, isWatchedState ? 20 : 0)
                                }
                            }
                            Spacer()
                        }
                    }
                }

                // Last Played Border (Centered, matches size, no clipping, only if available)
                if isAvailable && isLastPlayed {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.slooshAccent, lineWidth: 2)
                }
            }
            .frame(width: 160, height: 90)
            .contextMenu {
                if isAvailable {
                    Button {
                        onPlayTap()
                    } label: {
                        Label("Смотреть", systemImage: "play.fill")
                    }
                }
                
                Button {
                    onInfoTap(meta, seasonEpisode)
                } label: {
                    Label("О серии", systemImage: "info.circle")
                }
                
                if isAvailable {
                    Divider()
                    
                    if isWatchedState {
                        Button(role: .destructive) {
                            PlaybackProgressStore.shared.setWatched(mediaId: progressKey, watched: false)
                            updateProgressState()
                            onUpdate()
                        } label: {
                            Label("Сбросить прогресс", systemImage: "arrow.counterclockwise")
                        }
                    } else {
                        Button {
                            PlaybackProgressStore.shared.markAsWatched(mediaId: progressKey)
                            updateProgressState()
                            onUpdate()
                        } label: {
                            Label("Отметить как просмотренную", systemImage: "checkmark.circle")
                        }
                    }
                }
            }
            
            let rawTitle = seasonEpisode?.name ?? meta?.name ?? (episode == 0 ? "Пилотная серия" : fallbackTitle)
            let displayTitle: String = {
                if episode == 0 {
                    return rawTitle
                }
                return rawTitle.hasPrefix("\(episode).") ? rawTitle : "\(episode). \(rawTitle)"
            }()
            
            HStack(alignment: .top, spacing: 4) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(displayTitle)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    let airDate = seasonEpisode?.airDate ?? meta?.airDate ?? (episode == 0 ? (details?.releaseDate) : nil)
                    if let airDate = airDate, !airDate.isEmpty {
                        Text(formatEpisodeAirDate(airDate))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.prepare()
                    generator.impactOccurred()
                    onInfoTap(meta, seasonEpisode)
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary.opacity(0.8))
                        .padding(.leading, 4)
                }
                .buttonStyle(.plain)
            }
            .frame(width: 160)
        }
        .animation(.easeInOut(duration: 0.25), value: isLoading)
        .task(id: "\(season)-\(episode)") {
            updateProgressState()
            if seasonEpisode != nil { return }
            if isLoading { return }
            isLoading = true
            meta = nil
            do {
                var fetchedMeta: TvEpisodeDetailsDto? = nil
                let candidateIds = [movieId].compactMap { $0 }.filter { !$0.isEmpty }
                
                for candidateId in candidateIds {
                    do {
                        let result = try await MoviesRepository.shared.getEpisodeDetails(id: candidateId, season: season, episode: episode)
                        if result?.name != nil || result?.overview != nil || result?.ratings?.tmdb != nil || result?.ratings?.imdb != nil {
                            fetchedMeta = result
                            break
                        }
                    } catch {
                        continue
                    }
                }
                
                if let fetchedMeta = fetchedMeta {
                    meta = fetchedMeta
                } else {
                    meta = try await MoviesRepository.shared.getEpisodeDetails(id: movieId, season: season, episode: episode)
                }
            } catch {
                // Ignore
            }
            isLoading = false
        }
    }
}

struct InlineEpisodesSection: View {
    @ObservedObject var viewModel: DetailsViewModel
    let details: MediaDetailsDto
    var horizontalPadding: CGFloat = 16
    let onEpisodeTap: (Int, Int) -> Void

    @State private var selectedSeason: Int = 1
    @State private var selectedEpisodeForSheet: EpisodeDetailsSheetItem? = nil
    @State private var fullyWatchedSeasons: Set<Int> = []
    @State private var redrawTrigger: Bool = false
    @State private var currentSeasonData: TvSeasonDto? = nil

    var allSeasons: [Int] {
        let streamSeasons = viewModel.inlineSourceWrapper?.allohaResult?.seasons.map { $0.season } ?? []
        let metaSeasons = details.seasons?.compactMap { $0.seasonNumber }.filter { $0 > 0 } ?? []
        let combined = Array(Set(streamSeasons + metaSeasons)).sorted()
        return combined.isEmpty ? streamSeasons : combined
    }

    var rawId: String {
        details.ids?.kp?.description ?? details.id?.replacingOccurrences(of: "kp_", with: "") ?? ""
    }

    var tvSeriesId: String {
        if let tmdb = details.externalIds?.tmdb ?? details.ids?.tmdb, tmdb > 0 {
            return String(tmdb)
        }
        if let kp = details.ids?.kp ?? details.externalIds?.kp, kp > 0 {
            return "kp_\(kp)"
        }
        return details.id ?? rawId
    }

    var episodesForSelectedSeason: [Int] {
        let streamEpisodes = viewModel.inlineSourceWrapper?.allohaResult?.seasons.first(where: { $0.season == selectedSeason })?.episodes.map { $0.episode } ?? []
        let metaEpisodes = currentSeasonData?.episodes?.compactMap { $0.episodeNumber } ?? []
        let combined = Array(Set(streamEpisodes + metaEpisodes)).sorted()
        return combined.isEmpty ? streamEpisodes : combined
    }

    private func isEpisodeAvailable(_ episode: Int) -> Bool {
        guard let seasonObj = viewModel.inlineSourceWrapper?.allohaResult?.seasons.first(where: { $0.season == selectedSeason }) else {
            return false
        }
        return seasonObj.episodes.contains(where: { $0.episode == episode })
    }

    private func episodesCount(for seasonNum: Int) -> Int {
        let streamCount = viewModel.inlineSourceWrapper?.allohaResult?.seasons.first(where: { $0.season == seasonNum })?.episodes.count ?? 0
        if streamCount > 0 { return streamCount }
        return details.seasons?.first(where: { $0.seasonNumber == seasonNum })?.episodeCount ?? 0
    }

    private func loadCurrentSeason() {
        let idToFetch = tvSeriesId
        Task {
            do {
                currentSeasonData = try await MoviesRepository.shared.getSeason(id: idToFetch, season: selectedSeason)
            } catch {
                currentSeasonData = nil
            }
        }
    }

    private func updateWatchedSeasons() {
        guard let seasons = viewModel.inlineSourceWrapper?.allohaResult?.seasons else { return }
        var completed = Set<Int>()

        for s in seasons {
            let episodes = s.episodes.map { $0.episode }
            if !episodes.isEmpty {
                let allWatched = episodes.allSatisfy { ep in
                    let progressKey = "kp_\(rawId)_s\(s.season)_e\(ep)"
                    let progressFraction = PlaybackProgressStore.shared.normalizedProgress(mediaId: progressKey)
                    return PlaybackProgressStore.shared.loadWatched(mediaId: progressKey) || (progressFraction ?? 0) >= 0.9
                }
                if allWatched {
                    completed.insert(s.season)
                }
            }
        }
        self.fullyWatchedSeasons = completed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Сезоны и серии")
                .font(.system(size: 18, weight: .bold))
                .padding(.horizontal, horizontalPadding)

            if viewModel.isFetchingInlineSeasons && allSeasons.isEmpty {
                loadingView
            } else if allSeasons.isEmpty {
                Text("Эпизоды не найдены")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, horizontalPadding)
            } else {
                seasonPickerView
                episodesListView
            }
        }
        .onAppear {
            updateWatchedSeasons()
            guard let kpId = details.ids?.kp else {
                loadCurrentSeason()
                return
            }
            let lastSeason = PlaybackProgressStore.shared.loadLastSeason(kpId: kpId)
            if let lastSeason, allSeasons.contains(lastSeason) {
                selectedSeason = lastSeason
            } else if let firstSeason = allSeasons.first {
                selectedSeason = firstSeason
            }
            loadCurrentSeason()
        }
        .onChange(of: selectedSeason) { _, _ in
            loadCurrentSeason()
        }
        .onChange(of: allSeasons) { _, newSeasons in
            updateWatchedSeasons()
            if !newSeasons.contains(selectedSeason), let first = newSeasons.first {
                selectedSeason = first
            }
            loadCurrentSeason()
        }
        .sheet(item: $selectedEpisodeForSheet) { item in
            EpisodeDetailsSheet(
                item: item,
                details: details,
                onPlay: { () -> Void in
                    onEpisodeTap(item.season, item.episode)
                },
                onWatchedToggle: { (isWatched: Bool) -> Void in
                    let progressKey = "kp_\(item.movieId)_s\(item.season)_e\(item.episode)"
                    if isWatched {
                        PlaybackProgressStore.shared.markAsWatched(mediaId: progressKey)
                    } else {
                        PlaybackProgressStore.shared.setWatched(mediaId: progressKey, watched: false)
                    }
                    updateWatchedSeasons()
                    redrawTrigger.toggle()
                }
            )
            .environmentObject(viewModel)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var loadingView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(0..<4) { _ in
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 160, height: 90)
                        .shimmer()
                }
            }
            .padding(.horizontal, horizontalPadding)
        }
    }

    @ViewBuilder
    private var seasonPickerView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(allSeasons, id: \.self) { season in
                    Button(action: {
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.prepare()
                        generator.impactOccurred()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedSeason = season
                        }
                    }) {
                        HStack(spacing: 6) {
                            Text("\(season) сезон")
                                .font(.system(size: 14, weight: .semibold))
                            if fullyWatchedSeasons.contains(season) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(selectedSeason == season ? .black : Color.slooshAccent)
                                    .font(.system(size: 12, weight: .bold))
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            ZStack {
                                if selectedSeason == season {
                                    Capsule().fill(Color.white)
                                } else {
                                    Color.clear.glassEffect(in: Capsule())
                                }
                            }
                        )
                        .foregroundColor(selectedSeason == season ? .black : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, horizontalPadding)
        }
    }

    @ViewBuilder
    private var episodesListView: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(episodesForSelectedSeason, id: \.self) { episode in
                        let isAvailable = isEpisodeAvailable(episode)
                        let seasonEpisode: TvSeasonEpisodeDto? = {
                            if let found = currentSeasonData?.episodes?.first(where: { $0.episodeNumber == episode }) {
                                return found
                            }
                            if episode == 0 {
                                return TvSeasonEpisodeDto(
                                    id: 0,
                                    name: "Пилотная серия",
                                    overview: viewModel.details?.description ?? "Пилотный выпуск сериала.",
                                    airDate: currentSeasonData?.airDate ?? viewModel.details?.releaseDate ?? "",
                                    episodeNumber: 0,
                                    seasonNumber: selectedSeason,
                                    stillPath: viewModel.details?.previewBackdropUrl ?? viewModel.details?.displayBackdropUrl ?? viewModel.details?.backdrop,
                                    voteAverage: 0,
                                    duration: currentSeasonData?.episodes?.first?.duration
                                )
                            }
                            return nil
                        }()
                        Button(action: {
                            let generator = UIImpactFeedbackGenerator(style: isAvailable ? .medium : .light)
                            generator.prepare()
                            generator.impactOccurred()
                            if isAvailable {
                                onEpisodeTap(selectedSeason, episode)
                            } else {
                                selectedEpisodeForSheet = EpisodeDetailsSheetItem(
                                    movieId: rawId,
                                    season: selectedSeason,
                                    episode: episode,
                                    meta: nil,
                                    seasonEpisode: seasonEpisode,
                                    fallbackTitle: "Серия",
                                    isAvailable: false
                                )
                            }
                        }) {
                            EpisodeCellView(
                                movieId: rawId,
                                season: selectedSeason,
                                episode: episode,
                                fallbackTitle: "Серия",
                                seasonEpisode: seasonEpisode,
                                details: details,
                                isAvailable: isAvailable,
                                onPlayTap: { () -> Void in
                                    if isAvailable {
                                        onEpisodeTap(selectedSeason, episode)
                                    }
                                },
                                onUpdate: { () -> Void in
                                    updateWatchedSeasons()
                                    redrawTrigger.toggle()
                                },
                                onInfoTap: { (fetchedMeta: TvEpisodeDetailsDto?, epData: TvSeasonEpisodeDto?) -> Void in
                                    selectedEpisodeForSheet = EpisodeDetailsSheetItem(
                                        movieId: rawId,
                                        season: selectedSeason,
                                        episode: episode,
                                        meta: fetchedMeta,
                                        seasonEpisode: epData ?? seasonEpisode,
                                        fallbackTitle: "Серия",
                                        isAvailable: isAvailable
                                    )
                                }
                            )
                            .environmentObject(viewModel)
                            .id("\(selectedSeason)-\(episode)-\(seasonEpisode?.id ?? 0)-\(isAvailable)-\(redrawTrigger)")
                        }
                        .buttonStyle(.plain)
                        .id("\(selectedSeason)-\(episode)")
                    }
                }
                .padding(.horizontal, horizontalPadding)
            }
            .onAppear {
                scrollToLastPlayed(proxy: proxy)
            }
            .onChange(of: selectedSeason) { _, _ in
                scrollToLastPlayed(proxy: proxy)
            }
            .onChange(of: episodesForSelectedSeason) { _, _ in
                scrollToLastPlayed(proxy: proxy)
            }
        }
    }

    private func scrollToLastPlayed(proxy: ScrollViewProxy) {
        guard let kpId = details.ids?.kp else { return }
        let lastSeason = PlaybackProgressStore.shared.loadLastSeason(kpId: kpId) ?? 1
        let lastEpisode = PlaybackProgressStore.shared.loadLastEpisode(kpId: kpId) ?? 1

        if selectedSeason == lastSeason {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                    proxy.scrollTo("\(lastSeason)-\(lastEpisode)", anchor: .center)
                }
            }
        }
    }
}

// Обертка для Identifiable, чтобы использовать в .sheet(item:)
struct SourceResultWrapper: Identifiable {
    let id = UUID()
    var allohaResult: AllohaApiResult?
    var kpId: Int?
}

@MainActor
class DetailsViewModel: ObservableObject {
    @Published var details: MediaDetailsDto?
    @Published var isLoading = true

    @Published var isFetchingSources = false
    @Published var hasFinishedSourceFetch = false
    @Published var sourceResultWrapper: SourceResultWrapper?

    @Published var inlineSourceWrapper: SourceResultWrapper?
    @Published var selectedInlineSeason: Int = 1
    @Published var isFetchingInlineSeasons = false

    @Published var relatedStudio: RelatedStudioResponse? = nil
    @Published var movieCollection: MovieCollectionDto? = nil
    @Published var isFetchingRelatedStudio = false
    @Published var isFetchingCollection = false

    @Published var isFavorite: Bool = false

    private let allohaTranslationPreferenceKey = "alloha_last_translation_name"

    // MARK: - Sources cache (5 min TTL)
    private var sourcesCache: [Int: (wrapper: SourceResultWrapper, expiresAt: Date)] = [:]
    private let sourcesCacheTtl: TimeInterval = 5 * 60

    func prepareSourceSheet(kpId: Int, tmdbId: Int? = nil) {
        let effectiveTmdbId = tmdbId ?? details?.externalIds?.tmdb ?? details?.ids?.tmdb ?? Int(details?.id ?? "")
        let cacheKey = kpId > 0 ? kpId : (effectiveTmdbId ?? 0)

        if cacheKey > 0, let cached = sourcesCache[cacheKey], cached.expiresAt > Date() {
            sourceResultWrapper = cached.wrapper
            isFetchingSources = false
            hasFinishedSourceFetch = true
        } else {
            sourceResultWrapper = nil
            isFetchingSources = true
            hasFinishedSourceFetch = false
        }
    }

    func resetSourceSheet() {
        sourceResultWrapper = nil
        isFetchingSources = false
        hasFinishedSourceFetch = false
    }

    func saveAllohaTranslation(_ name: String?) {
        guard let name = name, !name.isEmpty else { return }
        UserDefaults.standard.set(name, forKey: allohaTranslationPreferenceKey)
    }

    func loadDetails(id: String, type: String? = nil, force: Bool = false, studio: StudioBrand? = nil) async {
        let inferredType = type ?? (id.hasPrefix("tv_") ? "tv" : (id.hasPrefix("movie_") ? "movie" : nil))
        if !force && details != nil && (details?.id == id || details?.ids?.kp?.description == id.replacingOccurrences(of: "kp_", with: "")) && (inferredType == nil || details?.type == inferredType) {
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            details = try await MoviesRepository.shared.getDetails(id: id, type: inferredType)
            if let details {
                PlaybackProgressStore.shared.saveMetadata(details: details)
            }
            checkFavoriteStatus()

            let isTv = details?.type == "tv" || inferredType == "tv"
            let effectiveKpId = details?.ids?.kp ?? details?.externalIds?.kp ?? (id.hasPrefix("kp_") ? Int(id.replacingOccurrences(of: "kp_", with: "")) : nil)
            let tmdbId = details?.externalIds?.tmdb ?? details?.ids?.tmdb ?? Int(details?.id ?? "")

            if isTv, ((effectiveKpId ?? 0) > 0 || (tmdbId ?? 0) > 0) {
                await fetchInlineSeasons(kpId: effectiveKpId ?? 0, tmdbId: tmdbId)
            }

            let studioToFetch = details?.identifiedStudio ?? studio
            let resolvedType = details?.type ?? inferredType ?? "movie"
            Task {
                await self.fetchRelatedByStudio(type: resolvedType, id: id, studio: studioToFetch)
            }
            if !isTv {
                Task {
                    await self.fetchMovieCollection(id: id)
                }
            }
        } catch {
            print("Error loading details: \(error)")
        }
    }

    func fetchRelatedByStudio(type: String, id: String, studio: StudioBrand? = nil) async {
        isFetchingRelatedStudio = true
        defer { isFetchingRelatedStudio = false }
        
        let rawCleanId = id.replacingOccurrences(of: "kp_", with: "")

        if let apiResult = await MoviesRepository.shared.getRelatedByStudio(type: type, id: id) {
            let items = apiResult.allItems
            if !items.isEmpty {
                let otherMovies = items.filter {
                    let itemCleanId = $0.id.replacingOccurrences(of: "kp_", with: "")
                    return itemCleanId != rawCleanId && $0.id != id
                }
                if !otherMovies.isEmpty {
                    let randomized = Array(otherMovies.shuffled().prefix(20))
                    self.relatedStudio = RelatedStudioResponse(
                        items: randomized,
                        label: apiResult.label,
                        page: apiResult.page,
                        totalPages: apiResult.totalPages,
                        totalResults: randomized.count
                    )
                    return
                }
            }
        }
        
        if let brand = studio {
            do {
                let collection = try await MoviesRepository.shared.getCollection(id: brand.id, page: 1)
                let otherMovies = collection.items.filter {
                    let itemCleanId = $0.id.replacingOccurrences(of: "kp_", with: "")
                    return itemCleanId != rawCleanId && $0.id != id
                }
                if !otherMovies.isEmpty {
                    let randomized = Array(otherMovies.shuffled().prefix(20))
                    self.relatedStudio = RelatedStudioResponse(
                        items: randomized,
                        label: brand.name,
                        page: 1,
                        totalPages: collection.totalPages,
                        totalResults: randomized.count
                    )
                }
            } catch {
                // Ignore fallback error
            }
        }
    }

    func fetchMovieCollection(id: String) async {
        isFetchingCollection = true
        defer { isFetchingCollection = false }
        self.movieCollection = await MoviesRepository.shared.getMovieCollection(id: id)
    }

    func fetchInlineSeasons(kpId: Int, tmdbId: Int? = nil) async {
        isFetchingInlineSeasons = true
        defer { isFetchingInlineSeasons = false }

        let effectiveTmdbId = tmdbId ?? details?.externalIds?.tmdb ?? details?.ids?.tmdb ?? Int(details?.id ?? "")
        do {
            let result = try await AllohaRepository.shared.fetchByKpId(kpId: kpId, tmdbId: effectiveTmdbId)
            if result.isSerial {
                self.inlineSourceWrapper = SourceResultWrapper(allohaResult: result, kpId: kpId > 0 ? kpId : (effectiveTmdbId ?? 0))
            }
        } catch {
            print("Error fetching inline seasons: \(error)")
        }
    }

    func checkFavoriteStatus() {
        guard let details = details else { return }
        guard let (mediaId, mediaType) = favoriteKey(for: details) else { return }
        var fav = FavoritesRepository.shared.isFavorite(mediaId: mediaId, mediaType: mediaType)
        if !fav, let kpId = details.ids?.kp?.description {
            fav = FavoritesRepository.shared.isFavorite(mediaId: kpId, mediaType: mediaType)
        }
        isFavorite = fav
    }

    func toggleFavorite() {
        guard let details = details else { return }
        guard let (mediaId, mediaType) = favoriteKey(for: details) else { return }

        let generator = UINotificationFeedbackGenerator()
        generator.prepare()

        if isFavorite {
            FavoritesRepository.shared.removeFromFavorites(mediaId: mediaId, mediaType: mediaType)
            if let kpId = details.ids?.kp?.description {
                FavoritesRepository.shared.removeFromFavorites(mediaId: kpId, mediaType: mediaType)
            }
            generator.notificationOccurred(.warning)
            ToastManager.shared.show(title: "Удалено из избранного", icon: "heart.slash.fill", iconColor: .primary, duration: 2.0)
        } else {
            FavoritesRepository.shared.addToFavorites(
                mediaId: mediaId,
                mediaType: mediaType,
                title: details.title ?? details.originalTitle,
                posterUrl: details.poster ?? details.backdrop,
                rating: details.ratings?.tmdb ?? details.ratings?.kp,
                year: details.year?.description,
                genres: details.genres?.compactMap { GenreDto(id: $0.lowercased(), name: $0) }
            )
            generator.notificationOccurred(.success)
            ToastManager.shared.show(title: "Добавлено в избранное", icon: "heart.fill", iconColor: .primary, duration: 2.0)
        }
        isFavorite.toggle()
    }

    private func favoriteKey(for details: MediaDetailsDto) -> (String, String)? {
        guard let mediaId = details.id, !mediaId.isEmpty else { return nil }
        let type = (details.type?.lowercased() == "tv" || details.type?.lowercased() == "series") ? "tv" : "movie"
        return (mediaId, type)
    }

    func fetchSources(kpId: Int, tmdbId: Int? = nil, title: String) async {
        let effectiveTmdbId = tmdbId ?? details?.externalIds?.tmdb ?? details?.ids?.tmdb ?? Int(details?.id ?? "")
        let cacheKey = kpId > 0 ? kpId : (effectiveTmdbId ?? 0)

        // Кэш на 5 минут — повторный тап «Смотреть» возвращает результат мгновенно
        if cacheKey > 0, let cached = sourcesCache[cacheKey], cached.expiresAt > Date() {
            sourceResultWrapper = cached.wrapper
            isFetchingSources = false
            hasFinishedSourceFetch = true
            return
        }

        sourceResultWrapper = nil
        isFetchingSources = true
        hasFinishedSourceFetch = false
        defer {
            isFetchingSources = false
            hasFinishedSourceFetch = true
        }

        do {
            let result: AllohaApiResult
            if kpId > 0 || (effectiveTmdbId ?? 0) > 0 {
                result = try await AllohaRepository.shared.fetchByKpId(kpId: kpId, tmdbId: effectiveTmdbId)
            } else {
                result = try await AllohaRepository.shared.fetchMedia(kpId: nil, tmdbId: nil, title: title)
            }
            let wrapper = SourceResultWrapper(allohaResult: result, kpId: kpId > 0 ? kpId : (effectiveTmdbId ?? 0))
            if cacheKey > 0 {
                sourcesCache[cacheKey] = (wrapper: wrapper, expiresAt: Date().addingTimeInterval(sourcesCacheTtl))
            }
            self.sourceResultWrapper = wrapper
        } catch {
            print("Error fetching sources: \(error)")
        }
    }

    private func preferredAllohaTranslation(from movie: AllohaMovie) -> AllohaTranslation? {
        let savedName = UserDefaults.standard.string(forKey: allohaTranslationPreferenceKey)
        return movie.translations.first(where: { $0.name == savedName }) ?? movie.translations.first
    }
}

// MARK: - Crew / Creators Section

private struct CrewSection: View {
    let crew: [CrewMemberDto]
    var namespace: Namespace.ID? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Создатели")
                .font(.system(size: 18, weight: .bold))
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 10) {
                    ForEach(crew) { member in
                        let transitionID = "crew_\(member.id)"
                        NavigationLink(
                            destination: PersonDetailView(
                                personId: member.id,
                                initialName: member.name,
                                navigationTransitionID: transitionID,
                                navigationTransitionNamespace: namespace
                            )
                            .navigationBarBackButtonHidden(true)
                        ) {
                            if let namespace {
                                CrewCardView(member: member)
                                    .matchedTransitionSource(id: transitionID, in: namespace)
                            } else {
                                CrewCardView(member: member)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

private struct CrewCardView: View {
    let member: CrewMemberDto

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 76, height: 76)

                if let photo = member.photo, let url = URL(string: photo) {
                    AsyncCachedImage(url: url) {
                        Circle()
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 76, height: 76)
                            .shimmer()
                    } content: { image in
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 76, height: 76)
                            .clipShape(Circle())
                    } fallback: {
                        placeholder
                    }
                } else {
                    placeholder
                }
            }
            .overlay(
                Circle()
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 3)

            VStack(spacing: 2) {
                Text(member.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .allowsTightening(true)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.center)

                if let role = member.role, !role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(role)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .allowsTightening(true)
                        .minimumScaleFactor(0.85)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(width: 76)
        }
        .frame(width: 76)
    }

    private var placeholder: some View {
        Image(systemName: "person.fill")
            .font(.system(size: 28))
            .foregroundStyle(Color.white.opacity(0.35))
            .frame(width: 76, height: 76)
    }
}

// MARK: - Cast / Actors Section

private struct ActorsSection: View {
    let cast: [CastMemberDto]
    var namespace: Namespace.ID? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Актёры")
                .font(.system(size: 18, weight: .bold))
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 10) {
                    ForEach(cast) { actor in
                        let transitionID = "actor_\(actor.id)"
                        NavigationLink(
                            destination: PersonDetailView(
                                personId: actor.id,
                                initialName: actor.name,
                                navigationTransitionID: transitionID,
                                navigationTransitionNamespace: namespace
                            )
                            .navigationBarBackButtonHidden(true)
                        ) {
                            if let namespace {
                                ActorCardView(actor: actor)
                                    .matchedTransitionSource(id: transitionID, in: namespace)
                            } else {
                                ActorCardView(actor: actor)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

private struct ActorCardView: View {
    let actor: CastMemberDto

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 76, height: 76)

                if let photo = actor.photo, let url = URL(string: photo) {
                    AsyncCachedImage(url: url) {
                        Circle()
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 76, height: 76)
                            .shimmer()
                    } content: { image in
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 76, height: 76)
                            .clipShape(Circle())
                    } fallback: {
                        placeholder
                    }
                } else {
                    placeholder
                }
            }
            .overlay(
                Circle()
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 3)

            VStack(spacing: 2) {
                Text(actor.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .allowsTightening(true)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.center)

                if let character = actor.character, !character.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(character)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .allowsTightening(true)
                        .minimumScaleFactor(0.85)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(width: 76)
        }
        .frame(width: 76)
    }

    private var placeholder: some View {
        Image(systemName: "person.fill")
            .font(.system(size: 28))
            .foregroundStyle(Color.white.opacity(0.35))
            .frame(width: 76, height: 76)
    }
}

// MARK: - Trailers Section

private struct TrailersSection: View {
    let trailers: [TrailerVideoDto]
    let onSelect: (TrailerVideoDto) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Трейлеры")
                .font(.system(size: 18, weight: .bold))
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(trailers) { trailer in
                        Button {
                            onSelect(trailer)
                        } label: {
                            TrailerCardView(trailer: trailer)
                        }
                        .buttonStyle(.glassPress)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

private struct TrailerCardView: View {
    let trailer: TrailerVideoDto

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .center) {
                if let url = trailer.thumbnailUrl {
                    AsyncCachedImage(url: url) {
                        Rectangle()
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 220, height: 124)
                            .shimmer()
                    } content: { image in
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 220, height: 124)
                            .clipped()
                    } fallback: {
                        fallbackThumbnail
                    }
                } else {
                    fallbackThumbnail
                }

                // Subtle bottom gradient for readability
                LinearGradient(
                    colors: [.clear, .black.opacity(0.45)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                // Centered Liquid Glass Play Badge
                Image(systemName: "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .glassEffect(.regular.interactive(), in: Circle())
                    .shadow(color: Color.black.opacity(0.35), radius: 6, x: 0, y: 3)
            }
            .frame(width: 220, height: 124)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 3)

            Text(trailer.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(width: 220, alignment: .leading)
        }
    }

    private var fallbackThumbnail: some View {
        ZStack {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 220, height: 124)
            Image(systemName: "film")
                .font(.system(size: 28))
                .foregroundStyle(Color.white.opacity(0.35))
        }
    }
}

// MARK: - Franchise & Studio Sections

private struct FranchiseCollectionSection: View {
    let collection: MovieCollectionDto
    var onDirectPlay: ((MediaDto) -> Void)? = nil

    var body: some View {
        if let parts = collection.parts, !parts.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Все части франшизы")
                        .font(.system(size: 18, weight: .bold))
                    if let name = collection.name, !name.isEmpty {
                        Text(name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(parts) { part in
                            NavigationLink(destination: DetailsView(movieId: part.id, mediaType: "movie", navigationTransitionID: nil, navigationTransitionNamespace: nil).navigationBarBackButtonHidden(true)) {
                                MoviePosterCard(movie: part)
                                    .frame(width: 120)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Group {
                                    Button {
                                        onDirectPlay?(part)
                                    } label: {
                                        Label("Смотреть", systemImage: "play.fill")
                                    }
                                    NavigationLink(destination: DetailsView(movieId: part.id, mediaType: "movie", navigationTransitionID: nil, navigationTransitionNamespace: nil).navigationBarBackButtonHidden(true)) {
                                        Label("Подробнее", systemImage: "info.circle")
                                    }
                                }
                                .tint(nil)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
}

private struct RelatedStudioSection: View {
    let response: RelatedStudioResponse
    var onDirectPlay: ((MediaDto) -> Void)? = nil

    var body: some View {
        let items = response.allItems
        if !items.isEmpty {
            let brand = response.label.flatMap { StudioBrand.find(by: $0) }
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("Другие релизы")
                        .font(.system(size: 18, weight: .bold))
                    if let label = response.label, !label.isEmpty {
                        NavigationLink(destination: StudioCatalogView(studioId: brand?.id ?? label, studioName: label)) {
                            Text(label)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .glassEffect(.regular.interactive(), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(items) { movie in
                            NavigationLink(destination: DetailsView(movieId: movie.id, mediaType: movie.type, navigationTransitionID: nil, navigationTransitionNamespace: nil, initialStudio: brand).navigationBarBackButtonHidden(true)) {
                                MoviePosterCard(movie: movie)
                                    .frame(width: 120)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Group {
                                    Button {
                                        onDirectPlay?(movie)
                                    } label: {
                                        Label("Смотреть", systemImage: "play.fill")
                                    }
                                    NavigationLink(destination: DetailsView(movieId: movie.id, mediaType: movie.type, navigationTransitionID: nil, navigationTransitionNamespace: nil, initialStudio: brand).navigationBarBackButtonHidden(true)) {
                                        Label("Подробнее", systemImage: "info.circle")
                                    }
                                }
                                .tint(nil)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
}

// MARK: - Similar Media Section

private struct SimilarMediaSection: View {
    let title: String
    let items: [MediaDto]
    var onDirectPlay: ((MediaDto) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(items) { item in
                        NavigationLink(destination: DetailsView(movieId: item.id, mediaType: item.type, navigationTransitionID: nil, navigationTransitionNamespace: nil).navigationBarBackButtonHidden(true)) {
                            MoviePosterCard(movie: item)
                                .frame(width: 120)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Group {
                                Button {
                                    onDirectPlay?(item)
                                } label: {
                                    Label("Смотреть", systemImage: "play.fill")
                                }
                                NavigationLink(destination: DetailsView(movieId: item.id, mediaType: item.type, navigationTransitionID: nil, navigationTransitionNamespace: nil).navigationBarBackButtonHidden(true)) {
                                    Label("Подробнее", systemImage: "info.circle")
                                }
                            }
                            .tint(nil)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

struct BlurFadeScaleModifier: ViewModifier {
    let isBlurry: Bool
    func body(content: Content) -> some View {
        content
            .opacity(isBlurry ? 0 : 1)
            .blur(radius: isBlurry ? 8 : 0)
            .scaleEffect(isBlurry ? 0.9 : 1)
    }
}

extension AnyTransition {
    static var blurFadeScale: AnyTransition {
        .modifier(
            active: BlurFadeScaleModifier(isBlurry: true),
            identity: BlurFadeScaleModifier(isBlurry: false)
        )
    }
}
