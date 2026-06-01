import SwiftUI

struct CollapsSelectionView: View {
    let result: [CollapsSeason]
    let movieResult: CollapsMovie?
    let kpId: Int?
    let isSerial: Bool
    let title: String
    let onPlay: (String, Int?, Int?, String?, [String], [CollapsSubtitle]) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedSeason: Int?
    @State private var selectedEpisode: Int?
    @State private var selectedTranslationName: String?
    
    var allTranslations: [String] {
        if isSerial {
            var names = Set<String>()
            for season in result {
                for episode in season.episodes {
                    for v in episode.voices {
                        names.insert(v)
                    }
                }
            }
            return Array(names).sorted()
        } else if let movie = movieResult {
            return movie.voices.sorted()
        }
        return []
    }
    
    var allSeasons: [Int] {
        return result.map { $0.season }.sorted()
    }
    
    var allEpisodes: [Int] {
        guard let s = selectedSeason, let season = result.first(where: { $0.season == s }) else { return [] }
        return season.episodes.map { $0.episode }.sorted()
    }
    
    func isTranslationAvailable(_ name: String) -> Bool {
        if isSerial {
            guard let s = selectedSeason, let e = selectedEpisode else { return false }
            return episodeHasTranslation(season: s, episode: e, t: name)
        } else if let movie = movieResult {
            return movie.voices.contains(name)
        }
        return false
    }
    
    func isSeasonAvailable(_ seasonNum: Int) -> Bool {
        guard let tName = selectedTranslationName else { return true }
        return seasonHasTranslation(season: seasonNum, t: tName)
    }
    
    func isEpisodeAvailable(_ episodeNum: Int) -> Bool {
        guard let s = selectedSeason, let tName = selectedTranslationName else { return true }
        return episodeHasTranslation(season: s, episode: episodeNum, t: tName)
    }
    
    func seasonHasTranslation(season: Int, t: String) -> Bool {
        guard let s = result.first(where: { $0.season == season }) else { return false }
        return s.episodes.contains { ep in ep.voices.contains(t) }
    }

    func episodeHasTranslation(season: Int, episode: Int, t: String) -> Bool {
        guard let s = result.first(where: { $0.season == season }),
              let ep = s.episodes.first(where: { $0.episode == episode }) else { return false }
        return ep.voices.contains(t)
    }
    
    func selectTranslation(_ name: String) {
        selectedTranslationName = name
        if isSerial {
            if let s = selectedSeason, !seasonHasTranslation(season: s, t: name) {
                if let newS = result.first(where: { seasonHasTranslation(season: $0.season, t: name) }) {
                    selectedSeason = newS.season
                }
            }
            if let s = selectedSeason, let e = selectedEpisode, !episodeHasTranslation(season: s, episode: e, t: name) {
                if let season = result.first(where: { $0.season == s }),
                   let newEp = season.episodes.first(where: { $0.voices.contains(name) }) {
                    selectedEpisode = newEp.episode
                }
            }
        }
    }
    
    func selectSeason(_ s: Int) {
        selectedSeason = s
        let seasonObj = result.first(where: { $0.season == s })!
        if let e = selectedEpisode, !seasonObj.episodes.contains(where: { $0.episode == e }) {
            selectedEpisode = seasonObj.episodes.first?.episode ?? 1
        }
        if let t = selectedTranslationName, let e = selectedEpisode, !episodeHasTranslation(season: s, episode: e, t: t) {
            if let ep = seasonObj.episodes.first(where: { $0.episode == e }), let firstT = ep.voices.first {
                selectedTranslationName = firstT
            }
        }
    }
    
    func selectEpisode(_ e: Int) {
        selectedEpisode = e
        if let s = selectedSeason, let t = selectedTranslationName, !episodeHasTranslation(season: s, episode: e, t: t) {
            if let seasonObj = result.first(where: { $0.season == s }),
               let epObj = seasonObj.episodes.first(where: { $0.episode == e }),
               let firstT = epObj.voices.first {
                selectedTranslationName = firstT
            }
        }
    }
    
    private func setupInitialSelection() {
        if isSerial {
            var initialSeason = result.first?.season
            var initialEpisode: Int? = nil
            
            if let kpId = kpId {
                if let lastSeason = CollapsPlaybackProgressStore.shared.loadLastSeason(kpId: kpId),
                   result.contains(where: { $0.season == lastSeason }) {
                    initialSeason = lastSeason
                }
                
                if let lastEpisode = CollapsPlaybackProgressStore.shared.loadLastEpisode(kpId: kpId) {
                    initialEpisode = lastEpisode
                }
            }
            
            if let seasonNum = initialSeason, let season = result.first(where: { $0.season == seasonNum }) {
                selectedSeason = seasonNum
                
                let episodeToSelect = initialEpisode.flatMap { epNum in
                    season.episodes.first(where: { $0.episode == epNum })
                } ?? season.episodes.first
                
                if let episode = episodeToSelect {
                    selectedEpisode = episode.episode
                    selectedTranslationName = episode.voices.first
                }
            }
        } else if let movie = movieResult {
            selectedTranslationName = movie.voices.first
        }
    }
    
    func playSelected() {
        if isSerial {
            guard let s = selectedSeason, let e = selectedEpisode else { return }
            guard let seasonObj = result.first(where: { $0.season == s }),
                  let epObj = seasonObj.episodes.first(where: { $0.episode == e }) else { return }
            
            if let kpId = kpId {
                CollapsPlaybackProgressStore.shared.saveLastPlayed(kpId: kpId, season: s, episode: e)
            }
            
            let tName = selectedTranslationName
            let voices = epObj.voices
            let subtitles = epObj.subtitles
            if let hls = epObj.hlsUrl, !hls.isEmpty {
                onPlay(hls, s, e, tName, voices, subtitles)
                dismiss()
            } else if let mpd = epObj.mpdUrl, !mpd.isEmpty {
                onPlay(mpd, s, e, tName, voices, subtitles)
                dismiss()
            }
        } else if let movie = movieResult {
            if let kpId = kpId {
                CollapsPlaybackProgressStore.shared.saveLastPlayed(kpId: kpId, season: nil, episode: nil)
            }
            
            let tName = selectedTranslationName
            let voices = movie.voices
            let subtitles = movie.subtitles
            if let hls = movie.hlsUrl, !hls.isEmpty {
                onPlay(hls, nil, nil, tName, voices, subtitles)
                dismiss()
            } else if let mpd = movie.mpdUrl, !mpd.isEmpty {
                onPlay(mpd, nil, nil, tName, voices, subtitles)
                dismiss()
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if !allTranslations.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Озвучка")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.primary)
                            
                            FlowLayout(spacing: 10) {
                                ForEach(allTranslations, id: \.self) { tName in
                                    WatchSelectorChip(
                                        title: tName,
                                        isSelected: selectedTranslationName == tName,
                                        isAvailable: isTranslationAvailable(tName)
                                    ) {
                                        selectTranslation(tName)
                                    }
                                }
                            }
                        }
                    }
                    
                    if isSerial && !allSeasons.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Сезон")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.primary)
                            
                            FlowLayout(spacing: 10) {
                                ForEach(allSeasons, id: \.self) { s in
                                    WatchSelectorChip(
                                        title: "\(s) сезон",
                                        isSelected: selectedSeason == s,
                                        isAvailable: isSeasonAvailable(s)
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
                                            isAvailable: isEpisodeAvailable(e)
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
    }
}
