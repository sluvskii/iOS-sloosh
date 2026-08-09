import SwiftUI

// PlayerConfig удалён — используется PlayerLaunchConfig из PlayerLauncher.swift

struct HomeDirectPlayWrapper: View {
    let movieId: String
    let fallbackTitle: String
    var initialKpId: Int? = nil
    
    @StateObject private var viewModel = DetailsViewModel()
    @State private var fetchAttempted = false
    @State private var launchConfig: PlayerLaunchConfig? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            if !fetchAttempted || viewModel.isFetchingSources || viewModel.isLoading {
                SourceSelectionLoadingView(title: viewModel.details?.title ?? fallbackTitle)
                    .transition(.opacity)
            } else if let wrapper = viewModel.sourceResultWrapper,
                      let result = wrapper.allohaResult {
                SourceSelectionView(mode: .play, result: result, kpId: wrapper.kpId, details: viewModel.details) { translation, season, episode, quality in
                    guard launchConfig == nil else { return }
                    launchConfig = PlayerLaunchConfig(
                        iframeUrl: translation.iframeUrl,
                        directStreamUrl: translation.streamUrl,
                        fallbackTitle: viewModel.details?.title ?? fallbackTitle,
                        kpId: wrapper.kpId,
                        season: season,
                        episode: episode,
                        selectedVoiceover: translation.name,
                        voices: result.allTranslationNames,
                        subtitles: [],
                        initialQuality: quality,
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
        .playerLauncher(config: launchConfig) {
            launchConfig = nil
            dismiss()
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
