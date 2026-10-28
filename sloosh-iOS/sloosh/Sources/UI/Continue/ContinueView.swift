// ContinueWatching Engine v2.2
import SwiftUI

struct ContinueView: View {
    @StateObject private var viewModel = ContinueViewModel()
    @ObservedObject private var mediaOverrides = MediaOverridesRepository.shared
    @State private var scrollOffset: CGFloat = 0

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.items.isEmpty && !viewModel.isLoading {
                    ContinueEmptyState()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(viewModel.items) { item in
                                Button {
                                    Task {
                                        await viewModel.resume(item)
                                    }
                                } label: {
                                    ContinueWatchingCard(item: item)
                                }
                                .buttonStyle(.cardPress)
                                .disabled(viewModel.isLaunching)
                                .contextMenu {
                                    Group {
                                        NavigationLink(destination: DetailsView(movieId: item.metadata?.detailsId ?? (item.kpId > 0 ? "kp_\(item.kpId)" : item.rootMediaKey), mediaType: item.metadata?.type, navigationTransitionID: nil, navigationTransitionNamespace: nil).navigationBarBackButtonHidden(true)) {
                                            Label("Подробнее", systemImage: "info.circle")
                                        }
                                        if item.record.isEpisode {
                                            Button {
                                                viewModel.markCurrentEpisodeWatched(item)
                                            } label: {
                                                Label("Серия просмотрена", systemImage: "checkmark.circle")
                                            }
                                            Button {
                                                viewModel.markEntireSeriesWatched(item)
                                            } label: {
                                                Label("Весь сериал просмотрен", systemImage: "eye")
                                            }
                                        } else {
                                            Button {
                                                viewModel.markAsWatched(item)
                                            } label: {
                                                Label("Отметить просмотренным", systemImage: "eye")
                                            }
                                        }
                                        Button(role: .destructive) {
                                            viewModel.removeFromHistory(item)
                                        } label: {
                                            Label("Удалить из истории", systemImage: "trash")
                                        }
                                    }
                                    .tint(nil)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .scrollIndicators(.hidden)
                    .refreshable {
                        await CloudSyncService.shared.syncAllDataAsync(force: true)
                        await viewModel.reload(forceMetadataRefresh: true)
                    }
                    .onScrollGeometryChange(for: CGFloat.self) { geometry in
                        geometry.contentOffset.y + geometry.contentInsets.top
                    } action: { _, newOffset in
                        scrollOffset = newOffset
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                SlooshTopBar(
                    title: "Продолжить",
                    scrollOffset: $scrollOffset
                )
            }
            .overlay {
                if viewModel.isLoading && viewModel.items.isEmpty {
                    ProgressView()
                        .controlSize(.large)
                }
            }
            .onAppear {
                Task {
                    await CloudSyncService.shared.syncAllDataAsync()
                    await viewModel.reload()
                }
            }
            .fullScreenCover(item: $viewModel.activePresentation, onDismiss: {
                viewModel.activePresentation = nil
                AppDelegate.lockToPortrait()
                Task {
                    await viewModel.reload()
                }
            }) { presentation in
                if presentation.isReady, let playback = presentation.route {
                    PlayerView(
                        iframeUrl: playback.iframeUrl,
                        fallbackTitle: playback.title,
                        kpId: playback.kpId,
                        season: playback.season,
                        episode: playback.episode,
                        selectedVoiceover: playback.voiceover,
                        directStreamUrl: playback.streamUrl,
                        voices: playback.voices,
                        subtitles: playback.subtitles,
                        initialQuality: playback.initialQuality,
                        seriesResult: playback.seriesResult,
                        customHeaders: playback.customHeaders,
                        mediaKey: playback.mediaKey,
                        tmdbId: playback.tmdbId,
                        posterUrl: playback.posterUrl,
                        backdropUrl: playback.backdropUrl,
                        logoUrl: playback.logoUrl,
                        streamSource: playback.streamSource,
                        episodeSubtitles: playback.episodeSubtitles
                    )
                    .preferredColorScheme(.dark)
                    .environment(\.colorScheme, .dark)
                } else {
                    ZStack {
                        Color.black.edgesIgnoringSafeArea(.all)
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                    }
                    .preferredColorScheme(.dark)
                    .environment(\.colorScheme, .dark)
                }
            }
            .alert("Не удалось начать воспроизведение", isPresented: launchErrorBinding) {
                Button("OK", role: .cancel) {
                    viewModel.launchErrorMessage = nil
                }
            } message: {
                Text(viewModel.launchErrorMessage ?? "")
            }
        }
    }

    private var launchErrorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.launchErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.launchErrorMessage = nil
                }
            }
        )
    }
}

