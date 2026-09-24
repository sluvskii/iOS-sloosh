import SwiftUI

enum SourceSelectionMode {
    case play
    case download
}

struct EpisodeKey: Hashable {
    let season: Int
    let episode: Int
}

struct TranslationChipItem: Identifiable, Hashable {
    let id: String
    let name: String
    let displayName: String
}

struct SourceSelectionView: View {
    let mode: SourceSelectionMode
    let result: AllohaApiResult
    let kpId: Int?
    let details: MediaDetailsDto?
    let onAction: (AllohaTranslation, Int?, Int?, VideoQualityPreference) -> Void
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedSeason: Int?
    @State private var selectedEpisode: Int?
    @State private var selectedTranslationName: String?
    
    @AppStorage("preferredVideoQuality") private var preferredQuality: VideoQualityPreference = .ask
    @State private var showQualitySelection = false

    // Precomputed immutable caches (calculated once on init)
    let allTranslations: [TranslationChipItem]
    let allSeasons: [Int]
    let seasonEpisodes: [Int: [Int]]
    let seasonTranslationsMap: [Int: Set<String>]
    let episodeTranslationsMap: [EpisodeKey: Set<String>]
    let movieTranslationNames: Set<String>

    init(
        mode: SourceSelectionMode,
        result: AllohaApiResult,
        kpId: Int?,
        details: MediaDetailsDto?,
        onAction: @escaping (AllohaTranslation, Int?, Int?, VideoQualityPreference) -> Void
    ) {
        self.mode = mode
        self.result = result
        self.kpId = kpId
        self.details = details
        self.onAction = onAction

        var transItems: [TranslationChipItem] = []
        var seasonsList: [Int] = []
        var sEpisodes: [Int: [Int]] = [:]
        var sTransMap: [Int: Set<String>] = [:]
        var epTransMap: [EpisodeKey: Set<String>] = [:]
        var movieNames = Set<String>()

        if result.isSerial {
            var allNames = Set<String>()
            for season in result.seasons {
                let epNums = season.episodes.map { $0.episode }.sorted()
                sEpisodes[season.season] = epNums

                for ep in season.episodes {
                    let epNames = ep.translations.map { $0.name }
                    allNames.formUnion(epNames)
                }
            }

            let sortedNames = Array(allNames).sorted()
            transItems = sortedNames.enumerated().map { idx, name in
                TranslationChipItem(
                    id: name,
                    name: name,
                    displayName: displayTranslationName(name, at: idx, in: sortedNames)
                )
            }
            seasonsList = result.seasons.map { $0.season }.sorted()

            // Precompute canonical Set<String> for each episode and season
            // This turns every runtime check into a pure O(1) set lookup
            for season in result.seasons {
                var seasonMatchedNames = Set<String>()
                for ep in season.episodes {
                    let rawEpNames = Set(ep.translations.map { $0.name })
                    var availableForEp = Set<String>()
                    for name in sortedNames {
                        if rawEpNames.contains(name) || rawEpNames.contains(where: { allohaTranslationNamesMatch($0, name, exactOnly: true) }) {
                            availableForEp.insert(name)
                        }
                    }
                    epTransMap[EpisodeKey(season: season.season, episode: ep.episode)] = availableForEp
                    seasonMatchedNames.formUnion(availableForEp)
                }
                sTransMap[season.season] = seasonMatchedNames
            }
        } else if let movie = result.movie {
            let sortedNames = movie.translations.map { $0.name }.sorted()
            movieNames = Set(sortedNames)
            transItems = sortedNames.enumerated().map { idx, name in
                TranslationChipItem(
                    id: name,
                    name: name,
                    displayName: displayTranslationName(name, at: idx, in: sortedNames)
                )
            }
        }

        self.allTranslations = transItems
        self.allSeasons = seasonsList
        self.seasonEpisodes = sEpisodes
        self.seasonTranslationsMap = sTransMap
        self.episodeTranslationsMap = epTransMap
        self.movieTranslationNames = movieNames

        let initial = Self.computeInitialSelection(
            result: result,
            kpId: kpId,
            details: details
        )
        _selectedSeason = State(initialValue: initial.season)
        _selectedEpisode = State(initialValue: initial.episode)
        _selectedTranslationName = State(initialValue: initial.translationName)
        _showQualitySelection = State(initialValue: false)
    }
    
