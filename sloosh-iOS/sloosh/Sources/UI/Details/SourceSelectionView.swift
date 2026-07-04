import SwiftUI

struct SourceSelectionView: View {
    let result: AllohaApiResult
    let kpId: Int?
    let details: MediaDetailsDto?
    let onPlay: (AllohaTranslation, Int?, Int?, VideoQualityPreference) -> Void
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedSeason: Int?
    @State private var selectedEpisode: Int?
    @State private var selectedTranslationName: String?
    
    @AppStorage("preferredVideoQuality") private var preferredQuality: VideoQualityPreference = .ask
    @State private var showQualitySelection = false
    
    @ObservedObject private var downloadManager = DownloadManager.shared
    @State private var showDeleteAlert = false
    
    // Computed properties for ALL unique values
    var allTranslations: [String] {
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
        return result.seasons.map { $0.season }.sorted()
    }
    
    var allEpisodes: [Int] {
        guard let s = selectedSeason, let season = result.seasons.first(where: { $0.season == s }) else { return [] }
        return season.episodes.map { $0.episode }.sorted()
    }
    
    // Available checking
    func isTranslationAvailable(_ name: String) -> Bool {
        if result.isSerial {
            guard let s = selectedSeason, let e = selectedEpisode else { return false }
            return episodeHasTranslation(season: s, episode: e, t: name)
        } else if let movie = result.movie {
            return movie.translations.contains { allohaTranslationNamesMatch($0.name, name, exactOnly: true) }
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
        guard let s = result.seasons.first(where: { $0.season == season }) else { return false }
        return s.episodes.contains { ep in ep.translations.contains { allohaTranslationNamesMatch($0.name, t, exactOnly: true) } }
    }

    func episodeHasTranslation(season: Int, episode: Int, t: String) -> Bool {
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
    func selectTranslation(_ name: String) {
        selectedTranslationName = name
        if result.isSerial {
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
        let seasonObj = result.seasons.first(where: { $0.season == s })!
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
        if let s = selectedSeason, let t = selectedTranslationName, !episodeHasTranslation(season: s, episode: e, t: t) {
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

        if result.isSerial {
            var initialSeason = result.seasons.first?.season
            var initialEpisode: Int? = nil
            
            if let kpId = kpId {
                if let lastSeason = PlaybackProgressStore.shared.loadLastSeason(kpId: kpId),
                   result.seasons.contains(where: { $0.season == lastSeason }) {
                    initialSeason = lastSeason
                }
                
                if let lastEpisode = PlaybackProgressStore.shared.loadLastEpisode(kpId: kpId) {
                    initialEpisode = lastEpisode
                    
                    // If the user fully watched this episode, auto-select the next one!
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
        } else if let movie = result.movie {
            selectedTranslationName = preferredTranslation(in: movie.translations, preferredName: savedVoiceover)?.name
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
        if result.isSerial {
            guard let s = selectedSeason, let e = selectedEpisode, let tName = selectedTranslationName else { return }
            guard let seasonObj = result.seasons.first(where: { $0.season == s }),
                  let epObj = seasonObj.episodes.first(where: { $0.episode == e }),
                  let translation = epObj.translations.first(where: { allohaTranslationNamesMatch($0.name, tName, exactOnly: true) }) else { return }
            
            if let kpId = kpId {
                PlaybackProgressStore.shared.saveLastPlayed(kpId: kpId, season: s, episode: e)
                PlaybackProgressStore.shared.saveLastVoiceover(kpId: kpId, source: "alloha", voiceover: translation.name)
            }
            
            onPlay(translation, s, e, quality)
            dismiss()
        } else if let movie = result.movie {
            guard let tName = selectedTranslationName,
                  let translation = movie.translations.first(where: { allohaTranslationNamesMatch($0.name, tName, exactOnly: true) }) else { return }
            
            if let kpId = kpId {
                PlaybackProgressStore.shared.saveLastPlayed(kpId: kpId, season: nil, episode: nil)
                PlaybackProgressStore.shared.saveLastVoiceover(kpId: kpId, source: "alloha", voiceover: translation.name)
            }
            
            onPlay(translation, nil, nil, quality)
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
                    
                    if result.isSerial && !allSeasons.isEmpty {
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
            .navigationTitle(result.title)
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
                ToolbarItem(placement: .bottomBar) {
                    HStack(spacing: 12) {
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
                        .disabled(!isReadyToPlay)
                        
                        if let details = details, isReadyToPlay {
                            downloadButton(for: details)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .alert("Удалить загрузку?", isPresented: $showDeleteAlert) {
            Button("Отмена", role: .cancel) {}
            Button("Удалить", role: .destructive) {
                if let item = currentDownloadItem {
                    DownloadManager.shared.deleteDownload(id: item.id)
                }
            }
        } message: {
            Text("Вы действительно хотите удалить этот файл из памяти устройства?")
        }
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
    
    private var currentDownloadItem: DownloadItem? {
        guard let kpId = kpId else { return nil }
        if result.isSerial {
            guard let s = selectedSeason, let e = selectedEpisode else { return nil }
            return downloadManager.getDownloadItem(kpId: kpId, season: s, episode: e)
        } else {
            return downloadManager.getDownloadItem(kpId: kpId, season: nil, episode: nil)
        }
    }
    
    @ViewBuilder
    private func downloadButton(for details: MediaDetailsDto) -> some View {
        let item = currentDownloadItem
        
        Button(action: {
            handleDownloadAction(details: details, item: item)
        }) {
            Group {
                if let item = item {
                    switch item.status {
                    case .pending:
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .primary))
                            .scaleEffect(0.8)
                    case .downloading:
                        ZStack {
                            Circle()
                                .stroke(Color.primary.opacity(0.15), lineWidth: 2.5)
                                .frame(width: 24, height: 24)
                            Circle()
                                .trim(from: 0.0, to: item.progress)
                                .stroke(Color.slooshAccent, lineWidth: 2.5)
                                .frame(width: 24, height: 24)
                                .rotationEffect(Angle(degrees: -90))
                            
                            Image(systemName: "square.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.primary)
                        }
                    case .completed:
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(Color.slooshAccent)
                    case .failed:
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.red)
                    }
                } else {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 20))
                        .foregroundColor(.primary)
                }
            }
            .frame(width: 44, height: 44)
            .background(Color.white.opacity(0.08))
            .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
    
    private func handleDownloadAction(details: MediaDetailsDto, item: DownloadItem?) {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
        
        if let item = item {
            switch item.status {
            case .downloading, .pending:
                DownloadManager.shared.pauseDownload(id: item.id)
            case .failed:
                startOrResumeDownload(details: details)
            case .completed:
                showDeleteAlert = true
            }
        } else {
            startOrResumeDownload(details: details)
        }
    }
    
    private func startOrResumeDownload(details: MediaDetailsDto) {
        guard let tName = selectedTranslationName else { return }
        
        let translation: AllohaTranslation
        if result.isSerial {
            guard let s = selectedSeason, let e = selectedEpisode,
                  let seasonObj = result.seasons.first(where: { $0.season == s }),
                  let epObj = seasonObj.episodes.first(where: { $0.episode == e }),
                  let transObj = epObj.translations.first(where: { allohaTranslationNamesMatch($0.name, tName, exactOnly: true) }) else { return }
            translation = transObj
        } else if let movie = result.movie,
                  let transObj = movie.translations.first(where: { allohaTranslationNamesMatch($0.name, tName, exactOnly: true) }) {
            translation = transObj
        } else {
            return
        }
        
        DownloadManager.shared.startDownload(
            details: details,
            season: selectedSeason,
            episode: selectedEpisode,
            translation: translation,
            preferredQuality: preferredQuality
        )
    }
}
