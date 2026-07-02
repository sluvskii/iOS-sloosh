import SwiftUI

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
    @Namespace private var transition
    
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

    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @State private var dominantBackdropColor: UIColor? = nil
    @State private var dominantPosterColor: UIColor? = nil

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
    
    var body: some View {
        ZStack {
            detailsContent
        }
            .optionalMovieNavigationTransition(
                sourceID: navigationTransitionID,
                in: navigationTransitionNamespace
            )
            .environment(\.colorScheme, .dark)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .ignoresSafeArea(edges: verticalSizeClass == .compact ? .all : .top)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(id: "details") {
                ToolbarItem(id: "favorite", placement: .topBarTrailing) {
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
                            .foregroundStyle(.white)
                            .symbolEffect(.bounce, value: favoriteBounce)
                    }
                    .disabled(viewModel.details == nil)
                }
            }
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
                        SourceSelectionView(result: result, kpId: wrapper.kpId) { translation, season, episode, quality in
                            playerKpId = wrapper.kpId
                            playerSeason = season
                            playerEpisode = episode
                            playerQuality = quality
                            playerSeriesResult = result
                            selectedIframeUrl = translation.iframeUrl
                            playerVoiceover = translation.name
                            playerStreamUrl = translation.streamUrl
                            showPlayer = true
                            showSourceSheet = false
                            viewModel.saveAllohaTranslation(translation.name)
                        }
                    } else {
                        SourceSelectionEmptyView(title: sourceSheetTitle)
                    }
                }
                .presentationDetents([.medium, .large], selection: $sourceSheetDetent)
                .navigationTransition(.zoom(sourceID: "playBtn", in: transition))
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
                        PlayerView(iframeUrl: iframeUrl, fallbackTitle: details.title ?? details.name ?? "", kpId: playerKpId, season: playerSeason, episode: playerEpisode, selectedVoiceover: playerVoiceover, directStreamUrl: playerStreamUrl, voices: playerVoices, subtitles: playerSubtitles, initialQuality: playerQuality, seriesResult: playerSeriesResult)
                    } else {
                        Text("Видео не найдено")
                    }
                }
            }
    }

    private func handlePlayAction(details: MediaDetailsDto) {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()

        guard let kpId = details.externalIds?.kp else { return }

        sourceSheetTitle = details.title ?? details.name ?? ""
        sourceSheetDetent = .medium
        viewModel.resetSourceSheet()
        showSourceSheet = true

        sourceFetchTask?.cancel()
        sourceFetchTask = Task {
            await viewModel.fetchSources(kpId: kpId, title: sourceSheetTitle)
        }
    }

    private func handleEpisodeSelection(details: MediaDetailsDto, season: Int, episode: Int) {
        guard let kpId = details.externalIds?.kp else { return }

        PlaybackProgressStore.shared.saveLastPlayed(
            kpId: kpId,
            season: season,
            episode: episode
        )

        sourceSheetTitle = details.title ?? details.name ?? ""
        sourceSheetDetent = .medium
        viewModel.resetSourceSheet()
        showSourceSheet = true

        sourceFetchTask?.cancel()
        sourceFetchTask = Task {
            await viewModel.fetchSources(kpId: kpId, title: sourceSheetTitle)
        }
    }

    private func playButton(for details: MediaDetailsDto) -> some View {
        Button(action: {
            handlePlayAction(details: details)
        }) {
            HStack {
                Image(systemName: "play.fill")
                    .font(.system(size: 18, weight: .black))
                Text("Смотреть")
                    .font(.system(size: 19, weight: .heavy))
            }
            .frame(height: 50)
            .padding(.horizontal, 32)
            .foregroundStyle(Color(UIColor.systemBackground))
        }
        .matchedTransitionSource(id: "playBtn", in: transition) { source in
            source
                .background(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
        }
        .contentShape(Capsule())
        .buttonStyle(.plain)
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

                    VStack(alignment: .center, spacing: 12) {
                        RemoteLogoView(
                            url: URL(string: details.displayLogoUrl ?? ""),
                            fallbackTitle: details.title ?? details.name ?? "Без названия",
                            alignment: .center
                        )
                        .padding(.bottom, 8)

                        if let originalTitle = details.originalTitle, !originalTitle.isEmpty, originalTitle != (details.title ?? details.name) {
                            Text(originalTitle)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                                .padding(.top, -8)
                        }

                        DetailsPrimaryMetadataRow(details: details, alignment: .center)

                        playButton(for: details)
                            .padding(.top, 8)
                            .padding(.bottom, -4)

                        DetailsInfoSection(details: details, backgroundColor: effectiveBackgroundColor)
                            .padding(.top, 20)
                            .padding(.horizontal)

                        if details.type == "tv" {
                            InlineEpisodesSection(viewModel: viewModel, details: details) { season, episode in
                                handleEpisodeSelection(details: details, season: season, episode: episode)
                            }
                            .padding(.top, 24)
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
        .background(effectiveBackgroundColor)
    }

    private var landscapeDetailsContent: some View {
        GeometryReader { geometry in
            ZStack {
                effectiveBackgroundColor.ignoresSafeArea()

                if viewModel.isLoading {
                    LandscapeDetailsSkeletonView()
                        .transition(.opacity)
                } else if let details = viewModel.details {
                    ZStack(alignment: .leading) {
                        // Left Backdrop Image with fade out to the right
                        AsyncCachedImage(url: URL(string: details.displayBackdropUrl ?? ""), fallbackUrl: URL(string: details.displayPosterUrl ?? "")) {
                            Rectangle().fill(Color.gray.opacity(0.2))
                                .shimmer()
                        } content: { image in
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .scaleEffect(1.2)
                                .offset(x: -60)
                        } fallback: {
                            Rectangle().fill(Color.clear)
                        }
                        .frame(width: geometry.size.width * 0.50, height: geometry.size.height)
                        .clipped()
                        .mask(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    .black,
                                    .black.opacity(0.85),
                                    .black.opacity(0.55),
                                    .black.opacity(0.2),
                                    .clear
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .ignoresSafeArea()

                        // Right Column: Details Content
                        HStack(spacing: 0) {
                            Spacer()
                                .frame(width: geometry.size.width * 0.32)

                            ScrollView {
                                VStack(alignment: .leading, spacing: 16) {
                                    RemoteLogoView(
                                        url: URL(string: details.displayLogoUrl ?? ""),
                                        fallbackTitle: details.title ?? details.name ?? "Без названия",
                                        alignment: .leading
                                    )
                                    .padding(.top, geometry.safeAreaInsets.top + 68)
                                    .padding(.trailing, 24 + geometry.safeAreaInsets.trailing)

                                    if let originalTitle = details.originalTitle, !originalTitle.isEmpty, originalTitle != (details.title ?? details.name) {
                                        Text(originalTitle)
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(.secondary)
                                            .padding(.trailing, 24 + geometry.safeAreaInsets.trailing)
                                    }

                                    DetailsPrimaryMetadataRow(details: details, alignment: .leading)
                                        .padding(.trailing, 24 + geometry.safeAreaInsets.trailing)

                                    playButton(for: details)
                                        .padding(.top, 8)
                                        .padding(.trailing, 24 + geometry.safeAreaInsets.trailing)

                                    DetailsInfoSection(details: details, backgroundColor: .clear)
                                        .padding(.top, 8)
                                        .padding(.trailing, 24 + geometry.safeAreaInsets.trailing)

                                    if details.type == "tv" {
                                        InlineEpisodesSection(viewModel: viewModel, details: details) { season, episode in
                                            handleEpisodeSelection(details: details, season: season, episode: episode)
                                        }
                                        .padding(.top, 16)
                                        .padding(.bottom, 24)
                                    }
                                }
                                .padding(.bottom, 24 + geometry.safeAreaInsets.bottom)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .scrollIndicators(.hidden)
                            .frame(width: geometry.size.width * 0.68)
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
                    .transition(.opacity)
                } else {
                    Text("Не удалось загрузить данные.")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.35), value: viewModel.isLoading)
        }
        .ignoresSafeArea()
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
        let baseHeight: CGFloat = verticalSizeClass == .compact ? 250 : 450
        
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
            .offset(y: -80)
        }
    }
}

private struct LandscapeDetailsSkeletonView: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Left Column / Backdrop skeleton
                Rectangle()
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: geometry.size.width * 0.50, height: geometry.size.height)
                    .mask(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                .black,
                                .black.opacity(0.8),
                                .black.opacity(0.4),
                                .black.opacity(0.1),
                                .clear
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .shimmer()
                
                // Right Column skeleton
                HStack(spacing: 0) {
                    Spacer()
                        .frame(width: geometry.size.width * 0.32)
                    
                    VStack(alignment: .leading, spacing: 16) {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 240, height: 40)
                            .cornerRadius(8)
                            .shimmer()
                        
                        HStack(spacing: 16) {
                            ForEach(0..<4) { _ in
                                Rectangle()
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(width: 40, height: 16)
                                    .cornerRadius(4)
                            }
                        }
                        .shimmer()
                        
                        Capsule()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 180, height: 50)
                            .shimmer()
                            .padding(.top, 8)
                        
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
                        .padding(.top, 16)
                        
                        VStack(alignment: .leading, spacing: 10) {
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 100, height: 20)
                                .cornerRadius(4)
                            
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(0..<4) { _ in
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(height: 16)
                                        .cornerRadius(4)
                                }
                            }
                        }
                        .shimmer()
                        .padding(.top, 16)
                    }
                    .padding(.top, geometry.safeAreaInsets.top + 68)
                    .padding(.bottom, 24 + geometry.safeAreaInsets.bottom)
                    .padding(.trailing, geometry.safeAreaInsets.trailing + 24)
                    .frame(width: geometry.size.width * 0.68, alignment: .leading)
                }
            }
        }
        .ignoresSafeArea()
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
            if let rating = details.rating, rating > 0 {
                Label(String(format: "%.1f", rating), systemImage: "star.fill")
                    .foregroundColor(.rating(rating))
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
        .multilineTextAlignment(alignment == .leading ? .leading : .center)
        .padding(.horizontal, alignment == .center ? 16 : 0)
        .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
    }
}

