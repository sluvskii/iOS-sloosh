import SwiftUI
import Foundation

enum SourceSelectionMode {
    case play
    case download
}

struct TranslationChipItem: Identifiable, Hashable {
    let id: String
    let name: String
    let displayName: String
    let studio: DubbingStudio?
    let flag: LanguageFlag?
}

struct PendingPlaybackCommit {
    let translation: AllohaTranslation
    let season: Int?
    let episode: Int?
    let subtitles: [PlaybackSubtitle]
    let customHeaders: [String: String]
    let source: MediaStreamSource
}

struct SourceSelectionView: View {
    let mode: SourceSelectionMode
    let isLoading: Bool
    let source1Result: AllohaApiResult?
    let source2Result: CollapsParser.ParseResult?
    let kpId: Int?
    let details: MediaDetailsDto?
    let fallbackTitle: String?
    let initialSeason: Int?
    let initialEpisode: Int?
    let onAction: (AllohaTranslation, Int?, Int?, VideoQualityPreference, MediaStreamSource, [PlaybackSubtitle], [String: String]) -> Void
    @Environment(\.dismiss) private var dismiss

    @AppStorage("preferredStreamSource") private var preferredSource: MediaStreamSource = .source1
    @State private var selectedSource: MediaStreamSource

    @AppStorage("preferredVideoQuality") private var preferredQuality: VideoQualityPreference = .ask
    @State private var isSelectingQuality: Bool = false
    @State private var selectedQuality: VideoQualityPreference = .auto
    @State private var rememberQualityChoice: Bool = false
    @State private var pendingCommit: PendingPlaybackCommit? = nil
    @StateObject private var catalogCache = SourceCatalogCache()

    private let availableQualities: [VideoQualityPreference] = [
        .auto,
        .q1080,
        .q720,
        .q480,
        .q360
    ]

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
        self.initialSeason = nil
        self.initialEpisode = nil
        self.onAction = { translation, season, episode, quality, _, _, _ in
            onAction(translation, season, episode, quality)
        }
        _selectedSource = State(initialValue: .source1)

