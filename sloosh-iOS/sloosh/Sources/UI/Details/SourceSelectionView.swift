import SwiftUI

enum SourceSelectionMode {
    case play
    case download
}

struct TranslationChipItem: Identifiable, Hashable {
    let id: String
    let name: String
    let displayName: String
}

struct SourceSelectionView: View {
    let mode: SourceSelectionMode
    let isLoading: Bool
    let source1Result: AllohaApiResult?
    let source2Result: CollapsParser.ParseResult?
    let kpId: Int?
    let details: MediaDetailsDto?
    let fallbackTitle: String?
    let onAction: (AllohaTranslation, Int?, Int?, VideoQualityPreference, MediaStreamSource, [PlaybackSubtitle], [String: String]) -> Void
    @Environment(\.dismiss) private var dismiss

    @AppStorage("preferredStreamSource") private var preferredSource: MediaStreamSource = .source1
    @State private var selectedSource: MediaStreamSource

    // Backward compatibility init
    init(
        mode: SourceSelectionMode,
        result: AllohaApiResult,
        kpId: Int?,
        details: MediaDetailsDto?,
        fallbackTitle: String? = nil,
        onAction: @escaping (AllohaTranslation, Int?, Int?, VideoQualityPreference) -> Void
    ) {
        self.mode = mode
        self.isLoading = false
        self.source1Result = result
        self.source2Result = nil
        self.kpId = kpId
        self.details = details
        self.fallbackTitle = fallbackTitle
        self.onAction = { translation, season, episode, quality, _, _, _ in
            onAction(translation, season, episode, quality)
        }
        _selectedSource = State(initialValue: .source1)
    }

    init(
        mode: SourceSelectionMode,
        isLoading: Bool = false,
        source1Result: AllohaApiResult? = nil,
        source2Result: CollapsParser.ParseResult? = nil,
        kpId: Int? = nil,
        details: MediaDetailsDto? = nil,
        fallbackTitle: String? = nil,
        onAction: @escaping (AllohaTranslation, Int?, Int?, VideoQualityPreference, MediaStreamSource, [PlaybackSubtitle], [String: String]) -> Void
    ) {
        self.mode = mode
        self.isLoading = isLoading
        self.source1Result = source1Result
        self.source2Result = source2Result
        self.kpId = kpId
        self.details = details
        self.fallbackTitle = fallbackTitle
        self.onAction = onAction

        let saved = UserDefaults.standard.string(forKey: "preferredStreamSource")
        let preferred = MediaStreamSource(rawValue: saved ?? "") ?? .source1

        let hasSource1 = source1Result != nil && (!source1Result!.seasons.isEmpty || source1Result!.movie != nil)
        let hasSource2 = source2Result != nil && (!source2Result!.apiResult.seasons.isEmpty || source2Result!.apiResult.movie != nil)

        let initial: MediaStreamSource
        if preferred == .source2 && hasSource2 {
            initial = .source2
        } else if preferred == .source1 && hasSource1 {
            initial = .source1
        } else if hasSource1 {
            initial = .source1
        } else if hasSource2 {
            initial = .source2
        } else {
            initial = preferred
        }
        _selectedSource = State(initialValue: initial)
    }

    private func selectSource(_ source: MediaStreamSource) {
        selectedSource = source
        preferredSource = source
        UserDefaults.standard.set(source.rawValue, forKey: "preferredStreamSource")
    }

    private func isSourceAvailable(_ source: MediaStreamSource) -> Bool {
        switch source {
        case .source1:
            guard let r = source1Result else { return false }
            return !r.seasons.isEmpty || r.movie != nil
        case .source2:
            guard let r = source2Result?.apiResult else { return false }
            return !r.seasons.isEmpty || r.movie != nil
        }
    }

    private var hasAnySource: Bool {
        isSourceAvailable(.source1) || isSourceAvailable(.source2)
    }

    private var isLikelySerial: Bool {
        if let isSerial = details?.isSerial { return isSerial }
        if let type = details?.type { return type == "tv" || type == "serial" }
        return false
    }

    private func adjustSourceIfNeeded() {
        guard !isLoading else { return }
        let hasSource1 = isSourceAvailable(.source1)
        let hasSource2 = isSourceAvailable(.source2)

        guard hasSource1 || hasSource2 else { return }

        if preferredSource == .source2 {
            if hasSource2 {
                if selectedSource != .source2 { selectedSource = .source2 }
            } else if hasSource1 {
                if selectedSource != .source1 { selectedSource = .source1 }
            }
        } else {
            if hasSource1 {
                if selectedSource != .source1 { selectedSource = .source1 }
            } else if hasSource2 {
                if selectedSource != .source2 { selectedSource = .source2 }
            }
        }
    }

