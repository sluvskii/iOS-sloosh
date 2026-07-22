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
                gradient: Gradient(colors: [
                    .black,
                    .black.opacity(0.8),
                    .black.opacity(0.4),
                    .black.opacity(0.1),
                    .clear
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
    
    var body: some View {
        AsyncCachedImage(url: url) {
            Text(fallbackTitle)
                .font(.system(size: 34, weight: .heavy))
                .multilineTextAlignment(alignment == .leading ? .leading : .center)
                .padding(.horizontal, alignment == .center ? 16 : 0)
                .shimmer()
                .frame(maxWidth: .infinity, alignment: alignment)
        } content: { image in
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 280, maxHeight: 110, alignment: alignment)
                .padding(.horizontal, alignment == .center ? 16 : 0)
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
        } fallback: {
            Text(fallbackTitle)
                .font(.system(size: 34, weight: .heavy))
                .multilineTextAlignment(alignment == .leading ? .leading : .center)
                .padding(.horizontal, alignment == .center ? 16 : 0)
                .frame(maxWidth: .infinity, alignment: alignment)
        }
    }
}

struct DetailsView: View {
    let movieId: String
    let navigationTransitionID: String?
    let navigationTransitionNamespace: Namespace.ID?
    @StateObject private var viewModel = DetailsViewModel()
    
    @State private var showPlayer = false
    @State private var showSourceSheet = false
    @State private var selectedIframeUrl: String? = nil
    @State private var sourceSheetTitle = ""
    @State private var sourceFetchTask: Task<Void, Never>?
    @State private var sourceSheetDetent: PresentationDetent = .medium
    @State private var sourceSheetMode: SourceSelectionMode = .play
    @Namespace private var transition
    @State private var sourceSheetSourceID: String = "playBtn"
    