        let savedQualityRaw = UserDefaults.standard.string(forKey: "preferredVideoQuality") ?? ""
        let savedQuality = VideoQualityPreference(rawValue: savedQualityRaw) ?? .auto
        let initialQuality = (savedQuality == .ask) ? .auto : savedQuality
        _selectedQuality = State(initialValue: initialQuality)
    }

    init(
        mode: SourceSelectionMode,
        isLoading: Bool = false,
        source1Result: AllohaApiResult? = nil,
        source2Result: CollapsParser.ParseResult? = nil,
        kpId: Int? = nil,
        details: MediaDetailsDto? = nil,
        fallbackTitle: String? = nil,
        initialSeason: Int? = nil,
        initialEpisode: Int? = nil,
        onAction: @escaping (AllohaTranslation, Int?, Int?, VideoQualityPreference, MediaStreamSource, [PlaybackSubtitle], [String: String]) -> Void
    ) {
        self.mode = mode
        self.isLoading = isLoading
        self.source1Result = source1Result
        self.source2Result = source2Result
        self.kpId = kpId
        self.details = details
        self.fallbackTitle = fallbackTitle
        self.initialSeason = initialSeason
        self.initialEpisode = initialEpisode
        self.onAction = onAction

        let saved = UserDefaults.standard.string(forKey: "preferredStreamSource")
        let preferred = MediaStreamSource(rawValue: saved ?? "") ?? .source1
        _selectedSource = State(initialValue: preferred)

        let savedQualityRaw = UserDefaults.standard.string(forKey: "preferredVideoQuality") ?? ""
        let savedQuality = VideoQualityPreference(rawValue: savedQualityRaw) ?? .auto
        let initialQuality = (savedQuality == .ask) ? .auto : savedQuality
        _selectedQuality = State(initialValue: initialQuality)
    }

    private func selectSource(_ source: MediaStreamSource) {
        selectedSource = source
        preferredSource = source
        UserDefaults.standard.set(source.rawValue, forKey: "preferredStreamSource")
    }

    private var isProjectMovie: Bool {
        if let type = details?.type?.lowercased() {
            if type == "movie" { return true }
            if type == "tv" || type == "serial" || type == "series" { return false }
        }
        if let seasons = details?.seasons, !seasons.isEmpty { return false }
        return false
    }

    private func isSourceAvailable(_ source: MediaStreamSource) -> Bool {
        switch source {
        case .source1:
            guard let r = source1Result else { return false }
            if isProjectMovie && r.isSerial { return false }
            return !r.seasons.isEmpty || r.movie != nil
        case .source2:
            guard let r = source2Result?.apiResult else { return false }
            if isProjectMovie && r.isSerial { return false }
            return !r.seasons.isEmpty || r.movie != nil
        }
    }

    private var hasAnySource: Bool {
        isSourceAvailable(.source1) || isSourceAvailable(.source2)
    }

    private var isLikelySerial: Bool {
        if isProjectMovie { return false }
        if let seasons = details?.seasons, !seasons.isEmpty { return true }
        if let type = details?.type { return type.lowercased() == "tv" || type.lowercased() == "serial" || type.lowercased() == "series" }
        return false
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
                sourcesContentView
                    .opacity(isSelectingQuality ? 0 : 1)
                    .offset(x: isSelectingQuality ? -50 : 0)
                    .allowsHitTesting(!isSelectingQuality)

                qualitySelectionContentView
                    .opacity(isSelectingQuality ? 1 : 0)
                    .offset(x: isSelectingQuality ? 0 : 50)
                    .allowsHitTesting(isSelectingQuality)
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: isSelectingQuality)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        if isSelectingQuality {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                isSelectingQuality = false
                            }
                        } else {
                            dismiss()
                        }
                    } label: {
                        Image(systemName: isSelectingQuality ? "chevron.left" : "xmark")
                            .foregroundStyle(.primary)
                            .glassForeground()
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .tint(.primary)
                    .accessibilityLabel(isSelectingQuality ? "Назад" : "Закрыть")
                }

                ToolbarItem(placement: .principal) {
                    if isSelectingQuality {
                        Text("Качество видео")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .transition(.opacity)
                    } else {
                        headerTitleOrLogoView
                            .transition(.opacity)
                    }
                }

                if !isSelectingQuality {
                    ToolbarItem(placement: .topBarTrailing) {
                        sourceCornerButton
                            .transition(.opacity)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        .presentationDetents([.fraction(0.62)])
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
                    .frame(maxHeight: 28)
            } fallback: {
                fallbackHeaderTitle
            }
            .frame(maxWidth: 220)
        } else {
            fallbackHeaderTitle
        }
    }

    private var fallbackHeaderTitle: some View {
        Text(currentTitle)
            .font(.system(size: 18, weight: .semibold))
            .backdropForeground()
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: 220)
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
                .renderingMode(.template)
                .foregroundStyle(Color.primary)
                .glassForeground()
        }
        .tint(Color.primary)
        .foregroundStyle(Color.primary)
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
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .all)
        .contentMargins(.horizontal, 20, for: .scrollContent)
        .contentMargins(.top, 16, for: .scrollContent)
        .contentMargins(.bottom, 28, for: .scrollContent)
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
    private var sourcesContentView: some View {
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
    }

    @ViewBuilder
    private var currentSourceContentView: some View {
        if selectedSource == .source1 {
            if let res1 = source1Result, (!res1.seasons.isEmpty || res1.movie != nil) {
                let prepared = catalogCache.catalog(
                    for: .source1,
                    result: res1,
                    kpId: kpId,
                    details: details,
                    initialSeason: initialSeason,
                    initialEpisode: initialEpisode
                )
                SingleSourceContentView(
                    mode: mode,
                    source: .source1,
                    result: res1,
                    kpId: kpId,
                    details: details,
                    episodeSubtitles: [:],
                    movieSubtitles: [],
                    customHeaders: [:],
                    initialSeason: initialSeason,
                    initialEpisode: initialEpisode,
                    preparedCatalog: prepared
                ) { translation, season, episode, subs, headers in
                    handleCommit(
                        translation: translation,
                        season: season,
                        episode: episode,
                        subs: subs,
                        headers: headers,
                        source: .source1
                    )
                }
            } else {
                sourceUnavailableView(for: .source1)
            }
        } else {
            if let res2 = source2Result?.apiResult, (!res2.seasons.isEmpty || res2.movie != nil) {
                let prepared = catalogCache.catalog(
                    for: .source2,
                    result: res2,
                    kpId: kpId,
                    details: details,
                    initialSeason: initialSeason,
                    initialEpisode: initialEpisode
                )
                SingleSourceContentView(
                    mode: mode,
                    source: .source2,
                    result: res2,
                    kpId: kpId,
                    details: details,
                    episodeSubtitles: source2Result?.episodeSubtitles ?? [:],
                    movieSubtitles: source2Result?.movieSubtitles ?? [],
                    customHeaders: CollapsRepository.streamHeaders,
                    initialSeason: initialSeason,
                    initialEpisode: initialEpisode,
                    preparedCatalog: prepared
                ) { translation, season, episode, subs, headers in
                    handleCommit(
                        translation: translation,
                        season: season,
                        episode: episode,
                        subs: subs,
                        headers: headers,
                        source: .source2
                    )
                }
            } else {
                sourceUnavailableView(for: .source2)
            }
        }
    }

    private func handleCommit(
        translation: AllohaTranslation,
        season: Int?,
        episode: Int?,
        subs: [PlaybackSubtitle],
        headers: [String: String],
        source: MediaStreamSource
    ) {
        if preferredQuality == .ask {
            pendingCommit = PendingPlaybackCommit(
                translation: translation,
                season: season,
                episode: episode,
                subtitles: subs,
                customHeaders: headers,
                source: source
            )
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                isSelectingQuality = true
            }
        } else {
            onAction(translation, season, episode, preferredQuality, source, subs, headers)
            dismiss()
        }
    }

    @ViewBuilder
    private var qualitySelectionContentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                qualitySection

                rememberChoiceSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .all)
        .contentMargins(.horizontal, 20, for: .scrollContent)
        .contentMargins(.top, 16, for: .scrollContent)
        .contentMargins(.bottom, 28, for: .scrollContent)
        .safeAreaInset(edge: .bottom) {
            qualityBottomActionButton
        }
    }

    private var qualitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Качество")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.primary)

            FlowLayout(spacing: 8) {
                ForEach(availableQualities) { quality in
                    WatchSelectorChip(
                        title: quality.title,
                        isSelected: selectedQuality == quality,
                        isAvailable: true,
                        badge: qualityBadge(for: quality)
                    ) {
                        selectedQuality = quality
                    }
                    .equatable()
                }
            }
        }
    }

    private func qualityBadge(for quality: VideoQualityPreference) -> String? {
        switch quality {
        case .auto:
            return "Реком."
        case .q1080:
            return "HD"
        default:
            return nil
        }
    }

    private var rememberChoiceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $rememberQualityChoice) {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.slooshAccent)
                    Text("Запомнить выбор")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
            .tint(Color.slooshAccent)

            Text("Вы всегда можете изменить качество по умолчанию в настройках.")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(UIColor.secondarySystemFill).opacity(0.45))
        )
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    private var qualityBottomActionButton: some View {
        Button(action: {
            confirmQualityAndCommit()
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
        .padding(.bottom, 8)
    }

    private func confirmQualityAndCommit() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if rememberQualityChoice {
            preferredQuality = selectedQuality
            UserDefaults.standard.set(selectedQuality.rawValue, forKey: "preferredVideoQuality")
        }
        guard let pending = pendingCommit else {
            dismiss()
            return
        }
        onAction(
            pending.translation,
            pending.season,
            pending.episode,
            selectedQuality,
            pending.source,
            pending.subtitles,
            pending.customHeaders
        )
        dismiss()
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

// MARK: - Precomputed Catalog & Cache

struct PreparedSourceCatalog {
    let mediaKey: String
    let isSerial: Bool
    let index: AllohaSourceAvailabilityIndex
    let allTranslations: [TranslationChipItem]
    let translationAvailability: TranslationAvailabilityPolicy
    let initialSeason: Int?
    let initialEpisode: Int?
    let initialTranslationName: String?

    init(
        source: MediaStreamSource,
        result: AllohaApiResult,
        kpId: Int?,
        details: MediaDetailsDto?,
        requestedSeason: Int?,
        requestedEpisode: Int?
    ) {
        let effectiveIsSerial: Bool = {
            if let type = details?.type?.lowercased() {
                if type == "movie" { return false }
                if type == "tv" || type == "serial" || type == "series" { return true }
            }
            if let seasons = details?.seasons, !seasons.isEmpty { return true }
            return result.isSerial
        }()

        let index = AllohaSourceAvailabilityIndex(result: result, effectiveIsSerial: effectiveIsSerial)
        let displayNames = displayTranslationNames(for: index.sortedNames)
        let transItems = zip(index.sortedNames, displayNames).map { name, displayName in
            TranslationChipItem(
                id: name,
                name: name,
                displayName: displayName,
                studio: DubbingStudio.detect(from: name),
                flag: LanguageFlag.detect(from: name + " " + displayName)
            )
        }

        self.mediaKey = Self.resolveMediaKey(kpId: kpId, details: details)
        self.isSerial = effectiveIsSerial
        self.index = index
        self.allTranslations = transItems
        self.translationAvailability = TranslationAvailabilityPolicy(
            isSerial: effectiveIsSerial,
            movieNames: index.movieNames,
            seasonNames: index.exactNamesBySeason,
            episodeNames: index.exactNamesByEpisode
        )

        let initial = SingleSourceContentView.computeInitialSelection(
            result: result,
            index: index,
            kpId: kpId,
            details: details,
            sourceKey: source == .source2 ? "collaps" : "alloha",
            requestedSeason: requestedSeason,
            requestedEpisode: requestedEpisode
        )
        self.initialSeason = initial.season
        self.initialEpisode = initial.episode
        self.initialTranslationName = initial.translationName
    }

    static func resolveMediaKey(kpId: Int?, details: MediaDetailsDto?) -> String {
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
}

@MainActor
private final class SourceCatalogCache: ObservableObject {
    private struct Entry {
        let result: AllohaApiResult
        let kpId: Int?
        let initialSeason: Int?
        let initialEpisode: Int?
        let catalog: PreparedSourceCatalog
    }

    private var entries: [MediaStreamSource: Entry] = [:]

    func catalog(
        for source: MediaStreamSource,
        result: AllohaApiResult,
        kpId: Int?,
        details: MediaDetailsDto?,
        initialSeason: Int?,
        initialEpisode: Int?
    ) -> PreparedSourceCatalog {
        if let existing = entries[source],
           existing.kpId == kpId,
           existing.initialSeason == initialSeason,
           existing.initialEpisode == initialEpisode,
           existing.result == result {
            return existing.catalog
        }
        let built = PreparedSourceCatalog(
            source: source,
            result: result,
            kpId: kpId,
            details: details,
            requestedSeason: initialSeason,
            requestedEpisode: initialEpisode
        )
        entries[source] = Entry(
            result: result,
            kpId: kpId,
            initialSeason: initialSeason,
            initialEpisode: initialEpisode,
            catalog: built
        )
        return built
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
    let onCommit: (AllohaTranslation, Int?, Int?, [PlaybackSubtitle], [String: String]) -> Void

    @State private var selectedSeason: Int?
    @State private var selectedEpisode: Int?
    @State private var selectedTranslationName: String?
    @State private var topTranslationNames: Set<String> = []

    private let catalog: PreparedSourceCatalog
    let initialSeason: Int?
    let initialEpisode: Int?

    private var isProjectMovie: Bool {
        if let type = details?.type?.lowercased() {
            if type == "movie" { return true }
            if type == "tv" || type == "serial" || type == "series" { return false }
        }
        if let seasons = details?.seasons, !seasons.isEmpty { return false }
        return false
    }

    private var isSerial: Bool {
        if isProjectMovie { return false }
        return catalog.isSerial
    }

    var allTranslations: [TranslationChipItem] { catalog.allTranslations }
    var allSeasons: [Int] { catalog.index.sortedSeasons }
    var seasonEpisodes: [Int: [Int]] { catalog.index.episodesBySeason }

    init(
        mode: SourceSelectionMode,
        source: MediaStreamSource,
        result: AllohaApiResult,
        kpId: Int?,
        details: MediaDetailsDto?,
        episodeSubtitles: [EpisodeKey: [PlaybackSubtitle]],
        movieSubtitles: [PlaybackSubtitle],
        customHeaders: [String: String],
        initialSeason: Int? = nil,
        initialEpisode: Int? = nil,
        preparedCatalog: PreparedSourceCatalog? = nil,
        onCommit: @escaping (AllohaTranslation, Int?, Int?, [PlaybackSubtitle], [String: String]) -> Void
    ) {
        self.mode = mode
        self.source = source
        self.result = result
        self.kpId = kpId
        self.details = details
        self.episodeSubtitles = episodeSubtitles
        self.movieSubtitles = movieSubtitles
        self.customHeaders = customHeaders
        self.initialSeason = initialSeason
        self.initialEpisode = initialEpisode
        self.onCommit = onCommit

        let builtCatalog = preparedCatalog ?? PreparedSourceCatalog(
            source: source,
            result: result,
            kpId: kpId,
            details: details,
            requestedSeason: initialSeason,
            requestedEpisode: initialEpisode
        )
        self.catalog = builtCatalog

        _selectedSeason = State(initialValue: builtCatalog.initialSeason)
        _selectedEpisode = State(initialValue: builtCatalog.initialEpisode)
        _selectedTranslationName = State(initialValue: builtCatalog.initialTranslationName)
    }

    var allEpisodes: [Int] {
        guard let s = selectedSeason else { return [] }
        return seasonEpisodes[s] ?? []
    }

    // Instant O(1) Available checking
    func isTranslationAvailable(_ name: String) -> Bool {
        catalog.translationAvailability.isAvailable(name: name, season: selectedSeason, episode: selectedEpisode)
    }

    func seasonHasTranslation(season: Int, name: String) -> Bool {
        catalog.index.seasonHasTranslation(season: season, name: name)
    }

    func episodeHasTranslation(season: Int, episode: Int, name: String) -> Bool {
        catalog.index.episodeHasTranslation(season: season, episode: episode, name: name)
    }

    func isSeasonAvailable(_ seasonNum: Int) -> Bool {
        guard let tName = selectedTranslationName else { return true }
        return seasonHasTranslation(season: seasonNum, name: tName)
    }

    func isEpisodeAvailable(_ episodeNum: Int) -> Bool {
        guard let s = selectedSeason, let tName = selectedTranslationName else { return true }
        return episodeHasTranslation(season: s, episode: episodeNum, name: tName)
    }

    func preferredTranslation(in translations: [AllohaTranslation], preferredName: String?) -> AllohaTranslation? {
        bestTranslation(in: translations, preferredName: preferredName)
    }

    // Selection actions
    func selectTranslation(_ name: String) {
        selectedTranslationName = name
        if isSerial {
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
        if let currentE = e,
           let currentT = selectedTranslationName,
           !episodeHasTranslation(season: s, episode: currentE, name: currentT),
           let epObj = catalog.index.episode(season: s, episode: currentE),
           let bestT = bestTranslation(in: epObj.translations, preferredName: currentT) {
            selectedTranslationName = bestT.name
        }
    }

    func selectEpisode(_ e: Int) {
        selectedEpisode = e
        if let s = selectedSeason {
            if let currentT = selectedTranslationName {
                if !episodeHasTranslation(season: s, episode: e, name: currentT),
                   let epObj = catalog.index.episode(season: s, episode: e),
                   let bestT = bestTranslation(in: epObj.translations, preferredName: currentT) {
                    selectedTranslationName = bestT.name
                }
            } else if let epObj = catalog.index.episode(season: s, episode: e),
                      let bestT = bestTranslation(in: epObj.translations, preferredName: nil) {
                selectedTranslationName = bestT.name
            }
        }
    }

    var mediaKey: String {
        catalog.mediaKey
    }

    static func computeInitialSelection(
        result: AllohaApiResult,
        index: AllohaSourceAvailabilityIndex,
        kpId: Int?,
        details: MediaDetailsDto?,
        sourceKey: String,
        requestedSeason: Int? = nil,
        requestedEpisode: Int? = nil
    ) -> (season: Int?, episode: Int?, translationName: String?) {
        let currentKey = PreparedSourceCatalog.resolveMediaKey(kpId: kpId, details: details)

        var savedVoiceover = PlaybackProgressStore.shared.loadLastVoiceover(mediaKey: currentKey, source: sourceKey)
        if savedVoiceover == nil, let kpId, kpId > 0 {
            savedVoiceover = PlaybackProgressStore.shared.loadLastVoiceover(kpId: kpId, source: sourceKey)
        }
        if savedVoiceover == nil && sourceKey == "alloha",
           let globalVoiceover = UserDefaults.standard.string(forKey: "alloha_last_translation_name"),
           !isOriginalOrEnglishTranslation(globalVoiceover) {
            savedVoiceover = globalVoiceover
        }

        if index.isSerial {
            var initialSeason = requestedSeason ?? result.seasons.first?.season
            var initialEpisode: Int? = requestedEpisode

            if requestedSeason == nil {
                if let lastSeason = PlaybackProgressStore.shared.loadLastSeason(mediaKey: currentKey) ?? (kpId.flatMap { $0 > 0 ? PlaybackProgressStore.shared.loadLastSeason(kpId: $0) : nil }),
                   index.episodesBySeason[lastSeason] != nil {
                    initialSeason = lastSeason
                }
            }

            if requestedEpisode == nil {
                if let lastEpisode = PlaybackProgressStore.shared.loadLastEpisode(mediaKey: currentKey) ?? (kpId.flatMap { $0 > 0 ? PlaybackProgressStore.shared.loadLastEpisode(kpId: $0) : nil }) {
                    initialEpisode = lastEpisode

                    let sNum = initialSeason ?? 1
                    let mediaId = "\(currentKey)_s\(sNum)_e\(lastEpisode)"
                    if PlaybackProgressStore.shared.loadWatched(mediaId: mediaId) {
                        var foundCurrent = false
                        var nextPair: (Int, Int)?
                        outerLoop: for s in index.sortedSeasons {
                            for epNum in index.episodesBySeason[s] ?? [] {
                                if foundCurrent {
                                    nextPair = (s, epNum)
                                    break outerLoop
                                }
                                if s == initialSeason && epNum == lastEpisode {
                                    foundCurrent = true
                                }
                            }
                        }
                        if let nextPair {
                            initialSeason = nextPair.0
                            initialEpisode = nextPair.1
                        }
                    }
                }
            }

            if let seasonNum = initialSeason,
               let epNums = index.episodesBySeason[seasonNum], !epNums.isEmpty {
                let resolvedEpNum = initialEpisode.flatMap { index.episode(season: seasonNum, episode: $0) != nil ? $0 : nil } ?? epNums.first
                let epObj = resolvedEpNum.flatMap { index.episode(season: seasonNum, episode: $0) }
                let tName = epObj.flatMap { bestTranslation(in: $0.translations, preferredName: savedVoiceover)?.name }
                return (seasonNum, resolvedEpNum, tName)
            }
            return (initialSeason, initialEpisode, nil)
        } else {
            let movieTranslations = result.movie?.translations ?? result.seasons.first?.episodes.first?.translations ?? []
            let tName = bestTranslation(in: movieTranslations, preferredName: savedVoiceover)?.name
            return (nil, nil, tName)
        }
    }

    func actionSelected() {
        finishAction()
    }

    func finishAction() {
        let currentKey = mediaKey
        let sourceKey = source == .source2 ? "collaps" : "alloha"

        if isSerial {
            guard let s = selectedSeason, let e = selectedEpisode, let tName = selectedTranslationName else { return }
            guard let epObj = catalog.index.episode(season: s, episode: e),
                  let translation = epObj.translations.first(where: { $0.name == tName })
                      ?? epObj.translations.first(where: { allohaTranslationNamesMatch($0.name, tName, exactOnly: true) })
                      ?? epObj.translations.first(where: { allohaTranslationNamesMatch($0.name, tName, exactOnly: false) })
                      ?? bestTranslation(in: epObj.translations, preferredName: tName) else { return }

            if mode == .play {
                PlaybackProgressStore.shared.saveLastPlayed(mediaKey: currentKey, season: s, episode: e)
                PlaybackProgressStore.shared.saveLastVoiceover(mediaKey: currentKey, source: sourceKey, voiceover: translation.name)
                if let kpId = kpId, kpId > 0 {
                    PlaybackProgressStore.shared.saveLastPlayed(kpId: kpId, season: s, episode: e)
                    PlaybackProgressStore.shared.saveLastVoiceover(kpId: kpId, source: sourceKey, voiceover: translation.name)
                }
            }

            let subs = episodeSubtitles[EpisodeKey(season: s, episode: e)] ?? []
            onCommit(translation, s, e, subs, customHeaders)
        } else {
            let availableTranslations = result.movie?.translations ?? result.seasons.first?.episodes.first?.translations ?? []
            guard let tName = selectedTranslationName,
                  let translation = availableTranslations.first(where: { $0.name == tName })
                      ?? availableTranslations.first(where: { allohaTranslationNamesMatch($0.name, tName, exactOnly: true) })
                      ?? availableTranslations.first(where: { allohaTranslationNamesMatch($0.name, tName, exactOnly: false) })
                      ?? bestTranslation(in: availableTranslations, preferredName: tName) else { return }

            if mode == .play {
                PlaybackProgressStore.shared.saveLastPlayed(mediaKey: currentKey, season: nil, episode: nil)
                PlaybackProgressStore.shared.saveLastVoiceover(mediaKey: currentKey, source: sourceKey, voiceover: translation.name)
                if let kpId = kpId, kpId > 0 {
                    PlaybackProgressStore.shared.saveLastPlayed(kpId: kpId, season: nil, episode: nil)
                    PlaybackProgressStore.shared.saveLastVoiceover(kpId: kpId, source: sourceKey, voiceover: translation.name)
                }
            }

            let subs = movieSubtitles
            onCommit(translation, nil, nil, subs, customHeaders)
        }
    }

    var isReadyToPlay: Bool {
        guard selectedTranslationName != nil else { return false }
        if isSerial {
            return selectedSeason != nil && selectedEpisode != nil
        }
        return true
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                translationsSection

                if isSerial && !allSeasons.isEmpty {
                    seasonsSection
                    if !allEpisodes.isEmpty {
                        episodesSection
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .all)
        .contentMargins(.horizontal, 20, for: .scrollContent)
        .contentMargins(.top, 16, for: .scrollContent)
        .contentMargins(.bottom, 28, for: .scrollContent)
        .safeAreaInset(edge: .bottom) {
            bottomActionButton
        }
        .task {
            let key = mediaKey
            if key != "unknown",
               let stats = await PlaybackAnalyticsService.shared.fetchMediaStats(mediaKey: key),
               allTranslations.count > 1,
               let top = stats.topTranslation,
               top.count >= 2 {
                topTranslationNames = Set(
                    allTranslations.map(\.name).filter { allohaTranslationNamesMatch($0, top.translation) }
                )
            }
        }
    }

    private func translationBadge(for name: String) -> String? {
        topTranslationNames.contains(name) ? "🔥 Топ" : nil
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
                            isAvailable: isTranslationAvailable(item.name),
                            badge: translationBadge(for: item.name),
                            studio: item.studio,
                            flag: item.flag
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