    var allEpisodes: [Int] {
        guard let s = selectedSeason else { return [] }
        return seasonEpisodes[s] ?? []
    }
    
    // Instant O(1) Available checking
    func isTranslationAvailable(_ name: String) -> Bool {
        if result.isSerial {
            guard let s = selectedSeason, let e = selectedEpisode else { return false }
            return episodeTranslationsMap[EpisodeKey(season: s, episode: e)]?.contains(name) ?? false
        } else {
            return movieTranslationNames.contains(name)
        }
    }
    
    func isSeasonAvailable(_ seasonNum: Int) -> Bool {
        guard let tName = selectedTranslationName else { return true }
        return seasonTranslationsMap[seasonNum]?.contains(tName) ?? false
    }
    
    func isEpisodeAvailable(_ episodeNum: Int) -> Bool {
        guard let s = selectedSeason, let tName = selectedTranslationName else { return true }
        return episodeTranslationsMap[EpisodeKey(season: s, episode: episodeNum)]?.contains(tName) ?? false
    }

    func preferredTranslation(in translations: [AllohaTranslation], preferredName: String?) -> AllohaTranslation? {
        bestTranslation(in: translations, preferredName: preferredName)
    }
    
    // Selection actions
    func selectTranslation(_ name: String) {
        selectedTranslationName = name
        if result.isSerial {
            if let s = selectedSeason, !isSeasonAvailable(s) {
                if let newS = allSeasons.first(where: { isSeasonAvailable($0) }) {
                    selectedSeason = newS
                }
            }
            if let s = selectedSeason, let e = selectedEpisode, !isEpisodeAvailable(e) {
                if let newEp = (seasonEpisodes[s] ?? []).first(where: { isEpisodeAvailable($0) }) {
                    selectedEpisode = newEp
                }
            }
        }
    }
    
    func selectSeason(_ s: Int) {
        selectedSeason = s
        let episodes = seasonEpisodes[s] ?? []
        if let e = selectedEpisode, !episodes.contains(e) {
            selectedEpisode = episodes.first ?? 1
        }
        if let t = selectedTranslationName, let e = selectedEpisode, !isEpisodeAvailable(e) {
            if let epNames = episodeTranslationsMap[EpisodeKey(season: s, episode: e)],
               let firstAvailable = allTranslations.first(where: { epNames.contains($0.name) }) {
                selectedTranslationName = firstAvailable.name
            }
        }
    }
    
    func selectEpisode(_ e: Int) {
        selectedEpisode = e
        if let s = selectedSeason, let t = selectedTranslationName, !isEpisodeAvailable(e) {
            if let epNames = episodeTranslationsMap[EpisodeKey(season: s, episode: e)],
               let firstAvailable = allTranslations.first(where: { epNames.contains($0.name) }) {
                selectedTranslationName = firstAvailable.name
            }
        }
    }
    
    var mediaKey: String {
        let validKp = (kpId ?? 0) > 0 ? (kpId ?? 0) : (details?.ids?.kp ?? details?.externalIds?.kp ?? 0)
        if validKp > 0 {
            return "kp_\(validKp)"
        }
        if let detailsId = details?.id, !detailsId.isEmpty {
            return detailsId.hasPrefix("kp_") || detailsId.hasPrefix("tmdb_") ? detailsId : "tmdb_\(detailsId)"
        }
        if let tmdb = details?.externalIds?.tmdb ?? details?.ids?.tmdb, tmdb > 0 {
            return "tmdb_\(tmdb)"
        }
        return "unknown"
    }