private struct DetailsInfoSection: View {
    let details: MediaDetailsDto
    let backgroundColor: Color
    @State private var isDescriptionExpanded = false

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

            if let description = details.description, !description.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Описание")
                        .font(.system(size: 18, weight: .bold))

                    ZStack(alignment: .bottom) {
                        Text(description)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(.secondary)
                            .lineSpacing(4)
                            .lineLimit(isDescriptionExpanded ? nil : 4)
                            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isDescriptionExpanded)

                        if !isDescriptionExpanded {
                            LinearGradient(
                                gradient: Gradient(colors: [.clear, backgroundColor]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 40)
                            .allowsHitTesting(false)
                        }
                    }

                    Button(action: {
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.prepare()
                        generator.impactOccurred()
                        withAnimation {
                            isDescriptionExpanded.toggle()
                        }
                    }) {
                        Text(isDescriptionExpanded ? "Свернуть" : "Читать далее...")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Color.slooshAccent)
                    }
                }
            }
        }
    }
}

struct EpisodeCellView: View {
    let movieId: String
    let season: Int
    let episode: Int
    let fallbackTitle: String
    
    @State private var meta: TvEpisodeDetailsDto?
    @State private var isLoading = false
    
    @EnvironmentObject private var viewModel: DetailsViewModel
    
