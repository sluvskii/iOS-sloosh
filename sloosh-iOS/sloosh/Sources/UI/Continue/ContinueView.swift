import SwiftUI

struct ContinueView: View {
    @StateObject private var viewModel = ContinueViewModel()

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
                                .buttonStyle(ScaleButtonStyle())
                                .disabled(viewModel.isLaunching)
                                .contextMenu {
                                    Group {
                                        NavigationLink(destination: DetailsView(movieId: item.metadata?.detailsId ?? (item.kpId > 0 ? "kp_\(item.kpId)" : item.id), mediaType: item.metadata?.type, navigationTransitionID: nil, navigationTransitionNamespace: nil).navigationBarBackButtonHidden(true)) {
                                            Label("Подробнее", systemImage: "info.circle")
                                        }
                                        Button {
                                            viewModel.markAsWatched(item)
                                        } label: {
                                            Label("Отметить просмотренным", systemImage: "eye")
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
                        await viewModel.reload(forceMetadataRefresh: true)
                    }
                }
            }
            .navigationTitle("Продолжить")
            .overlay {
                if viewModel.isLoading && viewModel.items.isEmpty {
                    ProgressView()
                        .controlSize(.large)
                }
            }
            .onAppear {
                Task {
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
                        subtitles: [],
                        initialQuality: playback.initialQuality,
                        seriesResult: playback.seriesResult,
                        mediaKey: playback.mediaKey,
                        tmdbId: playback.tmdbId,
                        posterUrl: playback.posterUrl,
                        backdropUrl: playback.backdropUrl,
                        logoUrl: playback.logoUrl
                    )
                } else {
                    ZStack {
                        Color.black.edgesIgnoringSafeArea(.all)
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                    }
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
        metadata?.posterUrl
    }

    var backdropUrl: String? {
        metadata?.backdropUrl
    }

    var logoUrl: String? {
        metadata?.logoUrl
    }

    var progressFraction: Double {
        record.progressFraction
    }

