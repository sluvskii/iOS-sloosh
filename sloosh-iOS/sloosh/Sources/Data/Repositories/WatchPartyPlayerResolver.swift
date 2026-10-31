import Foundation
import SwiftUI
import AVFoundation

@MainActor
enum WatchPartyPlayerResolver {
    /// Resolves exact PlayerConfig matching the host's selected voiceover, season, episode, and stream source.
    /// Operates completely in the background without displaying SourceSelectionView or prompting the guest.
    static func resolveConfig(for session: WatchPartySession) async -> PlayerConfig? {
        let vm = DetailsViewModel()
        let movieId = session.mediaId
        let mediaType = session.mediaType
        let fallbackTitle = session.title

        ToastManager.shared.show(
            title: "Смотреть вместе",
            subtitle: "Подключение к просмотру «\(fallbackTitle)»...",
            icon: "shareplay",
            iconColor: .green,
            duration: 3.0
        )

        await vm.loadDetails(id: movieId, type: mediaType)
        let resolvedKpId = vm.details?.ids?.kp ?? vm.details?.externalIds?.kp ?? (movieId.hasPrefix("kp_") ? Int(movieId.replacingOccurrences(of: "kp_", with: "")) : nil) ?? 0
        let resolvedTmdbId = vm.details?.externalIds?.tmdb ?? vm.details?.ids?.tmdb ?? (movieId.hasPrefix("tmdb_") ? Int(movieId.replacingOccurrences(of: "tmdb_", with: "")) : Int(movieId))
        let resolvedTitle = vm.details?.title ?? fallbackTitle
        let isTv: Bool? = {
            let lower = mediaType.lowercased()
            if lower == "tv" || lower == "serial" || lower == "series" { return true }
            if lower == "movie" { return false }
            if let seasons = vm.details?.seasons, !seasons.isEmpty { return true }
            return nil
        }()

        await vm.fetchSources(
            kpId: resolvedKpId,
            tmdbId: resolvedTmdbId,
            title: resolvedTitle,
            isTv: isTv
        )

        guard let wrapper = vm.sourceResultWrapper else {
            ToastManager.shared.show(
                title: "Смотреть вместе",
                subtitle: "Источник видео пока недоступен",
                icon: "exclamationmark.circle",
                iconColor: .red
            )
            return nil
        }

        let isSource2 = (session.streamSource == "source2")
        let activeSeriesResult = isSource2
            ? (wrapper.collapsResult?.apiResult ?? wrapper.allohaResult)
            : (wrapper.allohaResult ?? wrapper.collapsResult?.apiResult)

        guard let result = activeSeriesResult else {
            ToastManager.shared.show(
                title: "Смотреть вместе",
                subtitle: "Видео не найдено в источниках стриминга",
                icon: "exclamationmark.circle",
                iconColor: .red
            )
            return nil
        }

        let isSerial = (session.season != nil && session.episode != nil) || result.isSerial
        let targetVoice = session.translationName

        let chosenTranslation: AllohaTranslation?
        let targetSeason = session.season
        let targetEpisode = session.episode

        if isSerial, let s = targetSeason, let e = targetEpisode {
            let epObj = result.seasons.first(where: { $0.season == s })?.episodes.first(where: { $0.episode == e })
                ?? result.seasons.first?.episodes.first
            let translations = epObj?.translations ?? []
            chosenTranslation = translations.first(where: { t in
                if let tId = session.translationId, t.id == String(tId) { return true }
                guard let targetVoice else { return false }
                return allohaTranslationNamesMatch(t.name, targetVoice, exactOnly: true)
            }) ?? translations.first(where: { t in
                guard let targetVoice else { return false }
                return allohaTranslationNamesMatch(t.name, targetVoice, exactOnly: false)
            }) ?? translations.first(where: { $0.name == targetVoice }) ?? translations.first
        } else {
            let translations = result.movie?.translations ?? result.seasons.first?.episodes.first?.translations ?? []
            chosenTranslation = translations.first(where: { t in
                if let tId = session.translationId, t.id == String(tId) { return true }
                guard let targetVoice else { return false }
                return allohaTranslationNamesMatch(t.name, targetVoice, exactOnly: true)
            }) ?? translations.first(where: { t in
                guard let targetVoice else { return false }
                return allohaTranslationNamesMatch(t.name, targetVoice, exactOnly: false)
            }) ?? translations.first(where: { $0.name == targetVoice }) ?? translations.first
        }

        guard let translation = chosenTranslation else {
            ToastManager.shared.show(
                title: "Смотреть вместе",
                subtitle: "Не удалось загрузить выбранную озвучку",
                icon: "exclamationmark.circle",
                iconColor: .red
            )
            return nil
        }

        let tmdb = vm.details?.externalIds?.tmdb ?? vm.details?.ids?.tmdb ?? Int(vm.details?.id ?? "")
        let kp = (wrapper.kpId ?? 0) > 0 ? wrapper.kpId! : (vm.details?.ids?.kp ?? 0)
        let resolvedKey = kp > 0 ? "kp_\(kp)" : (vm.details?.id ?? "tmdb_\(tmdb ?? 0)")
        let voices = result.allTranslationNames
        let effectiveSource: MediaStreamSource = (isSource2 && wrapper.collapsResult != nil) ? .source2 : .source1
        let customHeaders = effectiveSource == .source2 ? CollapsRepository.streamHeaders : nil
        let subs: [PlaybackSubtitle] = effectiveSource == .source2
            ? (targetSeason != nil && targetEpisode != nil ? (wrapper.collapsResult?.episodeSubtitles[EpisodeKey(season: targetSeason!, episode: targetEpisode!)] ?? []) : (wrapper.collapsResult?.movieSubtitles ?? []))
            : []

        let nowMs = WatchPartyRepository.shared.calibratedNowMs
        let syncTime = session.playback.targetPosition(at: nowMs)

        return PlayerConfig(
            iframeUrl: translation.iframeUrl.isEmpty ? nil : translation.iframeUrl,
            title: vm.details?.title ?? fallbackTitle,
            kpId: wrapper.kpId,
            season: targetSeason,
            episode: targetEpisode,
            voiceover: translation.name,
            streamUrl: (effectiveSource == .source2 && translation.streamUrl?.isEmpty == false) ? translation.streamUrl : nil,
            voices: voices,
            subtitles: subs,
            quality: nil,
            seriesResult: activeSeriesResult,
            customHeaders: customHeaders,
            mediaKey: resolvedKey,
            tmdbId: tmdb,
            posterUrl: vm.details?.displayPosterUrl ?? session.posterUrl,
            backdropUrl: vm.details?.displayBackdropUrl ?? vm.details?.displayPosterUrl ?? session.posterUrl,
            logoUrl: vm.details?.displayLogoUrl,
            source: effectiveSource,
            episodeSubtitles: effectiveSource == .source2 ? (wrapper.collapsResult?.episodeSubtitles ?? [:]) : [:],
            initialPlaybackTime: syncTime,
            isInitiallyPaused: !session.playback.isPlaying
        )
    }
}