    static func computeInitialSelection(
        result: AllohaApiResult,
        kpId: Int?,
        details: MediaDetailsDto?
    ) -> (season: Int?, episode: Int?, translationName: String?) {
        let validKp = (kpId ?? 0) > 0 ? (kpId ?? 0) : (details?.ids?.kp ?? details?.externalIds?.kp ?? 0)
        let currentKey: String
        if validKp > 0 {
            currentKey = "kp_\(validKp)"
        } else if let detailsId = details?.id, !detailsId.isEmpty {
            currentKey = detailsId.hasPrefix("kp_") || detailsId.hasPrefix("tmdb_") ? detailsId : "tmdb_\(detailsId)"
        } else if let tmdb = details?.externalIds?.tmdb ?? details?.ids?.tmdb, tmdb > 0 {
            currentKey = "tmdb_\(tmdb)"
        } else {
            currentKey = "unknown"
        }

        var savedVoiceover = PlaybackProgressStore.shared.loadLastVoiceover(mediaKey: currentKey)
        if savedVoiceover == nil, let kpId, kpId > 0 {
            savedVoiceover = PlaybackProgressStore.shared.loadLastVoiceover(kpId: kpId, source: "alloha")
        }
        if savedVoiceover == nil,
           let globalVoiceover = UserDefaults.standard.string(forKey: "alloha_last_translation_name"),
           !isOriginalOrEnglishTranslation(globalVoiceover) {
            savedVoiceover = globalVoiceover
        }

        if result.isSerial {
            var initialSeason = result.seasons.first?.season
            var initialEpisode: Int? = nil
            
            if let lastSeason = PlaybackProgressStore.shared.loadLastSeason(mediaKey: currentKey) ?? (kpId.flatMap { $0 > 0 ? PlaybackProgressStore.shared.loadLastSeason(kpId: $0) : nil }),
               result.seasons.contains(where: { $0.season == lastSeason }) {
                initialSeason = lastSeason
            }
            
            if let lastEpisode = PlaybackProgressStore.shared.loadLastEpisode(mediaKey: currentKey) ?? (kpId.flatMap { $0 > 0 ? PlaybackProgressStore.shared.loadLastEpisode(kpId: $0) : nil }) {
                initialEpisode = lastEpisode
                
                // If the user fully watched this episode, auto-select the next one!
                let sNum = initialSeason ?? 1
                let mediaId = "\(currentKey)_s\(sNum)_e\(lastEpisode)"
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
            
            if let seasonNum = initialSeason, let season = result.seasons.first(where: { $0.season == seasonNum }) {
                let episodeToSelect = initialEpisode.flatMap { epNum in
                    season.episodes.first(where: { $0.episode == epNum })
                } ?? season.episodes.first
                
                let epNum = episodeToSelect?.episode
                let tName = episodeToSelect.flatMap { ep in
                    bestTranslation(in: ep.translations, preferredName: savedVoiceover)?.name
                }
                return (seasonNum, epNum, tName)
            }
            return (initialSeason, initialEpisode, nil)
        } else if let movie = result.movie {
            let tName = bestTranslation(in: movie.translations, preferredName: savedVoiceover)?.name
            return (nil, nil, tName)
        }
        return (nil, nil, nil)
    }
    
    func actionSelected() {
        if preferredQuality == .ask {
            showQualitySelection = true
        } else {
            finishAction(quality: preferredQuality)
        }
    }
    
    func finishAction(quality: VideoQualityPreference) {
        let currentKey = mediaKey
        if result.isSerial {
            guard let s = selectedSeason, let e = selectedEpisode, let tName = selectedTranslationName else { return }
            guard let seasonObj = result.seasons.first(where: { $0.season == s }),
                  let epObj = seasonObj.episodes.first(where: { $0.episode == e }),
                  let translation = epObj.translations.first(where: { allohaTranslationNamesMatch($0.name, tName, exactOnly: true) }) else { return }
            
            if mode == .play {
                PlaybackProgressStore.shared.saveLastPlayed(mediaKey: currentKey, season: s, episode: e)
                PlaybackProgressStore.shared.saveLastVoiceover(mediaKey: currentKey, source: "alloha", voiceover: translation.name)
                if let kpId = kpId, kpId > 0 {
                    PlaybackProgressStore.shared.saveLastPlayed(kpId: kpId, season: s, episode: e)
                    PlaybackProgressStore.shared.saveLastVoiceover(kpId: kpId, source: "alloha", voiceover: translation.name)
                }
            }
            
            onAction(translation, s, e, quality)
            dismiss()
        } else if let movie = result.movie {
            guard let tName = selectedTranslationName,
                  let translation = movie.translations.first(where: { $0.name == tName }) else { return }
            
            if mode == .play {
                PlaybackProgressStore.shared.saveLastPlayed(mediaKey: currentKey, season: nil, episode: nil)
                PlaybackProgressStore.shared.saveLastVoiceover(mediaKey: currentKey, source: "alloha", voiceover: translation.name)
                if let kpId = kpId, kpId > 0 {
                    PlaybackProgressStore.shared.saveLastPlayed(kpId: kpId, season: nil, episode: nil)
                    PlaybackProgressStore.shared.saveLastVoiceover(kpId: kpId, source: "alloha", voiceover: translation.name)
                }
            }
            
            onAction(translation, nil, nil, quality)
            dismiss()
        }
    }

    /// Кнопка «Смотреть» активна только когда пользователь сделал полный выбор.
    var isReadyToPlay: Bool {
        guard selectedTranslationName != nil else { return false }
        if result.isSerial {
            return selectedSeason != nil && selectedEpisode != nil
        }
        return true
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    translationsSection
                    
                    if result.isSerial && !allSeasons.isEmpty {
                        seasonsSection
                        if !allEpisodes.isEmpty {
                            episodesSection
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentMargins(.horizontal, 20, for: .scrollContent)
            .contentMargins(.top, 16, for: .scrollContent)
            .contentMargins(.bottom, 28, for: .scrollContent)
            .navigationTitle(result.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(.primary)
                    }
                    .tint(.primary)
                    .buttonStyle(.plain)
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomActionButton
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        .presentationBackground { Color.clear.glassEffect(in: .rect) }
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showQualitySelection) {
            QualitySelectionSheet { selectedQuality in
                showQualitySelection = false
                finishAction(quality: selectedQuality)
            }
        }
    }
    
    @ViewBuilder
    private var translationsSection: some View {
        if !allTranslations.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Озвучка")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.primary)
                
                FlowLayout(spacing: 8) {
                    ForEach(allTranslations) { item in
                        WatchSelectorChip(
                            title: item.displayName,
                            isSelected: selectedTranslationName == item.name,
                            isAvailable: isTranslationAvailable(item.name)
                        ) {
                            selectTranslation(item.name)
                        }
                        .equatable()
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var seasonsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Сезон")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.primary)
            
            FlowLayout(spacing: 8) {
                ForEach(allSeasons, id: \.self) { s in
                    WatchSelectorChip(
                        title: "\(s) сезон",
                        isSelected: selectedSeason == s,
                        isAvailable: isSeasonAvailable(s)
                    ) {
                        selectSeason(s)
                    }
                    .equatable()
                }
            }
        }
    }
    
    @ViewBuilder
    private var episodesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Серия")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.primary)
            
            FlowLayout(spacing: 8) {
                ForEach(allEpisodes, id: \.self) { e in
                    WatchSelectorChip(
                        title: "\(e) серия",
                        isSelected: selectedEpisode == e,
                        isAvailable: isEpisodeAvailable(e)
                    ) {
                        selectEpisode(e)
                    }
                    .equatable()
                }
            }
        }
    }
    
    @ViewBuilder
    private var bottomActionButton: some View {
        Button(action: {
            actionSelected()
        }) {
            HStack(spacing: 8) {
                Image(systemName: mode == .play ? "play.fill" : "arrow.down.circle.fill")
                    .font(.system(size: 18, weight: .black))
                Text(mode == .play ? "Смотреть" : "Скачать")
                    .font(.system(size: 19, weight: .heavy))
            }
            .foregroundStyle(Color.black)
            .padding(.horizontal, 26)
            .frame(height: 50)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.94))
            )
            .glassEffect(.regular.interactive(), in: .capsule)
            .shadow(color: Color.black.opacity(0.22), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.glassPress)
        .disabled(!isReadyToPlay)
        .opacity(isReadyToPlay ? 1.0 : 0.4)
        .padding(.bottom, 8)
    }
}
