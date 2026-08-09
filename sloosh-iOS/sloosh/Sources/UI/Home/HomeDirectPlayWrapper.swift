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
}

struct HomeDirectPlayWrapper: View {
    let movieId: String
    let fallbackTitle: String
    var initialKpId: Int? = nil
    
    @StateObject private var viewModel = DetailsViewModel()
    @State private var fetchAttempted = false
    @State private var playerConfig: PlayerConfig? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            if !fetchAttempted || viewModel.isFetchingSources || viewModel.isLoading {
                SourceSelectionLoadingView(title: viewModel.details?.title ?? fallbackTitle)
                    .transition(.opacity)
            } else if let wrapper = viewModel.sourceResultWrapper,
                      let result = wrapper.allohaResult {
                SourceSelectionView(mode: .play, result: result, kpId: wrapper.kpId, details: viewModel.details) { translation, season, episode, quality in
                    guard playerConfig == nil else { return }
                    playerConfig = PlayerConfig(
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
                        seriesResult: result
                    )
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
        .fullScreenCover(item: $playerConfig, onDismiss: {
            playerConfig = nil
            dismiss()
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
            if let initialKpId = initialKpId, initialKpId > 0 {
                await viewModel.fetchSources(kpId: initialKpId, title: fallbackTitle)
            } else {
                await viewModel.loadDetails(id: movieId)
                if let kpId = viewModel.details?.ids?.kp {
                    await viewModel.fetchSources(kpId: kpId, title: viewModel.details?.title ?? fallbackTitle)
                } else if let numericKp = Int(movieId.replacingOccurrences(of: "kp_", with: "")) {
                    await viewModel.fetchSources(kpId: numericKp, title: fallbackTitle)
                }
            }
            fetchAttempted = true
        }
    }
}
