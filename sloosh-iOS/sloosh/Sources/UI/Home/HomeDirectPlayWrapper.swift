import SwiftUI

struct PlayerConfig: Identifiable {
    let id = UUID()
    let iframeUrl: String?
    let title: String
    let kpId: Int?
    let season: Int?
    let episode: Int?
    let voiceover: String?
    let streamUrl: String?
    let voices: [String]
    let subtitles: [PlaybackSubtitle]
    let quality: VideoQualityPreference?
    let seriesResult: AllohaApiResult?
    let mediaKey: String?
    let tmdbId: Int?
    let posterUrl: String?
    let backdropUrl: String?
    let logoUrl: String?

    init(
        iframeUrl: String?,
        title: String,
        kpId: Int?,
        season: Int?,
        episode: Int?,
        voiceover: String?,
        streamUrl: String?,
        voices: [String],
        subtitles: [PlaybackSubtitle],
        quality: VideoQualityPreference?,
        seriesResult: AllohaApiResult?,
        mediaKey: String? = nil,
        tmdbId: Int? = nil,
        posterUrl: String? = nil,
        backdropUrl: String? = nil,
        logoUrl: String? = nil
    ) {
        self.iframeUrl = iframeUrl
        self.title = title
        self.kpId = kpId
        self.season = season
        self.episode = episode
        self.voiceover = voiceover
        self.streamUrl = streamUrl
        self.voices = voices
        self.subtitles = subtitles
        self.quality = quality
        self.seriesResult = seriesResult
        self.mediaKey = mediaKey
        self.tmdbId = tmdbId
        self.posterUrl = posterUrl
        self.backdropUrl = backdropUrl
        self.logoUrl = logoUrl
    }
}

struct HomeDirectPlayWrapper: View {
    let movieId: String
    var mediaType: String? = nil
    let fallbackTitle: String
    var initialKpId: Int? = nil
    let onPlay: (PlayerConfig) -> Void
    
    @StateObject private var viewModel = DetailsViewModel()
    @State private var fetchAttempted = false
    
    var body: some View {
        ZStack {
            if !fetchAttempted || viewModel.isFetchingSources || viewModel.isLoading {
                SourceSelectionLoadingView(title: viewModel.details?.title ?? fallbackTitle)
                    .transition(.opacity)
            } else if let wrapper = viewModel.sourceResultWrapper,
                      let result = wrapper.allohaResult {
                SourceSelectionView(mode: .play, result: result, kpId: wrapper.kpId, details: viewModel.details) { translation, season, episode, quality in
                    let tmdb = viewModel.details?.externalIds?.tmdb ?? viewModel.details?.ids?.tmdb ?? Int(viewModel.details?.id ?? "")
                    let kp = (wrapper.kpId ?? 0) > 0 ? wrapper.kpId! : (viewModel.details?.ids?.kp ?? 0)
                    let resolvedKey = kp > 0 ? "kp_\(kp)" : (viewModel.details?.id ?? "tmdb_\(tmdb ?? 0)")
                    let config = PlayerConfig(
                        iframeUrl: translation.iframeUrl,
                        title: viewModel.details?.title ?? fallbackTitle,
                        kpId: wrapper.kpId,
                        season: season,
                        episode: episode,
                        voiceover: translation.name,
                        streamUrl: translation.streamUrl,
                        voices: result.allTranslationNames,
                        subtitles: [],
                        quality: quality,
                        seriesResult: result,
                        mediaKey: resolvedKey,
                        tmdbId: tmdb,
                        posterUrl: viewModel.details?.displayPosterUrl,
                        backdropUrl: viewModel.details?.displayBackdropUrl ?? viewModel.details?.displayPosterUrl,
                        logoUrl: viewModel.details?.displayLogoUrl
                    )
                    onPlay(config)
                }
                .transition(.opacity)
            } else {
                SourceSelectionEmptyView(title: viewModel.details?.title ?? fallbackTitle)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.isFetchingSources)
        .animation(.easeInOut(duration: 0.3), value: viewModel.isLoading)
        .animation(.easeInOut(duration: 0.3), value: fetchAttempted)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            if let initialKpId = initialKpId, initialKpId > 0 {
                await viewModel.fetchSources(kpId: initialKpId, title: fallbackTitle)
            } else {
                await viewModel.loadDetails(id: movieId, type: mediaType)
                let resolvedKpId = viewModel.details?.ids?.kp ?? viewModel.details?.externalIds?.kp ?? (movieId.hasPrefix("kp_") ? Int(movieId.replacingOccurrences(of: "kp_", with: "")) : nil) ?? 0
                let resolvedTmdbId = viewModel.details?.externalIds?.tmdb ?? viewModel.details?.ids?.tmdb ?? (movieId.hasPrefix("tmdb_") ? Int(movieId.replacingOccurrences(of: "tmdb_", with: "")) : Int(movieId))
                let resolvedTitle = viewModel.details?.title ?? fallbackTitle
                await viewModel.fetchSources(
                    kpId: resolvedKpId,
                    tmdbId: resolvedTmdbId,
                    title: resolvedTitle
                )
            }
            fetchAttempted = true
        }
    }
}