    @State private var playerKpId: Int?
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

    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dismiss) private var dismiss

    @State private var dominantBackdropColor: UIColor? = nil
    @State private var dominantPosterColor: UIColor? = nil

    @AppStorage("hasSeenSourceSelectionTooltip") private var hasSeenSourceSelectionTooltip = false
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

    private func fetchAverageColor(from url: URL?) async -> UIColor? {
        guard let url else { return nil }

        do {
            let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
                  let image = UIImage(data: data) else {
                return nil
            }
            return image.averageColor
        } catch {
            return nil
        }
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
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                ZStack {
                    if let details = viewModel.details, isLogoAtTop {
                        RemoteLogoView(
                            url: URL(string: details.displayLogoUrl ?? ""),
                            fallbackTitle: details.title ?? details.originalTitle ?? "Без названия",
                            alignment: .center
                        )
                        .frame(height: 32)
                        .padding(.horizontal, 72)
                        .transition(.blurFadeScale)
                    }
                    
                    HStack {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .glassEffect(.regular.interactive(), in: .circle)
                        }
                        .tint(.white)
                        
                        Spacer()
                        
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
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(.white)
                                .symbolEffect(.bounce, value: favoriteBounce)
                                .frame(width: 44, height: 44)
                                .glassEffect(.regular.interactive(), in: .circle)
                        }
                        .disabled(viewModel.details == nil)
                        .accessibilityLabel(viewModel.isFavorite ? "Убрать из избранного" : "Добавить в избранное")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .background(
                    VariableBlurView(tintColor: effectiveBackgroundColor, tintOpacity: 0.6, style: .systemMaterialDark)
                        .padding(.bottom, -60)
                        .ignoresSafeArea(edges: .top)
                        .opacity(isLogoAtTop ? 1.0 : 0.0)
                        .animation(.easeInOut(duration: 0.25), value: isLogoAtTop)
                        .allowsHitTesting(false)
                )
            }
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .task {
                await viewModel.loadDetails(id: movieId)
            }
            .task(id: viewModel.details?.id) {
                await MainActor.run {
                    dominantBackdropColor = nil
                    dominantPosterColor = nil
                }

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
            }) {
                ZStack {
                    if viewModel.isFetchingSources {
                        SourceSelectionLoadingView(
                            title: sourceSheetTitle
                        )
                    } else if let wrapper = viewModel.sourceResultWrapper,
                              let result = wrapper.allohaResult {
                        SourceSelectionView(mode: sourceSheetMode, result: result, kpId: wrapper.kpId, details: viewModel.details) { translation, season, episode, quality in
                            if sourceSheetMode == .play {
                                playerKpId = wrapper.kpId
                                playerSeason = season
                                playerEpisode = episode
                                playerQuality = quality
                                playerSeriesResult = result
                                playerVoices = result.allTranslationNames
                                
                                if let kpId = wrapper.kpId,
                                   DownloadManager.shared.isDownloaded(kpId: kpId, season: season, episode: episode),
                                   let downloadItem = DownloadManager.shared.getDownloadItem(kpId: kpId, season: season, episode: episode),
                                   downloadItem.translationName == translation.name {
                                    selectedIframeUrl = nil
                                    playerVoiceover = downloadItem.translationName
                                    playerStreamUrl = downloadItem.localPlayableUrl?.absoluteString
                                } else {
                                    selectedIframeUrl = translation.iframeUrl
                                    playerVoiceover = translation.name
                                    playerStreamUrl = translation.streamUrl
                                }
                                
                                showPlayer = true
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
                    } else {
                        SourceSelectionEmptyView(title: sourceSheetTitle)
                    }
                }
                .presentationDetents([.medium, .large], selection: $sourceSheetDetent)
                .navigationTransition(.zoom(sourceID: sourceSheetSourceID, in: transition))
            }
            .fullScreenCover(isPresented: $showPlayer, onDismiss: {
                selectedIframeUrl = nil
                playerKpId = nil
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
                    if let iframeUrl = selectedIframeUrl {
                        PlayerView(iframeUrl: iframeUrl, fallbackTitle: details.title ?? details.originalTitle ?? "", kpId: playerKpId, season: playerSeason, episode: playerEpisode, selectedVoiceover: playerVoiceover, directStreamUrl: playerStreamUrl, voices: playerVoices, subtitles: playerSubtitles, initialQuality: playerQuality, seriesResult: playerSeriesResult)
                    } else if let streamUrl = playerStreamUrl {
                        PlayerView(iframeUrl: "", fallbackTitle: details.title ?? details.originalTitle ?? "", kpId: playerKpId, season: playerSeason, episode: playerEpisode, selectedVoiceover: playerVoiceover, directStreamUrl: streamUrl, voices: playerVoices, subtitles: playerSubtitles, initialQuality: playerQuality, seriesResult: playerSeriesResult)
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
    }

    private func handlePlayAction(details: MediaDetailsDto) {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()

        guard let kpId = details.ids?.kp else { return }

        sourceSheetSourceID = "playBtn"
        sourceSheetTitle = details.title ?? details.originalTitle ?? ""
        sourceSheetDetent = .medium
        sourceSheetMode = .play
        viewModel.resetSourceSheet()
        showSourceSheet = true

        sourceFetchTask?.cancel()
        sourceFetchTask = Task {
            await viewModel.fetchSources(kpId: kpId, title: sourceSheetTitle)
        }
    }

    private func handleEpisodeSelection(details: MediaDetailsDto, season: Int, episode: Int) {
        guard let kpId = details.ids?.kp else { return }

        PlaybackProgressStore.shared.saveLastPlayed(
            kpId: kpId,
            season: season,
            episode: episode
        )

        sourceSheetSourceID = "playBtn"
        sourceSheetTitle = details.title ?? details.originalTitle ?? ""
        sourceSheetDetent = .medium
        sourceSheetMode = .play
        viewModel.resetSourceSheet()
        showSourceSheet = true

        sourceFetchTask?.cancel()
        sourceFetchTask = Task {
            await viewModel.fetchSources(kpId: kpId, title: sourceSheetTitle)
        }
    }

    private func playAndDownloadRow(for details: MediaDetailsDto) -> some View {
        HStack(spacing: 8) {
            playButton(for: details)
                .tooltip(text: "Нажмите для выбора перевода", isVisible: $showTooltip, isTailTop: false)
            downloadButton(for: details)
        }
    }

    private func playButton(for details: MediaDetailsDto) -> some View {
        Button(action: {
            handlePlayAction(details: details)
        }) {
            HStack(spacing: 8) {
                Image(systemName: "play.fill")
                    .font(.system(size: 18, weight: .black))
                Text("Смотреть")
                    .font(.system(size: 19, weight: .heavy))
            }
            .frame(height: 50)
            .padding(.horizontal, 24)
        }
        .buttonStyle(GlassPlayButtonStyle())
        .matchedTransitionSource(id: "playBtn", in: transition) { source in
            source
                .background(.clear)
                .clipShape(RoundedRectangle(cornerRadius: 25))
        }
        .contentShape(Capsule())
    }

    @ViewBuilder
    private func downloadButton(for details: MediaDetailsDto) -> some View {
        let kpId = details.ids?.kp ?? 0
        let item = DownloadManager.shared.getDownloadItem(kpId: kpId, season: nil, episode: nil)
        
        Button(action: {
            handleDownloadAction(details: details, item: item)
        }) {
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
            .frame(width: 50, height: 50)
        }
        .buttonStyle(GlassDownloadButtonStyle())
        .matchedTransitionSource(id: "downloadBtn", in: transition) { source in
            source
                .background(.clear)
                .clipShape(RoundedRectangle(cornerRadius: 25))
        }
        .contentShape(Capsule())
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
        guard let kpId = details.ids?.kp else { return }
        
        sourceSheetTitle = details.title ?? details.originalTitle ?? ""
        sourceSheetDetent = .medium
        sourceSheetMode = .download
        viewModel.resetSourceSheet()
        showSourceSheet = true

        sourceFetchTask?.cancel()
        sourceFetchTask = Task {
            await viewModel.fetchSources(kpId: kpId, title: sourceSheetTitle)
        }
    }

    // MARK: - Image Saving

    @MainActor
    private func saveImage(from urlString: String?, label: String) async {
        guard let urlString, let url = URL(string: urlString) else { return }
        isSavingImage = true
        defer { isSavingImage = false }

        // Check/request authorization
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if currentStatus == .notDetermined {
            let granted = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard granted == .authorized || granted == .limited else {
                ToastManager.shared.show(title: "Нет доступа к Фото", icon: "lock")
                return
            }
        } else if currentStatus != .authorized && currentStatus != .limited {
            ToastManager.shared.show(title: "Нет доступа к Фото", icon: "lock")
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard UIImage(data: data) != nil else {
                ToastManager.shared.show(title: "Не удалось скачать \(label)", icon: "xmark.circle")
                return
            }
            // Use completion-based API to avoid ObjC exception crashes
            let saved = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                PHPhotoLibrary.shared().performChanges({
                    let req = PHAssetCreationRequest.forAsset()
                    req.addResource(with: .photo, data: data, options: nil)
                }, completionHandler: { success, _ in
                    cont.resume(returning: success)
                })
            }
            if saved {
                ToastManager.shared.show(title: "Сохранено в Фото", icon: "checkmark.circle.fill")
            } else {
                ToastManager.shared.show(title: "Не удалось сохранить", icon: "xmark.circle")
            }
        } catch {
            ToastManager.shared.show(title: "Ошибка при загрузке", icon: "xmark.circle")
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

    private var portraitDetailsContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                if viewModel.isLoading {
                    DetailsSkeletonView(backgroundColor: effectiveBackgroundColor)
                        .transition(.opacity)
                } else if let details = viewModel.details {
                    // Stretchy Backdrop
                    let baseHeight: CGFloat = 450
                    
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

                        if let originalTitle = details.originalTitle, !originalTitle.isEmpty, originalTitle != details.title {
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

                        DetailsInfoSection(details: details, backgroundColor: effectiveBackgroundColor)
                            .padding(.top, 20)
                            .padding(.horizontal)

                        if details.type == "tv" {
                            InlineEpisodesSection(viewModel: viewModel, details: details) { season, episode in
                                handleEpisodeSelection(details: details, season: season, episode: episode)
                            }
                            .padding(.top, 8)
                            .padding(.bottom, 20)
                        }
                    }
                    .offset(y: -80)
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
            if #available(iOS 18.0, *) {
                PremiumMeshBackground(dominantColor: dominantBackdropColor ?? dominantPosterColor)
            } else {
                effectiveBackgroundColor
            }
        }
        .refreshable {
            await viewModel.loadDetails(id: movieId, force: true)
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

                                if let originalTitle = details.originalTitle, !originalTitle.isEmpty, originalTitle != details.title {
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

                                DetailsInfoSection(details: details, backgroundColor: effectiveBackgroundColor)
                                    .padding(.top, 20)
                                    .padding(.horizontal)
                            }
                            .frame(maxWidth: 550)
                            .frame(maxWidth: .infinity, alignment: .center)

                            if details.type == "tv" {
                                let paddingVal = max(16, (outerGeometry.size.width - 550) / 2 + 16)
                                InlineEpisodesSection(
                                    viewModel: viewModel,
                                    details: details,
                                    horizontalPadding: paddingVal
                                ) { season, episode in
                                    handleEpisodeSelection(details: details, season: season, episode: episode)
                                }
                                .padding(.top, 8)
                                .padding(.bottom, 40)
                            }
                        }
                        .offset(y: -60)
                        .padding(.bottom, 24)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .background {
                if #available(iOS 18.0, *) {
                    PremiumMeshBackground(dominantColor: dominantBackdropColor ?? dominantPosterColor)
                } else {
                    effectiveBackgroundColor
                }
            }
            .refreshable {
                await viewModel.loadDetails(id: movieId, force: true)
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
        let baseHeight: CGFloat = verticalSizeClass == .compact ? 280 : 450
        
        VStack(spacing: 0) {
            // Backdrop
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(height: baseHeight)
                .mask(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            .black,
                            .black.opacity(0.8),
                            .black.opacity(0.4),
                            .black.opacity(0.1),
                            .clear
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shimmer()
            
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
            .offset(y: verticalSizeClass == .compact ? -60 : -80)
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
            if let rating = details.ratings?.kp, rating > 0 {
                Label(String(format: "%.1f", rating), systemImage: "star.fill")
                    .foregroundColor(.rating(rating))
            }

            if let year = details.year, year > 0 {
                Text(String(year))
            }

            if let country = details.countries?.first, !country.isEmpty {
                Text(country)
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
                            Text(genre)
                                .font(.system(size: 14, weight: .semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .glassEffect(in: Capsule())
                        }
                    }
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
                                                .init(color: .black, location: 0.7),
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
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                isDescriptionExpanded.toggle()
                            }
                        }) {
                            HStack(spacing: 6) {
                                Text(isDescriptionExpanded ? "Свернуть" : "Развернуть")
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 13, weight: .bold))
                                    .rotationEffect(.degrees(isDescriptionExpanded ? 180 : 0))
                            }
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(Color.slooshAccent)
                            .padding(.vertical, 4)
                        }
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
    let fallbackTitle: String
}

struct EpisodeDetailsSheet: View {
    let item: EpisodeDetailsSheetItem
    let onPlay: () -> Void
    let onWatchedToggle: (Bool) -> Void
    
    @State private var isWatched: Bool = false
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var downloadManager = DownloadManager.shared
    @EnvironmentObject private var viewModel: DetailsViewModel
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Still Image (Edge-to-edge)
                    let previewUrl = URL(string: "https://api.neome.uk/api/v1/images/screens/\(item.movieId)/\(item.season)/\(item.episode)/large")
                    
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
                            Color(UIColor.secondarySystemBackground)
                            Image(systemName: "photo")
                                .font(.system(size: 30))
                                .foregroundColor(.secondary)
                        }
                        .aspectRatio(16/9, contentMode: .fill)
                    }
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16/9, contentMode: .fill)
                    .clipped()
                    
                    // Content
                    VStack(alignment: .leading, spacing: 14) {
                        // Title
                        let title = item.meta?.name ?? item.fallbackTitle
                        Text(title)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.primary)
                        
                        // Metadata: Rating & Date
                        HStack(spacing: 12) {
                            if let rating = item.meta?.ratings?.tmdb ?? item.meta?.ratings?.imdb, rating > 0 {
                                Text(String(format: "%.1f", rating))
                                    .font(.system(size: 12, weight: .heavy))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 3)
                                    .background(Color.rating(rating))
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            
                            if let airDate = item.meta?.airDate, !airDate.isEmpty {
                                Text(formatAirDate(airDate))
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.bottom, 2)
                        
                        // Description / Overview
                        if let overview = item.meta?.overview, !overview.isEmpty {
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
                        
                        // Buttons at the bottom of scroll content (flying)
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
        .onAppear {
            let progressKey = "kp_\(item.movieId)_s\(item.season)_e\(item.episode)"
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
            await viewModel.fetchSources(kpId: kpId, title: title)
            guard let result = viewModel.sourceResultWrapper?.allohaResult else { return }
            
            let savedVoiceover = PlaybackProgressStore.shared.loadLastVoiceover(kpId: kpId, source: "alloha")
            let globalVoiceover = UserDefaults.standard.string(forKey: "alloha_last_translation_name")
            
            guard let seasonObj = result.seasons.first(where: { $0.season == item.season }),
                  let epObj = seasonObj.episodes.first(where: { $0.episode == item.episode }) else { return }
            
            let matching = epObj.translations.first(where: { allohaTranslationNamesMatch($0.name, savedVoiceover, exactOnly: true) })
            let globalMatching = epObj.translations.first(where: { allohaTranslationNamesMatch($0.name, globalVoiceover, exactOnly: false) })
            let translation = matching ?? globalMatching ?? epObj.translations.first!
            
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
    let onPlayTap: () -> Void
    let onUpdate: () -> Void
    let onInfoTap: (TvEpisodeDetailsDto?) -> Void
    
    @State private var meta: TvEpisodeDetailsDto?
    @State private var isLoading = false
    
    @State private var progressFractionState: Double?
    @State private var isWatchedState: Bool = false
    
    @EnvironmentObject private var viewModel: DetailsViewModel
    @ObservedObject private var downloadManager = DownloadManager.shared
    
    var previewUrl: URL? {
        URL(string: "https://api.neome.uk/api/v1/images/screens/\(movieId)/\(season)/\(episode)/large")
    }
    
    private var progressKey: String {
        "kp_\(movieId)_s\(season)_e\(episode)"
    }
    
    private var isLastPlayed: Bool {
        guard let kpId = viewModel.details?.ids?.kp else { return false }
        let lastSeason = PlaybackProgressStore.shared.loadLastSeason(kpId: kpId)
        let lastEpisode = PlaybackProgressStore.shared.loadLastEpisode(kpId: kpId)
        return lastSeason == season && lastEpisode == episode
    }

    private func updateProgressState() {
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
                } fallback: {
                    ZStack {
                        Color(UIColor.tertiarySystemFill)
                        Image(systemName: "photo")
                            .font(.system(size: 20))
                            .foregroundColor(.secondary)
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
                
                // Progress Bar (Bottom Aligned)
                if let progress = progressFractionState, progress > 0.02 {
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
                
                // Rating overlay on top-left of the card (Unified with design system)
                if let rating = meta?.ratings?.tmdb ?? meta?.ratings?.imdb, rating > 0 {
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
                }
                
                // Watched Checkmark Badge (Top-Right)
                if isWatchedState {
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
                
                // Download Badge (Top-Right, shifted left if watched is present)
                if let kpIdInt = Int(movieId) {
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

                // Last Played Border (Centered, matches size, no clipping)
                if isLastPlayed {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.slooshAccent, lineWidth: 2)
                }
            }
            .frame(width: 160, height: 90)
            .contextMenu {
                Button {
                    onPlayTap()
                } label: {
                    Label("Смотреть", systemImage: "play.fill")
                }
                
                Button {
                    onInfoTap(meta)
                } label: {
                    Label("О серии", systemImage: "info.circle")
                }
                
                Divider()
                
                if isWatchedState {
                    Button(role: .destructive) {
                        PlaybackProgressStore.shared.setWatched(mediaId: progressKey, watched: false)
                        UserDefaults.standard.removeObject(forKey: PlaybackProgressStore.shared.positionKeyPrefix + progressKey)
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
            
            let title = meta?.name ?? fallbackTitle
            let displayTitle = title.hasPrefix("\(episode).") ? title : "\(episode). \(title)"
            
            HStack(alignment: .top, spacing: 4) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(displayTitle)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    if let airDate = meta?.airDate, !airDate.isEmpty {
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
                    onInfoTap(meta)
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

    var allSeasons: [Int] {
        viewModel.inlineSourceWrapper?.allohaResult?.seasons.map { $0.season }.sorted() ?? []
    }
    
    var rawId: String {
        details.ids?.kp?.description ?? details.id?.replacingOccurrences(of: "kp_", with: "") ?? ""
    }

    var episodesForSelectedSeason: [Int] {
        if let season = viewModel.inlineSourceWrapper?.allohaResult?.seasons.first(where: { $0.season == selectedSeason }) {
            return season.episodes.map { $0.episode }.sorted()
        }
        return []
    }

    private func episodesCount(for seasonNum: Int) -> Int {
        viewModel.inlineSourceWrapper?.allohaResult?.seasons.first(where: { $0.season == seasonNum })?.episodes.count ?? 0
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

            if viewModel.isFetchingInlineSeasons {
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
            } else if allSeasons.isEmpty {
                Text("Эпизоды не найдены")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, horizontalPadding)
            } else {
                // Season Picker
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

                // Episodes List
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(episodesForSelectedSeason, id: \.self) { episode in
                                
                                Button(action: {
                                    let generator = UIImpactFeedbackGenerator(style: .medium)
                                    generator.prepare()
                                    generator.impactOccurred()
                                    onEpisodeTap(selectedSeason, episode)
                                }) {
                                    EpisodeCellView(
                                        movieId: rawId,
                                        season: selectedSeason,
                                        episode: episode,
                                        fallbackTitle: "Серия",
                                        onPlayTap: { () -> Void in
                                            onEpisodeTap(selectedSeason, episode)
                                        },
                                        onUpdate: { () -> Void in
                                            updateWatchedSeasons()
                                            redrawTrigger.toggle()
                                        },
                                        onInfoTap: { (fetchedMeta: TvEpisodeDetailsDto?) -> Void in
                                            selectedEpisodeForSheet = EpisodeDetailsSheetItem(
                                                movieId: rawId,
                                                season: selectedSeason,
                                                episode: episode,
                                                meta: fetchedMeta,
                                                fallbackTitle: "Серия"
                                            )
                                        }
                                    )
                                    .environmentObject(viewModel)
                                    .id(redrawTrigger)
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
        }
        .onAppear {
            updateWatchedSeasons()
            guard let kpId = details.ids?.kp else { return }
            let lastSeason = PlaybackProgressStore.shared.loadLastSeason(kpId: kpId)
            if let lastSeason, allSeasons.contains(lastSeason) {
                selectedSeason = lastSeason
            } else if let firstSeason = allSeasons.first {
                selectedSeason = firstSeason
            }
        }
        .onChange(of: allSeasons) { _, newSeasons in
            updateWatchedSeasons()
            if !newSeasons.contains(selectedSeason), let first = newSeasons.first {
                selectedSeason = first
            }
        }
        .sheet(item: $selectedEpisodeForSheet) { item in
            EpisodeDetailsSheet(
                item: item,
                onPlay: { () -> Void in
                    onEpisodeTap(item.season, item.episode)
                },
                onWatchedToggle: { (isWatched: Bool) -> Void in
                    let progressKey = "kp_\(item.movieId)_s\(item.season)_e\(item.episode)"
                    if isWatched {
                        PlaybackProgressStore.shared.markAsWatched(mediaId: progressKey)
                    } else {
                        PlaybackProgressStore.shared.setWatched(mediaId: progressKey, watched: false)
                        UserDefaults.standard.removeObject(forKey: PlaybackProgressStore.shared.positionKeyPrefix + progressKey)
                    }
                    updateWatchedSeasons()
                    redrawTrigger.toggle()
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
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
    @Published var sourceResultWrapper: SourceResultWrapper?

    @Published var inlineSourceWrapper: SourceResultWrapper?
    @Published var selectedInlineSeason: Int = 1
    @Published var isFetchingInlineSeasons = false

    @Published var isFavorite: Bool = false

    private let allohaTranslationPreferenceKey = "alloha_last_translation_name"

    // MARK: - Sources cache (5 min TTL)
    private var sourcesCache: [Int: (wrapper: SourceResultWrapper, expiresAt: Date)] = [:]
    private let sourcesCacheTtl: TimeInterval = 5 * 60

    func resetSourceSheet() {
        sourceResultWrapper = nil
    }

    func saveAllohaTranslation(_ name: String?) {
        guard let name = name, !name.isEmpty else { return }
        UserDefaults.standard.set(name, forKey: allohaTranslationPreferenceKey)
    }

    func loadDetails(id: String, force: Bool = false) async {
        if !force && details != nil && (details?.id == id || details?.ids?.kp?.description == id.replacingOccurrences(of: "kp_", with: "")) {
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            details = try await MoviesRepository.shared.getDetails(id: id)
            if let details {
                PlaybackProgressStore.shared.saveMetadata(details: details)
            }
            checkFavoriteStatus()

            if details?.type == "tv", let kpId = details?.ids?.kp {
                await fetchInlineSeasons(kpId: kpId)
            }
        } catch {
            print("Error loading details: \(error)")
        }
    }

    func fetchInlineSeasons(kpId: Int) async {
        isFetchingInlineSeasons = true
        defer { isFetchingInlineSeasons = false }

        do {
            let result = try await AllohaRepository.shared.fetchByKpId(kpId: kpId)
            if result.isSerial {
                self.inlineSourceWrapper = SourceResultWrapper(allohaResult: result, kpId: kpId)
            }
        } catch {
            print("Error fetching inline seasons: \(error)")
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

        let generator = UINotificationFeedbackGenerator()
        generator.prepare()

        if isFavorite {
            FavoritesRepository.shared.removeFromFavorites(mediaId: mediaId, mediaType: mediaType)
            generator.notificationOccurred(.warning)
            ToastManager.shared.show(title: "Удалено из избранного", icon: "heart.slash.fill", duration: 2.0)
        } else {
            FavoritesRepository.shared.addToFavorites(
                mediaId: mediaId,
                mediaType: mediaType,
                title: details.title ?? details.originalTitle,
                posterUrl: details.poster ?? details.backdrop,
                rating: details.ratings?.kp,
                year: details.year?.description,
                genres: details.genres?.compactMap { GenreDto(id: $0.lowercased(), name: $0) }
            )
            generator.notificationOccurred(.success)
            ToastManager.shared.show(title: "Добавлено в избранное", icon: "heart.fill", duration: 2.0)
        }
        isFavorite.toggle()
    }

    private func favoriteKey(for details: MediaDetailsDto) -> (String, String)? {
        let mediaId = details.ids?.kp?.description ?? details.id
        guard let validId = mediaId, !validId.isEmpty else { return nil }
        let type = (details.type?.lowercased() == "tv" || details.type?.lowercased() == "series") ? "tv" : "movie"
        return (validId.replacingOccurrences(of: "kp_", with: ""), type)
    }

    func fetchSources(kpId: Int, title: String) async {
        // Кэш на 5 минут — повторный тап «Смотреть» возвращает результат мгновенно
        if let cached = sourcesCache[kpId], cached.expiresAt > Date() {
            sourceResultWrapper = cached.wrapper
            return
        }

        sourceResultWrapper = nil
        isFetchingSources = true
        defer { isFetchingSources = false }

        do {
            let result = try await AllohaRepository.shared.fetchByKpId(kpId: kpId)
            let wrapper = SourceResultWrapper(allohaResult: result, kpId: kpId)
            sourcesCache[kpId] = (wrapper: wrapper, expiresAt: Date().addingTimeInterval(sourcesCacheTtl))
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

struct GlassPlayButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.black)
            .background(
                Capsule()
                    .fill(.white.opacity(0.85))
            )
            .glassEffect(in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct GlassDownloadButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .glassEffect(in: Circle())
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
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