private struct ContinueWatchingItem: Identifiable {
    let record: PlaybackProgressRecord
    let metadata: PlaybackMediaMetadata?
    /// Труе если это следующий эпизод (предыдущий был досмотрен).
    let isNextEpisode: Bool

    var id: String { record.mediaId }

    var rootMediaKey: String { record.rootMediaKey }

    var kpId: Int { record.kpId }

    var tmdbId: Int? { record.tmdbId ?? metadata?.tmdbId }

    var title: String {
        metadata?.title ?? "Без названия"
    }

    var posterUrl: String? {
        let key = record.rootMediaKey
        if let override = MediaOverridesRepository.shared.override(for: key, tmdbId: tmdbId, kpId: kpId)?.posterUrl, !override.isEmpty {
            return override
        }
        return metadata?.posterUrl
    }

    var backdropUrl: String? {
        let key = record.rootMediaKey
        if let override = MediaOverridesRepository.shared.override(for: key, tmdbId: tmdbId, kpId: kpId)?.backdropUrl, !override.isEmpty {
            return override
        }
        return metadata?.backdropUrl
    }

    var logoUrl: String? {
        let key = record.rootMediaKey
        if let override = MediaOverridesRepository.shared.override(for: key, tmdbId: tmdbId, kpId: kpId)?.logoUrl, !override.isEmpty {
            return override
        }
        return metadata?.logoUrl
    }

    var progressFraction: Double {
        record.progressFraction
    }

    var subtitle: String? {
        if let season = record.season, let episode = record.episode {
            return "Сезон \(season), серия \(episode)"
        }
        return nil
    }

    var progressText: String {
        "\(ContinueTimeFormatter.playback(record.positionSec)) / \(ContinueTimeFormatter.playback(record.durationSec))"
    }

    var remainingText: String? {
        let remaining = max(record.durationSec - record.positionSec, 0)
        guard remaining > 60 else { return nil }
        return "Осталось \(ContinueTimeFormatter.shortDuration(remaining))"
    }

    var imageURL: URL? {
        let isLowQuality = UserDefaults.standard.string(forKey: "posterQuality") == "low"
        if let urlStr = backdropUrl ?? posterUrl, !urlStr.isEmpty {
            var finalUrlStr = urlStr
            if isLowQuality {
                if finalUrlStr.contains("/backdrops/") && finalUrlStr.contains("/original") {
                    finalUrlStr = finalUrlStr.replacingOccurrences(of: "/original", with: "/large")
                }
                if finalUrlStr.contains("/backdrops/") && finalUrlStr.contains("/small") {
                    finalUrlStr = finalUrlStr.replacingOccurrences(of: "/small", with: "/large")
                }
                if finalUrlStr.contains("/kp/") {
                    finalUrlStr = finalUrlStr.replacingOccurrences(of: "/kp/", with: "/kp_small/")
                }
            } else {
                if finalUrlStr.contains("/backdrops/") && finalUrlStr.contains("/large") {
                    finalUrlStr = finalUrlStr.replacingOccurrences(of: "/large", with: "/original")
                }
                if finalUrlStr.contains("/backdrops/") && finalUrlStr.contains("/small") {
                    finalUrlStr = finalUrlStr.replacingOccurrences(of: "/small", with: "/original")
                }
                if finalUrlStr.contains("/kp_small/") {
                    finalUrlStr = finalUrlStr.replacingOccurrences(of: "/kp_small/", with: "/kp/")
                }
            }
            
            finalUrlStr = adjustExternalImageUrl(urlStr: finalUrlStr, isLowQuality: isLowQuality)
            return URL(string: finalUrlStr)
        }
        return nil
    }

