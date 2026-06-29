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
        SourceSelectionView(
            title: title,
            viewModel: viewModel,
            detent: $sourceSheetDetent,
            onSelectionComplete: { seriesResult, kpId, season, episode, voiceover, quality, streamUrl in
                self.playerSeriesResult = seriesResult
                self.playerKpId = kpId
                self.playerSeason = season
                self.playerEpisode = episode
                self.playerVoiceover = voiceover
                self.playerQuality = quality
                self.playerStreamUrl = streamUrl
                
                self.selectedIframeUrl = "https://alloha.tv/?kp=\(kpId)"
                self.showPlayer = true
            }
        )
        .presentationDetents([.medium, .large], selection: $sourceSheetDetent)
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