    var previewUrl: URL? {
        URL(string: "https://api.neome.uk/api/v1/images/screens/\(movieId)/\(season)/\(episode)/large")
    }
    

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                Rectangle()
                    .fill(Color(UIColor.tertiarySystemFill))
                    .frame(width: 150, height: 85)
                    .cornerRadius(12)
                
                AsyncCachedImage(url: previewUrl) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 150, height: 85)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shimmer()
                } content: { image in
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 150, height: 85)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } fallback: {
                    Image(systemName: "photo")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)
                        .frame(width: 150, height: 85)
                        .background(Color(UIColor.tertiarySystemFill))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .animation(.easeInOut(duration: 0.3), value: previewUrl)
                
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.white.opacity(0.8))
                    .shadow(radius: 2)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                if isLoading {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 100, height: 16)
                        .cornerRadius(4)
                        .shimmer()
                    
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 60, height: 14)
                        .cornerRadius(4)
                        .shimmer()
                } else {
                    let title = meta?.name ?? fallbackTitle
                    let displayTitle = title.hasPrefix("\(episode).") ? title : "\(episode). \(title)"
                    Text(displayTitle)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .frame(width: 150, alignment: .leading)
                    
                    if let rating = meta?.ratings?.tmdb, rating > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.rating(rating))
                            Text(String(format: "%.1f", rating))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.rating(rating))
                        }
                    } else if let rating = meta?.ratings?.imdb, rating > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.rating(rating))
                            Text(String(format: "%.1f", rating))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.rating(rating))
                        }
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isLoading)
        .task(id: "\(season)-\(episode)") {
            if isLoading { return }
            isLoading = true
            meta = nil
            do {
                // Пытаемся получить данные по ID (внутреннему) или по SourceId
                var fetchedMeta: TvEpisodeDetailsDto? = nil
                let candidateIds = [movieId, viewModel.details?.sourceId].compactMap { $0 }.filter { !$0.isEmpty }
                
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
                    // Fallback to basic fetch if loop failed to find useful data
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
    let onEpisodeTap: (Int, Int) -> Void

    @State private var selectedSeason: Int = 1

    var allSeasons: [Int] {
        viewModel.inlineSourceWrapper?.allohaResult?.seasons.map { $0.season }.sorted() ?? []
    }

    var episodesForSelectedSeason: [Int] {
        if let season = viewModel.inlineSourceWrapper?.allohaResult?.seasons.first(where: { $0.season == selectedSeason }) {
            return season.episodes.map { $0.episode }.sorted()
        }
        return []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Сезоны и серии")
                .font(.system(size: 18, weight: .bold))
                .padding(.horizontal)

            if viewModel.isFetchingInlineSeasons {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(0..<4) { _ in
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 140, height: 80)
                                .shimmer()
                        }
                    }
                    .padding(.horizontal)
                }
            } else if allSeasons.isEmpty {
                Text("Эпизоды не найдены")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            } else {
                // Season Picker
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(allSeasons, id: \.self) { season in
                            Button(action: {
                                let generator = UIImpactFeedbackGenerator(style: .light)
                                generator.prepare()
                                generator.impactOccurred()
                                selectedSeason = season
                            }) {
                                Text("\(season) сезон")
                                    .font(.system(size: 15, weight: .semibold))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(selectedSeason == season ? Color.primary : Color(UIColor.secondarySystemFill))
                                    .foregroundColor(selectedSeason == season ? Color(UIColor.systemBackground) : .primary)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                // Episodes List
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(episodesForSelectedSeason, id: \.self) { episode in
                            Button(action: {
                                let generator = UIImpactFeedbackGenerator(style: .medium)
                                generator.prepare()
                                generator.impactOccurred()
                                onEpisodeTap(selectedSeason, episode)
                            }) {
                                let rawId = details.externalIds?.kp?.description ?? details.id?.replacingOccurrences(of: "kp_", with: "") ?? ""
                                EpisodeCellView(movieId: rawId, season: selectedSeason, episode: episode, fallbackTitle: "Серия")
                                    .environmentObject(viewModel)
                            }
                            .buttonStyle(.plain)
                            .id("\(selectedSeason)-\(episode)")
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .onAppear {
            if let firstSeason = allSeasons.first {
                selectedSeason = firstSeason
            }
        }
        .onChange(of: allSeasons) { _, newSeasons in
            if !newSeasons.contains(selectedSeason), let first = newSeasons.first {
                selectedSeason = first
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

    func loadDetails(id: String) async {
        if details != nil && (details?.id == id || details?.sourceId == id || details?.externalIds?.kp?.description == id.replacingOccurrences(of: "kp_", with: "")) {
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

            if details?.type == "tv", let kpId = details?.externalIds?.kp {
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

        if isFavorite {
            FavoritesRepository.shared.removeFromFavorites(mediaId: mediaId, mediaType: mediaType)
        } else {
            let year = details.releaseDate.map { String($0.prefix(4)) }
            FavoritesRepository.shared.addToFavorites(
                mediaId: mediaId,
                mediaType: mediaType,
                title: details.title ?? details.name,
                posterUrl: details.posterUrl ?? details.backdropUrl,
                rating: details.rating,
                year: year,
                genres: details.genres
            )
        }
        isFavorite.toggle()
    }

    private func favoriteKey(for details: MediaDetailsDto) -> (String, String)? {
        let mediaId = details.externalIds?.kp?.description ?? details.id ?? details.sourceId
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
