import SwiftUI

struct RemoteBackdropView: View {
    let url: URL?
    let fallbackUrl: URL?
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
            
            var fetchedImage: UIImage? = nil
            do {
                let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)
                let (data, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200, let uiImg = UIImage(data: data) {
                    fetchedImage = uiImg
                }
            } catch {}
            
            if fetchedImage == nil, let fallback = fallbackUrl {
                do {
                    let request = URLRequest(url: fallback, cachePolicy: .returnCacheDataElseLoad)
                    let (data, response) = try await URLSession.shared.data(for: request)
                    if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200, let uiImg = UIImage(data: data) {
                        fetchedImage = uiImg
                    }
                } catch {}
            }
            
            if let fetchedImage = fetchedImage {
                self.image = fetchedImage
            }
            
            isLoading = false
        }
    }
}

struct RemoteLogoView: View {
    let url: URL?
    let fallbackTitle: String
    
    @State private var image: UIImage?
    @State private var isLoading = false
    @State private var hasError = false
    
    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 280, maxHeight: 110)
                    .padding(.horizontal)
            } else if isLoading {
                Rectangle().fill(Color.gray.opacity(0.2))
                    .frame(width: 200, height: 60)
                    .cornerRadius(8)
                    .shimmer()
                    .padding(.horizontal)
            } else {
                Text(fallbackTitle)
                    .font(.system(size: 34, weight: .heavy))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .task(id: url) {
            guard let url = url, image == nil else {
                if url == nil {
                    hasError = true
                    isLoading = false
                }
                return
            }
            isLoading = true
            hasError = false
            do {
                let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)
                let (data, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200, let uiImg = UIImage(data: data) {
                    self.image = uiImg
                } else {
                    self.hasError = true
                }
            } catch {
                self.hasError = true
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
    
    @State private var playerKpId: Int?
    @State private var playerSeason: Int?
    @State private var playerEpisode: Int?
    @State private var playerVoiceover: String?
    @State private var playerVoices: [String] = []
    @State private var playerSubtitles: [CollapsSubtitle] = []
    @State private var playerQuality: VideoQualityPreference? = nil
    
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
                            url: URL(string: details.displayBackdropUrl ?? ""),
                            fallbackUrl: URL(string: details.displayPosterUrl ?? ""),
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
                        RemoteLogoView(
                            url: URL(string: details.displayLogoUrl ?? ""),
                            fallbackTitle: details.title ?? details.name ?? "Без названия"
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

                        DetailsPrimaryMetadataRow(details: details)
                        
                        // Play Button
                        Button(action: {
                            let generator = UIImpactFeedbackGenerator(style: .medium)
                            generator.prepare()
                            generator.impactOccurred()
                            
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
                        .padding(.top, 8)
                        .padding(.bottom, -4)

                        DetailsInfoSection(details: details)
                            .padding(.top, 20)
                            .padding(.horizontal)

                        if details.type == "tv" {
                            InlineEpisodesSection(viewModel: viewModel, details: details) { season, episode in
                                guard let kpId = details.externalIds?.kp else { return }
                                
                                // To handle pre-selection, we can use a new state property in DetailsView or just save to progress store
                                // CollapsPlaybackProgressStore reads from store when opened, so let's temporarily save it there to auto-select
                                CollapsPlaybackProgressStore.shared.saveLastPlayed(
                                    kpId: kpId,
                                    season: season,
                                    episode: episode,
                                    voiceover: nil,
                                    source: "collaps" // This affects initial selection in SourceSelection as well, if we use the same store
                                )
                                
                                sourceSheetMode = SourceManager.shared.currentMode
                                sourceSheetTitle = details.title ?? details.name ?? ""
                                sourceSheetDetent = .medium
                                viewModel.resetSourceSheet()
                                showSourceSheet = true
                                
                                sourceFetchTask?.cancel()
                                sourceFetchTask = Task {
                                    await viewModel.fetchSources(kpId: kpId, title: sourceSheetTitle)
                                }
                            }
                            .padding(.top, 24)
                            .padding(.bottom, 20)
                        }
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
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(id: "details") {
            ToolbarItem(id: "favorite", placement: .topBarTrailing) {
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.prepare()
                    generator.impactOccurred()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.5, blendDuration: 0.5)) {
                        viewModel.toggleFavorite()
                    }
                } label: {
                    Image(systemName: viewModel.isFavorite ? "heart.fill" : "heart")
                        .foregroundColor(viewModel.isFavorite ? .red : .primary)
                        .scaleEffect(viewModel.isFavorite ? 1.15 : 1.0)
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
                    SourceSelectionView(result: result, kpId: wrapper.kpId) { translation, season, episode, quality in
                        playerKpId = wrapper.kpId
                        playerSeason = season
                        playerEpisode = episode
                        playerVoiceover = translation.name
                        playerVoices = [translation.name]
                        playerSubtitles = []
                        playerQuality = quality
                        selectedIframeUrl = translation.iframeUrl
                        showPlayer = true
                        showSourceSheet = false
                    }
                } else if let wrapper = viewModel.sourceResultWrapper, wrapper.mode == .collaps {
                    let isSerial = wrapper.collapsSeasons != nil && !(wrapper.collapsSeasons?.isEmpty ?? true)
                    CollapsSelectionView(
                        result: wrapper.collapsSeasons ?? [],
                        movieResult: wrapper.collapsMovie,
                        kpId: wrapper.kpId,
                        isSerial: isSerial,
                        title: viewModel.details?.title ?? viewModel.details?.name ?? "",
                        onPlay: { url, season, episode, voiceover, voices, subtitles, quality in
                            // Collaps returns direct HLS/MPD urls
                            selectedIframeUrl = url // we use this state variable for the URL
                            playerKpId = wrapper.kpId
                            playerSeason = season
                            playerEpisode = episode
                            playerVoiceover = voiceover
                            playerVoices = voices
                            playerSubtitles = subtitles
                            playerQuality = quality
                            showPlayer = true
                            showSourceSheet = false
                        }
                    )
                } else {
                    SourceSelectionEmptyView(title: sourceSheetTitle)
                }
            }
            .presentationDetents([.medium, .large], selection: $sourceSheetDetent)
            .navigationTransition(.zoom(sourceID: "playBtn", in: transition))
        }
        .fullScreenCover(isPresented: $showPlayer, onDismiss: {
            selectedIframeUrl = nil
            selectedDirectVideoUrl = nil
            playerKpId = nil
            playerSeason = nil
            playerEpisode = nil
            playerVoiceover = nil
            playerVoices = []
            playerSubtitles = []
            playerQuality = nil
        }) {
            if let details = viewModel.details {
                let mode = SourceManager.shared.currentMode
                if mode == .alloha {
                    if let iframeUrl = selectedIframeUrl {
                        PlayerView(iframeUrl: iframeUrl, fallbackTitle: details.title ?? details.name ?? "", kpId: playerKpId, season: playerSeason, episode: playerEpisode, selectedVoiceover: playerVoiceover, voices: playerVoices, subtitles: playerSubtitles, initialQuality: playerQuality)
                    } else {
                        Text("Видео не найдено")
                    }
                } else {
                    if let directUrl = selectedIframeUrl ?? selectedDirectVideoUrl {
                        PlayerView(directVideoUrl: directUrl, fallbackTitle: details.title ?? details.name ?? "", kpId: playerKpId, season: playerSeason, episode: playerEpisode, selectedVoiceover: playerVoiceover, voices: playerVoices, subtitles: playerSubtitles, initialQuality: playerQuality)
                    } else {
                        Text("Видео не найдено")
                    }
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
                    .tint(.primary)
                    .buttonStyle(.plain)
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
                                gradient: Gradient(colors: [.clear, Color(UIColor.systemBackground)]),
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

struct InlineEpisodesSection: View {
    @ObservedObject var viewModel: DetailsViewModel
    let details: MediaDetailsDto
    let onEpisodeTap: (Int, Int) -> Void

    @State private var selectedSeason: Int = 1

    var allSeasons: [Int] {
        if let wrapper = viewModel.inlineSourceWrapper {
            if wrapper.mode == .collaps, let collapsSeasons = wrapper.collapsSeasons {
                return collapsSeasons.map { $0.season }.sorted()
            } else if wrapper.mode == .alloha, let allohaResult = wrapper.allohaResult {
                return allohaResult.seasons.map { $0.season }.sorted()
            }
        }
        return []
    }

    var episodesForSelectedSeason: [Int] {
        if let wrapper = viewModel.inlineSourceWrapper {
            if wrapper.mode == .collaps, let collapsSeasons = wrapper.collapsSeasons {
                if let season = collapsSeasons.first(where: { $0.season == selectedSeason }) {
                    return season.episodes.map { $0.episode }.sorted()
                }
            } else if wrapper.mode == .alloha, let allohaResult = wrapper.allohaResult {
                if let season = allohaResult.seasons.first(where: { $0.season == selectedSeason }) {
                    return season.episodes.map { $0.episode }.sorted()
                }
            }
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
                                withAnimation {
                                    selectedSeason = season
                                }
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
                                VStack(alignment: .leading, spacing: 8) {
                                    ZStack {
                                        Rectangle()
                                            .fill(Color(UIColor.tertiarySystemFill))
                                            .frame(width: 150, height: 85)
                                            .cornerRadius(12)
                                        
                                        Image(systemName: "play.circle.fill")
                                            .font(.system(size: 32))
                                            .foregroundColor(.white.opacity(0.8))
                                    }
                                    
                                    Text("\(episode) серия")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundColor(.primary)
                                }
                            }
                            .buttonStyle(.plain)
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
    let mode: SourceMode
    var allohaResult: AllohaApiResult?
    var collapsSeasons: [CollapsSeason]?
    var collapsMovie: CollapsMovie?
    var kpId: Int?
}

@MainActor
class DetailsViewModel: ObservableObject {
    @Published var details: MediaDetailsDto?
    @Published var isLoading = true
    
    @Published var isFetchingSources = false
    @Published var sourceResultWrapper: SourceResultWrapper?
    
    @Published var inlineSeasons: [CollapsSeason]? // Or AllohaSeason mapped to a common model? Let's use SourceResultWrapper for inline too.
    @Published var inlineSourceWrapper: SourceResultWrapper?
    @Published var selectedInlineSeason: Int = 1
    @Published var isFetchingInlineSeasons = false
    
    @Published var isFavorite: Bool = false

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
        
        let mode = SourceManager.shared.currentMode
        do {
            switch mode {
            case .alloha:
                let result = try await AllohaRepository.shared.fetchByKpId(kpId: kpId)
                if result.isSerial {
                    self.inlineSourceWrapper = SourceResultWrapper(mode: .alloha, allohaResult: result, kpId: kpId)
                }
            case .collaps:
                let seasons = try await CollapsRepository.shared.getSeasonsByKpId(kpId: kpId)
                if !seasons.isEmpty {
                    self.inlineSourceWrapper = SourceResultWrapper(mode: .collaps, collapsSeasons: seasons, kpId: kpId)
                }
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
                self.sourceResultWrapper = SourceResultWrapper(mode: .alloha, allohaResult: result, kpId: kpId)
            case .collaps:
                let seasons = try await CollapsRepository.shared.getSeasonsByKpId(kpId: kpId)
                if seasons.isEmpty {
                    let movie = try await CollapsRepository.shared.getMovieByKpId(kpId: kpId)
                    self.sourceResultWrapper = SourceResultWrapper(mode: .collaps, collapsMovie: movie, kpId: kpId)
                } else {
                    self.sourceResultWrapper = SourceResultWrapper(mode: .collaps, collapsSeasons: seasons, kpId: kpId)
                }
            }
        } catch {
            print("Error fetching sources: \(error)")
        }
    }
}
