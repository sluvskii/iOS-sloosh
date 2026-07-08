import SwiftUI

struct PlayerConfig: Identifiable {
    let id = UUID()
    let iframeUrl: String
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
    let provider: String
}

struct HomeDirectPlayWrapper: View {
    let kpId: Int
    let title: String
    let onPlay: (PlayerConfig) -> Void
    
    @StateObject private var viewModel = DetailsViewModel()
    @State private var fetchAttempted = false
    
    var body: some View {
        ZStack {
            if !fetchAttempted || viewModel.isFetchingSources {
                SourceSelectionLoadingView(title: title)
                    .transition(.opacity)
            } else if let wrapper = viewModel.sourceResultWrapper,
                      let result = wrapper.allohaResult {
                SourceSelectionView(mode: .play, allohaResult: result, cdnResult: nil, kpId: wrapper.kpId, details: viewModel.details) { provider, translation, season, episode, quality in
                    let config = PlayerConfig(
                        iframeUrl: translation.iframeUrl,
                        title: title,
                        kpId: wrapper.kpId,
                        season: season,
                        episode: episode,
                        voiceover: translation.name,
                        streamUrl: translation.streamUrl,
                        voices: [],
                        subtitles: [],
                        quality: quality,
                        provider: provider,
                        seriesResult: result
                    )
                    onPlay(config)
                }
                .transition(.opacity)
            } else {
                Text("Не удалось загрузить данные.")
                    .padding()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.isFetchingSources)
        .animation(.easeInOut(duration: 0.3), value: fetchAttempted)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            await viewModel.fetchSources(kpId: kpId, title: title)
            fetchAttempted = true
        }
    }
}