    private var currentTitle: String {
        if let t = details?.title, !t.isEmpty {
            return t
        }
        if let fallback = fallbackTitle, !fallback.isEmpty {
            return fallback
        }
        if selectedSource == .source1, let t = source1Result?.title, !t.isEmpty {
            return t
        }
        if selectedSource == .source2, let t = source2Result?.apiResult.title, !t.isEmpty {
            return t
        }
        return details?.originalTitle ?? "Выбор озвучки"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if isLoading {
                    skeletonContentView
                        .transition(.opacity)
                } else if !hasAnySource {
                    emptyContentView
                        .transition(.opacity)
                } else {
                    currentSourceContentView
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: isLoading)
            .animation(.easeInOut(duration: 0.25), value: selectedSource)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                    }
                    .tint(.primary)
                }

                ToolbarItem(placement: .principal) {
                    headerTitleOrLogoView
                }

                ToolbarItem(placement: .topBarTrailing) {
                    sourceCornerButton
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .onAppear {
                adjustSourceIfNeeded()
            }
            .onChange(of: isLoading) { _, loading in
                if !loading {
                    adjustSourceIfNeeded()
                }
            }
            .onChange(of: source1Result != nil) { _, _ in
                adjustSourceIfNeeded()
            }
            .onChange(of: source2Result != nil) { _, _ in
                adjustSourceIfNeeded()
            }
        }
        .presentationBackground { Color.clear.glassEffect(in: .rect) }
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var headerTitleOrLogoView: some View {
        if let logoString = details?.displayLogoUrl,
           let logoUrl = URL(string: logoString) {
            AsyncCachedImage(url: logoUrl) {
                fallbackHeaderTitle
            } content: { image in
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 26)
            } fallback: {
                fallbackHeaderTitle
            }
            .frame(maxWidth: 180)
        } else {
            fallbackHeaderTitle
        }
    }

    private var fallbackHeaderTitle: some View {
        Text(currentTitle)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: 180)
    }

    @ViewBuilder
    private var sourceCornerButton: some View {
        Menu {
            Section("Источник") {
                ForEach(MediaStreamSource.allCases) { source in
                    Button {
                        selectSource(source)
                    } label: {
                        if selectedSource == source {
                            Label(source.title, systemImage: "checkmark")
                        } else {
                            Text(source.title)
                        }
                    }
                    .disabled(isLoading ? false : !isSourceAvailable(source))
                }
            }
        } label: {
            Image(systemName: "server.rack")
        }
        .tint(.primary)
        .disabled(isLoading)
        .opacity(isLoading ? 0.45 : 1.0)
    }

    @ViewBuilder
    private var skeletonContentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SourceSelectionSkeletonSection(
                    title: "Озвучка",
                    chipWidths: [96, 128, 108, 116, 92, 104]
                )

                if isLikelySerial {
                    SourceSelectionSkeletonSection(
                        title: "Сезон",
                        chipWidths: [88, 88, 88]
                    )
                    SourceSelectionSkeletonSection(
                        title: "Серия",
                        chipWidths: [82, 82, 82, 82, 82, 82]
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentMargins(.horizontal, 20, for: .scrollContent)
        .contentMargins(.top, 16, for: .scrollContent)
        .contentMargins(.bottom, 28, for: .scrollContent)
        .safeAreaInset(edge: .bottom) {
            skeletonBottomActionButton
        }
    }

    @ViewBuilder
    private var skeletonBottomActionButton: some View {
        HStack(spacing: 8) {
            Image(systemName: mode == .play ? "play.fill" : "arrow.down.circle.fill")
                .font(.system(size: 18, weight: .black))
            Text(mode == .play ? "Смотреть" : "Скачать")
                .font(.system(size: 19, weight: .heavy))
        }
        .foregroundStyle(Color.black.opacity(0.28))
        .padding(.horizontal, 26)
        .frame(height: 50)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.35))
        )
        .glassEffect(.regular, in: .capsule)
        .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 4)
        .shimmer()
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var emptyContentView: some View {
        VStack(spacing: 16) {
            Image(systemName: "film.stack")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("Видео пока недоступно")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.primary)

            Text("Этот проект пока отсутствует в источниках стриминга или еще не вышел в релиз.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 80)
    }

    @ViewBuilder
    private var currentSourceContentView: some View {
        if selectedSource == .source1 {
            if let res1 = source1Result, (!res1.seasons.isEmpty || res1.movie != nil) {
                SingleSourceContentView(
                    mode: mode,
                    source: .source1,
                    result: res1,
                    kpId: kpId,
                    details: details,
                    episodeSubtitles: [:],
                    movieSubtitles: [],
                    customHeaders: [:]
                ) { translation, season, episode, quality, subs, headers in
                    onAction(translation, season, episode, quality, .source1, subs, headers)
                    dismiss()
                }
            } else {
                sourceUnavailableView(for: .source1)
            }
        } else {
            if let res2 = source2Result?.apiResult, (!res2.seasons.isEmpty || res2.movie != nil) {
                SingleSourceContentView(
                    mode: mode,
                    source: .source2,
                    result: res2,
                    kpId: kpId,
                    details: details,
                    episodeSubtitles: source2Result?.episodeSubtitles ?? [:],
                    movieSubtitles: source2Result?.movieSubtitles ?? [],
                    customHeaders: CollapsRepository.streamHeaders
                ) { translation, season, episode, quality, subs, headers in
                    onAction(translation, season, episode, quality, .source2, subs, headers)
                    dismiss()
                }
            } else {
                sourceUnavailableView(for: .source2)
            }
        }
    }

    @ViewBuilder
    private func sourceUnavailableView(for source: MediaStreamSource) -> some View {
        let alternate = (source == .source1) ? MediaStreamSource.source2 : MediaStreamSource.source1
        VStack(spacing: 16) {
            Image(systemName: "film.stack")
                .font(.system(size: 46))
                .foregroundStyle(.secondary.opacity(0.7))
            Text("В источнике видео пока недоступно")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.primary)
            Text("Пожалуйста, переключитесь на \(alternate.title)")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            if isSourceAvailable(alternate) {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        selectSource(alternate)
                    }
                } label: {
                    Text("Переключиться на \(alternate.title)")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.slooshAccent)
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 80)
    }
}

