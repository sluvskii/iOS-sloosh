import SwiftUI

struct HomeDirectPlayWrapper: View {
    let kpId: Int
    let title: String
    
    @StateObject private var viewModel = DetailsViewModel()
    @State private var sourceSheetDetent: PresentationDetent = .medium
    
    // Player State
    @State private var showPlayer = false
    @State private var selectedIframeUrl: String?
    @State private var playerKpId: Int?
    @State private var playerSeason: Int?
    @State private var playerEpisode: Int?
    @State private var playerVoiceover: String?
    @State private var playerStreamUrl: String?
    @State private var playerVoices: [String] = []
    @State private var playerSubtitles: [PlaybackSubtitle] = []
    @State private var playerQuality: VideoQualityPreference?
    @State private var playerSeriesResult: AllohaApiResult?

    var body: some View {
        ZStack {
            if viewModel.isFetchingSources {
                SourceSelectionLoadingView(title: title)
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
                }
            } else {
                Text("Не удалось загрузить данные.")
                    .padding()
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            await viewModel.fetchSources(kpId: kpId, title: title)
        }
        .fullScreenCover(isPresented: $showPlayer) {
            if let iframeUrl = selectedIframeUrl {
                PlayerView(
                    iframeUrl: iframeUrl,
                    fallbackTitle: title,
                    kpId: playerKpId,
                    season: playerSeason,
                    episode: playerEpisode,
                    selectedVoiceover: playerVoiceover,
                    directStreamUrl: playerStreamUrl,
                    voices: playerVoices,
                    subtitles: playerSubtitles,
                    initialQuality: playerQuality,
                    seriesResult: playerSeriesResult
                )
            }
        }
    }
}
