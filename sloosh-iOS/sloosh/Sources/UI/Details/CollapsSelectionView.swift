import SwiftUI

struct CollapsSelectionView: View {
    let result: [CollapsSeason]
    let movieResult: CollapsMovie?
    let isSerial: Bool
    let title: String
    let onPlay: (String) -> Void
    
    @Environment(\.presentationMode) var presentationMode
    
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
            if let firstSeason = result.first {
                selectedSeason = firstSeason.season
                if let firstEpisode = firstSeason.episodes.first {
                    selectedEpisode = firstEpisode.episode
                    selectedTranslationName = firstEpisode.voices.first
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
            
            // Prefer hlsUrl or mpdUrl
            if let hls = epObj.hlsUrl, !hls.isEmpty {
                onPlay(hls)
                presentationMode.wrappedValue.dismiss()
            } else if let mpd = epObj.mpdUrl, !mpd.isEmpty {
                onPlay(mpd)
                presentationMode.wrappedValue.dismiss()
            }
        } else if let movie = movieResult {
            if let hls = movie.hlsUrl, !hls.isEmpty {
                onPlay(hls)
                presentationMode.wrappedValue.dismiss()
            } else if let mpd = movie.mpdUrl, !mpd.isEmpty {
                onPlay(mpd)
                presentationMode.wrappedValue.dismiss()
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if !allTranslations.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Озвучка")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                
                                FlowLayout(spacing: 8) {
                                    ForEach(allTranslations, id: \.self) { tName in
                                        ChipView(
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
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                
                                FlowLayout(spacing: 8) {
                                    ForEach(allSeasons, id: \.self) { s in
                                        ChipView(
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
                                        .font(.headline)
                                        .foregroundColor(.secondary)
                                    
                                    FlowLayout(spacing: 8) {
                                        ForEach(allEpisodes, id: \.self) { e in
                                            ChipView(
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
                        
                        Color.clear.frame(height: 80)
                    }
                    .padding()
                }
                
                Button(action: {
                    playSelected()
                }) {
                    Text("Далее")
                        .font(.system(size: 17, weight: .semibold))
                        .padding(.horizontal, 48)
                        .padding(.vertical, 14)
                        .foregroundColor(Color(UIColor.systemBackground))
                        .background(
                            Capsule()
                                .fill(Color.primary)
                        )
                }
                .buttonStyle(.plain)
                .padding(.bottom, 16)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                }
            }
        }
        .onAppear {
            setupInitialSelection()
        }
    }
}