// MARK: - Single Source Content View

struct SingleSourceContentView: View {
    let mode: SourceSelectionMode
    let source: MediaStreamSource
    let result: AllohaApiResult
    let kpId: Int?
    let details: MediaDetailsDto?
    let episodeSubtitles: [EpisodeKey: [PlaybackSubtitle]]
    let movieSubtitles: [PlaybackSubtitle]
    let customHeaders: [String: String]
    let onCommit: (AllohaTranslation, Int?, Int?, VideoQualityPreference, [PlaybackSubtitle], [String: String]) -> Void

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
        source: MediaStreamSource,
        result: AllohaApiResult,
        kpId: Int?,
        details: MediaDetailsDto?,
        episodeSubtitles: [EpisodeKey: [PlaybackSubtitle]],
        movieSubtitles: [PlaybackSubtitle],
        customHeaders: [String: String],
        onCommit: @escaping (AllohaTranslation, Int?, Int?, VideoQualityPreference, [PlaybackSubtitle], [String: String]) -> Void
    ) {
        self.mode = mode
        self.source = source
        self.result = result
        self.kpId = kpId
        self.details = details
        self.episodeSubtitles = episodeSubtitles
        self.movieSubtitles = movieSubtitles
        self.customHeaders = customHeaders
        self.onCommit = onCommit

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
            details: details,
            sourceKey: source == .source2 ? "collaps" : "alloha"
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

    func seasonHasTranslation(season: Int, name: String) -> Bool {
        seasonTranslationsMap[season]?.contains(name) ?? false
    }

    func episodeHasTranslation(season: Int, episode: Int, name: String) -> Bool {
        episodeTranslationsMap[EpisodeKey(season: season, episode: episode)]?.contains(name) ?? false
    }

    func preferredTranslation(in translations: [AllohaTranslation], preferredName: String?) -> AllohaTranslation? {
        bestTranslation(in: translations, preferredName: preferredName)
    }

    // Selection actions
    func selectTranslation(_ name: String) {
        selectedTranslationName = name
        if result.isSerial {
            var s = selectedSeason
            if let currentS = s, !seasonHasTranslation(season: currentS, name: name) {
                if let newS = allSeasons.first(where: { seasonHasTranslation(season: $0, name: name) }) {
                    s = newS
                    selectedSeason = newS
                }
            }
            if let currentS = s {
                let currentE = selectedEpisode
                if currentE == nil || !episodeHasTranslation(season: currentS, episode: currentE!, name: name) {
                    if let newEp = (seasonEpisodes[currentS] ?? []).first(where: { episodeHasTranslation(season: currentS, episode: $0, name: name) }) {
                        selectedEpisode = newEp
                    }
                }
            }
        }
    }

    func selectSeason(_ s: Int) {
        selectedSeason = s
        let episodes = seasonEpisodes[s] ?? []
        var e = selectedEpisode
        if e == nil || !episodes.contains(e!) {
            e = episodes.first ?? 1
            selectedEpisode = e
        }
        if let currentE = e {
            if let currentT = selectedTranslationName, !episodeHasTranslation(season: s, episode: currentE, name: currentT) {
                if let seasonObj = result.seasons.first(where: { $0.season == s }),
                   let epObj = seasonObj.episodes.first(where: { $0.episode == currentE }),
                   let bestT = bestTranslation(in: epObj.translations, preferredName: currentT) {
                    selectedTranslationName = bestT.name
                }
            }
        }
    }

    func selectEpisode(_ e: Int) {
        selectedEpisode = e
        if let s = selectedSeason {
            let epNames = episodeTranslationsMap[EpisodeKey(season: s, episode: e)] ?? []
            if let currentT = selectedTranslationName {
                if !epNames.contains(currentT) {
                    if let seasonObj = result.seasons.first(where: { $0.season == s }),
                       let epObj = seasonObj.episodes.first(where: { $0.episode == e }),
                       let bestT = bestTranslation(in: epObj.translations, preferredName: currentT) {
                        selectedTranslationName = bestT.name
                    }
                }
            } else {
                if let seasonObj = result.seasons.first(where: { $0.season == s }),
                   let epObj = seasonObj.episodes.first(where: { $0.episode == e }),
                   let bestT = bestTranslation(in: epObj.translations, preferredName: nil) {
                    selectedTranslationName = bestT.name
                }
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
        details: MediaDetailsDto?,
        sourceKey: String
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

        var savedVoiceover = PlaybackProgressStore.shared.loadLastVoiceover(mediaKey: currentKey, source: sourceKey)
        if savedVoiceover == nil, let kpId, kpId > 0 {
            savedVoiceover = PlaybackProgressStore.shared.loadLastVoiceover(kpId: kpId, source: sourceKey)
        }
        if savedVoiceover == nil && sourceKey == "alloha",
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
        let sourceKey = source == .source2 ? "collaps" : "alloha"

        if result.isSerial {
            guard let s = selectedSeason, let e = selectedEpisode, let tName = selectedTranslationName else { return }
            guard let seasonObj = result.seasons.first(where: { $0.season == s }),
                  let epObj = seasonObj.episodes.first(where: { $0.episode == e }),
                  let translation = epObj.translations.first(where: { allohaTranslationNamesMatch($0.name, tName, exactOnly: true) }) else { return }

            if mode == .play {
                PlaybackProgressStore.shared.saveLastPlayed(mediaKey: currentKey, season: s, episode: e)
                PlaybackProgressStore.shared.saveLastVoiceover(mediaKey: currentKey, source: sourceKey, voiceover: translation.name)
                if let kpId = kpId, kpId > 0 {
                    PlaybackProgressStore.shared.saveLastPlayed(kpId: kpId, season: s, episode: e)
                    PlaybackProgressStore.shared.saveLastVoiceover(kpId: kpId, source: sourceKey, voiceover: translation.name)
                }
            }

            let subs = episodeSubtitles[EpisodeKey(season: s, episode: e)] ?? []
            onCommit(translation, s, e, quality, subs, customHeaders)
        } else if let movie = result.movie {
            guard let tName = selectedTranslationName,
                  let translation = movie.translations.first(where: { $0.name == tName }) else { return }

            if mode == .play {
                PlaybackProgressStore.shared.saveLastPlayed(mediaKey: currentKey, season: nil, episode: nil)
                PlaybackProgressStore.shared.saveLastVoiceover(mediaKey: currentKey, source: sourceKey, voiceover: translation.name)
                if let kpId = kpId, kpId > 0 {
                    PlaybackProgressStore.shared.saveLastPlayed(kpId: kpId, season: nil, episode: nil)
                    PlaybackProgressStore.shared.saveLastVoiceover(kpId: kpId, source: sourceKey, voiceover: translation.name)
                }
            }

            let subs = movieSubtitles
            onCommit(translation, nil, nil, quality, subs, customHeaders)
        }
    }

    var isReadyToPlay: Bool {
        guard selectedTranslationName != nil else { return false }
        if result.isSerial {
            return selectedSeason != nil && selectedEpisode != nil
        }
        return true
    }

    var body: some View {
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
        .safeAreaInset(edge: .bottom) {
            bottomActionButton
        }
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

// MARK: - Skeleton Section

struct SourceSelectionSkeletonSection: View {
    let title: String
    let chipWidths: [CGFloat]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.primary)

            FlowLayout(spacing: 8) {
                ForEach(Array(chipWidths.enumerated()), id: \.offset) { _, width in
                    Capsule()
                        .fill(Color(UIColor.secondarySystemFill))
                        .frame(width: width, height: 32)
                }
            }
        }
        .shimmer()
    }
}