    @MainActor
    var voiceover: String? {
        if let v = record.voiceover, !v.isEmpty { return v }
        if let v = PlaybackProgressStore.shared.loadLastVoiceover(mediaKey: record.rootMediaKey), !v.isEmpty { return v }
        if record.kpId > 0, let v = PlaybackProgressStore.shared.loadLastVoiceover(kpId: record.kpId, source: "alloha"), !v.isEmpty { return v }
        if let g = UserDefaults.standard.string(forKey: "alloha_last_translation_name"), !isOriginalOrEnglishTranslation(g) { return g }
        return nil
    }
}

@MainActor
private final class ContinueViewModel: ObservableObject {
    @Published var items: [ContinueWatchingItem] = []
    @Published var isLoading = false
    @Published var isLaunching = false
    @Published var launchingTitle: String?
    @Published var activePresentation: ContinuePresentation?
    @Published var launchErrorMessage: String?

    private let store = PlaybackProgressStore.shared
    private var metadataBackfillAttempted = Set<String>()

    func reload(forceMetadataRefresh: Bool = false) async {
        if isLoading { return }

        isLoading = true
        defer { isLoading = false }

        let records = filteredRecords()
        let (initialItems, missingMetadataKeys) = makeItems(from: records)
        if !initialItems.isEmpty || items.isEmpty {
            items = initialItems
        }

        let keysToRefresh: Set<String>
        if forceMetadataRefresh {
            keysToRefresh = Set(initialItems.map(\.rootMediaKey))
        } else {
            keysToRefresh = missingMetadataKeys.subtracting(metadataBackfillAttempted)
        }

        guard !keysToRefresh.isEmpty else { return }
        metadataBackfillAttempted.formUnion(keysToRefresh)

        await backfillMetadata(for: keysToRefresh)

        let freshRecords = filteredRecords()
        let (refreshedItems, _) = makeItems(from: freshRecords)
        if !refreshedItems.isEmpty || freshRecords.isEmpty {
            items = refreshedItems
        }
    }

    private func filteredRecords() -> [PlaybackProgressRecord] {
        store.listProgressRecords()
            .filter { $0.updatedAtMs > 0 }
            .filter { $0.positionSec >= 5 || $0.watched }
            .sorted { $0.updatedAtMs > $1.updatedAtMs }
    }

    private func groupRecordsByEntity(_ records: [PlaybackProgressRecord]) -> [[PlaybackProgressRecord]] {
        var groups: [[PlaybackProgressRecord]] = []

        for record in records {
            let root = record.rootMediaKey
            let kp = record.kpId
            let tmdb = record.tmdbId
            let meta = store.loadMetadata(mediaKey: root) ?? (kp > 0 ? store.loadMetadata(kpId: kp) : nil)
            let effectiveKp = kp > 0 ? kp : (meta?.kpId ?? 0)
            let effectiveTmdb = tmdb ?? meta?.tmdbId
            let detailsId = meta?.detailsId

            let matchIndex = groups.firstIndex { group in
                group.contains { existing in
                    // 1. Literal root media key match
                    if existing.rootMediaKey == root { return true }

                    // 2. Kinopoisk ID match
                    if effectiveKp > 0 {
                        if existing.kpId > 0 && existing.kpId == effectiveKp { return true }
                        if let existMeta = store.loadMetadata(mediaKey: existing.rootMediaKey),
                           existMeta.kpId > 0 && existMeta.kpId == effectiveKp {
                            return true
                        }
                    }

                    // 3. TMDB ID match
                    if let effTmdb = effectiveTmdb, effTmdb > 0 {
                        if let existTmdb = existing.tmdbId, existTmdb == effTmdb { return true }
                        if let existMeta = store.loadMetadata(mediaKey: existing.rootMediaKey),
                           let emTmdb = existMeta.tmdbId, emTmdb == effTmdb {
                            return true
                        }
                    }

                    // 4. Details ID match
                    if let dId = detailsId, !dId.isEmpty {
                        if let existMeta = store.loadMetadata(mediaKey: existing.rootMediaKey),
                           existMeta.detailsId == dId {
                            return true
                        }
                    }

                    return false
                }
            }

            if let idx = matchIndex {
                groups[idx].append(record)
            } else {
                groups.append([record])
            }
        }

        return groups
    }

