import SwiftUI

enum SourceSelectionMode {
    case play
    case download
}

struct SourceSelectionView: View {
    let mode: SourceSelectionMode
    let allohaResult: AllohaApiResult?
    let cdnResult: AllohaApiResult?
    let kpId: Int?
    let details: MediaDetailsDto?
    let onAction: (String, AllohaTranslation, Int?, Int?, VideoQualityPreference) -> Void
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedSeason: Int?
    @State private var selectedEpisode: Int?
    @State private var selectedTranslationName: String?
    
    @State private var selectedProvider: String = "Alloha"
    
    var result: AllohaApiResult? {
        if selectedProvider == "CDNMovies" {
            return cdnResult
        }
        return allohaResult
    }
    
    @AppStorage("preferredVideoQuality") private var preferredQuality: VideoQualityPreference = .ask
    @State private var showQualitySelection = false
    
    // Computed properties for ALL unique values
    var allTranslations: [String] {
        guard let result = result else { return [] }
        if result.isSerial {
            var names = Set<String>()
            for season in result.seasons {
                for episode in season.episodes {
                    for t in episode.translations {
                        names.insert(t.name)
                    }
                }
            }
            return Array(names).sorted()
        } else if let movie = result.movie {
            return movie.translations.map { $0.name }.sorted()
        }
        return []
    }
    
    var allSeasons: [Int] {
        guard let result = result else { return [] }
        return result.seasons.map { $0.season }.sorted()
    }
    
    var allEpisodes: [Int] {
        guard let result = result, let s = selectedSeason, let season = result.seasons.first(where: { $0.season == s }) else { return [] }
        return season.episodes.map { $0.episode }.sorted()
    }
    
    private func autoSelectInitialValues() {
        guard let result = result else { return }
        
        if result.isSerial {
            if let firstSeason = result.seasons.first {
                selectedSeason = firstSeason.season
                if let firstEpisode = firstSeason.episodes.first {
                    selectedEpisode = firstEpisode.episode
                    if let firstTranslation = firstEpisode.translations.first {
                        selectedTranslationName = firstTranslation.name
                    }
                }
            }
        } else if let movie = result.movie, let firstTranslation = movie.translations.first {
            selectedTranslationName = firstTranslation.name
        }
    }
    
