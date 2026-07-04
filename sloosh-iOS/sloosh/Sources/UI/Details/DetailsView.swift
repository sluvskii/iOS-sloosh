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
            .ignoresSafeArea(edges: .top)
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
        }
        .buttonStyle(GlassPlayButtonStyle())
        .matchedTransitionSource(id: "playBtn", in: transition) { source in
            source
                .background(.clear)
                .clipShape(RoundedRectangle(cornerRadius: 25))
        }
        .contentShape(Capsule())
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
                                .padding(.top, 24)
                            }
                        }
                        .offset(y: -60)
                        .padding(.bottom, 24)
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .background(effectiveBackgroundColor)
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
    @State private var canExpand = false
    @State private var fullHeight: CGFloat = 0
    @State private var visibleHeight: CGFloat = 0

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

                        if canExpand && !isDescriptionExpanded {
                            LinearGradient(
                                gradient: Gradient(colors: [backgroundColor.opacity(0), backgroundColor]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 40)
                            .allowsHitTesting(false)
                        }
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

struct EpisodeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
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
    
    var body: some View {
        VStack(spacing: 0) {
            // Still Image
            ZStack(alignment: .topTrailing) {
                let previewUrl = URL(string: "https://api.neome.uk/api/v1/images/screens/\(item.movieId)/\(item.season)/\(item.episode)/large")
                
                AsyncCachedImage(url: previewUrl) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.15))
                        .aspectRatio(16/9, contentMode: .fit)
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
                    .aspectRatio(16/9, contentMode: .fit)
                }
                
                // Dismiss button
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.white.opacity(0.7))
                        .background(Circle().fill(.black.opacity(0.2)))
                }
                .padding(16)
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(16/9, contentMode: .fit)
            .clipped()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Season/Episode and Title
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(item.season) сезон, \(item.episode) серия")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Color.slooshAccent)
                            .textCase(.uppercase)
                        
                        let title = item.meta?.name ?? item.fallbackTitle
                        Text(title)
                            .font(.system(size: 24, weight: .heavy))
                            .foregroundColor(.primary)
                    }
                    
                    // Metadata: Rating & Date
                    HStack(spacing: 12) {
                        if let rating = item.meta?.ratings?.tmdb ?? item.meta?.ratings?.imdb, rating > 0 {
                            Label(String(format: "%.1f", rating), systemImage: "star.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.rating(rating))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.rating(rating).opacity(0.1))
                                .cornerRadius(6)
                        }
                        
                        if let airDate = item.meta?.airDate, !airDate.isEmpty {
                            Text(formatAirDate(airDate))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Divider()
                        .padding(.vertical, 4)
                    
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
                }
                .padding(24)
            }
            
            // Bottom Buttons
            VStack(spacing: 12) {
                // Play Button
                Button {
                    dismiss()
                    onPlay()
                } label: {
                    HStack {
                        Image(systemName: "play.fill")
                            .font(.system(size: 16, weight: .bold))
                        Text("Смотреть серию")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.slooshAccent)
                    .foregroundColor(.black)
                    .cornerRadius(25)
                }
                .buttonStyle(.plain)
                
                // Mark as Watched Toggle Button
                Button {
                    isWatched.toggle()
                    onWatchedToggle(isWatched)
                } label: {
                    HStack {
                        Image(systemName: isWatched ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 16))
                        Text(isWatched ? "Просмотрено" : "Отметить как просмотренное")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color(UIColor.secondarySystemBackground))
                    .foregroundColor(.primary)
                    .cornerRadius(22)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 34)
            .padding(.top, 12)
            .background(Color(UIColor.systemBackground))
        }
        .background(Color(UIColor.systemBackground))
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
    
    var previewUrl: URL? {
        URL(string: "https://api.neome.uk/api/v1/images/screens/\(movieId)/\(season)/\(episode)/large")
    }
    
    private var progressKey: String {
        "kp_\(movieId)_s\(season)_e\(episode)"
    }
    
    private var isLastPlayed: Bool {
        guard let kpId = viewModel.details?.externalIds?.kp else { return false }
        let lastSeason = PlaybackProgressStore.shared.loadLastSeason(kpId: kpId)
        let lastEpisode = PlaybackProgressStore.shared.loadLastEpisode(kpId: kpId)
        return lastSeason == season && lastEpisode == episode
    }

    private func updateProgressState() {
        progressFractionState = PlaybackProgressStore.shared.normalizedProgress(mediaId: progressKey)
        isWatchedState = PlaybackProgressStore.shared.loadWatched(mediaId: progressKey) || (progressFractionState ?? 0) >= 0.9
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottom) {
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
                LinearGradient(
                    gradient: Gradient(colors: [.clear, .black.opacity(0.35)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
                // Play Overlay
                Image(systemName: "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .padding(10)
                    .background(.black.opacity(0.45))
                    .clipShape(Circle())
                    .shadow(radius: 4)
                    .opacity(isLastPlayed ? 1.0 : 0.75)
                
                // Progress Bar
                if let progress = progressFractionState, progress > 0.02 {
                    VStack(spacing: 0) {
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
                
                // Watched Checkmark Badge (top-right)
                if isWatchedState {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(Color.slooshAccent)
                                .padding(4)
                                .background(.black.opacity(0.6))
                                .clipShape(Circle())
                                .padding([.top, .trailing], 6)
                        }
                        Spacer()
                    }
                    .frame(width: 160, height: 90)
                }

                // Last Played Border
                if isLastPlayed {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.slooshAccent, lineWidth: 2)
                        .frame(width: 160, height: 90)
                }
            }
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
                        .foregroundColor(isLastPlayed ? Color.slooshAccent : .primary)
                        .lineLimit(1)
                    
                    HStack(spacing: 8) {
                        if let rating = meta?.ratings?.tmdb ?? meta?.ratings?.imdb, rating > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(.rating(rating))
                                Text(String(format: "%.1f", rating))
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.rating(rating))
                            }
                        }
                        
                        if let airDate = meta?.airDate, !airDate.isEmpty {
                            let year = airDate.prefix(4)
                            Text(year)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                        }
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
                        .padding(.vertical, 2)
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
        let rawId = details.externalIds?.kp?.description ?? details.id?.replacingOccurrences(of: "kp_", with: "") ?? ""
        
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
        VStack(alignment: .leading, spacing: 16) {
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
                    HStack(spacing: 12) {
                        ForEach(allSeasons, id: \.self) { season in
                            Button(action: {
                                let generator = UIImpactFeedbackGenerator(style: .light)
                                generator.prepare()
                                generator.impactOccurred()
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedSeason = season
                                }
                            }) {
                                VStack(spacing: 2) {
                                    HStack(spacing: 4) {
                                        Text("\(season) сезон")
                                            .font(.system(size: 14, weight: .bold))
                                        if fullyWatchedSeasons.contains(season) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(selectedSeason == season ? .black : Color.slooshAccent)
                                                .font(.system(size: 11, weight: .bold))
                                        }
                                    }
                                    
                                    let count = episodesCount(for: season)
                                    if count > 0 {
                                        Text("\(count) сер.")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor(selectedSeason == season ? .black.opacity(0.6) : .secondary)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(selectedSeason == season ? Color.white : Color.white.opacity(0.06))
                                )
                                .foregroundColor(selectedSeason == season ? .black : .primary)
                                .scaleEffect(selectedSeason == season ? 1.04 : 1.0)
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
                                let rawId = details.externalIds?.kp?.description ?? details.id?.replacingOccurrences(of: "kp_", with: "") ?? ""
                                
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
                                        onPlayTap: {
                                            onEpisodeTap(selectedSeason, episode)
                                        },
                                        onUpdate: {
                                            updateWatchedSeasons()
                                            redrawTrigger.toggle()
                                        },
                                        onInfoTap: { fetchedMeta in
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
                                .buttonStyle(EpisodeButtonStyle())
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
            guard let kpId = details.externalIds?.kp else { return }
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
                onPlay: {
                    onEpisodeTap(item.season, item.episode)
                },
                onWatchedToggle: { isWatched in
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
        guard let kpId = details.externalIds?.kp else { return }
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