    private func makeItems(from records: [PlaybackProgressRecord]) -> ([ContinueWatchingItem], Set<String>) {
        let entityGroups = groupRecordsByEntity(records)
        var missingMetadataKeys = Set<String>()

        let items = entityGroups.compactMap { group -> ContinueWatchingItem? in
            // Deduplicate multiple records for the exact same episode or movie
            var dedupedByEpisode: [String: PlaybackProgressRecord] = [:]
            for r in group {
                let epKey = "\(r.season ?? 0)_\(r.episode ?? 0)"
                if let existing = dedupedByEpisode[epKey] {
                    if (r.watched && !existing.watched) || r.updatedAtMs > existing.updatedAtMs {
                        dedupedByEpisode[epKey] = r
                    }
                } else {
                    dedupedByEpisode[epKey] = r
                }
            }
            let dedupedGroup = Array(dedupedByEpisode.values)

            guard let latestRecord = dedupedGroup.max(by: { $0.updatedAtMs < $1.updatedAtMs }) else { return nil }

            // If the series has been explicitly marked as fully watched, do not display it
            if latestRecord.isEpisode && store.isSeriesMarkedWatched(mediaKey: latestRecord.rootMediaKey, kpId: latestRecord.kpId, tmdbId: latestRecord.tmdbId) {
                return nil
            }

            let displayRecord: PlaybackProgressRecord
            if latestRecord.watched, let nextRecord = nextEpisodeRecord(after: latestRecord, in: dedupedGroup, allRecords: records) {
                displayRecord = nextRecord
            } else if latestRecord.watched && latestRecord.isEpisode {
                if let virtualNext = virtualNextEpisodeRecord(after: latestRecord) {
                    displayRecord = virtualNext
                } else {
                    return nil
                }
            } else if !latestRecord.watched && latestRecord.positionSec >= 5 {
                displayRecord = latestRecord
            } else if latestRecord.watched {
                // Фильм досмотрен (>= 95%) — скрываем из «Продолжить»
                return nil
            } else {
                // Меньше 5 секунд — не показываем
                return nil
            }

            let metadata = store.loadMetadata(mediaKey: latestRecord.rootMediaKey)
                ?? (latestRecord.kpId > 0 ? store.loadMetadata(kpId: latestRecord.kpId) : nil)
                ?? (latestRecord.tmdbId.flatMap { $0 > 0 ? store.loadMetadata(mediaKey: "tmdb_\($0)") : nil })
            if metadata == nil || (metadata?.posterUrl == nil && metadata?.backdropUrl == nil) {
                missingMetadataKeys.insert(latestRecord.rootMediaKey)
            }
            return ContinueWatchingItem(
                record: displayRecord,
                metadata: metadata,
                isNextEpisode: displayRecord.mediaId != latestRecord.mediaId || (latestRecord.watched && displayRecord.isEpisode)
            )
        }
        .sorted { $0.record.updatedAtMs > $1.record.updatedAtMs }

        return (items, missingMetadataKeys)
    }

    /// Ищет запись следующего эпизода в уже просмотренной истории (пользователь открывал его).
    private func nextEpisodeRecord(
        after current: PlaybackProgressRecord,
        in group: [PlaybackProgressRecord],
        allRecords: [PlaybackProgressRecord]
    ) -> PlaybackProgressRecord? {
        guard let currentSeason = current.season, let currentEpisode = current.episode else { return nil }
        // Ищем в истории запись, которая идёт хронологически следующей после current
        return group
            .filter { !$0.watched }
            .filter { $0.positionSec >= 15 }
            .filter { record in
                guard let s = record.season, let e = record.episode else { return false }
                return (s == currentSeason && e > currentEpisode) || s > currentSeason
            }
            .min { lhs, rhs in
                let ls = lhs.season ?? 0; let le = lhs.episode ?? 0
                let rs = rhs.season ?? 0; let re = rhs.episode ?? 0
                return ls != rs ? ls < rs : le < re
            }
    }

