import SwiftUI

struct CdnSelectionView: View {
    let data: CdnPlayerData
    let kpId: Int?
    let title: String
    let onPlay: (String, Int?, Int?, VideoQualityPreference) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedSeason: Int?
    @State private var selectedEpisode: Int?
    
    @AppStorage("preferredVideoQuality") private var preferredQuality: VideoQualityPreference = .ask
    @State private var showQualitySelection = false
    
    var allSeasons: [Int] {
        return data.seasons?.map { $0.season }.sorted() ?? []
    }
    
    var allEpisodes: [Int] {
        guard let s = selectedSeason, let season = data.seasons?.first(where: { $0.season == s }) else { return [] }
        return season.episodes.map { $0.episode }.sorted()
    }
    
    func selectSeason(_ s: Int) {
        selectedSeason = s
        guard let seasonObj = data.seasons?.first(where: { $0.season == s }) else { return }
        if let e = selectedEpisode, !seasonObj.episodes.contains(where: { $0.episode == e }) {
            selectedEpisode = seasonObj.episodes.first?.episode ?? 1
        }
    }
    
    func selectEpisode(_ e: Int) {
        selectedEpisode = e
    }
    
    private func setupInitialSelection() {
        guard data.isSeries, let seasons = data.seasons else { return }
        
        var initialSeason = seasons.first?.season
        var initialEpisode: Int? = nil
        
        if let kpId = kpId {
            if let lastSeason = CollapsPlaybackProgressStore.shared.loadLastSeason(kpId: kpId),
               seasons.contains(where: { $0.season == lastSeason }) {
                initialSeason = lastSeason
            }
            
            if let lastEpisode = CollapsPlaybackProgressStore.shared.loadLastEpisode(kpId: kpId) {
                initialEpisode = lastEpisode
            }
        }
        
        if let seasonNum = initialSeason, let season = seasons.first(where: { $0.season == seasonNum }) {
            selectedSeason = seasonNum
            
            let episodeToSelect = initialEpisode.flatMap { epNum in
                season.episodes.first(where: { $0.episode == epNum })
            } ?? season.episodes.first
            
            if let episode = episodeToSelect {
                selectedEpisode = episode.episode
            }
        }
    }
    
    func playSelected() {
        if preferredQuality == .ask {
            showQualitySelection = true
        } else {
            finishPlay(quality: preferredQuality)
        }
    }
    
    func finishPlay(quality: VideoQualityPreference) {
        if data.isSeries {
            guard let s = selectedSeason, let e = selectedEpisode else { return }
            guard let seasonObj = data.seasons?.first(where: { $0.season == s }),
                  let epObj = seasonObj.episodes.first(where: { $0.episode == e }) else { return }
            
            if let kpId = kpId {
                CollapsPlaybackProgressStore.shared.saveLastPlayed(kpId: kpId, season: s, episode: e)
            }
            
            onPlay(epObj.filepath, s, e, quality)
        } else {
            if let kpId = kpId {
                CollapsPlaybackProgressStore.shared.saveLastPlayed(kpId: kpId, season: nil, episode: nil)
            }
            onPlay(data.initialM3u8, nil, nil, quality)
        }
        dismiss()
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if !allSeasons.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Сезон")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.primary)
                            
                            FlowLayout(spacing: 10) {
                                ForEach(allSeasons, id: \.self) { s in
                                    WatchSelectorChip(
                                        title: "\(s) сезон",
                                        isSelected: selectedSeason == s,
                                        isAvailable: true
                                    ) {
                                        selectSeason(s)
                                    }
                                }
                            }
                        }
                        
                        if !allEpisodes.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Серия")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.primary)
                                
                                FlowLayout(spacing: 10) {
                                    ForEach(allEpisodes, id: \.self) { e in
                                        WatchSelectorChip(
                                            title: "\(e) серия",
                                            isSelected: selectedEpisode == e,
                                            isAvailable: true
                                        ) {
                                            selectEpisode(e)
                                        }
                                    }
                                }
                            }
                        }
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
                ToolbarItem(placement: .bottomBar) {
                    Button(action: {
                        playSelected()
                    }) {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Смотреть")
                        }
                        .font(.system(size: 17, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .buttonBorderShape(.capsule)
                    .tint(.primary)
                    .foregroundStyle(Color(UIColor.systemBackground))
                    .padding(.horizontal)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .onAppear {
            setupInitialSelection()
        }
        .sheet(isPresented: $showQualitySelection) {
            QualitySelectionSheet { selectedQuality in
                showQualitySelection = false
                finishPlay(quality: selectedQuality)
            }
        }
    }
}