    var subtitle: String? {
        if let season = record.season, let episode = record.episode {
            return "Сезон \(season) • Серия \(episode)"
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
        record.voiceover ??
        PlaybackProgressStore.shared.loadLastVoiceover(mediaKey: record.rootMediaKey) ??
        (record.kpId > 0 ? PlaybackProgressStore.shared.loadLastVoiceover(kpId: record.kpId, source: "alloha") : nil) ??
        UserDefaults.standard.string(forKey: "alloha_last_translation_name")
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

    private func makeItems(from records: [PlaybackProgressRecord]) -> ([ContinueWatchingItem], Set<String>) {
        let grouped = Dictionary(grouping: records, by: \.rootMediaKey)
        var missingMetadataKeys = Set<String>()

        let items = grouped.values.compactMap { group -> ContinueWatchingItem? in
            // Берём запись, которую нужно показать пользователю.
            // Для сериалов: если последний просмотренный эпизод досмотрен (watched),
            // ищем следующий эпизод по номеру сезона/серии.
            guard let latestRecord = group.max(by: { $0.updatedAtMs < $1.updatedAtMs }) else { return nil }

            let displayRecord: PlaybackProgressRecord
            if latestRecord.watched, let nextRecord = nextEpisodeRecord(after: latestRecord, in: group, allRecords: records) {
                displayRecord = nextRecord
            } else if latestRecord.watched && latestRecord.isEpisode {
                // Досмотрен и следующего эпизода в истории нет — создаём виртуальную запись для следующего
                displayRecord = virtualNextEpisodeRecord(after: latestRecord) ?? latestRecord
            } else if !latestRecord.watched && latestRecord.positionSec >= 5 {
                displayRecord = latestRecord
            } else if latestRecord.watched {
                // Фильм досмотрен (>= 95%) — скрываем из «Продолжить»
                return nil
            } else {
                // Меньше 5 секунд — не показываем
                return nil
            }

            let metadata = store.loadMetadata(mediaKey: latestRecord.rootMediaKey) ?? (latestRecord.kpId > 0 ? store.loadMetadata(kpId: latestRecord.kpId) : nil)
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

        do {
            let result = try await AllohaRepository.shared.fetchMedia(
                kpId: item.kpId > 0 ? item.kpId : nil,
                tmdbId: item.tmdbId,
                title: item.title
            )
            guard let route = makePlaybackRoute(for: item, result: result) else {
                activePresentation = nil
                launchErrorMessage = "Не удалось подобрать источник для продолжения просмотра."
                return
            }

            // Обновляем презентацию In-Place (ID тот же, поэтому SwiftUI просто обновит содержимое модального окна)
            activePresentation = ContinuePresentation(id: presId, isReady: true, title: item.title, route: route)
        } catch {
            activePresentation = nil
            launchErrorMessage = "Не удалось загрузить источник. Попробуй еще раз."
        }
    }

    private func makePlaybackRoute(for item: ContinueWatchingItem, result: AllohaApiResult) -> ContinuePlaybackRoute? {
        let preferredQuality = preferredQualityForResume()
        let savedVoiceover = item.voiceover

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
            store.saveLastVoiceover(mediaKey: item.rootMediaKey, source: "alloha", voiceover: translation.name)
            if item.kpId > 0 {
                store.saveLastPlayed(kpId: item.kpId, season: finalSeason.season, episode: finalEpisode.episode)
                store.saveLastVoiceover(kpId: item.kpId, source: "alloha", voiceover: translation.name)
            }

            return ContinuePlaybackRoute(
                iframeUrl: translation.iframeUrl,
                title: item.title,
                kpId: item.kpId,
                season: finalSeason.season,
                episode: finalEpisode.episode,
                voiceover: translation.name,
                streamUrl: translation.streamUrl,
                voices: result.allTranslationNames,
                initialQuality: preferredQuality,
                seriesResult: result,
                mediaKey: item.rootMediaKey,
                tmdbId: item.tmdbId,
                posterUrl: item.posterUrl,
                backdropUrl: item.backdropUrl,
                logoUrl: item.logoUrl
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
        store.saveLastVoiceover(mediaKey: item.rootMediaKey, source: "alloha", voiceover: translation.name)
        if item.kpId > 0 {
            store.saveLastPlayed(kpId: item.kpId, season: nil, episode: nil)
            store.saveLastVoiceover(kpId: item.kpId, source: "alloha", voiceover: translation.name)
        }

        return ContinuePlaybackRoute(
            iframeUrl: translation.iframeUrl,
            title: item.title,
            kpId: item.kpId,
            season: nil,
            episode: nil,
            voiceover: translation.name,
            streamUrl: translation.streamUrl,
            voices: result.allTranslationNames,
            initialQuality: preferredQuality,
            seriesResult: result,
            mediaKey: item.rootMediaKey,
            tmdbId: item.tmdbId,
            posterUrl: item.posterUrl,
            backdropUrl: item.backdropUrl,
            logoUrl: item.logoUrl
        )
    }

    func markAsWatched(_ item: ContinueWatchingItem) {
        store.markAsWatched(mediaId: item.record.mediaId)
        Task { await reload() }
    }

    func removeFromHistory(_ item: ContinueWatchingItem) {
        store.removeRecord(mediaId: item.record.mediaId)
        Task { await reload() }
    }

    private func preferredTranslation(in translations: [AllohaTranslation], preferredVoiceover: String?) -> AllohaTranslation? {
        guard !translations.isEmpty else { return nil }

        // 1. Try specified voiceover (per-show preference) - exact match
        if let preferredVoiceover,
           let translation = translations.first(where: { allohaTranslationNamesMatch($0.name, preferredVoiceover, exactOnly: true) }) {
            return translation
        }

        // 1b. Try specified voiceover (per-show preference) - fuzzy/studio match
        if let preferredVoiceover,
           let translation = translations.first(where: { allohaTranslationNamesMatch($0.name, preferredVoiceover, exactOnly: false) }) {
            return translation
        }

        // 2. Try global preferred voiceover
        if let globalVoiceover = UserDefaults.standard.string(forKey: "alloha_last_translation_name"),
           let translation = translations.first(where: { allohaTranslationNamesMatch($0.name, globalVoiceover, exactOnly: false) }) {
            return translation
        }

        // 3. Fallback to first available
        return translations.first
    }

    private func preferredQualityForResume() -> VideoQualityPreference? {
        let rawValue = UserDefaults.standard.string(forKey: "preferredVideoQuality") ?? VideoQualityPreference.ask.rawValue
        let preference = VideoQualityPreference(rawValue: rawValue) ?? .ask
        return preference == .ask ? .auto : preference
    }
}

private struct ContinuePlaybackRoute: Identifiable {
    let id = UUID()
    let iframeUrl: String
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
}

private struct ContinuePresentation: Identifiable {
    let id: Int // kpId
    var isReady: Bool = false
    var title: String
    var route: ContinuePlaybackRoute?
}

private struct ContinueWatchingCard: View {
    let item: ContinueWatchingItem

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

                VStack(alignment: .leading, spacing: 4) {
                    if let logoStr = item.logoUrl, let logoUrl = URL(string: logoStr) {
                        AsyncCachedImage(url: logoUrl) {
                            Text(item.title)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                        } content: { image in
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: 180, maxHeight: 44, alignment: .leading)
                                .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 2)
                        } fallback: {
                            Text(item.title)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                        }
                    } else {
                        Text(item.title)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                    }

                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.74))
                            .lineLimit(1)
                    }
                }

                if item.isNextEpisode {
                    // Для следующей серии прогресс-бар не показываем
                    EmptyView()
                } else {
                    ContinueProgressBar(progress: item.progressFraction)

                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(item.progressText)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.92))

                        Spacer(minLength: 0)

                        if let remainingText = item.remainingText {
                            Text(remainingText)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.72))
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
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
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
                    .fill(.white.opacity(0.18))

                Capsule()
                    .fill(Color.slooshAccent)
                    .frame(width: geometry.size.width * max(0, min(progress, 1)))
            }
        }
        .frame(height: 5)
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

private struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
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