    /// Создаёт виртуальную запись следующего эпизода (которого пользователь ещё не открывал).
    /// Используется, чтобы показать кнопку «Смотреть следующую серию», даже если записи нет в истории.
    private func virtualNextEpisodeRecord(after current: PlaybackProgressRecord) -> PlaybackProgressRecord? {
        guard let season = current.season, let episode = current.episode else { return nil }
        if store.isSeriesMarkedWatched(mediaKey: current.rootMediaKey, kpId: current.kpId, tmdbId: current.tmdbId) {
            return nil
        }
        let nextEpisode = episode + 1
        let nextMediaId = "\(current.rootMediaKey)_s\(season)_e\(nextEpisode)"
        return PlaybackProgressRecord(
            mediaId: nextMediaId,
            kpId: current.kpId,
            tmdbId: current.tmdbId,
            season: season,
            episode: nextEpisode,
            voiceover: current.voiceover,
            positionSec: 0,
            durationSec: 0,
            watched: false,
            updatedAtMs: current.updatedAtMs
        )
    }

    private func backfillMetadata(for keys: Set<String>) async {
        for key in keys {
            let queryId: String
            if key.hasPrefix("kp_") {
                queryId = key
            } else if key.hasPrefix("tmdb_") {
                queryId = String(key.dropFirst(5))
            } else {
                queryId = key
            }
            do {
                if let details = try await MoviesRepository.shared.getDetails(id: queryId) {
                    store.saveMetadata(details: details)
                }
            } catch {
                continue
            }
        }
    }

    func resume(_ item: ContinueWatchingItem) async {
        if isLaunching { return }

        isLaunching = true
        launchingTitle = item.title
        launchErrorMessage = nil
        
        let presId = abs(item.rootMediaKey.hashValue)
        // Показываем загрузочный экран плеера моментально
        activePresentation = ContinuePresentation(id: presId, isReady: false, title: item.title, route: nil)
        
        defer {
            isLaunching = false
            launchingTitle = nil
        }

        // Determine which source to try first:
        // 1. Last used source for this specific item (from store)
        // 2. User's preferred stream source setting from Settings
        let lastSource = store.loadLastStreamSource(mediaKey: item.rootMediaKey)
            ?? (item.kpId > 0 ? store.loadLastStreamSource(mediaKey: "kp_\(item.kpId)") : nil)
        let preferredSourceSetting = UserDefaults.standard.string(forKey: "preferredStreamSource") ?? MediaStreamSource.source1.rawValue
        let initialSource: MediaStreamSource = lastSource ?? (preferredSourceSetting == MediaStreamSource.source2.rawValue ? .source2 : .source1)

        var route: ContinuePlaybackRoute? = nil

        if initialSource == .source2 {
            // Try Backup (Collaps) first, fall back to Primary (Alloha)
            route = await resolveCollaps(for: item)
            if route == nil {
                route = await resolveAlloha(for: item)
            }
        } else {
            // Try Primary (Alloha) first, fall back to Backup (Collaps)
            route = await resolveAlloha(for: item)
            if route == nil {
                route = await resolveCollaps(for: item)
            }
        }

        guard let finalRoute = route else {
            activePresentation = nil
            launchErrorMessage = "Не удалось подобрать источник для продолжения просмотра."
            return
        }

        // Обновляем презентацию In-Place (ID тот же, поэтому SwiftUI просто обновит содержимое модального окна)
        activePresentation = ContinuePresentation(id: presId, isReady: true, title: item.title, route: finalRoute)
    }

    private func resolveAlloha(for item: ContinueWatchingItem) async -> ContinuePlaybackRoute? {
        do {
            let result = try await AllohaRepository.shared.fetchMedia(
                kpId: item.kpId > 0 ? item.kpId : nil,
                tmdbId: item.tmdbId,
                title: item.title
            )
            return makePlaybackRoute(
                for: item,
                result: result,
                source: .source1,
                customHeaders: nil,
                movieSubtitles: [],
                episodeSubtitles: [:]
            )
        } catch {
            return nil
        }
    }

    private func resolveCollaps(for item: ContinueWatchingItem) async -> ContinuePlaybackRoute? {
        do {
            guard let parseResult = try await CollapsRepository.shared.fetchMedia(
                kpId: item.kpId > 0 ? item.kpId : nil,
                imdbId: nil,
                title: item.title
            ) else {
                return nil
            }
            return makePlaybackRoute(
                for: item,
                result: parseResult.apiResult,
                source: .source2,
                customHeaders: CollapsRepository.streamHeaders,
                movieSubtitles: parseResult.movieSubtitles,
                episodeSubtitles: parseResult.episodeSubtitles
            )
        } catch {
            return nil
        }
    }