    // Available checking
    func isTranslationAvailable(_ name: String) -> Bool {
        guard let result = result else { return false }
        if result.isSerial {
            guard let s = selectedSeason, let e = selectedEpisode else { return false }
            return episodeHasTranslation(season: s, episode: e, t: name)
        } else if let movie = result.movie {
            return movie.translations.contains { $0.name == name }
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
    
    // Logic
    func seasonHasTranslation(season: Int, t: String) -> Bool {
        guard let result = result else { return false }
        guard let sInfo = result.seasons.first(where: { $0.season == season }) else { return false }
        return sInfo.episodes.contains { ep in ep.translations.contains { allohaTranslationNamesMatch($0.name, t, exactOnly: true) } }
    }

    func episodeHasTranslation(season: Int, episode: Int, t: String) -> Bool {
        guard let result = result else { return false }
        guard let s = result.seasons.first(where: { $0.season == season }),
              let ep = s.episodes.first(where: { $0.episode == episode }) else { return false }
        return ep.translations.contains { allohaTranslationNamesMatch($0.name, t, exactOnly: true) }
    }

    func preferredTranslation(in translations: [AllohaTranslation], preferredName: String?) -> AllohaTranslation? {
        guard !translations.isEmpty else { return nil }
        
        // 1. Try specified voiceover (per-show preference)
        if let preferredName,
           let match = translations.first(where: { allohaTranslationNamesMatch($0.name, preferredName, exactOnly: true) }) {
            return match
        }
        
        // 2. Try global preferred voiceover
        if let globalVoiceover = UserDefaults.standard.string(forKey: "alloha_last_translation_name"),
           let match = translations.first(where: { allohaTranslationNamesMatch($0.name, globalVoiceover, exactOnly: false) }) {
            return match
        }
        
        // 3. Fallback to first available
        return translations.first
    }
    
    // Selection actions
    private func getTranslationObject(name: String) -> AllohaTranslation? {
        guard let result = result else { return nil }
        if result.isSerial {
            guard let s = selectedSeason, let e = selectedEpisode else { return nil }
            guard let season = result.seasons.first(where: { $0.season == s }),
                  let ep = season.episodes.first(where: { $0.episode == e }) else { return nil }
            return ep.translations.first(where: { allohaTranslationNamesMatch($0.name, name, exactOnly: true) })
        } else if let movie = result.movie {
            return movie.translations.first(where: { $0.name == name })
        }
        return nil
    }

    func selectTranslation(_ name: String) {
        selectedTranslationName = name
        if let result = result, result.isSerial {
            if let s = selectedSeason, !seasonHasTranslation(season: s, t: name) {
                if let newS = result.seasons.first(where: { seasonHasTranslation(season: $0.season, t: name) }) {
                    selectedSeason = newS.season
                }
            }
            if let s = selectedSeason, let e = selectedEpisode, !episodeHasTranslation(season: s, episode: e, t: name) {
                if let season = result.seasons.first(where: { $0.season == s }),
                   let newEp = season.episodes.first(where: { $0.translations.contains(where: { allohaTranslationNamesMatch($0.name, name, exactOnly: true) }) }) {
                    selectedEpisode = newEp.episode
                }
            }
        }
    }
    
    func selectSeason(_ s: Int) {
        selectedSeason = s
        guard let result = result, let seasonObj = result.seasons.first(where: { $0.season == s }) else { return }
        if let e = selectedEpisode, !seasonObj.episodes.contains(where: { $0.episode == e }) {
            selectedEpisode = seasonObj.episodes.first?.episode ?? 1
        }
        if let t = selectedTranslationName, let e = selectedEpisode, !episodeHasTranslation(season: s, episode: e, t: t) {
            if let ep = seasonObj.episodes.first(where: { $0.episode == e }), let firstT = ep.translations.first {
                selectedTranslationName = firstT.name
            }
        }
    }
    
    func selectEpisode(_ e: Int) {
        selectedEpisode = e
        if let result = result, let s = selectedSeason, let t = selectedTranslationName, !episodeHasTranslation(season: s, episode: e, t: t) {
            if let seasonObj = result.seasons.first(where: { $0.season == s }),
               let epObj = seasonObj.episodes.first(where: { $0.episode == e }),
               let firstT = epObj.translations.first {
                selectedTranslationName = firstT.name
            }
        }
    }
    
    private func setupInitialSelection() {
        let savedVoiceover = kpId.flatMap {
            PlaybackProgressStore.shared.loadLastVoiceover(kpId: $0, source: "alloha")
        } ?? UserDefaults.standard.string(forKey: "alloha_last_translation_name")

        if let result = result, result.isSerial {
            var initialSeason = result.seasons.first?.season
            var initialEpisode: Int? = nil
            
            if let kpId = kpId {
                if let lastSeason = PlaybackProgressStore.shared.loadLastSeason(kpId: kpId),
                   result.seasons.contains(where: { $0.season == lastSeason }) {
                    initialSeason = lastSeason
                }
                
                if let lastEpisode = PlaybackProgressStore.shared.loadLastEpisode(kpId: kpId) {
                    initialEpisode = lastEpisode
                    
                    let mediaId = "kp_\(kpId)_s\(initialSeason ?? 1)_e\(lastEpisode)"
                    if PlaybackProgressStore.shared.loadWatched(mediaId: mediaId) {
                        let allEpisodes = result.seasons
                            .flatMap { s in s.episodes.map { (s.season, $0.episode) } }
                            .sorted {
                                if $0.0 != $1.0 { return $0.0 < $1.0 }
                                return $0.1 < $1.1
                            }
                        
                        if let currentIdx = allEpisodes.firstIndex(where: { $0.0 == initialSeason && $0.1 == lastEpisode }),
                           currentIdx + 1 < allEpisodes.count {
                            let nextEp = allEpisodes[currentIdx + 1]
                            initialSeason = nextEp.0
                            initialEpisode = nextEp.1
                        }
                    }
                }
            }
            
            if let seasonNum = initialSeason, let season = result.seasons.first(where: { $0.season == seasonNum }) {
                selectedSeason = seasonNum
                
                let episodeToSelect = initialEpisode.flatMap { epNum in
                    season.episodes.first(where: { $0.episode == epNum })
                } ?? season.episodes.first
                
                if let episode = episodeToSelect {
                    selectedEpisode = episode.episode
                    selectedTranslationName = preferredTranslation(in: episode.translations, preferredName: savedVoiceover)?.name
                }
            }
        } else if let movie = result?.movie {
            selectedTranslationName = preferredTranslation(in: movie.translations, preferredName: savedVoiceover)?.name
        }
    }
    
    func actionSelected() {
        if preferredQuality == .ask {
            showQualitySelection = true
        } else {
            if let t = getTranslationObject(name: selectedTranslationName ?? "") {
                if mode == .play, let kpId = kpId {
                    PlaybackProgressStore.shared.saveLastPlayed(kpId: kpId, season: selectedSeason, episode: selectedEpisode)
                    PlaybackProgressStore.shared.saveLastVoiceover(kpId: kpId, source: "alloha", voiceover: t.name)
                }
                onAction(selectedProvider, t, selectedSeason, selectedEpisode, preferredQuality)
                dismiss()
            }
        }
    }

    /// Кнопка «Смотреть» активна только когда пользователь сделал полный выбор.
    var isReadyToPlay: Bool {
        guard selectedTranslationName != nil else { return false }
        if let result = result, result.isSerial {
            return selectedSeason != nil && selectedEpisode != nil
        }
        return true
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    
                    if allohaResult != nil && cdnResult != nil {
                        Picker("Источник", selection: $selectedProvider) {
                            Text("Alloha").tag("Alloha")
                            Text("CDNMovies").tag("CDNMovies")
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                        .onChange(of: selectedProvider) { _ in
                            autoSelectInitialValues()
                        }
                    }
                    
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
                    
                    if let result = result, result.isSerial && !allSeasons.isEmpty {
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
            .navigationTitle(result?.title ?? "Выбор")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(.primary)
                    }
                    .tint(.primary)
                    .buttonStyle(.plain)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: {
                    actionSelected()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: mode == .play ? "play.fill" : "arrow.down.circle.fill")
                            .font(.system(size: 18, weight: .black))
                        Text(mode == .play ? "Смотреть" : "Скачать")
                            .font(.system(size: 19, weight: .heavy))
                    }
                    .frame(height: 50)
                    .padding(.horizontal, 24)
                }
                .buttonStyle(GlassPlayButtonStyle())
                .disabled(!isReadyToPlay)
                .padding(.bottom, 8)
            }
        }
        .presentationDragIndicator(.visible)
        .onAppear {
            setupInitialSelection()
        }
        .sheet(isPresented: $showQualitySelection) {
            if let t = getTranslationObject(name: selectedTranslationName ?? "") {
                QualitySelectionSheet { selectedQuality in
                    if mode == .play, let kpId = kpId {
                        PlaybackProgressStore.shared.saveLastPlayed(kpId: kpId, season: selectedSeason, episode: selectedEpisode)
                        PlaybackProgressStore.shared.saveLastVoiceover(kpId: kpId, source: "alloha", voiceover: t.name)
                    }
                    onAction(selectedProvider, t, selectedSeason, selectedEpisode, selectedQuality)
                    showQualitySelection = false
                    dismiss()
                }
            }
        }
    }
}