    private func makePlaybackRoute(
        for item: ContinueWatchingItem,
        result: AllohaApiResult,
        source: MediaStreamSource,
        customHeaders: [String: String]?,
        movieSubtitles: [PlaybackSubtitle],
        episodeSubtitles: [EpisodeKey: [PlaybackSubtitle]]
    ) -> ContinuePlaybackRoute? {
        let preferredQuality = preferredQualityForResume()
        let sourceKey = source == .source2 ? "collaps" : "alloha"
        let savedVoiceover = store.loadLastVoiceover(mediaKey: item.rootMediaKey, source: sourceKey)
            ?? (item.kpId > 0 ? store.loadLastVoiceover(kpId: item.kpId, source: sourceKey) : nil)
            ?? item.voiceover

        if result.isSerial {
            let targetSeason = item.record.season
                ?? store.loadLastSeason(mediaKey: item.rootMediaKey)
                ?? (item.kpId > 0 ? store.loadLastSeason(kpId: item.kpId) : nil)
                ?? result.seasons.first?.season

            guard let targetSeason else { return nil }

            let targetEpisode = item.record.episode
                ?? store.loadLastEpisode(mediaKey: item.rootMediaKey)
                ?? (item.kpId > 0 ? store.loadLastEpisode(kpId: item.kpId) : nil)

            var chosenSeason = result.seasons.first(where: { $0.season == targetSeason })
            var chosenEpisode = targetEpisode.flatMap { epNum in
                chosenSeason?.episodes.first(where: { $0.episode == epNum })
            }

            // Если запрашиваемый эпизод не найден (например, завершился сезон, и виртуальный эпизод +1 вышел за рамки),
            // то ищем хронологически следующий по всему сериалу.
            if chosenEpisode == nil, item.isNextEpisode, let epNum = targetEpisode {
                let lastWatchedEpisode = epNum - 1
                let allEpisodes = result.seasons
                    .flatMap { s in s.episodes }
                    .sorted { a, b in
                        if a.season != b.season {
                            return a.season < b.season
                        }
                        return a.episode < b.episode
                    }

                if let currentIndex = allEpisodes.firstIndex(where: { $0.season == targetSeason && $0.episode == lastWatchedEpisode }) {
                    let nextIndex = currentIndex + 1
                    if nextIndex < allEpisodes.count {
                        let nextEp = allEpisodes[nextIndex]
                        chosenSeason = result.seasons.first(where: { $0.season == nextEp.season })
                        chosenEpisode = nextEp
                    } else {
                        // Сериал полностью просмотрен — остаемся на последней просмотренной серии
                        chosenSeason = result.seasons.first(where: { $0.season == targetSeason })
                        chosenEpisode = chosenSeason?.episodes.first(where: { $0.episode == lastWatchedEpisode })
                    }
                }
            }

            let finalSeason = chosenSeason ?? result.seasons.first(where: { $0.season == targetSeason }) ?? result.seasons.first
            guard let finalSeason else { return nil }

            let finalEpisode = chosenEpisode ?? targetEpisode.flatMap { epNum in
                finalSeason.episodes.first(where: { $0.episode == epNum })
            } ?? finalSeason.episodes.first

            guard let finalEpisode else { return nil }

            let translation = preferredTranslation(
                in: finalEpisode.translations,
                preferredVoiceover: savedVoiceover
            )

            guard let translation else { return nil }

            store.saveLastPlayed(mediaKey: item.rootMediaKey, season: finalSeason.season, episode: finalEpisode.episode)
            store.saveLastVoiceover(mediaKey: item.rootMediaKey, source: sourceKey, voiceover: translation.name)
            store.saveLastStreamSource(mediaKey: item.rootMediaKey, source: source)
            if item.kpId > 0 {
                store.saveLastPlayed(kpId: item.kpId, season: finalSeason.season, episode: finalEpisode.episode)
                store.saveLastVoiceover(kpId: item.kpId, source: sourceKey, voiceover: translation.name)
                store.saveLastStreamSource(mediaKey: "kp_\(item.kpId)", source: source)
            }

            let subs = episodeSubtitles[EpisodeKey(season: finalSeason.season, episode: finalEpisode.episode)] ?? []

            return ContinuePlaybackRoute(
                iframeUrl: translation.iframeUrl.isEmpty ? nil : translation.iframeUrl,
                title: item.title,
                kpId: item.kpId,
                season: finalSeason.season,
                episode: finalEpisode.episode,
                voiceover: translation.name,
                streamUrl: (source == .source2 && translation.streamUrl?.isEmpty == false) ? translation.streamUrl : nil,
                voices: result.allTranslationNames,
                initialQuality: preferredQuality,
                seriesResult: result,
                mediaKey: item.rootMediaKey,
                tmdbId: item.tmdbId,
                posterUrl: item.posterUrl,
                backdropUrl: item.backdropUrl,
                logoUrl: item.logoUrl,
                streamSource: source,
                customHeaders: customHeaders,
                subtitles: subs,
                episodeSubtitles: episodeSubtitles
            )
        }

        guard let movie = result.movie else { return nil }
        guard let translation = preferredTranslation(
            in: movie.translations,
            preferredVoiceover: savedVoiceover
        ) else {
            return nil
        }

        store.saveLastPlayed(mediaKey: item.rootMediaKey, season: nil, episode: nil)
        store.saveLastVoiceover(mediaKey: item.rootMediaKey, source: sourceKey, voiceover: translation.name)
        store.saveLastStreamSource(mediaKey: item.rootMediaKey, source: source)
        if item.kpId > 0 {
            store.saveLastPlayed(kpId: item.kpId, season: nil, episode: nil)
            store.saveLastVoiceover(kpId: item.kpId, source: sourceKey, voiceover: translation.name)
            store.saveLastStreamSource(mediaKey: "kp_\(item.kpId)", source: source)
        }

        return ContinuePlaybackRoute(
            iframeUrl: translation.iframeUrl.isEmpty ? nil : translation.iframeUrl,
            title: item.title,
            kpId: item.kpId,
            season: nil,
            episode: nil,
            voiceover: translation.name,
            streamUrl: (source == .source2 && translation.streamUrl?.isEmpty == false) ? translation.streamUrl : nil,
            voices: result.allTranslationNames,
            initialQuality: preferredQuality,
            seriesResult: result,
            mediaKey: item.rootMediaKey,
            tmdbId: item.tmdbId,
            posterUrl: item.posterUrl,
            backdropUrl: item.backdropUrl,
            logoUrl: item.logoUrl,
            streamSource: source,
            customHeaders: customHeaders,
            subtitles: movieSubtitles,
            episodeSubtitles: [:]
        )
    }

    func markAsWatched(_ item: ContinueWatchingItem) {
        store.markAsWatched(mediaId: item.record.mediaId)
        Task { await reload() }
    }

    func markCurrentEpisodeWatched(_ item: ContinueWatchingItem) {
        store.markAsWatched(mediaId: item.record.mediaId)
        Task { await reload() }
    }

    func markEntireSeriesWatched(_ item: ContinueWatchingItem) {
        store.markSeriesWatched(mediaKey: item.rootMediaKey, kpId: item.kpId > 0 ? item.kpId : nil, tmdbId: item.tmdbId)
        Task { await reload() }
    }

    func removeFromHistory(_ item: ContinueWatchingItem) {
        store.removeHistory(for: item.rootMediaKey, kpId: item.kpId > 0 ? item.kpId : nil, tmdbId: item.tmdbId)
        store.removeRecord(mediaId: item.record.mediaId)
        Task { await reload() }
    }

    private func preferredTranslation(in translations: [AllohaTranslation], preferredVoiceover: String?) -> AllohaTranslation? {
        bestTranslation(in: translations, preferredName: preferredVoiceover)
    }

    private func preferredQualityForResume() -> VideoQualityPreference? {
        let rawValue = UserDefaults.standard.string(forKey: "preferredVideoQuality") ?? VideoQualityPreference.ask.rawValue
        let preference = VideoQualityPreference(rawValue: rawValue) ?? .ask
        return preference == .ask ? .auto : preference
    }
}

private struct ContinuePlaybackRoute: Identifiable {
    let id = UUID()
    let iframeUrl: String?
    let title: String
    let kpId: Int
    let season: Int?
    let episode: Int?
    let voiceover: String?
    let streamUrl: String?
    let voices: [String]
    let initialQuality: VideoQualityPreference?
    let seriesResult: AllohaApiResult?
    let mediaKey: String
    let tmdbId: Int?
    let posterUrl: String?
    let backdropUrl: String?
    let logoUrl: String?
    let streamSource: MediaStreamSource
    let customHeaders: [String: String]?
    let subtitles: [PlaybackSubtitle]
    let episodeSubtitles: [EpisodeKey: [PlaybackSubtitle]]
}

private struct ContinuePresentation: Identifiable {
    let id: Int // kpId
    var isReady: Bool = false
    var title: String
    var route: ContinuePlaybackRoute?
}

private struct ContinueWatchingCard: View {
    let item: ContinueWatchingItem
    @ObservedObject private var mediaOverrides = MediaOverridesRepository.shared

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ContinueArtworkView(url: item.imageURL)

            LinearGradient(
                colors: [
                    .black.opacity(0.10),
                    .black.opacity(0.28),
                    .black.opacity(0.88)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 12) {
                Spacer(minLength: 0)

                // Бейдж «Следующая серия»
                if item.isNextEpisode {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text("Следующая серия")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.white, in: Capsule())
                }

                HStack(alignment: .bottom, spacing: 10) {
                    if let logoStr = item.logoUrl, let logoUrl = URL(string: logoStr) {
                        AsyncCachedImage(url: logoUrl) {
                            Text(item.title)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(.white)
                                .blendMode(.plusLighter)
                                .lineLimit(2)
                        } content: { image in
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: 180, maxHeight: 42, alignment: .leading)
                                .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 2)
                        } fallback: {
                            Text(item.title)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(.white)
                                .blendMode(.plusLighter)
                                .lineLimit(2)
                        }
                    } else {
                        Text(item.title)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                            .blendMode(.plusLighter)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 8)

                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.72))
                            .blendMode(.plusLighter)
                            .lineLimit(1)
                            .layoutPriority(1)
                    }
                }

                if item.isNextEpisode {
                    // Для следующей серии прогресс-бар не показываем
                    EmptyView()
                } else {
                    ContinueProgressBar(progress: item.progressFraction)

                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(item.progressText)
                            .font(.system(size: 12.5, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.92))
                            .blendMode(.plusLighter)

                        Spacer(minLength: 0)

                        if let remainingText = item.remainingText {
                            Text(remainingText)
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(.white.opacity(0.70))
                                .blendMode(.plusLighter)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 8)
    }
}

private struct ContinueArtworkView: View {
    let url: URL?

    var body: some View {
        AsyncCachedImage(url: url) {
            Rectangle()
                .fill(Color.gray.opacity(0.18))
                .overlay {
                    Rectangle()
                        .fill(Color.gray.opacity(0.12))
                        .shimmer()
                }
        } content: { image in
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } fallback: {
            ContinueArtworkPlaceholder()
        }
        .background(Color(UIColor.secondarySystemFill))
    }
}

private struct ContinueArtworkPlaceholder: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(UIColor.secondarySystemFill),
                    Color(UIColor.tertiarySystemFill)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: "play.rectangle.on.rectangle.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

private struct ContinueProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.20))

                Capsule()
                    .fill(.white)
                    .frame(width: geometry.size.width * max(0, min(progress, 1)))
            }
        }
        .frame(height: 4.5)
        .blendMode(.plusLighter)
    }
}

private struct ContinueEmptyState: View {
    var body: some View {
        AppEmptyStateView(
            icon: "clock.arrow.circlepath",
            title: "Пока нечего продолжать",
            description: "Фильмы и серии, которые ты уже начал смотреть, появятся здесь с прогрессом и временем."
        )
    }
}

private enum ContinueTimeFormatter {
    static func playback(_ seconds: Double) -> String {
        let clamped = max(Int(seconds.rounded()), 0)
        let hours = clamped / 3600
        let minutes = (clamped % 3600) / 60
        let secs = clamped % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }

        return String(format: "%d:%02d", minutes, secs)
    }

    static func shortDuration(_ seconds: Double) -> String {
        let clamped = max(Int(seconds.rounded()), 0)
        let hours = clamped / 3600
        let minutes = (clamped % 3600) / 60

        if hours > 0 {
            return minutes > 0 ? "\(hours) ч \(minutes) мин" : "\(hours) ч"
        }

        if minutes > 0 {
            return "\(minutes) мин"
        }

        return "\(max(clamped, 1)) сек"
    }
}
