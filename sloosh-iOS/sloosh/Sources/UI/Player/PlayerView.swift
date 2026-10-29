import SwiftUI
import AVKit
import AVFoundation
import MediaPlayer
import Combine

// MARK: - UIViewControllerRepresentable: запускает PlayerHostingController
// Это точка входа из SwiftUI fullScreenCover → UIKit-контроллер, который управляет landscape-ориентацией

struct PlayerPresenter: UIViewControllerRepresentable {
    @ObservedObject var vm: PlayerViewModel
    var onDismiss: () -> Void

    func makeUIViewController(context: Context) -> PlayerHostingController<PlayerContainerView> {
        vm.acquirePlaybackFocus()
        let container = PlayerContainerView(vm: vm, onDismiss: {
            context.coordinator.dismissPlayer()
        })
        let hc = PlayerHostingController(rootView: container)
        hc.overrideUserInterfaceStyle = .dark
        hc.onDismissed = {
            context.coordinator.didDismiss()
        }
        context.coordinator.hostingController = hc
        return hc
    }

    func updateUIViewController(_ uiViewController: PlayerHostingController<PlayerContainerView>, context: Context) {
        uiViewController.overrideUserInterfaceStyle = .dark
    }

    func makeCoordinator() -> Coordinator { Coordinator(vm: vm, onDismiss: onDismiss) }

    class Coordinator {
        weak var hostingController: UIViewController?
        private let vm: PlayerViewModel
        private let onDismiss: () -> Void
        private var dismissCalled = false

        init(vm: PlayerViewModel, onDismiss: @escaping () -> Void) {
            self.vm = vm
            self.onDismiss = onDismiss
        }

        func dismissPlayer() {
            guard !dismissCalled else { return }
            dismissCalled = true
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    vm.prepareForDismiss()
                    onDismiss()
                }
            } else {
                Task { @MainActor in
                    self.vm.prepareForDismiss()
                    self.onDismiss()
                }
            }
        }

        func didDismiss() {
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    vm.cleanup()
                }
            } else {
                Task { @MainActor in
                    self.vm.cleanup()
                }
            }
        }
    }
}

// MARK: - PlayerView — публичная SwiftUI точка входа

struct PlayerView: View {
    let iframeUrl: String?
    let fallbackTitle: String
    let kpId: Int?
    let season: Int?
    let episode: Int?
    let selectedVoiceover: String?
    /// Pre-resolved direct stream URL. When set, skips iframe resolution and name-matching.
    let directStreamUrl: String?
    let voices: [String]
    let subtitles: [PlaybackSubtitle]
    let initialQuality: VideoQualityPreference?
    let seriesResult: AllohaApiResult?
    let customHeaders: [String: String]?
    let mediaKey: String?
    let tmdbId: Int?
    let posterUrl: String?
    let backdropUrl: String?
    let logoUrl: String?
    let streamSource: MediaStreamSource
    let episodeSubtitles: [EpisodeKey: [PlaybackSubtitle]]
    let initialPlaybackTime: Double?

    @StateObject private var viewModel = PlayerViewModel()
    @Environment(\.dismiss) private var dismissEnv

    init(
        iframeUrl: String? = nil,
        fallbackTitle: String,
        kpId: Int? = nil,
        season: Int? = nil,
        episode: Int? = nil,
        selectedVoiceover: String? = nil,
        directStreamUrl: String? = nil,
        voices: [String] = [],
        subtitles: [PlaybackSubtitle] = [],
        initialQuality: VideoQualityPreference? = nil,
        seriesResult: AllohaApiResult? = nil,
        customHeaders: [String: String]? = nil,
        mediaKey: String? = nil,
        tmdbId: Int? = nil,
        posterUrl: String? = nil,
        backdropUrl: String? = nil,
        logoUrl: String? = nil,
        streamSource: MediaStreamSource = .source1,
        episodeSubtitles: [EpisodeKey: [PlaybackSubtitle]] = [:],
        initialPlaybackTime: Double? = nil
    ) {
        self.iframeUrl = iframeUrl
        self.fallbackTitle = fallbackTitle
        self.kpId = kpId
        self.season = season
        self.episode = episode
        self.selectedVoiceover = selectedVoiceover
        self.directStreamUrl = directStreamUrl
        self.voices = voices
        self.subtitles = subtitles
        self.initialQuality = initialQuality
        self.seriesResult = seriesResult
        self.customHeaders = customHeaders
        self.mediaKey = mediaKey
        self.tmdbId = tmdbId
        self.posterUrl = posterUrl
        self.backdropUrl = backdropUrl
        self.logoUrl = logoUrl
        self.streamSource = streamSource
        self.episodeSubtitles = episodeSubtitles
        self.initialPlaybackTime = initialPlaybackTime
    }

    init(config: PlayerConfig) {
        self.init(
            iframeUrl: config.iframeUrl,
            fallbackTitle: config.title,
            kpId: config.kpId,
            season: config.season,
            episode: config.episode,
            selectedVoiceover: config.voiceover,
            directStreamUrl: config.streamUrl,
            voices: config.voices,
            subtitles: config.subtitles,
            initialQuality: config.quality,
            seriesResult: config.seriesResult,
            customHeaders: config.customHeaders,
            mediaKey: config.mediaKey,
            tmdbId: config.tmdbId,
            posterUrl: config.posterUrl,
            backdropUrl: config.backdropUrl,
            logoUrl: config.logoUrl,
            streamSource: config.source,
            episodeSubtitles: config.episodeSubtitles,
            initialPlaybackTime: config.initialPlaybackTime
        )
    }

    var body: some View {
        PlayerPresenter(vm: viewModel) {
            dismissEnv()
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .environment(\.colorScheme, .dark)
        .onDisappear {
            viewModel.cleanup()
        }
        .onAppear {
            guard viewModel.player == nil else { return }
            viewModel.player = AVPlayer()
            viewModel.fallbackTitle = fallbackTitle
            viewModel.targetQualityPreference = initialQuality
            viewModel.seriesResult = seriesResult
            viewModel.mediaKey = mediaKey
            viewModel.tmdbId = tmdbId
            viewModel.posterUrl = posterUrl
            viewModel.backdropUrl = backdropUrl
            viewModel.logoUrl = logoUrl
            viewModel.streamSource = streamSource
            viewModel.episodeSubtitles = episodeSubtitles

            if let initTime = initialPlaybackTime, initTime > 0 {
                viewModel.pendingSeekPosition = initTime
                viewModel.isInitialSeekPending = true
                viewModel.currentTime = initTime
            }

            if iframeUrl != nil || directStreamUrl != nil || (kpId != nil && kpId! > 0) || (tmdbId != nil && tmdbId! > 0) {
                viewModel.load(
                    iframeUrl: iframeUrl,
                    kpId: kpId,
                    season: season,
                    episode: episode,
                    selectedVoiceover: selectedVoiceover,
                    directStreamUrl: directStreamUrl,
                    voices: voices,
                    subtitles: subtitles,
                    customHeaders: customHeaders,
                    mediaKey: mediaKey,
                    tmdbId: tmdbId,
                    posterUrl: posterUrl,
                    backdropUrl: backdropUrl,
                    logoUrl: logoUrl
                )
            } else {
                viewModel.error = "Нет URL для воспроизведения"
                viewModel.isLoading = false
            }
        }
    }
}


@MainActor
public final class PlayerTimeTracker: ObservableObject {
    @Published public var currentTime: Double = 0
    @Published public var currentDuration: Double = 0
    @Published public var bufferedProgress: Double = 0
}

@MainActor
class PlayerViewModel: ObservableObject {
    private let playbackFocusID = UUID()

    func acquirePlaybackFocus() {
        PlaybackFocus.shared.beginMainPlayer(playbackFocusID)
    }

    struct PlaybackQualityOption: Equatable {
        let key: String
        let url: URL
        let preferredPeakBitRate: Double?
        let isAuto: Bool
        let shouldReloadOnSelect: Bool
    }

    // MARK: - Playback state
    @Published var player: AVPlayer?
    @Published var isLoading = true
    @Published var isBuffering = false
    @Published var isPlaying = false
    @Published var error: String?
    
    var isUserSeeking = false
    var isPausedByUser = false

    var isMovie: Bool {
        return seriesResult?.isSerial == false || seriesResult?.movie != nil
    }

    var hasNextEpisode: Bool {
        return nextEpisodeCandidate() != nil
    }

    var hasPreviousEpisode: Bool {
        return previousEpisodeCandidate() != nil
    }

    // MARK: - Timing (Isolated to timeTracker to prevent full-tree re-renders during playback)
    public let timeTracker = PlayerTimeTracker()

    var currentTime: Double {
        get { timeTracker.currentTime }
        set { timeTracker.currentTime = newValue }
    }

    var currentDuration: Double {
        get { timeTracker.currentDuration }
        set { timeTracker.currentDuration = newValue }
    }

    var bufferedProgress: Double {
        get { timeTracker.bufferedProgress }
        set { timeTracker.bufferedProgress = newValue }
    }

    private var lastProgressSaveSecond: Int = -1

    @Published var screenScrubTime: Double?
    @Published var introRange: ClosedRange<Double>?
    @Published var outroRange: ClosedRange<Double>?
    @Published var showSkipIntro = false
    @Published var showSkipOutro = false

    // MARK: - Scrub Preview Thumbnails (Telegram-style)
    @Published var scrubPreviewImage: UIImage? = nil
    @Published var scrubPreviewAspectRatio: CGFloat = 16.0 / 9.0
    private var imageGenerator: AVAssetImageGenerator?
    private var thumbnailTask: Task<Void, Never>?
    private var lastRequestedThumbnailTime: Double = -1
    private var thumbnailCache: [Int: (image: UIImage, ratio: CGFloat)] = [:]
    private static let sharedCIContext = CIContext(options: [.useSoftwareRenderer: false])
    @Published var isLocalPlayback: Bool = false

    func setupImageGenerator(asset: AVAsset) {
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 320, height: 180)
        gen.requestedTimeToleranceBefore = CMTime(seconds: 5, preferredTimescale: 600)
        gen.requestedTimeToleranceAfter = CMTime(seconds: 5, preferredTimescale: 600)
        self.imageGenerator = gen
        self.thumbnailCache.removeAll()
    }

    func generateFilmstrip(times: [Double], completion: @escaping ([Double: UIImage]) -> Void) {
        guard let asset = player?.currentItem?.asset else {
            completion([:])
            return
        }
        if imageGenerator == nil {
            setupImageGenerator(asset: asset)
        }
        guard let gen = imageGenerator else {
            completion([:])
            return
        }

        let cmTimes = times.map { NSValue(time: CMTime(seconds: max(0, $0), preferredTimescale: 600)) }
        var collected: [Double: UIImage] = [:]
        let totalCount = cmTimes.count
        var receivedCount = 0

        gen.generateCGImagesAsynchronously(forTimes: cmTimes) { requestedTime, cgImage, actualTime, result, error in
            DispatchQueue.main.async {
                receivedCount += 1
                if result == .succeeded, let cgImage {
                    let img = UIImage(cgImage: cgImage)
                    collected[requestedTime.seconds] = img
                }
                if receivedCount >= totalCount {
                    completion(collected)
                }
            }
        }
    }

    func generateScrubThumbnail(at seconds: Double) {
        guard seconds >= 0 else { return }
        let cacheKey = Int(seconds / 5.0) * 5
        
        // 1. Пробуем взять кадр из оперативного кэша
        if let cached = thumbnailCache[cacheKey] {
            self.scrubPreviewAspectRatio = cached.ratio
            self.scrubPreviewImage = cached.image
            return
        }
        
        guard abs(seconds - lastRequestedThumbnailTime) > 0.15 else { return }
        lastRequestedThumbnailTime = seconds
        
        // 2. Асинхронно извлекаем точный кадр через AVAssetImageGenerator
        guard let gen = self.imageGenerator else { return }
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        let timeValue = NSValue(time: time)
        
        gen.generateCGImagesAsynchronously(forTimes: [timeValue]) { [weak self] requestedTime, cgImage, actualTime, result, error in
            guard let self, let cgImage, result == .succeeded else { return }
            
            let reqSec = requestedTime.seconds
            let actSec = actualTime.seconds
            guard reqSec.isFinite, actSec.isFinite, abs(reqSec - actSec) < 30.0 else { return }
            
            let uiImage = UIImage(cgImage: cgImage)
            let ratio = CGFloat(cgImage.width) / max(1.0, CGFloat(cgImage.height))
            
            DispatchQueue.main.async {
                if self.thumbnailCache.count > 60 {
                    self.thumbnailCache.removeAll()
                }
                self.thumbnailCache[cacheKey] = (uiImage, ratio)
                self.scrubPreviewAspectRatio = ratio
                self.scrubPreviewImage = uiImage
            }
        }
    }

    // MARK: - Quality & Rate
    @Published var availableQualities: [PlaybackQualityOption] = []
    @Published var currentQualityKey: String?
    @Published var playbackRate: Float = 1.0

    // MARK: - Voiceovers
    @Published var availableVoiceovers: [String] = []
    var currentTranslationName: String? { _currentTranslationName }
    @Published private var _currentTranslationName: String?

    // MARK: - Subtitles
    @Published var availableSubtitles: [PlaybackSubtitle] = []
    @Published var currentSubtitle: PlaybackSubtitle?
    @Published var currentSubtitleText: String?
    private var activeSubtitleCues: [SubtitleCue] = []
    private var subtitleFetchTask: Task<Void, Never>?
    private var legibleDelegate: LegibleOutputDelegate?
    private var legibleOutput: AVPlayerItemLegibleOutput?
    /// Выход кадров декодера для захвата кадров плёнки триммера.
    private var videoOutput: AVPlayerItemVideoOutput?

    // MARK: - PiP
    @Published var isPiPActive = false

    // MARK: - In-Player Clip Trimmer
    static let clipMinDuration: Double = 3.0
    static let clipMaxDuration: Double = 600.0
    @Published var isClipMode = false
    @Published var isInterfaceLocked = false
    @Published var clipStartTime: Double = 0.0
    @Published var clipEndTime: Double = 0.0
    @Published var isClipPublishing: Bool = false
    @Published var clipCaption: String = ""
    @Published var clipPublishErrorMessage: String? = nil
    @Published var latestCapturedFrame: UIImage? = nil
    var onClipPlaybackTimeUpdated: ((Double) -> Void)? = nil
    var pipController: AVPictureInPictureController?

    // MARK: - Meta
    var fallbackTitle: String = ""
    var posterUrl: String?
    var backdropUrl: String?
    var logoUrl: String?
    var streamSource: MediaStreamSource = .source1
    var episodeSubtitles: [EpisodeKey: [PlaybackSubtitle]] = [:]

    public var isCollapsStream: Bool {
        streamSource == .source2 ||
        (originalStreamURL?.host?.contains("interkh") == true) ||
        (currentPlaybackSourceURL?.host?.contains("interkh") == true) ||
        (targetDirectStreamUrl?.contains("interkh") == true) ||
        (currentPlaybackSourceURL?.absoluteString.contains("interkh") == true)
    }

    private var lastSeekTimestamp: Date = .distantPast

    private var resolver: AllohaRuntimeResolver?
    private var resolveTask: Task<Void, Never>?
    private var currentHeaders: [String: String] = [:]
    private var customHeaders: [String: String]? = nil
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var bufferObserver: NSKeyValueObservation?
    private var playbackEndObserver: NSObjectProtocol?
    private var failedToEndObserver: NSObjectProtocol?
    private var playbackStalledObserver: NSObjectProtocol?
    private var resignActiveObserver: NSObjectProtocol?
    private var foregroundObserver: NSObjectProtocol?
    private var audioInterruptionObserver: NSObjectProtocol?
    private var rateObserver: NSKeyValueObservation?
    /// Оригинальный upstream URL стрима (без 127.0.0.1 прокси). Используется для перезапуска после фона.
    private var originalStreamURL: URL?
    /// Исходный мастер-URL стрима (плейлист или основной поток до переключения на сублисты качества).
    private var masterStreamURL: URL?
    /// Проксированный URL который дали в AVPlayer (может быть 127.0.0.1).
    private var currentPlaybackSourceURL: URL?
    private lazy var trustedSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.waitsForConnectivity = true
        let delegate = ProxyTrustAllSessionDelegate()
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }()

    private(set) var currentKpId: Int?
    var mediaKey: String?
    var tmdbId: Int?
    @Published private(set) var currentSeason: Int?
    @Published private(set) var currentEpisode: Int?
    private var targetVoiceover: String?
    /// Pre-resolved direct stream URL; bypasses audioVariant matching when set.
    private var targetDirectStreamUrl: String?
    private var isAdvancingToNextEpisode = false
    /// Оригинальный iframeUrl Alloha. Нужен для корректного переключения озвучки в плеере.
    private var currentIframeUrl: String?
    /// Все audioVariants из последнего resolve. Нужны для мгновенного переключения озвучки без re-resolve.
    private var resolvedAudioVariants: [[String: Any]] = []
    var isInitialSeekPending = false
    var pendingSeekPosition: Double?
    private var wasPlayingBeforeReload: Bool = false

    public var activeIframeUrl: String? {
        currentIframeUrl
    }

    public var activeStreamUrlString: String? {
        originalStreamURL?.absoluteString ?? currentPlaybackSourceURL?.absoluteString ?? targetDirectStreamUrl
    }

    public var activeHeaders: [String: String] {
        customHeaders ?? currentHeaders
    }

    var rootMediaKey: String? {
        if let kpId = currentKpId, kpId > 0 {
            return "kp_\(kpId)"
        }
        if let key = mediaKey, !key.isEmpty {
            return key
        }
        if let tmdbId = tmdbId, tmdbId > 0 {
            return "tmdb_\(tmdbId)"
        }
        if !fallbackTitle.isEmpty {
            return "title_\(abs(fallbackTitle.hashValue))"
        }
        return nil
    }

    var currentMediaId: String? {
        guard let root = rootMediaKey else { return nil }
        if let season = currentSeason, let episode = currentEpisode {
            return "\(root)_s\(season)_e\(episode)"
        } else {
            return root
        }
    }

    var targetQualityPreference: VideoQualityPreference?
    var seriesResult: AllohaApiResult?
    private var hasStartedLoading = false
    private var playbackRetryCount = 0
    private let maxPlaybackRetries = 3
    private var networkCancellable: AnyCancellable?

    var displayLogoUrl: URL? {
        if let logo = logoUrl, let url = URL(string: logo) {
            return url
        }
        if let kpId = currentKpId, kpId > 0 {
            return URL(string: "\(MoviesApi.activeImagesBaseURL)/api/v1/images/logos/\(kpId)/original")
        }
        return nil
    }

    private var autoplayNextEpisodeEnabled: Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "autoplayNextEpisode") == nil {
            return true
        }
        return defaults.bool(forKey: "autoplayNextEpisode")
    }

    private func isLocalProxyUrl(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "127.0.0.1" || host == "localhost"
    }
    
    func load(
        iframeUrl: String?,
        kpId: Int?,
        season: Int?,
        episode: Int?,
        selectedVoiceover: String?,
        directStreamUrl: String? = nil,
        voices: [String] = [],
        subtitles: [PlaybackSubtitle] = [],
        customHeaders: [String: String]? = nil,
        mediaKey: String? = nil,
        tmdbId: Int? = nil,
        posterUrl: String? = nil,
        backdropUrl: String? = nil,
        logoUrl: String? = nil
    ) {
        guard !isPreparedForDismiss, !isCleaningUp else { return }
        if hasStartedLoading { return } // Защита от двойного вызова
        acquirePlaybackFocus()
        hasStartedLoading = true
        if let posterUrl, !posterUrl.isEmpty { self.posterUrl = posterUrl }
        if let backdropUrl, !backdropUrl.isEmpty { self.backdropUrl = backdropUrl }
        if let logoUrl, !logoUrl.isEmpty { self.logoUrl = logoUrl }
        logDebug("load called with iframeUrl=\(iframeUrl ?? "nil"), selectedVoiceover=\(selectedVoiceover ?? "nil"), directStreamUrl=\(directStreamUrl ?? "nil"), mediaKey=\(mediaKey ?? "nil")")
        beginLoad(
            iframeUrl: iframeUrl,
            kpId: kpId,
            season: season,
            episode: episode,
            selectedVoiceover: selectedVoiceover,
            directStreamUrl: directStreamUrl,
            voices: voices,
            subtitles: subtitles,
            customHeaders: customHeaders,
            mediaKey: mediaKey,
            tmdbId: tmdbId
        )
    }

    /// Честный повтор: инвалидирует кеши и перезапрашивает свежий поток у Alloha / Collaps с сохранением позиции.
    func retryPlayback() {
        error = nil
        isLoading = true
        playbackRetryCount = 0

        // Сохраняем текущую позицию, чтобы после переподключения продолжить с неё
        saveCurrentProgress()

        if isCollapsStream {
            CollapsRepository.shared.invalidateCache()
            originalStreamURL = nil
            masterStreamURL = nil
            currentPlaybackSourceURL = nil
            retryCollapsPlayback()
            return
        }

        if let iframeUrl = currentIframeUrl, !iframeUrl.isEmpty {
            AllohaRuntimeResolver.invalidateCache(for: iframeUrl)
        }
        AllohaRepository.shared.invalidateCache()

        originalStreamURL = nil
        masterStreamURL = nil
        currentPlaybackSourceURL = nil

        if let iframeUrl = currentIframeUrl, !iframeUrl.isEmpty {
            print("retryPlayback: full fresh re-resolve via currentIframeUrl")
            hasStartedLoading = false
            beginLoad(
                iframeUrl: iframeUrl,
                kpId: currentKpId,
                season: currentSeason,
                episode: currentEpisode,
                selectedVoiceover: targetVoiceover ?? _currentTranslationName,
                directStreamUrl: nil,
                voices: [],
                subtitles: availableSubtitles,
                customHeaders: customHeaders,
                mediaKey: mediaKey,
                tmdbId: tmdbId
            )
        } else if let directUrl = targetDirectStreamUrl {
            print("retryPlayback: reloading direct stream")
            hasStartedLoading = false
            beginLoad(
                iframeUrl: nil,
                kpId: currentKpId,
                season: currentSeason,
                episode: currentEpisode,
                selectedVoiceover: targetVoiceover ?? _currentTranslationName,
                directStreamUrl: directUrl,
                voices: availableVoiceovers,
                subtitles: availableSubtitles,
                customHeaders: customHeaders,
                mediaKey: mediaKey,
                tmdbId: tmdbId
            )
        } else if let kpId = currentKpId, kpId > 0 {
            print("retryPlayback: fetching fresh media via kpId \(kpId)")
            hasStartedLoading = false
            load(
                iframeUrl: nil,
                kpId: kpId,
                season: currentSeason,
                episode: currentEpisode,
                selectedVoiceover: targetVoiceover ?? _currentTranslationName,
                directStreamUrl: nil,
                voices: [],
                subtitles: availableSubtitles,
                customHeaders: customHeaders,
                mediaKey: mediaKey,
                tmdbId: tmdbId,
                posterUrl: posterUrl,
                backdropUrl: backdropUrl,
                logoUrl: logoUrl
            )
        } else {
            hasStartedLoading = false
            isLoading = false
            error = "Не удалось восстановить видеопоток. Закройте плеер и откройте заново."
        }
    }

    private func retryCollapsPlayback() {
        Task { [weak self] in
            guard let self else { return }
            await self.executeCollapsRetry()
        }
    }

    private func executeCollapsRetry() async {
        do {
            let isTv = (currentSeason != nil && currentSeason! > 0) || (currentEpisode != nil && currentEpisode! > 0)
            let result = try await CollapsRepository.shared.fetchMedia(
                kpId: currentKpId,
                imdbId: nil,
                title: fallbackTitle,
                isTv: isTv
            )
            guard let result else {
                isLoading = false
                error = "Не удалось обновить ссылку на резервный видеопоток"
                return
            }

            seriesResult = result.apiResult
            episodeSubtitles = result.episodeSubtitles

            let currentSeasonNum = currentSeason ?? 1
            let currentEpisodeNum = currentEpisode ?? 1

            let streamUrl: String?
            let voices: [String]
            let subtitles: [PlaybackSubtitle]

            switch result.catalog {
            case .series(_, let seasons):
                let seasonMatch = seasons.first(where: { $0.season == currentSeasonNum })
                let epMatch = seasonMatch?.episodes.first(where: { $0.episode == currentEpisodeNum })
                streamUrl = epMatch?.playlist.primaryUrl
                voices = epMatch?.playlist.voiceovers ?? []
                let epKey = EpisodeKey(season: currentSeasonNum, episode: currentEpisodeNum)
                subtitles = result.episodeSubtitles[epKey] ?? []
            case .movie(_, let playlist):
                streamUrl = playlist.primaryUrl
                voices = playlist.voiceovers
                subtitles = result.movieSubtitles
            }

            guard let freshUrl = streamUrl, !freshUrl.isEmpty else {
                isLoading = false
                self.error = "Не удалось обновить ссылку на видео"
                return
            }

            targetDirectStreamUrl = freshUrl
            hasStartedLoading = false
            let voiceToSelect = targetVoiceover ?? _currentTranslationName
            beginLoad(
                iframeUrl: nil,
                kpId: currentKpId,
                season: currentSeason,
                episode: currentEpisode,
                selectedVoiceover: voiceToSelect,
                directStreamUrl: freshUrl,
                voices: voices,
                subtitles: subtitles,
                customHeaders: CollapsRepository.streamHeaders,
                mediaKey: mediaKey,
                tmdbId: tmdbId
            )
        } catch {
            isLoading = false
            self.error = "Не удалось обновить видеопоток: \(error.localizedDescription)"
        }
    }

    private func beginLoad(
        iframeUrl: String?,
        kpId: Int?,
        season: Int?,
        episode: Int?,
        selectedVoiceover: String?,
        directStreamUrl: String? = nil,
        voices: [String] = [],
        subtitles: [PlaybackSubtitle] = [],
        customHeaders: [String: String]? = nil,
        mediaKey: String? = nil,
        tmdbId: Int? = nil
    ) {
        if let customHeaders {
            self.customHeaders = customHeaders
        }

        // Отменяем незаконченные задачи предыдущего эпизода
        resolveTask?.cancel()
        resolveTask = nil
        resolver?.cancel()
        resolver = nil

        // КРИТИЧНО: удаляем старый timeObserver ДО сброса currentTime.
        // Задачи (Task), уже поставленные в очередь старым observer'ом, содержат
        // self.currentTime = <конец старого эпизода> и могут выполниться ПОСЛЕ
        // того как мы установим currentTime = 0, перезаписав его неверным значением.
        // Удаление observer'а здесь не отменяет уже отправленные Task-и, но сам
        // observer больше не создаст новых; а все уже отправленные Task-и проверяют
        // capturedItem и выходят досрочно (см. startTrackingProgress).
        if let observer = timeObserver, let player = player {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }

        self.currentKpId = kpId
        self.currentSeason = season
        self.currentEpisode = episode
        if let mediaKey, !mediaKey.isEmpty {
            self.mediaKey = mediaKey
        }
        if let tmdbId, tmdbId > 0 {
            self.tmdbId = tmdbId
        }
        if let root = self.rootMediaKey, !self.fallbackTitle.isEmpty {
            let existing = PlaybackProgressStore.shared.loadMetadata(mediaKey: root)
                ?? (kpId.flatMap { $0 > 0 ? PlaybackProgressStore.shared.loadMetadata(kpId: $0) : nil })
            let finalPoster = self.posterUrl ?? existing?.posterUrl
            let finalBackdrop = self.backdropUrl ?? existing?.backdropUrl ?? finalPoster
            let finalLogo = self.logoUrl ?? existing?.logoUrl ?? self.displayLogoUrl?.absoluteString
            let finalTitle = (existing?.title.isEmpty == false && existing?.title != "Без названия") ? (existing?.title ?? self.fallbackTitle) : self.fallbackTitle
            let finalType = (season != nil && episode != nil) ? "tv" : (existing?.type ?? "movie")

            if self.posterUrl == nil { self.posterUrl = finalPoster }
            if self.backdropUrl == nil { self.backdropUrl = finalBackdrop }
            if self.logoUrl == nil { self.logoUrl = finalLogo }

            PlaybackProgressStore.shared.saveMetadata(
                kpId: kpId ?? existing?.kpId ?? 0,
                tmdbId: tmdbId ?? existing?.tmdbId,
                detailsId: root,
                title: finalTitle,
                type: finalType,
                posterUrl: finalPoster,
                backdropUrl: finalBackdrop,
                logoUrl: finalLogo,
                mediaKey: root
            )
        }
        if self.targetVoiceover == nil {
            self.targetVoiceover = selectedVoiceover
        }
        self._currentTranslationName = selectedVoiceover
        self.targetDirectStreamUrl = directStreamUrl
        if isCollapsStream && self.streamSource != .source2 {
            self.streamSource = .source2
        }
        if let root = self.rootMediaKey {
            PlaybackProgressStore.shared.saveLastStreamSource(mediaKey: root, source: self.streamSource)
            if let kp = self.currentKpId, kp > 0 {
                PlaybackProgressStore.shared.saveLastStreamSource(mediaKey: "kp_\(kp)", source: self.streamSource)
            }
        }
        self.isAdvancingToNextEpisode = false
        self.playbackRetryCount = 0
        self.wasPlayingBeforeReload = true
        if self.isInitialSeekPending, let initSeek = self.pendingSeekPosition, initSeek > 0 {
            self.currentTime = initSeek
            logDebug("beginLoad: preserved explicit initial seek to \(initSeek)s")
        } else if let mediaId = self.currentMediaId {
            var saved = PlaybackProgressStore.shared.load(mediaId: mediaId)
            if saved <= 2, let root = self.rootMediaKey {
                if let tmdb = self.tmdbId, tmdb > 0 {
                    let altMediaId = (self.currentSeason != nil && self.currentEpisode != nil) ? "tmdb_\(tmdb)_s\(self.currentSeason!)_e\(self.currentEpisode!)" : "tmdb_\(tmdb)"
                    let altSaved = PlaybackProgressStore.shared.load(mediaId: altMediaId)
                    if altSaved > 2 { saved = altSaved }
                }
                if saved <= 2, let origKey = self.mediaKey, origKey != root {
                    let altMediaId = (self.currentSeason != nil && self.currentEpisode != nil) ? "\(origKey)_s\(self.currentSeason!)_e\(self.currentEpisode!)" : origKey
                    let altSaved = PlaybackProgressStore.shared.load(mediaId: altMediaId)
                    if altSaved > 2 { saved = altSaved }
                }
            }
            if saved > 2 {
                self.pendingSeekPosition = saved
                self.isInitialSeekPending = true
                self.currentTime = saved
                logDebug("beginLoad: initialized with saved progress \(saved)s for \(mediaId)")
            } else if isCollapsStream {
                self.pendingSeekPosition = 3.5
                self.isInitialSeekPending = true
                self.currentTime = 3.5
                logDebug("beginLoad: Collaps stream initialized with 3.5s offset")
            } else {
                self.pendingSeekPosition = nil
                self.isInitialSeekPending = false
                self.currentTime = 0
            }
        } else if isCollapsStream {
            self.pendingSeekPosition = 3.5
            self.isInitialSeekPending = true
            self.currentTime = 3.5
            logDebug("beginLoad: Collaps stream initialized with 3.5s offset")
        } else {
            self.pendingSeekPosition = nil
            self.isInitialSeekPending = false
            self.currentTime = 0
        }
        self.currentDuration = 0

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard let self, self.isInitialSeekPending else { return }
            self.isInitialSeekPending = false
            self.pendingSeekPosition = nil
        }
        // Сохраняем iframeUrl — нужен для переключения озвучки внутри плеера
        if let iframeUrl, !iframeUrl.isEmpty {
            self.currentIframeUrl = iframeUrl
        }
        // Сбрасываем кэш audioVariants — будет обновлён после resolve нового стрима
        self.resolvedAudioVariants = []

        // Настраиваем availableVoiceovers: для сериалов берем озвучки конкретного эпизода,
        // чтобы их порядок и индексы точно совпадали с аудиодорожками HLS манифеста (особенно для Источника 2)
        if let seriesResult = self.seriesResult, let s = season, let e = episode,
           let seasonObj = seriesResult.seasons.first(where: { $0.season == s }),
           let epObj = seasonObj.episodes.first(where: { $0.episode == e }) {
            self.availableVoiceovers = epObj.translations.map { $0.name }
        } else if let seriesResult = self.seriesResult, let movie = seriesResult.movie {
            self.availableVoiceovers = movie.translations.map { $0.name }
        } else if !voices.isEmpty {
            self.availableVoiceovers = voices
        }

        if (kpId != nil || self.rootMediaKey != nil), let selectedVoiceover, !selectedVoiceover.isEmpty {
            if let pref = targetVoiceover, allohaTranslationNamesMatch(selectedVoiceover, pref) {
                persistVoiceoverSelection(selectedVoiceover)
            } else if targetVoiceover == nil {
                persistVoiceoverSelection(selectedVoiceover)
            }
        }

        isLoading = true
        isPlaying = false
        error = nil

        if let directUrlString = directStreamUrl, let directUrl = URL(string: directUrlString) {
            let isLocal = directUrl.isFileURL || directUrlString.contains("/local/")
            if isLocal {
                // Direct HLS playback (local file URL)
                availableQualities = [
                    PlaybackQualityOption(
                        key: "Локальный",
                        url: directUrl,
                        preferredPeakBitRate: nil,
                        isAuto: false,
                        shouldReloadOnSelect: false
                    )
                ]
                currentQualityKey = "Локальный"
                playVideo(url: directUrl, headers: [:], voices: [], subtitles: [])
            } else {
                // Online direct stream (e.g. Collaps / Source 2)
                let effectiveHeaders = customHeaders ?? self.customHeaders ?? CollapsRepository.streamHeaders
                self.customHeaders = effectiveHeaders
                if self.availableVoiceovers.isEmpty && !voices.isEmpty {
                    self.availableVoiceovers = voices
                }
                if !subtitles.isEmpty {
                    self.availableSubtitles = subtitles
                }
                if let target = targetVoiceover ?? selectedVoiceover {
                    self._currentTranslationName = target
                }
                self.availableQualities = [
                    makeAutoQualityOption(url: directUrl)
                ]
                self.currentQualityKey = "Авто"
                playVideo(url: directUrl, headers: effectiveHeaders, voices: voices, subtitles: subtitles)
                Task { [weak self] in
                    guard let self else { return }
                    await self.fetchAndUpdateQualitiesFromMaster(url: directUrl, headers: effectiveHeaders)
                }
            }
        } else if let iframe = iframeUrl, !iframe.isEmpty {
            startParsing(iframeUrl: iframe, voices: voices, subtitles: subtitles)
        } else if (kpId != nil && kpId! > 0) || (tmdbId != nil && tmdbId! > 0) {
            // Dynamic fetch from AllohaRepository if iframeUrl was not provided
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let isTv = (season != nil && season! > 0) || (episode != nil && episode! > 0)
                    let res = try await AllohaRepository.shared.fetchByKpId(
                        kpId: kpId ?? 0,
                        tmdbId: tmdbId,
                        title: self.fallbackTitle,
                        isTv: isTv
                    )
                    self.seriesResult = res
                    var targetIframe: String? = nil
                    var availableVoices: [String] = []
                    if let s = season, let e = episode,
                       let seasonObj = res.seasons.first(where: { $0.season == s }),
                       let epObj = seasonObj.episodes.first(where: { $0.episode == e }) {
                        availableVoices = epObj.translations.map { $0.name }
                        if let trName = selectedVoiceover,
                           let tr = epObj.translations.first(where: { allohaTranslationNamesMatch($0.name, trName, exactOnly: true) })
                                ?? epObj.translations.first(where: { allohaTranslationNamesMatch($0.name, trName, exactOnly: false) }) {
                            targetIframe = tr.iframeUrl
                        } else {
                            targetIframe = epObj.translations.first?.iframeUrl
                        }
                    } else if let movie = res.movie {
                        availableVoices = movie.translations.map { $0.name }
                        if let trName = selectedVoiceover,
                           let tr = movie.translations.first(where: { allohaTranslationNamesMatch($0.name, trName, exactOnly: true) })
                                ?? movie.translations.first(where: { allohaTranslationNamesMatch($0.name, trName, exactOnly: false) }) {
                            targetIframe = tr.iframeUrl
                        } else {
                            targetIframe = movie.translations.first?.iframeUrl ?? movie.iframeUrl
                        }
                    }
                    if self.availableVoiceovers.isEmpty {
                        self.availableVoiceovers = availableVoices
                    }
                    guard let iframe = targetIframe, !iframe.isEmpty else {
                        self.error = "Видео не найдено"
                        self.isLoading = false
                        return
                    }
                    self.currentIframeUrl = iframe
                    self.startParsing(iframeUrl: iframe, voices: availableVoices, subtitles: subtitles)
                } catch {
                    self.error = "Не удалось загрузить видео: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        } else {
            error = "Нет URL для воспроизведения"
            isLoading = false
        }
    }

    private func parseMasterPlaylist(content: String, baseUrl: URL) {
        var qualities: [PlaybackQualityOption] = [
            PlaybackQualityOption(
                key: "Авто",
                url: proxiedPlaybackURL(for: baseUrl, quality: nil) ?? baseUrl,
                preferredPeakBitRate: nil,
                isAuto: true,
                shouldReloadOnSelect: false
            )
        ]
        
        let lines = content.components(separatedBy: .newlines)
        var currentResolution: String?
        var currentBandwidth: Double?
        
        for line in lines {
            if line.hasPrefix("#EXT-X-STREAM-INF:") {
                currentBandwidth = nil
                if let range = line.range(of: "BANDWIDTH=([0-9]+)", options: .regularExpression) {
                    let match = String(line[range])
                    let bw = match.replacingOccurrences(of: "BANDWIDTH=", with: "")
                    if let bandwidth = Double(bw) {
                        currentBandwidth = bandwidth
                    }
                }

                var resStr: String?
                if let range = line.range(of: "RESOLUTION=([0-9]+)x([0-9]+)", options: .regularExpression) {
                    let match = String(line[range])
                    let res = match.replacingOccurrences(of: "RESOLUTION=", with: "")
                    let components = res.components(separatedBy: "x")
                    if components.count == 2, let width = Int(components[0]), let height = Int(components[1]) {
                        if height > 1080 && width > 1920 { continue }
                        resStr = PlaybackHlsRewriter.normalizeResolutionLabel(width: width, height: height)
                    }
                } else if let bw = currentBandwidth {
                    resStr = "\(Int(bw / 1000)) kbps"
                }
                currentResolution = resStr
            } else if !line.hasPrefix("#") && !line.isEmpty {
                if let res = currentResolution {
                    let targetUrl = proxiedPlaybackURL(for: baseUrl, quality: res) ?? baseUrl
                    if let index = qualities.firstIndex(where: { $0.key == res }) {
                        if let currentBandwidth, (qualities[index].preferredPeakBitRate ?? 0) < currentBandwidth {
                            qualities[index] = PlaybackQualityOption(
                                key: res,
                                url: targetUrl,
                                preferredPeakBitRate: currentBandwidth,
                                isAuto: false,
                                shouldReloadOnSelect: true
                            )
                        }
                    } else {
                        qualities.append(
                            PlaybackQualityOption(
                                key: res,
                                url: targetUrl,
                                preferredPeakBitRate: currentBandwidth,
                                isAuto: false,
                                shouldReloadOnSelect: true
                            )
                        )
                    }
                    currentResolution = nil
                    currentBandwidth = nil
                }
            }
        }
        
        if qualities.count > 1 {
            let autoQuality = qualities.removeFirst()
            qualities.sort { (a, b) -> Bool in
                let valA = Int(a.key.replacingOccurrences(of: "p", with: "")) ?? 0
                let valB = Int(b.key.replacingOccurrences(of: "p", with: "")) ?? 0
                return valA > valB
            }
            qualities.insert(autoQuality, at: 0)
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                var mergedQualities = qualities
                let existingKeys = Set(qualities.map { $0.key })
                for originalQuality in self.availableQualities {
                    if !existingKeys.contains(originalQuality.key) {
                        mergedQualities.append(originalQuality)
                    }
                }
                
                // Capped at 1080p max
                mergedQualities = mergedQualities.filter { q in
                    if q.isAuto { return true }
                    let h = Int(q.key.replacingOccurrences(of: "p", with: "")) ?? 0
                    return h <= 1080
                }
                
                if mergedQualities.count > 1 {
                    let autoQ = mergedQualities.removeFirst()
                    mergedQualities.sort { (a, b) -> Bool in
                        let valA = Int(a.key.replacingOccurrences(of: "p", with: "")) ?? 0
                        let valB = Int(b.key.replacingOccurrences(of: "p", with: "")) ?? 0
                        return valA > valB
                    }
                    mergedQualities.insert(autoQ, at: 0)
                }
                
                self.availableQualities = mergedQualities
                NotificationCenter.default.post(name: NSNotification.Name("QualitiesUpdated"), object: nil)
                self.applyInitialQuality()
            }
        }
    }
    
    /// Selects the best playback URL and bitrate from `availableQualities` to preserve the user's
    /// currently active or preferred video quality (e.g. 1080p), preventing quality drops on stream switches.
    private func selectPreservedPlaybackTarget(fallbackUrl: URL) -> (url: URL, bitrate: Double?) {
        let desiredKey: String? = {
            if let current = self.currentQualityKey, !current.isEmpty, current != "Авто" {
                return current
            }
            if let pref = self.targetQualityPreference, pref != .ask && pref != .auto {
                return pref.rawValue
            }
            let saved = UserDefaults.standard.string(forKey: "preferredVideoQuality") ?? VideoQualityPreference.ask.rawValue
            if let prefEnum = VideoQualityPreference(rawValue: saved), prefEnum != .ask && prefEnum != .auto {
                return prefEnum.rawValue
            }
            return nil
        }()

        if let desired = desiredKey {
            // 1. Exact match (e.g. "1080p")
            if let match = self.availableQualities.first(where: { $0.key.lowercased() == desired.lowercased() }) {
                self.currentQualityKey = match.key
                let bitrate = self.resolvedBitrate(for: match)
                logDebug("selectPreservedPlaybackTarget: exact quality match '\(match.key)', bitrate=\(bitrate)")
                return (match.url, bitrate)
            }

            // 2. Prefix match (e.g. "1080p" prefix for "1080p (60fps)")
            if let match = self.availableQualities.first(where: { $0.key.lowercased().hasPrefix(desired.lowercased()) }) {
                self.currentQualityKey = match.key
                let bitrate = self.resolvedBitrate(for: match)
                logDebug("selectPreservedPlaybackTarget: prefix quality match '\(match.key)', bitrate=\(bitrate)")
                return (match.url, bitrate)
            }

            // 3. Closest resolution match
            let prefVal = normalizedQualityHeight(desired)
            if prefVal > 0 {
                var closest: PlaybackQualityOption?
                var minDiff = Int.max
                for q in self.availableQualities where !q.isAuto {
                    let val = normalizedQualityHeight(q.key)
                    if val > 0 {
                        let diff = abs(val - prefVal)
                        if diff < minDiff {
                            minDiff = diff
                            closest = q
                        }
                    }
                }
                if let closestMatch = closest {
                    self.currentQualityKey = closestMatch.key
                    let bitrate = self.resolvedBitrate(for: closestMatch)
                    logDebug("selectPreservedPlaybackTarget: closest quality match '\(closestMatch.key)' for desired '\(desired)', bitrate=\(bitrate)")
                    return (closestMatch.url, bitrate)
                }
            }
        }

        // Auto / fallback to default stream
        if let autoOpt = self.availableQualities.first(where: { $0.isAuto }) {
            self.currentQualityKey = autoOpt.key
            return (autoOpt.url, 0)
        }
        self.currentQualityKey = "Авто"
        return (fallbackUrl, 0)
    }

    private func restoreOrApplyQuality() {
        let dummyUrl = originalStreamURL ?? currentPlaybackSourceURL ?? URL(string: "about:blank")!
        let (_, targetBitrate) = selectPreservedPlaybackTarget(fallbackUrl: dummyUrl)
        if let currentKey = self.currentQualityKey, currentKey != "Авто" {
            let targetRes = targetResolution(for: currentKey)
            if targetRes != .zero {
                player?.currentItem?.preferredMaximumResolution = targetRes
            }
        }
        if let targetBitrate, targetBitrate > 0 {
            player?.currentItem?.preferredPeakBitRate = targetBitrate
        }
    }

    private func applyInitialQuality() {
        let prefRaw = UserDefaults.standard.string(forKey: "preferredVideoQuality") ?? VideoQualityPreference.ask.rawValue
        let globalPref = VideoQualityPreference(rawValue: prefRaw) ?? .ask
        let targetQuality = self.targetQualityPreference ?? (self.currentQualityKey.flatMap { VideoQualityPreference(rawValue: $0) }) ?? globalPref
        
        logDebug("applyInitialQuality: prefRaw=\(prefRaw), globalPref=\(globalPref.rawValue), targetQualityPreference=\(self.targetQualityPreference?.rawValue ?? "nil"), targetQuality=\(targetQuality.rawValue)")
        
        guard targetQuality != .ask && targetQuality != .auto else {
            logDebug("applyInitialQuality: targetQuality is .ask or .auto, returning without changing quality.")
            return
        }
        
        let targetKey = targetQuality.rawValue
        
        // Exact match (1080p -> 1080p)
        if let exact = availableQualities.first(where: { $0.key.hasPrefix(targetKey) }) {
            logDebug("applyInitialQuality: exact match found for targetKey '\(targetKey)' -> '\(exact.key)'")
            changeQuality(to: exact.key)
            return
        }
        
        // Find closest resolution
        let prefVal = normalizedQualityHeight(targetKey)
        guard prefVal > 0 else { return }
        
        var closest: String?
        var minDiff = Int.max
        for q in availableQualities {
            let val = normalizedQualityHeight(q.key)
            if val > 0 {
                let diff = abs(val - prefVal)
                if diff < minDiff {
                    minDiff = diff
                    closest = q.key
                }
            }
        }
        
        if let closestKey = closest {
            changeQuality(to: closestKey)
        }
    }

    
    private func startParsing(iframeUrl: String, voices: [String] = [], subtitles: [PlaybackSubtitle] = []) {
        resolveTask?.cancel()
        resolver?.cancel()

        let resolver = AllohaRuntimeResolver()
        self.resolver = resolver

        resolveTask = Task { [weak self] in
            do {
                let resolved = try await resolver.resolve(iframeUrl: iframeUrl)
                guard let self, !Task.isCancelled else { return }
                self.applyResolvedAllohaStream(resolved)
            } catch is CancellationError {
                return
            } catch {
                guard let self, !Task.isCancelled else { return }

                if let localized = error as? LocalizedError, let desc = localized.errorDescription {
                    self.error = desc
                } else if error is URLError {
                    self.error = "Нет подключения к интернету"
                } else {
                    self.error = "Не удалось загрузить видеопоток. Попробуйте еще раз."
                }
                self.isLoading = false
            }
        }
    }
    
    private var isPreparedForDismiss = false
    private var isCleaningUp = false

    /// Мгновенная подготовка к закрытию плеера: останавливает звук, снимает таймеры и KVO,
    /// фиксирует прогресс в памяти. Не выполняет дисковых и IPC операций, гарантируя 0ms задержки UI.
    func prepareForDismiss() {
        guard !isPreparedForDismiss else { return }
        isPreparedForDismiss = true

        PlaybackAnalyticsService.shared.stopWatching()

        // 1. Быстрая остановка аудио и видео
        player?.pause()
        isPlaying = false

        // 2. Мгновенная фиксация прогресса в памяти
        saveCurrentProgressInMemory()

        // 3. Отмена сетевых задач резолвера потоков и субтитров
        resolveTask?.cancel()
        resolveTask = nil
        resolver?.cancel()
        resolver = nil
        subtitleFetchTask?.cancel()
        subtitleFetchTask = nil
        activeSubtitleCues.removeAll()
        currentSubtitleText = nil

        // 4. Снятие высокочастотных KVO и таймеров
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        statusObserver?.invalidate()
        statusObserver = nil
        bufferObserver?.invalidate()
        bufferObserver = nil
        rateObserver?.invalidate()
        rateObserver = nil

        isInterfaceLocked = false
        UIApplication.shared.isIdleTimerDisabled = false
    }

    /// Полная очистка ресурсов после завершения анимации закрытия плеера
    func cleanup() {
        detachVideoOutput()
        prepareForDismiss()
        guard !isCleaningUp else { return }
        isCleaningUp = true
        PlaybackAnalyticsService.shared.stopWatching()

        // Читаем параметры прогресса до обнуления
        let mediaId = currentMediaId
        let playerPos = player?.currentTime().seconds ?? 0
        let pos = (playerPos.isFinite && !playerPos.isNaN && playerPos > 0) ? playerPos : currentTime
        let playerDur = player?.currentItem?.duration.seconds ?? 0
        let rawDur = (playerDur.isFinite && !playerDur.isNaN && playerDur > 0) ? playerDur : currentDuration
        let dur = (rawDur.isFinite && !rawDur.isNaN && rawDur >= 120) ? rawDur : nil
        let voiceover = _currentTranslationName
        let isSeekPending = isInitialSeekPending

        hasStartedLoading = false
        currentPlaybackSourceURL = nil
        originalStreamURL = nil
        isInitialSeekPending = false
        pendingSeekPosition = nil

        if let playbackEndObserver {
            NotificationCenter.default.removeObserver(playbackEndObserver)
            self.playbackEndObserver = nil
        }
        if let failedToEndObserver {
            NotificationCenter.default.removeObserver(failedToEndObserver)
            self.failedToEndObserver = nil
        }
        if let playbackStalledObserver {
            NotificationCenter.default.removeObserver(playbackStalledObserver)
            self.playbackStalledObserver = nil
        }
        if let resignActiveObserver {
            NotificationCenter.default.removeObserver(resignActiveObserver)
            self.resignActiveObserver = nil
        }
        if let foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
            self.foregroundObserver = nil
        }
        if let audioInterruptionObserver {
            NotificationCenter.default.removeObserver(audioInterruptionObserver)
            self.audioInterruptionObserver = nil
        }
        networkCancellable?.cancel()
        networkCancellable = nil

        clearNowPlaying()

        let finalMediaId = mediaId
        let finalPos = pos
        let finalDur = dur
        let finalVoiceover = voiceover
        let finalIsSeekPending = isSeekPending

        // Keep moments blocked until proxy/audio teardown is finished too. A
        // resumed moment must not have its audio session deactivated underneath it.
        let focusID = playbackFocusID
        // Отложенная очистка: даём UI-анимации закрытия завершиться без малейших микрофризов
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            self?.player = nil
            self?.legibleDelegate = nil
            self?.legibleOutput = nil

            if !finalIsSeekPending, let finalMediaId, finalPos > 1 {
                PlaybackProgressStore.shared.save(
                    mediaId: finalMediaId,
                    kpId: self?.currentKpId,
                    tmdbId: self?.tmdbId,
                    season: self?.currentSeason,
                    episode: self?.currentEpisode,
                    positionSec: finalPos,
                    durationSec: finalDur,
                    voiceover: finalVoiceover,
                    forceDiskSave: true
                )
            }

            HlsProxyServer.shared.stop()

            await Task.detached(priority: .utility) {
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            }.value
            PlaybackFocus.shared.endMainPlayer(focusID)
        }
    }

    // MARK: - Playback actions

    func togglePlayPause() {
        guard let player else { return }
        if isPlaying || player.rate > 0 || player.timeControlStatus == .playing {
            player.pause()
            isPlaying = false
            isBuffering = false
            isPausedByUser = true
            saveCurrentProgress()
        } else {
            isPausedByUser = false
            player.play()
            isPlaying = true
        }
        updateNowPlaying()
    }

    func seek(by seconds: Double) {
        guard let player else { return }
        let current = player.currentTime().seconds
        let validCurrent = (current.isFinite && !current.isNaN && current >= 0) ? current : currentTime
        let minTime: Double = isCollapsStream ? 3.5 : 0.0
        let target: Double
        if currentDuration > 0 {
            target = max(minTime, min(currentDuration, validCurrent + seconds))
        } else if let dur = player.currentItem?.duration.seconds, dur.isFinite, dur > 0 {
            target = max(minTime, min(dur, validCurrent + seconds))
        } else {
            target = max(minTime, validCurrent + seconds)
        }
        seek(to: target)
    }


    func seek(to seconds: Double) {
        guard let player else { return }
        let minTime: Double = isCollapsStream ? 3.5 : 0.0
        let effectiveSeconds = max(minTime, seconds)
        let time = CMTime(seconds: effectiveSeconds, preferredTimescale: 600)
        let tolerance = CMTime(seconds: 1.5, preferredTimescale: 600)
        isUserSeeking = true
        lastSeekTimestamp = Date()
        currentTime = effectiveSeconds
        updateSubtitleCue(at: effectiveSeconds)
        player.seek(to: time, toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isUserSeeking = false
                self.saveCurrentProgress()
                if !self.isPausedByUser {
                    self.player?.play()
                }
            }
        }
        updateNowPlaying()
    }

    func togglePiP() {
        guard let pip = pipController else { return }
        if pip.isPictureInPictureActive {
            pip.stopPictureInPicture()
        } else {
            pip.startPictureInPicture()
        }
    }

    // MARK: - In-Player Clip Trimmer Actions

    func enterClipMode() {
        attachVideoOutputIfNeeded()
        let current = (currentTime.isFinite && !currentTime.isNaN && currentTime >= 0) ? currentTime : 0
        let dur = currentDuration > 0 ? currentDuration : (current + 600)
        let s = max(0.0, current - 10.0)
        let e = min(dur, s + 30.0)
        clipStartTime = s
        clipEndTime = max(s + Self.clipMinDuration, e)
        clipCaption = ""
        clipPublishErrorMessage = nil
        isClipMode = true
        isClipPreviewRequested = false
        isPlaying = false
        player?.pause()
        if imageGenerator == nil, let asset = player?.currentItem?.asset {
            setupImageGenerator(asset: asset)
        }
        // Нативное поведение видеоредакторов: при входе в обрезку воспроизведение на паузе,
        // кадр выделения показан статично. Превью момента — по тапу на центр (с зацикливанием).
        seekClip(to: clipStartTime) { [weak self] in
            _ = self?.captureCurrentFrame()
        }
    }

    func exitClipMode() {
        isClipMode = false
        isClipPreviewRequested = false
        onClipPlaybackTimeUpdated = nil
        detachVideoOutput()
    }

    /// Фиксация выделения момента после жестов триммера (без seek — превью управляет триммер).
    func commitClipSelection(start: Double, end: Double) {
        let dur = currentDuration > 0 ? currentDuration : (end + 60.0)
        clipStartTime = max(0.0, start)
        clipEndTime = min(dur, max(start + Self.clipMinDuration, end))
    }

    /// Пауза на время взаимодействия с ручками (нативно: обрезка всегда на паузе).
    func pauseForTrim() {
        isPausedByUser = true
        player?.pause()
    }

    // MARK: - Динамическое подключение VideoOutput (только на время создания момента)

    func attachVideoOutputIfNeeded() {
        guard videoOutput == nil, let item = player?.currentItem else { return }
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        let vOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: pixelBufferAttributes)
        item.add(vOutput)
        self.videoOutput = vOutput
    }

    func detachVideoOutput() {
        guard let vOutput = videoOutput else { return }
        if let item = player?.currentItem {
            item.remove(vOutput)
        }
        self.videoOutput = nil
    }

    // MARK: - Превью выбранного момента (детерминированное, в обход неоднозначного togglePlayPause)

    /// Показывает, что пользователь хочет играть превью выделения (сбрасывается паузой).
    var isClipPreviewRequested = false

    /// Нативный просмотр момента: точный seek к началу выделения и запуск воспроизведения.
    /// Вызывается тапом по центру — всегда начинает с начала выделения (как в Photos).
    func playClipPreview() {
        guard let player else { return }
        isClipPreviewRequested = true
        let target = max(0.0, clipStartTime)
        let time = CMTime(seconds: target, preferredTimescale: 600)
        let tol = CMTime(seconds: 0.1, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: tol, toleranceAfter: tol) { [weak self] _ in
            guard let self else { return }
            // Пока шёл seek, пользователь мог передумать (тапнул паузу/вышел из режима)
            guard self.isClipMode, self.isClipPreviewRequested else { return }
            self.player?.play()
            self.isPlaying = true
            self.updateNowPlaying()
        }
    }

    /// Останавливает превью выделения.
    func pauseClipPreview() {
        isClipPreviewRequested = false
        isPausedByUser = true
        player?.pause()
        isPlaying = false
    }

    /// Захват текущего кадра из работающего декодера плеера (AVPlayerItemVideoOutput).
    /// Подключается только по требованию, забирает уже отрендеренный декодером кадр без доп. перемоток.
    func captureCurrentFrame() -> UIImage? {
        guard let player, let item = player.currentItem else { return nil }
        if videoOutput == nil {
            attachVideoOutputIfNeeded()
        }
        guard let videoOutput else { return nil }
        let itemTime = item.currentTime()
        guard let pixelBuffer = videoOutput.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil) else {
            return nil
        }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        // Даунскейл до ширины слота плёнки — кадр 1080p в память не нужен
        let targetWidth: CGFloat = 320
        let scale = targetWidth / max(1.0, ciImage.extent.width)
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = Self.sharedCIContext.createCGImage(scaled, from: scaled.extent) else { return nil }
        let img = UIImage(cgImage: cgImage)
        self.latestCapturedFrame = img
        return img
    }

    /// Точный seek в режиме момента (границы выделения, зацикливание превью).
    func seekClip(to seconds: Double, completion: (() -> Void)? = nil) {
        guard let player else {
            completion?()
            return
        }
        let time = CMTime(seconds: max(0.0, seconds), preferredTimescale: 600)
        let tol = CMTime(seconds: 0.1, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: tol, toleranceAfter: tol) { _ in
            completion?()
        }
    }

    /// Грубый быстрый seek для превью за ручкой триммера (в движении пальца).
    func seekClipFast(to seconds: Double) {
        guard let player else { return }
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        let tol = CMTime(seconds: 0.35, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: tol, toleranceAfter: tol)
    }

    func publishClip() async throws {
        guard !isClipPublishing else { return }
        isClipPublishing = true
        clipPublishErrorMessage = nil
        defer { isClipPublishing = false }

        let user = AuthRepository.shared.currentUser
        let authorId = user?.id ?? "guest_\(UIDevice.current.identifierForVendor?.uuidString ?? "user")"
        let authorName = (user?.displayName?.isEmpty == false ? user?.displayName : nil) ?? user?.displayTitle ?? "Зритель"
        let authorAvatar = user?.photoURL

        let resolvedTitle = !fallbackTitle.isEmpty ? fallbackTitle : (isMovie ? "Фильм" : "Сериал")

        let clip = MovieClip(
            mediaId: tmdbId ?? currentKpId ?? 0,
            mediaType: isMovie ? "movie" : "tv",
            title: resolvedTitle,
            posterPath: posterUrl,
            backdropPath: backdropUrl,
            logoPath: logoUrl,
            season: currentSeason,
            episode: currentEpisode,
            translationName: currentTranslationName,
            startTime: clipStartTime,
            endTime: clipEndTime,
            caption: clipCaption.trimmingCharacters(in: .whitespacesAndNewlines),
            authorId: authorId,
            authorName: authorName,
            authorAvatar: authorAvatar,
            streamUrl: activeStreamUrlString,
            iframeUrl: activeIframeUrl,
            kpId: currentKpId,
            tmdbId: tmdbId
        )

        try await ClipsRepository.shared.publishClip(clip)
        exitClipMode()
    }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        player?.rate = rate
        updateNowPlaying()
    }

    func setSubtitle(_ subtitle: PlaybackSubtitle?) {
        currentSubtitle = subtitle
        logDebug("setSubtitle: user selected '\(subtitle?.label ?? "Выкл.")'")

        subtitleFetchTask?.cancel()
        subtitleFetchTask = nil
        activeSubtitleCues = []
        currentSubtitleText = nil

        guard let subtitle = subtitle else {
            applySubtitleToPlayer(nil)
            return
        }

        let didSelectNative = applySubtitleToPlayer(subtitle)
        if didSelectNative {
            logDebug("setSubtitle: native track applied to AVPlayer, external VTT fetch skipped")
            return
        }

        if subtitle.url.hasPrefix("http://") || subtitle.url.hasPrefix("https://") {
            loadExternalSubtitles(from: subtitle.url)
        }
    }

    private func loadExternalSubtitles(from urlString: String) {
        guard let url = URL(string: urlString) else { return }
        logDebug("loadExternalSubtitles: fetching from \(url.absoluteString)")

        let headers = customHeaders ?? currentHeaders
        subtitleFetchTask = Task { [weak self] in
            guard let self else { return }
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 10
                for (k, v) in headers {
                    request.setValue(v, forHTTPHeaderField: k)
                }
                if request.value(forHTTPHeaderField: "User-Agent") == nil {
                    request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X)", forHTTPHeaderField: "User-Agent")
                }

                let (data, response) = try await self.trustedSession.data(for: request)
                if Task.isCancelled { return }

                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    self.logDebug("loadExternalSubtitles: non-200 HTTP response")
                    return
                }

                let text = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .windowsCP1251)
                    ?? String(decoding: data, as: UTF8.self)

                let cues = WebVTTParser.parse(text: text)
                self.logDebug("loadExternalSubtitles: parsed \(cues.count) cues from \(url.lastPathComponent)")

                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.activeSubtitleCues = cues
                    self.updateSubtitleCue(at: self.currentTime)
                }
            } catch {
                if !Task.isCancelled {
                    self.logDebug("loadExternalSubtitles: failed to fetch: \(error.localizedDescription)")
                }
            }
        }
    }

    func updateSubtitleCue(at time: TimeInterval) {
        guard !activeSubtitleCues.isEmpty else { return }
        let cue = WebVTTParser.cue(at: time, in: activeSubtitleCues)
        let newText = cue?.text
        if currentSubtitleText != newText {
            currentSubtitleText = newText
        }
    }

    @discardableResult
    private func applySubtitleToPlayer(_ subtitle: PlaybackSubtitle?) -> Bool {
        guard let player = player,
              let item = player.currentItem,
              let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible) else {
            logDebug("applySubtitleToPlayer: legible group not available yet")
            return false
        }

        guard let subtitle = subtitle else {
            if group.allowsEmptySelection {
                item.select(nil, in: group)
            }
            logDebug("applySubtitleToPlayer: disabled subtitles (selected nil)")
            return false
        }

        // External VTT subtitles are loaded and rendered by our custom parser and overlay
        if subtitle.url.hasPrefix("http://") || subtitle.url.hasPrefix("https://") {
            if group.allowsEmptySelection {
                item.select(nil, in: group)
            }
            logDebug("applySubtitleToPlayer: external VTT subtitle '\(subtitle.label)' — deselected native track")
            return false
        }

        let options = group.options
        logDebug("applySubtitleToPlayer: target='\(subtitle.label)', url='\(subtitle.url)', available options=\(options.map { $0.displayName })")

        // 0. Native track index if url is "native_X"
        if subtitle.url.hasPrefix("native_"),
           let idxStr = subtitle.url.components(separatedBy: "_").last,
           let idx = Int(idxStr),
           idx < options.count {
            item.select(options[idx], in: group)
            logDebug("applySubtitleToPlayer: selected native index [\(idx)] '\(options[idx].displayName)'")
            activeSubtitleCues = []
            return true
        }

        // 1. Exact match by displayName
        let cleanTarget = subtitle.label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let option = options.first(where: {
            $0.displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == cleanTarget
        }) {
            item.select(option, in: group)
            logDebug("applySubtitleToPlayer: selected exact match native option '\(option.displayName)'")
            activeSubtitleCues = []
            return true
        }

        // 2. Fuzzy match by name containment
        let subLabel = subtitle.label.lowercased()
        if let option = options.first(where: {
            let optName = $0.displayName.lowercased()
            return optName.contains(subLabel) || subLabel.contains(optName)
        }) {
            item.select(option, in: group)
            logDebug("applySubtitleToPlayer: selected fuzzy match native option '\(option.displayName)'")
            activeSubtitleCues = []
            return true
        }

        // 3. Match by index in availableSubtitles
        if let idx = availableSubtitles.firstIndex(where: { $0.url == subtitle.url && $0.label == subtitle.label }),
           idx < options.count {
            item.select(options[idx], in: group)
            logDebug("applySubtitleToPlayer: selected index match [\(idx)] '\(options[idx].displayName)'")
            activeSubtitleCues = []
            return true
        }

        // 4. Match by language code
        if !subtitle.lang.isEmpty,
           let option = options.first(where: {
               $0.locale?.language.languageCode?.identifier.lowercased() == subtitle.lang.lowercased() ||
               $0.extendedLanguageTag?.lowercased().hasPrefix(subtitle.lang.lowercased()) == true
           }) {
            item.select(option, in: group)
            logDebug("applySubtitleToPlayer: selected language match native option '\(option.displayName)'")
            activeSubtitleCues = []
            return true
        }

        // Ни одна нативная дорожка не подошла — сбрасываем выбор в AVPlayer (будет воспроизведено через SubtitleOverlayView)
        if group.allowsEmptySelection {
            item.select(nil, in: group)
        }
        return false
    }


    /// Переключает озвучку без закрытия плеера с сохранением позиции воспроизведения и качества видео
    func switchVoiceover(to name: String, at index: Int? = nil) {
        logDebug("switchVoiceover: switching to '\(name)' at index \(index ?? -1)")
        let savedTime: Double = {
            if self.isInitialSeekPending, let pending = self.pendingSeekPosition { return pending }
            if self.isUserSeeking { return self.currentTime }
            let pos = self.player?.currentTime().seconds ?? 0
            return (pos > 0 && pos.isFinite && !pos.isNaN) ? pos : self.currentTime
        }()
        let canonicalName: String = {
            if let matched = self.availableVoiceovers.first(where: { allohaTranslationNamesMatch($0, name, exactOnly: true) })
                ?? self.availableVoiceovers.first(where: { allohaTranslationNamesMatch($0, name, exactOnly: false) }) {
                return matched
            }
            return cleanTranslationName(name)
        }()

        // 1. Ищем target AllohaTranslation в seriesResult (для сериалов и фильмов с отдельными iframe)
        var targetTranslation: AllohaTranslation?

        if isMovie {
            if let movie = seriesResult?.movie {
                if let match = movie.translations.first(where: { allohaTranslationNamesMatch($0.name, name, exactOnly: true) }) {
                    targetTranslation = match
                } else if let match = movie.translations.first(where: { allohaTranslationNamesMatch($0.name, name, exactOnly: false) }) {
                    targetTranslation = match
                } else if let idx = index, idx < movie.translations.count {
                    let candidate = movie.translations[idx]
                    if allohaTranslationNamesMatch(candidate.name, name) {
                        targetTranslation = candidate
                    }
                }
            }
        } else {
            if let seriesResult, let season = currentSeason, let episode = currentEpisode,
               let seasonObj = seriesResult.seasons.first(where: { $0.season == season }),
               let epObj = seasonObj.episodes.first(where: { $0.episode == episode }) {
                if let match = epObj.translations.first(where: { allohaTranslationNamesMatch($0.name, name, exactOnly: true) }) {
                    targetTranslation = match
                } else if let match = epObj.translations.first(where: { allohaTranslationNamesMatch($0.name, name, exactOnly: false) }) {
                    targetTranslation = match
                } else if let idx = index, idx < epObj.translations.count {
                    let candidate = epObj.translations[idx]
                    if allohaTranslationNamesMatch(candidate.name, name) {
                        targetTranslation = candidate
                    }
                }
            }
        }

        // 2. Если найдена отдельная translation в seriesResult:
        if let translation = targetTranslation {
            let matchedCanonical = self.availableVoiceovers.first(where: { allohaTranslationNamesMatch($0, translation.name, exactOnly: true) })
                ?? self.availableVoiceovers.first(where: { allohaTranslationNamesMatch($0, translation.name, exactOnly: false) })
                ?? canonicalName
            logDebug("switchVoiceover: matched targetTranslation='\(matchedCanonical)', iframeUrl='\(translation.iframeUrl)'")
            _currentTranslationName = matchedCanonical
            targetVoiceover = matchedCanonical
            persistVoiceoverSelection(matchedCanonical)
            HlsProxyServer.shared.updatePreferredVoice(matchedCanonical)
            saveCurrentProgress()

            // 2a. Если уже есть прямой pre-resolved стрим
            if let streamUrlString = translation.streamUrl, let streamUrl = URL(string: streamUrlString) {
                logDebug("switchVoiceover: using pre-resolved streamUrl=\(streamUrlString)")
                self.currentTime = savedTime

                if streamUrl == self.originalStreamURL {
                    let resolvedIndex = index
                        ?? self.availableVoiceovers.firstIndex(where: { allohaTranslationNamesMatch($0, name, exactOnly: true) })
                        ?? self.availableVoiceovers.firstIndex(where: { allohaTranslationNamesMatch($0, name, exactOnly: false) })
                    self.selectAudioTrackInPlayer(named: name, at: resolvedIndex)
                    return
                }

                let (targetPlaybackUrl, activeBitrate) = self.selectPreservedPlaybackTarget(fallbackUrl: streamUrl)
                reloadPlayback(to: targetPlaybackUrl, preferredPeakBitRate: activeBitrate)
                return
            }

            // 2b. Резолвим iframeUrl для выбранной озвучки, если он отличается от текущего
            let iframeUrl = translation.iframeUrl
            if !iframeUrl.isEmpty && iframeUrl != self.currentIframeUrl {
                self.currentIframeUrl = iframeUrl
                AllohaRuntimeResolver.invalidateCache(for: iframeUrl)
                resolveTask?.cancel()
                resolver?.cancel()

                isLoading = true
                let resolver = AllohaRuntimeResolver()
                self.resolver = resolver

                resolveTask = Task { [weak self] in
                    do {
                        let resolved = try await resolver.resolve(iframeUrl: iframeUrl)
                        guard let self, !Task.isCancelled else { return }

                        var resolvedUrlString = (resolved["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        let audioVariants = (resolved["audioVariants"] as? [[String: Any]]) ?? []
                        self.resolvedAudioVariants = audioVariants

                        let matchedVariant = findMatchingAudioVariant(in: audioVariants, for: translation.name, isDedicatedIframe: true)
                        if let matchedVariant,
                           let variantUrl = (matchedVariant["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                           !variantUrl.isEmpty {
                            resolvedUrlString = variantUrl
                            logDebug("switchVoiceover: matched audioVariant '\(matchedVariant["title"] ?? "")' -> \(variantUrl)")
                        } else {
                            logDebug("switchVoiceover: no audioVariant matched for '\(translation.name)', available variants: \(audioVariants.compactMap { $0["title"] as? String })")
                        }

                        guard let resolvedUrl = URL(string: resolvedUrlString) else {
                            self.error = "Не удалось извлечь ссылку на видео"
                            self.isLoading = false
                            return
                        }

                        let headers = (resolved["headers"] as? [String: String]) ?? [:]
                        self.currentHeaders = headers

                        let resolvedSubs = self.resolvedSubtitles(from: resolved)
                        if !resolvedSubs.isEmpty {
                            self.availableSubtitles = resolvedSubs
                        }

                        if let intro = resolved["introRange"] as? [String: Double],
                           let start = intro["start"], let end = intro["end"] {
                            self.introRange = start...end
                        } else {
                            self.introRange = nil
                        }
                        if let outro = resolved["outroRange"] as? [String: Double],
                           let start = outro["start"], let end = outro["end"] {
                            self.outroRange = start...end
                        } else {
                            self.outroRange = nil
                        }

                        let qualityVariants = (resolved["qualityVariants"] as? [[String: Any]]) ?? []

                        self.availableQualities = self.makeResolvedQualityOptions(
                            resolvedUrl: resolvedUrl,
                            qualityVariants: qualityVariants,
                            audioVariants: audioVariants,
                            preferredAudioVariant: matchedVariant
                        )

                        self.currentTime = savedTime
                        let (targetPlaybackUrl, activeBitrate) = self.selectPreservedPlaybackTarget(fallbackUrl: resolvedUrl)
                        self.reloadPlayback(to: targetPlaybackUrl, preferredPeakBitRate: activeBitrate, qualityKey: self.currentQualityKey)
                        NotificationCenter.default.post(name: NSNotification.Name("QualitiesUpdated"), object: nil)
                    } catch {
                        guard let self, !Task.isCancelled else { return }
                        self.error = "Не удалось переключить озвучку"
                        self.isLoading = false
                    }
                }
                return
            }
        }

        // 3. Быстрое переключение через resolvedAudioVariants (прямые HLS ссылки внутри текущего iframe)
        if !resolvedAudioVariants.isEmpty {
            if let variant = findMatchingAudioVariant(in: resolvedAudioVariants, for: name, isDedicatedIframe: false),
               let variantUrlString = (variant["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
               let variantUrl = URL(string: variantUrlString) {
                logDebug("switchVoiceover: fast switching to audioVariant '\(canonicalName)' -> \(variantUrlString)")
                _currentTranslationName = canonicalName
                targetVoiceover = canonicalName
                persistVoiceoverSelection(canonicalName)
                saveCurrentProgress()
                
                self.currentTime = savedTime
                self.availableQualities = self.makeResolvedQualityOptions(
                    resolvedUrl: variantUrl,
                    qualityVariants: (variant["qualityVariants"] as? [[String: Any]]) ?? [],
                    audioVariants: resolvedAudioVariants,
                    preferredAudioVariant: variant
                )
                
                let (targetPlaybackUrl, activeBitrate) = self.selectPreservedPlaybackTarget(fallbackUrl: variantUrl)
                self.reloadPlayback(to: targetPlaybackUrl, preferredPeakBitRate: activeBitrate)
                NotificationCenter.default.post(name: NSNotification.Name("QualitiesUpdated"), object: nil)
                return
            }
        }

        // 4. Фолбэк: если это мульти-аудио HLS стрим без отдельных iframe, переключаем нативную аудиодорожку
        _currentTranslationName = canonicalName
        targetVoiceover = canonicalName
        persistVoiceoverSelection(canonicalName)
        HlsProxyServer.shared.updatePreferredVoice(canonicalName)
        saveCurrentProgress()
        selectAudioTrackInPlayer(named: name, at: index)
    }


    /// Сохраняет текущую позицию воспроизведения. Вызывается и по таймеру, и при закрытии/сворачивании приложения.
    private func saveCurrentProgress() {
        guard !isInitialSeekPending else { return }
        guard let mediaId = currentMediaId else { return }
        let playerPos = player?.currentTime().seconds ?? 0
        let pos = (playerPos.isFinite && !playerPos.isNaN && playerPos > 0) ? playerPos : currentTime
        guard pos.isFinite, !pos.isNaN, pos > 1 else { return }

        let playerDur = player?.currentItem?.duration.seconds ?? 0
        let rawDur = (playerDur.isFinite && !playerDur.isNaN && playerDur > 0) ? playerDur : currentDuration
        let dur = (rawDur.isFinite && !rawDur.isNaN && rawDur >= 120) ? rawDur : nil
        PlaybackProgressStore.shared.save(
            mediaId: mediaId,
            kpId: currentKpId,
            tmdbId: tmdbId,
            season: currentSeason,
            episode: currentEpisode,
            positionSec: pos,
            durationSec: dur,
            voiceover: _currentTranslationName,
            forceDiskSave: true
        )
    }

    /// Быстрое сохранение позиции воспроизведения только в оперативную память (без синхронной записи на диск)
    private func saveCurrentProgressInMemory() {
        guard !isInitialSeekPending else { return }
        guard let mediaId = currentMediaId else { return }
        let playerPos = player?.currentTime().seconds ?? 0
        let pos = (playerPos.isFinite && !playerPos.isNaN && playerPos > 0) ? playerPos : currentTime
        guard pos.isFinite, !pos.isNaN, pos > 1 else { return }

        let playerDur = player?.currentItem?.duration.seconds ?? 0
        let rawDur = (playerDur.isFinite && !playerDur.isNaN && playerDur > 0) ? playerDur : currentDuration
        let dur = (rawDur.isFinite && !rawDur.isNaN && rawDur >= 120) ? rawDur : nil
        PlaybackProgressStore.shared.save(
            mediaId: mediaId,
            kpId: currentKpId,
            tmdbId: tmdbId,
            season: currentSeason,
            episode: currentEpisode,
            positionSec: pos,
            durationSec: dur,
            voiceover: _currentTranslationName,
            forceDiskSave: false
        )
    }

    
    func changeQuality(to key: String) {
        logDebug("changeQuality: called with key='\(key)'")
        guard let quality = availableQualities.first(where: { $0.key == key }) else {
            logDebug("changeQuality: quality key '\(key)' not found in availableQualities!")
            return
        }
        self.currentQualityKey = key
        
        if let newPreference = VideoQualityPreference(rawValue: key) {
            self.targetQualityPreference = newPreference
        }
        
        let targetRes = targetResolution(for: key)
        let targetBitrate = resolvedBitrate(for: quality)
        logDebug("changeQuality: quality='\(key)', targetBitrate=\(targetBitrate), targetResolution=\(targetRes)")
        
        if quality.isAuto {
            player?.currentItem?.preferredPeakBitRate = 0
            player?.currentItem?.preferredMaximumResolution = .zero
            let targetUrl = masterStreamURL ?? originalStreamURL ?? quality.url
            reloadPlayback(to: targetUrl, preferredPeakBitRate: 0, preferredMaximumResolution: .zero, qualityKey: nil)
            return
        }

        // Перезапускаем поток с передачей qualityKey в прокси, чтобы PlaybackHlsRewriter
        // зафиксировал плейлист на выбранном качестве (1080p, 720p и т.д.)
        let targetUrl = quality.shouldReloadOnSelect ? quality.url : (masterStreamURL ?? originalStreamURL ?? quality.url)
        reloadPlayback(to: targetUrl, preferredPeakBitRate: targetBitrate, preferredMaximumResolution: targetRes, qualityKey: key)
    }

    private func reloadPlayback(to sourceURL: URL, preferredPeakBitRate: Double?, preferredMaximumResolution: CGSize = .zero, qualityKey: String? = nil) {
        logDebug("reloadPlayback: called with sourceURL=\(sourceURL.absoluteString), preferredPeakBitRate=\(preferredPeakBitRate ?? -1), qualityKey=\(qualityKey ?? "none")")
        let savedTime: Double = {
            if self.isInitialSeekPending, let pending = self.pendingSeekPosition, pending > 2 {
                return pending
            }
            if self.currentTime > 2 {
                return self.currentTime
            }
            if let mediaId = self.currentMediaId {
                let s = PlaybackProgressStore.shared.load(mediaId: mediaId)
                if s > 2 { return s }
            }
            return 0
        }()
        let wasPlaying = player?.timeControlStatus == .playing || player?.timeControlStatus == .waitingToPlayAtSpecifiedRate
        self.wasPlayingBeforeReload = wasPlaying

        if savedTime > 2 {
            self.isInitialSeekPending = true
            self.pendingSeekPosition = savedTime
            self.currentTime = savedTime
            logDebug("reloadPlayback: preserving seek target \(savedTime)s")
        }

        // Обновляем originalStreamURL если пришёл не прокси-URL
        if !isLocalProxyUrl(sourceURL) {
            originalStreamURL = sourceURL.absoluteURL
            if masterStreamURL == nil {
                masterStreamURL = sourceURL.absoluteURL
            }
        }

        let asset: AVURLAsset
        let urlStringLower = sourceURL.absoluteString.lowercased()
        let isHls = urlStringLower.contains(".m3u8")

        if sourceURL.absoluteString.contains("127.0.0.1") || sourceURL.absoluteString.contains("localhost") {
            currentPlaybackSourceURL = sourceURL.absoluteURL
            asset = AVURLAsset(url: sourceURL)
        } else if sourceURL.isFileURL {
            currentPlaybackSourceURL = sourceURL.absoluteURL
            asset = AVURLAsset(url: sourceURL)
        } else if !isHls {
            logDebug("reloadPlayback: Direct stream URL played with headers")
            currentPlaybackSourceURL = sourceURL.absoluteURL
            let options = ["AVURLAssetHTTPHeaderFieldsKey": currentHeaders]
            asset = AVURLAsset(url: sourceURL, options: options)
        } else {
            let effectiveQuality = qualityKey ?? (self.currentQualityKey != "Авто" ? self.currentQualityKey : nil)
            guard let proxyUrl = proxiedPlaybackURL(for: sourceURL, quality: effectiveQuality) else { return }
            logDebug("reloadPlayback: Proxied HLS stream URL: \(proxyUrl.absoluteString)")
            currentPlaybackSourceURL = proxyUrl
            asset = AVURLAsset(url: proxyUrl)
        }

        let playerItem = AVPlayerItem(asset: asset)
        playerItem.preferredPeakBitRate = max(0, preferredPeakBitRate ?? 0)
        playerItem.preferredMaximumResolution = preferredMaximumResolution
        playerItem.preferredForwardBufferDuration = 0.0

        self.isLoading = true

        self.player?.replaceCurrentItem(with: playerItem)
        setupPlayerItemObservers(for: playerItem)

        if self.currentTime > 2 {
            self.isInitialSeekPending = true
            self.pendingSeekPosition = self.currentTime
            let tolerance = CMTime(seconds: 1.5, preferredTimescale: 600)
            self.player?.seek(
                to: CMTime(seconds: self.currentTime, preferredTimescale: 600),
                toleranceBefore: tolerance,
                toleranceAfter: tolerance
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isInitialSeekPending = false
                    self.pendingSeekPosition = nil
                    if !self.isPausedByUser {
                        self.player?.play()
                    }
                }
            }
        }
    }

    private func proxiedPlaybackURL(for sourceURL: URL, quality: String? = nil) -> URL? {
        let absoluteUrlString = sourceURL.absoluteURL.absoluteString
        guard let encodedData = absoluteUrlString.data(using: .utf8) else { return nil }
        let encoded = encodedData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        let ext = sourceURL.pathExtension
        let pathSuffix = ext.isEmpty ? "stream.m3u8" : "stream.\(ext)"

        var baseString = "http://127.0.0.1:\(HlsProxyServer.shared.port.rawValue)/proxy/\(pathSuffix)?url=\(encoded)"
        if let quality, !quality.isEmpty, quality != "Авто", quality.lowercased() != "auto" {
            if let encQ = quality.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                baseString += "&q=\(encQ)"
            }
        }

        return URL(string: baseString)
    }

    private func shouldReloadForAutoSelection(autoURL: URL) -> Bool {
        guard let currentPlaybackSourceURL else { return false }
        if currentPlaybackSourceURL.absoluteURL.absoluteString == autoURL.absoluteURL.absoluteString {
            return false
        }
        if currentPlaybackSourceURL.absoluteString.contains("&q=") || currentPlaybackSourceURL.absoluteString.contains("?q=") {
            return true
        }
        if isLocalProxyUrl(currentPlaybackSourceURL), let orig = originalStreamURL, orig.absoluteURL.absoluteString == autoURL.absoluteURL.absoluteString {
            return false
        }
        return true
    }

    private func normalizedQualityHeight(_ key: String) -> Int {
        let clean = key.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.contains("4k") || clean.contains("2160") { return 2160 }
        if clean.contains("2k") || clean.contains("1440") { return 1440 }
        if clean.contains("1080") { return 1080 }
        if clean.contains("720") { return 720 }
        if clean.contains("480") { return 480 }
        if clean.contains("360") { return 360 }
        if clean.contains("240") { return 240 }
        if let regex = try? NSRegularExpression(pattern: #"(\d{3,4})"#),
           let match = regex.firstMatch(in: clean, range: NSRange(clean.startIndex..<clean.endIndex, in: clean)),
           let r = Range(match.range(at: 1), in: clean),
           let val = Int(clean[r]) {
            return val
        }
        return 0
    }

    private func targetResolution(for qualityKey: String) -> CGSize {
        let height = normalizedQualityHeight(qualityKey)
        switch height {
        case 2160...: return CGSize(width: 3840, height: 2160)
        case 1440..<2160: return CGSize(width: 2560, height: 1440)
        case 1080..<1440: return CGSize(width: 1920, height: 1080)
        case 720..<1080: return CGSize(width: 1280, height: 720)
        case 480..<720: return CGSize(width: 854, height: 480)
        case 360..<480: return CGSize(width: 640, height: 360)
        case 1..<360: return CGSize(width: 426, height: 240)
        default: return .zero
        }
    }

    private func resolvedBitrate(for quality: PlaybackQualityOption) -> Double {
        resolvedBitrate(forQualityKey: quality.key, fallbackBandwidth: quality.preferredPeakBitRate)
    }

    private func resolvedBitrate(forQualityKey key: String, fallbackBandwidth: Double? = nil) -> Double {
        let height = normalizedQualityHeight(key)
        switch height {
        case 2160...: return 25_000_000 // 4K UHD
        case 1440..<2160: return 16_000_000 // 2K/1440p
        case 1080..<1440: return 10_000_000 // Full HD
        case 720..<1080: return 6_000_000 // HD
        case 480..<720: return 2_500_000 // 480p
        case 360..<480: return 1_200_000 // 360p
        case 1..<360: return 800_000
        default:
            if let bw = fallbackBandwidth, bw > 0 {
                return bw * 2.5
            }
            return 0
        }
    }

    private func bitrateValue(from variant: [String: Any]) -> Double? {
        if let bitrate = variant["bitrate"] as? Double, bitrate > 0 { return bitrate }
        if let bitrate = variant["bitrate"] as? NSNumber, bitrate.doubleValue > 0 { return bitrate.doubleValue }
        if let bandwidth = variant["bandwidth"] as? Double, bandwidth > 0 { return bandwidth }
        if let bandwidth = variant["bandwidth"] as? NSNumber, bandwidth.doubleValue > 0 { return bandwidth.doubleValue }
        return nil
    }

    private func absoluteQualityURL(from rawURL: String) -> URL? {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)?.absoluteURL
    }

    private func makeQualityOption(
        key: String,
        url: URL,
        preferredPeakBitRate: Double?,
        isAuto: Bool,
        shouldReloadOnSelect: Bool
    ) -> PlaybackQualityOption {
        PlaybackQualityOption(
            key: key,
            url: url.absoluteURL,
            preferredPeakBitRate: preferredPeakBitRate,
            isAuto: isAuto,
            shouldReloadOnSelect: shouldReloadOnSelect
        )
    }

    private func makeAutoQualityOption(url: URL) -> PlaybackQualityOption {
        makeQualityOption(
            key: "Авто",
            url: url,
            preferredPeakBitRate: nil,
            isAuto: true,
            shouldReloadOnSelect: false
        )
    }

    private func makeResolvedQualityOptions(
        resolvedUrl: URL,
        qualityVariants: [[String: Any]],
        audioVariants: [[String: Any]],
        preferredAudioVariant: [String: Any]? = nil
    ) -> [PlaybackQualityOption] {
        let targetVoice = targetVoiceover ?? _currentTranslationName
        let isDedicated = currentIframeUrl != nil
        let selectedAudioVariant: [String: Any]? = preferredAudioVariant
            ?? {
                if let target = targetVoice, !target.isEmpty {
                    return findMatchingAudioVariant(in: audioVariants, for: target, isDedicatedIframe: isDedicated)
                }
                return nil
            }()
            ?? (isDedicated ? nil : audioVariants.first(where: { (($0["url"] as? String) ?? "").isEmpty == false }))

        let activeUrl: URL = {
            if let variantUrlString = selectedAudioVariant?["url"] as? String,
               let variantUrl = URL(string: variantUrlString.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return variantUrl
            }
            return resolvedUrl
        }()

        var qualities = [makeAutoQualityOption(url: activeUrl)]
        var seenKeys = Set<String>(["Авто"])

        if let selectedAudio = selectedAudioVariant,
           let nestedQualityVariants = selectedAudio["qualityVariants"] as? [[String: Any]],
           !nestedQualityVariants.isEmpty {
            appendQualityVariants(nestedQualityVariants, masterUrl: activeUrl, to: &qualities, seenKeys: &seenKeys)
        } else {
            appendQualityVariants(qualityVariants, masterUrl: activeUrl, to: &qualities, seenKeys: &seenKeys)
        }

        // Filter out any qualities higher than 1080p (e.g. 1440p, 2160p)
        qualities = qualities.filter { q in
            if q.isAuto { return true }
            let h = normalizedQualityHeight(q.key)
            return h <= 1080
        }

        if qualities.count > 1 {
            let autoQuality = qualities.removeFirst()
            qualities.sort { lhs, rhs in
                normalizedQualityHeight(lhs.key) > normalizedQualityHeight(rhs.key)
            }
            qualities.insert(autoQuality, at: 0)
        }
        
        let originalLabels = qualityVariants.compactMap { $0["label"] as? String }.joined(separator: ", ")
        logDebug("makeResolvedQualityOptions: server returned qualities = [\(originalLabels)]")
        logDebug("makeResolvedQualityOptions: final qualities for player = [\(qualities.map { $0.key }.joined(separator: ", "))]")

        return qualities
    }
    
    
    private func playVideo(url: URL, headers: [String: String], voices: [String] = [], subtitles: [PlaybackSubtitle] = []) {
        guard !isPreparedForDismiss, !isCleaningUp else { return }
        acquirePlaybackFocus()
        logDebug("playVideo: starting playback, url=\(url.absoluteString)")
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        // Запрещаем автоблокировку экрана во время воспроизведения:
        // без этого экран гаснет через 5 минут, iOS замораживает процесс и прокси падает
        UIApplication.shared.isIdleTimerDisabled = true
        // Сохраняем оригинальный URL ДО проксирования — нужен для перезапуска после фона
        originalStreamURL = url.absoluteURL
        masterStreamURL = url.absoluteURL
        currentHeaders = headers

        let asset: AVURLAsset
        let urlStringLower = url.absoluteString.lowercased()
        let isMp4 = url.pathExtension.lowercased() == "mp4" || (!urlStringLower.contains(".m3u8") && urlStringLower.contains(".mp4"))
        // Определяем, является ли контент локальным (скачанным)
        let isLocalFile = url.absoluteString.contains("/local/") || url.isFileURL

        if url.absoluteString.contains("127.0.0.1") || url.absoluteString.contains("localhost") {
            // Уже локальный URL — не проксируем
            logDebug("playVideo: local proxy URL directly played")
            currentPlaybackSourceURL = url.absoluteURL
            HlsProxyServer.shared.start(headers: [:], voices: [], subtitles: [], mediaId: "local")
            asset = AVURLAsset(url: url)
        } else if url.isFileURL {
            logDebug("playVideo: file URL directly played")
            currentPlaybackSourceURL = url.absoluteURL
            asset = AVURLAsset(url: url)
        } else if isMp4 {
            // Прямые ссылки на .mp4 файлы (обычно 1440p и 2160p от Alloha) не проксируем,
            // так как прокси HLS попытается загрузить весь файл в оперативную память, вызывая OOM/таймаут.
            logDebug("playVideo: MP4 URL directly played with headers")
            currentPlaybackSourceURL = url.absoluteURL
            let options = ["AVURLAssetHTTPHeaderFieldsKey": headers]
            asset = AVURLAsset(url: url, options: options)
        } else {
            let initialQuality: String? = {
                if let current = self.currentQualityKey, !current.isEmpty, current != "Авто" {
                    return current
                }
                if let pref = self.targetQualityPreference, pref != .ask && pref != .auto {
                    return pref.rawValue
                }
                let saved = UserDefaults.standard.string(forKey: "preferredVideoQuality") ?? ""
                if let prefEnum = VideoQualityPreference(rawValue: saved), prefEnum != .ask && prefEnum != .auto {
                    return prefEnum.rawValue
                }
                return nil
            }()
            guard let proxyUrl = proxiedPlaybackURL(for: url, quality: initialQuality) else {
                logDebug("playVideo error: failed to form proxy URL")
                self.error = "Ошибка формирования URL"
                self.isLoading = false
                return
            }

            let mediaId = currentMediaId ?? (currentKpId.map { "kp_\($0)" } ?? "unknown")

            HlsProxyServer.shared.start(
                headers: headers,
                voices: voices,
                subtitles: subtitles,
                mediaId: mediaId,
                preferredVoiceName: targetVoiceover ?? _currentTranslationName
            )
            // currentPlaybackSourceURL — прокси URL (127.0.0.1); для перезапуска используем originalStreamURL
            currentPlaybackSourceURL = proxyUrl
            asset = AVURLAsset(url: proxyUrl)
        }

        let playerItem = AVPlayerItem(asset: asset)
        playerItem.preferredForwardBufferDuration = 0.0
        if let currentKey = currentQualityKey, currentKey != "Авто" {
            let res = targetResolution(for: currentKey)
            if res != .zero {
                playerItem.preferredMaximumResolution = res
            }
        }
        self.isLocalPlayback = isLocalFile || isMp4
        setupImageGenerator(asset: asset)

        if self.player == nil {
            let newPlayer = AVPlayer()
            self.player = newPlayer
        }
        self.player?.replaceCurrentItem(with: playerItem)

        self.player?.automaticallyWaitsToMinimizeStalling = true
        self.player?.rate = playbackRate
        self.isPausedByUser = false

        let minStartTime: Double = isCollapsStream ? 3.5 : 0.0
        let targetSeek: Double = {
            if self.isInitialSeekPending, let pending = self.pendingSeekPosition, pending > 2 {
                return pending
            }
            if self.currentTime > 2 {
                return self.currentTime
            }
            if let mediaId = self.currentMediaId {
                let s = PlaybackProgressStore.shared.load(mediaId: mediaId)
                if s > 2 { return s }
            }
            return minStartTime
        }()

        if targetSeek > 2 {
            self.isInitialSeekPending = true
            self.pendingSeekPosition = targetSeek
            self.logDebug("setupPlayer: pre-queuing initial seek to \(targetSeek)s for \(self.currentMediaId ?? "")")
            let tolerance = CMTime(seconds: 1.5, preferredTimescale: 600)
            self.player?.seek(
                to: CMTime(seconds: targetSeek, preferredTimescale: 600),
                toleranceBefore: tolerance,
                toleranceAfter: tolerance
            ) { [weak self] finished in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isInitialSeekPending = false
                    self.pendingSeekPosition = nil
                    if finished {
                        self.currentTime = targetSeek
                        self.updateSubtitleCue(at: targetSeek)
                        self.logDebug("setupPlayer: pre-queued seek to \(targetSeek)s completed")
                    }
                    if !self.isPausedByUser {
                        self.player?.play()
                    }
                    self.updateNowPlaying()
                }
            }
        }

        setupPlayerItemObservers(for: playerItem)

        rateObserver?.invalidate()
        rateObserver = self.player?.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let status = player.timeControlStatus
                self.isPlaying = (status == .playing)
                self.isBuffering = (status == .waitingToPlayAtSpecifiedRate)

                // Управляем блокировкой экрана: включена во время воспроизведения/буферизации,
                // выключена при паузе (разрешаем экрану гаснуть когда пользователь поставил на паузу)
                UIApplication.shared.isIdleTimerDisabled = (status == .playing || status == .waitingToPlayAtSpecifiedRate)

                self.updateNowPlaying()
            }
        }

        self.isLoading = false
        self.startTrackingProgress()
        if !self.isInitialSeekPending {
            self.player?.play()
        }
    }
    
    private func setupPlayerItemObservers(for playerItem: AVPlayerItem) {
        statusObserver?.invalidate()
        bufferObserver?.invalidate()

        let delegate = LegibleOutputDelegate { [weak self] lines in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.activeSubtitleCues.isEmpty else { return }
                guard self.currentSubtitle != nil else {
                    if self.currentSubtitleText != nil {
                        self.currentSubtitleText = nil
                    }
                    return
                }
                let clean = lines.joined(separator: "\n")
                let final = clean.isEmpty ? nil : clean
                if self.currentSubtitleText != final {
                    self.currentSubtitleText = final
                }
            }
        }
        let legible = AVPlayerItemLegibleOutput()
        legible.suppressesPlayerRendering = true
        legible.setDelegate(delegate, queue: DispatchQueue.main)
        playerItem.add(legible)
        self.legibleDelegate = delegate
        self.legibleOutput = legible

        // Выход кадров декодера: подключается динамически ТОЛЬКО в режиме обрезки момента
        if self.isClipMode {
            self.attachVideoOutputIfNeeded()
        }

        if let playbackEndObserver {
            NotificationCenter.default.removeObserver(playbackEndObserver)
            self.playbackEndObserver = nil
        }
        if let failedToEndObserver {
            NotificationCenter.default.removeObserver(failedToEndObserver)
            self.failedToEndObserver = nil
        }

        failedToEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] notif in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard playerItem === self.player?.currentItem else { return }
                let err = notif.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? NSError
                self.logDebug("setupPlayerItemObservers: item failedToPlayToEndTime: \(err?.localizedDescription ?? "unknown")")
                if UIApplication.shared.applicationState != .active {
                    // Приложение свернуто или экран заблокирован. Не показываем ошибку, тихо сохраняем прогресс.
                    // При возврате в приложение foregroundObserver восстановит воспроизведение.
                    self.saveCurrentProgress()
                    return
                }
                if self.playbackRetryCount < self.maxPlaybackRetries {
                    self.playbackRetryCount += 1
                    let attempt = self.playbackRetryCount
                    self.logDebug("setupPlayerItemObservers: failedToPlayToEndTime auto-retry (\(attempt)/\(self.maxPlaybackRetries))")
                    Task { @MainActor [weak self] in
                        guard let self, !self.isPreparedForDismiss, !self.isCleaningUp else { return }
                        let delay = Double(attempt) * 0.4
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        guard !self.isPreparedForDismiss, !self.isCleaningUp else { return }
                        self.retryPlayback()
                    }
                    return
                }
                self.error = "Воспроизведение было прервано. Нажмите «Попробовать снова»."
                self.isLoading = false
                self.isBuffering = false
            }
        }

        if let playbackStalledObserver {
            NotificationCenter.default.removeObserver(playbackStalledObserver)
            self.playbackStalledObserver = nil
        }

        playbackStalledObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard playerItem === self.player?.currentItem else { return }
                self.logDebug("setupPlayerItemObservers: playback stalled, marking buffering")
                self.isBuffering = true
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 12_000_000_000)
                    guard let self, !self.isPreparedForDismiss, !self.isCleaningUp else { return }
                    if self.player?.timeControlStatus == .waitingToPlayAtSpecifiedRate,
                       !self.isUserSeeking,
                       !self.isInitialSeekPending,
                       !self.isPausedByUser,
                       Date().timeIntervalSince(self.lastSeekTimestamp) >= 10.0,
                       NetworkMonitor.shared.isConnected,
                       self.player?.currentItem === playerItem {
                        self.logDebug("setupPlayerItemObservers: stall persisted > 12s while connected, attempting play before reload")
                        self.player?.play()
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        if self.player?.timeControlStatus == .waitingToPlayAtSpecifiedRate,
                           self.player?.currentItem === playerItem {
                            self.logDebug("setupPlayerItemObservers: still stalled after 14s, auto-recovering stream via retryPlayback()")
                            self.retryPlayback()
                        }
                    }
                }
            }
        }

        statusObserver = playerItem.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Guard: only process failure for the *currently active* player item.
                // When a player item is replaced (e.g. on quality change or retry), the old
                // item may asynchronously report .failed after the KVO observer is invalidated
                // but before the already-enqueued Task runs. Without this guard, each quality
                // switch would trigger a cascade of unnecessary fallbacks.
                guard item === self.player?.currentItem else { return }
                if item.status == .failed {
                    let nsError = item.error as NSError?
                    self.logDebug("setupPlayerItemObservers: item failed! Domain=\(nsError?.domain ?? ""), Code=\(nsError?.code ?? 0), Desc=\(nsError?.localizedDescription ?? "")")
                    print("PlayerItem failed: \(nsError?.localizedDescription ?? "Unknown error")")
                    
                    if let iframeUrl = self.currentIframeUrl, !iframeUrl.isEmpty {
                        AllohaRuntimeResolver.invalidateCache(for: iframeUrl)
                    }
                    
                    if nsError?.domain == AVFoundationErrorDomain, nsError?.code == -11848 {
                        self.logDebug("setupPlayerItemObservers: Cannot Open (-11848) detected.")
                        
                        // First try immediate fallback to next quality
                        if let currentKey = self.currentQualityKey,
                           let currentIndex = self.availableQualities.firstIndex(where: { $0.key == currentKey }) {
                            var fallbackCandidate: PlaybackQualityOption?
                            for i in (currentIndex + 1)..<self.availableQualities.count {
                                if self.availableQualities[i].key != "Авто" {
                                    fallbackCandidate = self.availableQualities[i]
                                    break
                                }
                            }
                            if let fallback = fallbackCandidate {
                                self.logDebug("setupPlayerItemObservers: Auto-falling back from \(currentKey) to \(fallback.key)")
                                self.changeQuality(to: fallback.key)
                                return
                            }
                        }
                        
                        // No fallback quality available yet — qualities may still be loading from
                        // master playlist. Wait briefly then retry from the beginning of the list.
                        Task { [weak self] in
                            guard let self else { return }
                            try? await Task.sleep(nanoseconds: 2_500_000_000)
                            guard let url = self.originalStreamURL ?? self.currentPlaybackSourceURL else { return }
                            // After wait, if we now have quality options below the Auto level, use them
                            let nonAutoQualities = self.availableQualities.filter { !$0.isAuto }
                            if let best = nonAutoQualities.first {
                                self.logDebug("setupPlayerItemObservers: Retrying with quality '\(best.key)' after async quality population")
                                self.changeQuality(to: best.key)
                            } else {
                                // Still no alternatives — perform a clean reload
                                self.logDebug("setupPlayerItemObservers: No alternative quality found, retrying stream URL")
                                 HlsProxyServer.shared.start(
                                    headers: self.currentHeaders,
                                    voices: self.availableVoiceovers,
                                    subtitles: self.availableSubtitles,
                                    mediaId: self.currentMediaId ?? (self.currentKpId.map { "kp_\($0)" } ?? "unknown"),
                                    preferredVoiceName: self.targetVoiceover ?? self._currentTranslationName
                                )
                                self.reloadPlayback(to: url, preferredPeakBitRate: nil, qualityKey: self.currentQualityKey)
                            }
                        }
                        return
                    } // end -11848

                    // General retry for non-11848 errors: используем умный лимит попыток
                    if self.playbackRetryCount < self.maxPlaybackRetries, let url = self.originalStreamURL ?? self.currentPlaybackSourceURL {
                        self.playbackRetryCount += 1
                        let attempt = self.playbackRetryCount
                        print("Auto-retrying playback after failure (\(attempt)/\(self.maxPlaybackRetries)) with originalStreamURL...")
                        self.saveCurrentProgress()
                        Task { @MainActor [weak self] in
                            guard let self, !self.isPreparedForDismiss, !self.isCleaningUp else { return }
                            let delay = Double(attempt) * 0.4
                            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                            guard !self.isPreparedForDismiss, !self.isCleaningUp else { return }
                            // Перезапускаем прокси перед retry, так как именно он мог упасть
                            if let origUrl = self.originalStreamURL {
                                HlsProxyServer.shared.start(
                                    headers: self.currentHeaders,
                                    voices: self.availableVoiceovers,
                                    subtitles: self.availableSubtitles,
                                    mediaId: self.currentMediaId ?? (self.currentKpId.map { "kp_\($0)" } ?? "unknown"),
                                    preferredVoiceName: self.targetVoiceover ?? self._currentTranslationName
                                )
                                self.reloadPlayback(to: origUrl, preferredPeakBitRate: self.player?.currentItem?.preferredPeakBitRate, qualityKey: self.currentQualityKey)
                            } else {
                                self.reloadPlayback(to: url, preferredPeakBitRate: self.player?.currentItem?.preferredPeakBitRate, qualityKey: self.currentQualityKey)
                            }
                        }
                    } else {
                        self.logDebug("setupPlayerItemObservers: stream reload retries exhausted, initiating full re-resolve via retryPlayback()")
                        self.playbackRetryCount = 0
                        self.retryPlayback()
                    }
                } else if item.status == .readyToPlay {
                    self.isLoading = false
                    self.playbackRetryCount = 0
                    self.logDebug("setupPlayerItemObservers: playerItem is readyToPlay")
                    self.applySeekIfNeeded(for: item)
                    Task {
                        do {
                            _ = try await item.asset.loadMediaSelectionGroup(for: .audible)
                        } catch {
                            self.logDebug("setupPlayerItemObservers: failed to load audible group \(error)")
                        }
                        do {
                            _ = try await item.asset.loadMediaSelectionGroup(for: .legible)
                        } catch {
                            self.logDebug("setupPlayerItemObservers: failed to load legible group \(error)")
                        }
                        await MainActor.run {
                            self.syncNativeAudioTracks()
                            let targetVoice = self.targetVoiceover ?? self._currentTranslationName ?? self.availableVoiceovers.first ?? "Дубляж"
                            let voiceIndex = self.availableVoiceovers.firstIndex(where: { allohaTranslationNamesMatch($0, targetVoice, exactOnly: true) })
                                ?? self.availableVoiceovers.firstIndex(where: { allohaTranslationNamesMatch($0, targetVoice, exactOnly: false) })
                            self.selectAudioTrackInPlayer(named: targetVoice, at: voiceIndex)
                            self.syncNativeSubtitleTracks()

                            if let root = self.rootMediaKey {
                                let titleToReport = self.fallbackTitle.isEmpty ? "Без названия" : self.fallbackTitle
                                PlaybackAnalyticsService.shared.startWatching(
                                    mediaKey: root,
                                    title: titleToReport,
                                    season: self.currentSeason,
                                    episode: self.currentEpisode,
                                    translation: targetVoice,
                                    posterUrl: self.posterUrl
                                )
                            }
                        }
                    }
                }
            }
        }

        bufferObserver = playerItem.observe(\.loadedTimeRanges, options: [.new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let duration = item.duration.seconds
                guard duration > 0 else { return }
                let buffered = item.loadedTimeRanges
                    .map { $0.timeRangeValue }
                    .filter { $0.start.seconds <= self.currentTime }
                    .map { $0.start.seconds + $0.duration.seconds }
                    .max() ?? 0
                self.bufferedProgress = buffered / duration
            }
        }

        observePlaybackCompletion(for: playerItem)

        if playerItem.status == .readyToPlay {
            self.applySeekIfNeeded(for: playerItem)
        }
    }
    
    private func applySeekIfNeeded(for item: AVPlayerItem) {
        guard let player = self.player else { return }
        guard item === player.currentItem else { return }

        let minStartTime: Double = isCollapsStream ? 3.5 : 0.0
        let targetSeek: Double = {
            if self.isInitialSeekPending, let pending = self.pendingSeekPosition, pending > 2 {
                return pending
            }
            if self.currentTime > 2 {
                return self.currentTime
            }
            if let mediaId = self.currentMediaId {
                let s = PlaybackProgressStore.shared.load(mediaId: mediaId)
                if s > 2 { return s }
            }
            return minStartTime
        }()

        guard targetSeek > 2 else {
            self.isInitialSeekPending = false
            self.pendingSeekPosition = nil
            if !self.isPausedByUser {
                self.player?.play()
            }
            return
        }

        let currentPos = player.currentTime().seconds
        if currentPos.isFinite && abs(currentPos - targetSeek) < 1.0 {
            self.isInitialSeekPending = false
            self.pendingSeekPosition = nil
            if !self.isPausedByUser {
                self.player?.play()
            }
            return
        }

        self.isInitialSeekPending = true
        self.pendingSeekPosition = targetSeek
        self.logDebug("applySeekIfNeeded: seeking to \(targetSeek)s for \(self.currentMediaId ?? "")")
        let tolerance = CMTime(seconds: 1.5, preferredTimescale: 600)
        player.seek(
            to: CMTime(seconds: targetSeek, preferredTimescale: 600),
            toleranceBefore: tolerance,
            toleranceAfter: tolerance
        ) { [weak self] finished in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isInitialSeekPending = false
                self.pendingSeekPosition = nil
                if finished {
                    self.currentTime = targetSeek
                    self.updateSubtitleCue(at: targetSeek)
                    self.logDebug("applySeekIfNeeded: seek to \(targetSeek)s completed successfully")
                }
                if !self.isPausedByUser {
                    self.player?.play()
                }
                self.updateNowPlaying()
            }
        }
    }

    private func startTrackingProgress() {
        guard let player = player else { return }
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }

        guard let mediaId = currentMediaId else { return }

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
        ) { [weak self, weak player] time in
            MainActor.assumeIsolated {
                guard let self, let player else { return }
                if self.isUserSeeking || self.isInitialSeekPending { return }
                let t = player.currentTime().seconds
                if t.isFinite && !t.isNaN && t >= 0 {
                    if t > 3.0 && self.playbackRetryCount > 0 {
                        self.playbackRetryCount = 0
                    }
                    if self.isClipMode && !self.isUserSeeking && player.rate > 0.01 {
                        // Зацикливание превью момента — только во время реального воспроизведения,
                        // чтобы не конфликтовать со scrub-превью триммера на паузе.
                        if t >= self.clipEndTime || t < self.clipStartTime - 0.5 {
                            self.currentTime = self.clipStartTime
                            self.seekClip(to: self.clipStartTime)
                            return
                        }
                        self.onClipPlaybackTimeUpdated?(t)
                    }
                    if abs(self.currentTime - t) >= 0.1 {
                        self.currentTime = t
                    }
                    if !self.activeSubtitleCues.isEmpty {
                        self.updateSubtitleCue(at: t)
                    }
                }
                let d = player.currentItem?.duration.seconds ?? 0
                if d.isFinite && !d.isNaN && d > 0 {
                    if abs(self.currentDuration - d) > 0.5 {
                        self.currentDuration = d
                    }
                }
                
                if let intro = self.introRange, intro.contains(self.currentTime) {
                    if !self.showSkipIntro {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            self.showSkipIntro = true
                        }
                    }
                } else {
                    if self.showSkipIntro {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            self.showSkipIntro = false
                        }
                    }
                }
                
                if let outro = self.outroRange, outro.contains(self.currentTime) {
                    if !self.showSkipOutro {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            self.showSkipOutro = true
                        }
                    }
                } else {
                    if self.showSkipOutro {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            self.showSkipOutro = false
                        }
                    }
                }
                
                // Сохраняем прогресс каждые 5 секунд (только если не висит начальный seek и позиция > 2 секунд)
                let currentSec = Int(t)
                if !self.isInitialSeekPending && currentSec % 5 == 0 && currentSec != self.lastProgressSaveSecond && t > 2 {
                    self.lastProgressSaveSecond = currentSec
                    let dur = self.currentDuration >= 120 ? self.currentDuration : nil
                    PlaybackProgressStore.shared.save(
                        mediaId: mediaId,
                        kpId: self.currentKpId,
                        tmdbId: self.tmdbId,
                        season: self.currentSeason,
                        episode: self.currentEpisode,
                        positionSec: t,
                        durationSec: dur,
                        voiceover: self._currentTranslationName
                    )
                }
            }
        }



        setupRemoteCommands()
        updateNowPlaying()

        // Сохраняем прогресс немедленно при сворачивании — даже если система потом убьёт процесс
        if let existing = resignActiveObserver {
            NotificationCenter.default.removeObserver(existing)
        }
        resignActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.playbackRetryCount = 0 // Сбрасываем счетчик ретраев, чтобы при возврате из фона авто-ретрай мог сработать
                let status = self.player?.timeControlStatus
                let wasPlaying = status == .playing || status == .waitingToPlayAtSpecifiedRate
                UserDefaults.standard.set(wasPlaying, forKey: "sloosh_was_playing_before_bg")
                self.saveCurrentProgress()
            }
        }
        
        if let existingFg = foregroundObserver {
            NotificationCenter.default.removeObserver(existingFg)
        }
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }

                // 1. Восстанавливаем аудиосессию
                try? AVAudioSession.sharedInstance().setActive(true)

                // 2. Пинаем прокси (восстановит слушатель если упал)
                HlsProxyServer.shared.appWillEnterForeground()

                // 3. Восстанавливаем блокировку экрана для активного плеера
                if let status = self.player?.timeControlStatus,
                   status == .playing || status == .waitingToPlayAtSpecifiedRate {
                    UIApplication.shared.isIdleTimerDisabled = true
                }

                // 4. Возобновляем воспроизведение если играло до ухода в фон, либо восстанавливаем упавший поток
                if self.player?.currentItem?.status == .failed || self.error != nil {
                    self.logDebug("foregroundObserver: player item failed or error present, auto-retrying playback")
                    self.retryPlayback()
                } else {
                    let wasPlaying = UserDefaults.standard.bool(forKey: "sloosh_was_playing_before_bg")
                    if wasPlaying && self.player?.timeControlStatus != .playing {
                        self.player?.play()
                    }
                }

                // ВАЖНО: watchdog по таймеру УДАЛЁН.
                // Любой реальный сбой потока (item.status == .failed) обрабатывает
                // statusObserver (setupPlayerItemObservers), который делает корректный
                // reloadPlayback. Таймер 4с вызывал ложные перезагрузки при обычной
                // буферизации на медленной сети.
            }
        }
        
        // Обрабатываем прерывания аудиосессии (звонок, Siri, другие приложения)
        if let existingIntr = audioInterruptionObserver {
            NotificationCenter.default.removeObserver(existingIntr)
        }
        audioInterruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if type == .ended {
                    // Прерывание завершено — восстанавливаем сессию и возобновляем
                    try? AVAudioSession.sharedInstance().setActive(true)
                    // Проверяем опциональный флаг shouldResume
                    let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                    let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                    if options.contains(.shouldResume) {
                        self.player?.play()
                    }
                }
            }
        }

        // 5. Авто-восстановление воспроизведения при смене сети (Wi-Fi/LTE/VPN)
        networkCancellable?.cancel()
        networkCancellable = NetworkMonitor.shared.$isConnected
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isConnected in
                guard let self else { return }
                if isConnected {
                    if self.error != nil || self.player?.currentItem?.status == .failed || self.isBuffering {
                        self.logDebug("Network restored: auto-recovering playback...")
                        self.error = nil
                        self.playbackRetryCount = 0
                        self.retryPlayback()
                    }
                } else {
                    let status = self.player?.timeControlStatus
                    if status == .playing || status == .waitingToPlayAtSpecifiedRate {
                        self.isBuffering = true
                    }
                }
            }
    }

    // MARK: - Now Playing

    private func setupRemoteCommands() {
        let cc = MPRemoteCommandCenter.shared()
        // Сначала удаляем все предыдущие обработчики, чтобы не накапливались при переключении серий
        cc.playCommand.removeTarget(nil)
        cc.pauseCommand.removeTarget(nil)
        cc.togglePlayPauseCommand.removeTarget(nil)
        cc.changePlaybackPositionCommand.removeTarget(nil)
        cc.skipForwardCommand.removeTarget(nil)
        cc.skipBackwardCommand.removeTarget(nil)
        
        cc.playCommand.isEnabled = true
        cc.playCommand.addTarget { [weak self] _ in
            self?.isPausedByUser = false
            self?.player?.play()
            return .success
        }
        cc.pauseCommand.isEnabled = true
        cc.pauseCommand.addTarget { [weak self] _ in
            self?.isPausedByUser = true
            self?.player?.pause()
            return .success
        }
        cc.togglePlayPauseCommand.isEnabled = true
        cc.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause(); return .success
        }
        cc.changePlaybackPositionCommand.isEnabled = true
        cc.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.seek(to: e.positionTime)
            return .success
        }
        cc.skipForwardCommand.isEnabled = true
        cc.skipForwardCommand.preferredIntervals = [10]
        cc.skipForwardCommand.addTarget { [weak self] _ in
            self?.seek(by: 10); return .success
        }
        cc.skipBackwardCommand.isEnabled = true
        cc.skipBackwardCommand.preferredIntervals = [10]
        cc.skipBackwardCommand.addTarget { [weak self] _ in
            self?.seek(by: -10); return .success
        }
    }

    func updateNowPlaying() {
        guard let player else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: fallbackTitle.isEmpty ? "Смотреть" : fallbackTitle,
            MPMediaItemPropertyPlaybackDuration: currentDuration > 0 ? currentDuration : 0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: player.rate,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue
        ]
        if let season = currentSeason, let episode = currentEpisode {
            info[MPMediaItemPropertyArtist] = episode == 0 ? "Сезон \(season), Пилотная серия" : "Сезон \(season), Серия \(episode)"
        } else if let voiceover = _currentTranslationName, !voiceover.isEmpty {
            info[MPMediaItemPropertyArtist] = voiceover
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = player.timeControlStatus == .playing ? .playing : .paused
    }

    private func clearNowPlaying() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func observePlaybackCompletion(for item: AVPlayerItem) {
        playbackEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.handlePlaybackEnded()
            }
        }
    }

    private func handlePlaybackEnded() async {
        guard autoplayNextEpisodeEnabled,
              !isAdvancingToNextEpisode,
              hasNextEpisode else {
            // Если нет следующей серии — отмечаем текущую как просмотренную
            if let mediaId = currentMediaId {
                PlaybackProgressStore.shared.markAsWatched(mediaId: mediaId)
            }
            return
        }

        isAdvancingToNextEpisode = true
        defer { isAdvancingToNextEpisode = false }

        // Отмечаем текущую серию как просмотренную
        if let mediaId = currentMediaId {
            PlaybackProgressStore.shared.markAsWatched(mediaId: mediaId)
        }

        playNextEpisode()
    }

    private var isEpisodeSwitching = false
    private var lastEpisodeSwitchTimestamp: Date = .distantPast

    func playNextEpisode() {
        guard let nextEpisode = nextEpisodeCandidate() else { return }
        playEpisode(nextEpisode)
    }

    func playPreviousEpisode() {
        guard let prevEpisode = previousEpisodeCandidate() else { return }
        playEpisode(prevEpisode)
    }

    func selectEpisode(season: Int, episode: Int) {
        guard let seriesResult,
              let seasonObj = seriesResult.seasons.first(where: { $0.season == season }),
              let epObj = seasonObj.episodes.first(where: { $0.episode == episode }) else { return }
        guard let translation = preferredTranslation(in: epObj) else { return }
        playEpisode((season: season, episode: episode, translation: translation))
    }

    private func playEpisode(_ episode: (season: Int, episode: Int, translation: AllohaTranslation)) {
        let now = Date()
        guard now.timeIntervalSince(lastEpisodeSwitchTimestamp) > 0.6 else {
            logDebug("playEpisode: debounced rapid episode switch attempt")
            return
        }
        lastEpisodeSwitchTimestamp = now

        // 1. Сохраняем прогресс ТЕКУЩЕГО эпизода ДО обновления currentSeason/currentEpisode
        saveCurrentProgress()

        // 2. Сбрасываем флаг загрузки — beginLoad не имеет собственной защиты от повторного вызова
        hasStartedLoading = false

        // Обновляем текущую активную озвучку под загружаемый эпизод
        _currentTranslationName = episode.translation.name

        // Сохраняем targetVoiceover как предпочтение пользователя, если оно еще не установлено
        if targetVoiceover == nil {
            targetVoiceover = episode.translation.name
        }
        // Если воспроизводимая озвучка совпадает с предпочтением, персистим выбор
        if let pref = targetVoiceover, allohaTranslationNamesMatch(episode.translation.name, pref) {
            persistVoiceoverSelection(episode.translation.name)
        }

        if let root = rootMediaKey {
            PlaybackProgressStore.shared.saveLastPlayed(mediaKey: root, season: episode.season, episode: episode.episode)
        } else if let kpId = currentKpId, kpId > 0 {
            PlaybackProgressStore.shared.saveLastPlayed(kpId: kpId, season: episode.season, episode: episode.episode)
        }

        let epVoices: [String] = {
            if let seasonObj = seriesResult?.seasons.first(where: { $0.season == episode.season }),
               let epObj = seasonObj.episodes.first(where: { $0.episode == episode.episode }) {
                let names = epObj.translations.map { $0.name }.filter { !$0.isEmpty }
                if !names.isEmpty { return names }
            }
            return self.availableVoiceovers
        }()

        let epSubs: [PlaybackSubtitle] = {
            let key = EpisodeKey(season: episode.season, episode: episode.episode)
            if let specificSubs = self.episodeSubtitles[key], !specificSubs.isEmpty {
                return specificSubs
            }
            return self.availableSubtitles
        }()

        beginLoad(
            iframeUrl: episode.translation.iframeUrl,
            kpId: currentKpId,
            season: episode.season,
            episode: episode.episode,
            selectedVoiceover: episode.translation.name,
            directStreamUrl: (episode.translation.streamUrl?.isEmpty == false) ? episode.translation.streamUrl : nil,
            voices: epVoices,
            subtitles: epSubs,
            customHeaders: self.customHeaders,
            mediaKey: rootMediaKey,
            tmdbId: tmdbId
        )
    }


    private func nextEpisodeCandidate() -> (season: Int, episode: Int, translation: AllohaTranslation)? {
        guard let seriesResult, seriesResult.isSerial,
              let currentSeason, let currentEpisode else {
            return nil
        }

        let sortedSeasons = seriesResult.seasons.sorted { $0.season < $1.season }
        var foundCurrentEpisode = false

        for season in sortedSeasons {
            for episode in season.episodes.sorted(by: { $0.episode < $1.episode }) {
                if foundCurrentEpisode {
                    guard let translation = preferredTranslation(in: episode) else { return nil }
                    return (season.season, episode.episode, translation)
                }

                if season.season == currentSeason && episode.episode == currentEpisode {
                    foundCurrentEpisode = true
                }
            }
        }

        return nil
    }

    private func previousEpisodeCandidate() -> (season: Int, episode: Int, translation: AllohaTranslation)? {
        guard let seriesResult, seriesResult.isSerial,
              let currentSeason, let currentEpisode else {
            return nil
        }

        let sortedSeasons = seriesResult.seasons.sorted { $0.season < $1.season }
        var lastSeenEpisode: (season: Int, episode: Int, translation: AllohaTranslation)? = nil

        for season in sortedSeasons {
            for episode in season.episodes.sorted(by: { $0.episode < $1.episode }) {
                if season.season == currentSeason && episode.episode == currentEpisode {
                    return lastSeenEpisode
                }
                if let translation = preferredTranslation(in: episode) {
                    lastSeenEpisode = (season.season, episode.episode, translation)
                }
            }
        }

        return nil
    }

    private func preferredTranslation(in episode: AllohaEpisode) -> AllohaTranslation? {
        var pref = targetVoiceover ?? _currentTranslationName
        let sourceKey = isCollapsStream ? "collaps" : "alloha"
        if pref == nil, let root = rootMediaKey {
            pref = PlaybackProgressStore.shared.loadLastVoiceover(mediaKey: root, source: sourceKey)
        }
        if pref == nil, let kpId = currentKpId, kpId > 0 {
            pref = PlaybackProgressStore.shared.loadLastVoiceover(kpId: kpId, source: sourceKey)
        }
        if pref == nil {
            pref = UserDefaults.standard.string(forKey: "\(sourceKey)_last_translation_name")
        }
        return bestTranslation(in: episode.translations, preferredName: pref)
    }


    private func applyResolvedAllohaStream(_ resolved: [String: Any]) {
        var resolvedUrlString = (resolved["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let audioVariants = (resolved["audioVariants"] as? [[String: Any]]) ?? []
        logDebug("applyResolvedAllohaStream: resolvedUrlString=\(resolvedUrlString), audioVariants count=\(audioVariants.count)")

        if let directUrl = targetDirectStreamUrl, !directUrl.isEmpty {
            // Pre-resolved URL stored at fetch time: use directly, no name matching needed.
            logDebug("applyResolvedAllohaStream: using targetDirectStreamUrl=\(directUrl)")
            resolvedUrlString = directUrl
        } else {
            // Check if audioVariants contains a track specifically matching our targetVoiceover or selectedVoiceover
            let targetVoice = targetVoiceover ?? _currentTranslationName
            if let target = targetVoice, !target.isEmpty {
                if let matchingVariant = findMatchingAudioVariant(in: audioVariants, for: target, isDedicatedIframe: currentIframeUrl != nil),
                   let variantUrl = (matchingVariant["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !variantUrl.isEmpty {
                    resolvedUrlString = variantUrl
                    let rawTitle = (matchingVariant["title"] as? String) ?? ""
                    let cleanTitle = self.availableVoiceovers.first(where: { allohaTranslationNamesMatch($0, rawTitle, exactOnly: true) })
                        ?? self.availableVoiceovers.first(where: { allohaTranslationNamesMatch($0, rawTitle, exactOnly: false) })
                        ?? cleanTranslationName(rawTitle)
                    if _currentTranslationName == nil || _currentTranslationName?.isEmpty == true {
                        _currentTranslationName = cleanTitle
                    }
                    if targetVoiceover == nil || targetVoiceover?.isEmpty == true {
                        targetVoiceover = cleanTitle
                    }
                    logDebug("applyResolvedAllohaStream: matched audioVariant '\(matchingVariant["title"] ?? "")' -> \(variantUrl)")
                }
            } else if !audioVariants.isEmpty {
                // Если озвучка явно не выбрана, приоритетно отдаём русский вариант, а не английский дефолт 0
                if let matchingVariant = findMatchingAudioVariant(in: audioVariants, for: "Дубляж", isDedicatedIframe: currentIframeUrl != nil),
                   let variantUrl = (matchingVariant["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !variantUrl.isEmpty {
                    resolvedUrlString = variantUrl
                    let rawTitle = (matchingVariant["title"] as? String) ?? ""
                    let cleanTitle = self.availableVoiceovers.first(where: { allohaTranslationNamesMatch($0, rawTitle, exactOnly: true) })
                        ?? self.availableVoiceovers.first(where: { allohaTranslationNamesMatch($0, rawTitle, exactOnly: false) })
                        ?? cleanTranslationName(rawTitle)
                    _currentTranslationName = cleanTitle
                    targetVoiceover = cleanTitle
                    logDebug("applyResolvedAllohaStream: defaulted to Russian audioVariant '\(rawTitle)' -> \(variantUrl)")
                }
            }
        }

        guard let resolvedUrl = URL(string: resolvedUrlString) else {
            self.error = "Не удалось извлечь ссылку на видео"
            self.isLoading = false
            return
        }

        let headers = (resolved["headers"] as? [String: String]) ?? [:]
        currentHeaders = headers
        let resolvedSubtitles = resolvedSubtitles(from: resolved)
        self.availableSubtitles = resolvedSubtitles

        if let intro = resolved["introRange"] as? [String: Double],
           let start = intro["start"], let end = intro["end"] {
            self.introRange = start...end
        } else {
            self.introRange = nil
        }
        
        if let outro = resolved["outroRange"] as? [String: Double],
           let start = outro["start"], let end = outro["end"] {
            self.outroRange = start...end
        } else {
            self.outroRange = nil
        }

        // Заполняем список вариантов стримов из audioVariants (нужны для переключения озвучки)
        self.resolvedAudioVariants = audioVariants
        // Вычисляем реальные аудиодорожки из стрима Alloha и обновляем availableVoiceovers ТОЛЬКО если
        // у нас ещё не было аутентичного списка озвучек из каталога / страницы выбора.
        let voices = resolvedVoiceovers(from: resolved)
        if !voices.isEmpty && self.availableVoiceovers.count <= 1 {
            self.availableVoiceovers = voices
        }

        let qualityVariants = (resolved["qualityVariants"] as? [[String: Any]]) ?? []
        let matchedInitialVariant = findMatchingAudioVariant(in: audioVariants, for: targetVoiceover ?? _currentTranslationName, isDedicatedIframe: currentIframeUrl != nil)

        availableQualities = makeResolvedQualityOptions(
            resolvedUrl: resolvedUrl,
            qualityVariants: qualityVariants,
            audioVariants: audioVariants,
            preferredAudioVariant: matchedInitialVariant
        )
        let (initialPlaybackUrl, initialBitrate) = selectPreservedPlaybackTarget(fallbackUrl: resolvedUrl)
        playVideo(url: initialPlaybackUrl, headers: headers, voices: voices, subtitles: resolvedSubtitles)
        if let initialBitrate, initialBitrate > 0 {
            player?.currentItem?.preferredPeakBitRate = initialBitrate
        }
        NotificationCenter.default.post(name: NSNotification.Name("QualitiesUpdated"), object: nil)

        // If the parser returned no quality variants (e.g. only a master URL with no explicit
        // quality JSON), fetch the HLS master playlist in the background to populate quality
        // options from the actual #EXT-X-STREAM-INF entries.
        if availableQualities.count <= 1 {
            let capturedUrl = resolvedUrl
            let capturedHeaders = headers
            Task { [weak self] in
                await self?.fetchAndUpdateQualitiesFromMaster(url: capturedUrl, headers: capturedHeaders)
            }
        }
    }

    /// Fetches the HLS master playlist from the original CDN URL and populates quality options
    /// by calling parseMasterPlaylist. Used when AllohaRuntimeParser returns no qualityVariants
    /// (e.g. the stream is delivered via a signed CDN URL with no JSON quality metadata).
    private func fetchAndUpdateQualitiesFromMaster(url: URL, headers: [String: String]) async {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        for (k, v) in headers {
            request.setValue(v, forHTTPHeaderField: k)
        }
        if request.value(forHTTPHeaderField: "User-Agent") == nil {
            request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64)", forHTTPHeaderField: "User-Agent")
        }
        if request.value(forHTTPHeaderField: "Accept") == nil {
            request.setValue("*/*", forHTTPHeaderField: "Accept")
        }

        guard let (data, response) = try? await trustedSession.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode),
              let content = String(data: data, encoding: .utf8),
              content.contains("#EXT-X-STREAM-INF") else {
            logDebug("fetchAndUpdateQualitiesFromMaster: no HLS master content at \(url.absoluteString)")
            return
        }

        let finalUrl = response.url ?? url
        logDebug("fetchAndUpdateQualitiesFromMaster: found master playlist, parsing qualities from \(finalUrl.absoluteString)")
        parseMasterPlaylist(content: content, baseUrl: finalUrl)
    }

    private func resolvedVoiceovers(from resolved: [String: Any]) -> [String] {
        let variants = (resolved["audioVariants"] as? [[String: Any]]) ?? []
        var seen = Set<String>()
        return variants.compactMap { variant in
            let title = (variant["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !title.isEmpty else { return nil }
            let cleanTitle = normalizedAllohaTranslationName(title).isEmpty ? title : normalizedAllohaTranslationName(title)
            let lower = cleanTitle.lowercased()
            if lower.contains("субтитр") || lower.contains("subtitle") {
                return nil
            }
            return seen.insert(cleanTitle).inserted ? cleanTitle : nil
        }
    }

    private func resolvedSubtitles(from resolved: [String: Any]) -> [PlaybackSubtitle] {
        let subtitles = (resolved["subtitles"] as? [[String: Any]]) ?? []
        return subtitles.compactMap { item in
            let url = ((item["url"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !url.isEmpty else { return nil }
            let label = ((item["label"] as? String) ?? (item["name"] as? String) ?? "Субтитры")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let language = ((item["language"] as? String) ?? (item["lang"] as? String) ?? "ru")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return PlaybackSubtitle(
                url: url,
                label: label.isEmpty ? "Субтитры" : label,
                lang: language.isEmpty ? "ru" : language
            )
        }
    }


    private func selectAudioTrackInPlayer(named name: String, at index: Int? = nil) {
        guard let player = player,
              let item = player.currentItem,
              let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .audible) else {
            logDebug("selectAudioTrackInPlayer: no player, currentItem or audible mediaSelectionGroup")
            return
        }
        
        let canonicalName = self.availableVoiceovers.first(where: { allohaTranslationNamesMatch($0, name, exactOnly: true) })
            ?? self.availableVoiceovers.first(where: { allohaTranslationNamesMatch($0, name, exactOnly: false) })
            ?? cleanTranslationName(name)
        
        let options = group.options
        logDebug("selectAudioTrackInPlayer: target='\(name)', index=\(index ?? -1), options=\(options.map { "\($0.displayName) [title: \(self.extractTrackTitle(from: $0))]" })")
        
        func applySelection(_ option: AVMediaSelectionOption, reason: String) {
            item.select(option, in: group)
            persistVoiceoverSelection(canonicalName)
            HlsProxyServer.shared.updatePreferredVoice(canonicalName)
            saveCurrentProgress()
            logDebug("selectAudioTrackInPlayer: \(reason) option='\(option.displayName)' title='\(self.extractTrackTitle(from: option))'")
        }

        // 1. Exact match by authentic track title from HLS metadata
        if let option = options.first(where: { 
            let title = self.extractTrackTitle(from: $0)
            return allohaTranslationNamesMatch(title, name, exactOnly: true)
        }) {
            applySelection(option, reason: "selected exact title match")
            return
        }
        
        // 2. Fuzzy match by authentic track title from HLS metadata
        if let option = options.first(where: { 
            let title = self.extractTrackTitle(from: $0)
            return allohaTranslationNamesMatch(title, name, exactOnly: false)
        }) {
            applySelection(option, reason: "selected fuzzy title match")
            return
        }

        // 3. Exact match by displayName
        if let option = options.first(where: { allohaTranslationNamesMatch($0.displayName, name, exactOnly: true) }) {
            applySelection(option, reason: "selected exact displayName match")
            return
        }
        
        // 4. Fuzzy match by displayName
        if let option = options.first(where: { allohaTranslationNamesMatch($0.displayName, name, exactOnly: false) }) {
            applySelection(option, reason: "selected fuzzy displayName match")
            return
        }
        
        // 5. Match by track index (crucial for Collaps / Source 2 and multi-audio manifests where audio0..audioN map to availableVoiceovers)
        let resolvedTrackIndex: Int? = {
            if let index, index >= 0, index < options.count {
                return index
            }
            if let idx = self.availableVoiceovers.firstIndex(of: name) ??
                         self.availableVoiceovers.firstIndex(where: { allohaTranslationNamesMatch($0, name, exactOnly: true) }) ??
                         self.availableVoiceovers.firstIndex(where: { allohaTranslationNamesMatch($0, name, exactOnly: false) }),
               idx >= 0 && idx < options.count {
                return idx
            }
            return nil
        }()

        if let resolvedTrackIndex {
            applySelection(options[resolvedTrackIndex], reason: "selected by trackIndex \(resolvedTrackIndex)")
            return
        }
        
        // 6. Match by language tag ONLY if unambiguous (e.g. single English or single Ukrainian track)
        let lowerName = name.lowercased()
        let isLookingForEnglish = lowerName.contains("eng") || lowerName.contains("original") || lowerName.contains("англ") || lowerName.contains("ori")
        let isLookingForRussian = lowerName.contains("rus") || lowerName.contains("рус") || lowerName.contains("дуб") || !isLookingForEnglish
        let targetLang: String? = {
            if isLookingForEnglish { return "en" }
            if isLookingForRussian { return "ru" }
            if lowerName.contains("ukr") || lowerName.contains("укр") { return "uk" }
            return nil
        }()
        
        if let targetLang {
            let matchingLangOptions = options.filter {
                $0.extendedLanguageTag?.lowercased().hasPrefix(targetLang) == true ||
                $0.locale?.identifier.lowercased().hasPrefix(targetLang) == true ||
                ($0.extendedLanguageTag?.lowercased() == "rus" && targetLang == "ru") ||
                ($0.locale?.identifier.lowercased().contains("ru") == true && targetLang == "ru")
            }
            // If only one option matches the language, safe to select it
            if matchingLangOptions.count == 1, let option = matchingLangOptions.first {
                applySelection(option, reason: "selected single language tag match '\(targetLang)'")
                return
            }
        }
        
        if let targetIndex = extractAudioIndex(from: name), targetIndex < options.count {
            applySelection(options[targetIndex], reason: "selected by index \(targetIndex)")
            return
        }

        // 7. Fallback for Russian target: if there are multiple options and option 0 is English, select option 1
        if isLookingForRussian && options.count > 1 {
            let opt0Name = options[0].displayName.lowercased()
            let opt0Tag = options[0].extendedLanguageTag?.lowercased() ?? ""
            if opt0Name.contains("eng") || opt0Name.contains("ori") || opt0Tag.hasPrefix("en") {
                applySelection(options[1], reason: "selected non-English fallback option")
                return
            }
        }

        // Guaranteed fallback: ensure an audio track IS ALWAYS SELECTED so playback doesn't stay silent
        if let defaultOpt = group.defaultOption {
            applySelection(defaultOpt, reason: "fallback selected group.defaultOption")
            return
        } else if let firstOpt = options.first {
            applySelection(firstOpt, reason: "fallback selected first available option")
            return
        }

        logDebug("selectAudioTrackInPlayer: failed to match any track for '\(name)'")
    }

    private func extractTrackTitle(from option: AVMediaSelectionOption) -> String {
        if let title = AVMetadataItem.metadataItems(from: option.commonMetadata, withKey: AVMetadataKey.commonKeyTitle, keySpace: .common).first?.stringValue,
           !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return title.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for item in option.commonMetadata {
            if let val = item.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !val.isEmpty, val != option.displayName {
                return val
            }
        }
        for format in option.availableMetadataFormats {
            let items = option.metadata(forFormat: format)
            for item in items {
                if let key = item.commonKey, key == .commonKeyTitle, let str = item.stringValue, !str.isEmpty {
                    return str.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        return option.displayName
    }
    
    private func syncNativeAudioTracks() {
        guard let player = player,
              let item = player.currentItem,
              let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .audible) else {
            return
        }
        
        let nativeNames = group.options.map { option in
            let title = extractTrackTitle(from: option)
            return title.isEmpty ? option.displayName : title
        }
        logDebug("syncNativeAudioTracks: nativeNames=\(nativeNames)")
        guard nativeNames.count > 1 else { return }
        
        // If availableVoiceovers is already populated with authentic translations, do not overwrite or append raw AVPlayer track names
        guard self.availableVoiceovers.isEmpty else { return }
        
        var updatedVoiceovers: [String] = []
        
        for name in nativeNames {
            let cleanName = normalizedAllohaTranslationName(name)
            let finalName = cleanName.isEmpty ? name : cleanName
            if !updatedVoiceovers.contains(where: { allohaTranslationNamesMatch($0, finalName) }) {
                updatedVoiceovers.append(finalName)
            }
        }
        
        if !updatedVoiceovers.isEmpty {
            self.availableVoiceovers = updatedVoiceovers
            logDebug("syncNativeAudioTracks: updated availableVoiceovers=\(self.availableVoiceovers)")
        }
    }

    private func syncNativeSubtitleTracks() {
        guard let player = player,
              let item = player.currentItem,
              let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible) else {
            return
        }

        let nativeOptions = group.options
        logDebug("syncNativeSubtitleTracks: native legible options count=\(nativeOptions.count), names=\(nativeOptions.map { $0.displayName })")

        // Always deselect native legible if we already have an active external VTT.
        // This prevents AVPlayer from rendering duplicates over our SubtitleOverlayView.
        if let current = self.currentSubtitle,
           current.url.hasPrefix("http://") || current.url.hasPrefix("https://") {
            if group.allowsEmptySelection {
                item.select(nil, in: group)
            }
            logDebug("syncNativeSubtitleTracks: external VTT active — native legible deselected")
            return
        }

        if !nativeOptions.isEmpty {
            for (index, opt) in nativeOptions.enumerated() {
                // Skip dummy Closed-Captions tracks (e.g. Alloha's empty "CC" track)
                let upperName = opt.displayName.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                if upperName == "CC" || upperName == "CLOSED CAPTIONS" {
                    logDebug("syncNativeSubtitleTracks: skipping dummy CC track '\(opt.displayName)'")
                    continue
                }
                // Skip if we already have an external VTT track covering the same language
                let lang = opt.locale?.language.languageCode?.identifier ?? "ru"
                if self.availableSubtitles.contains(where: {
                    !$0.url.hasPrefix("native_") && ($0.lang.lowercased() == lang.lowercased())
                }) {
                    logDebug("syncNativeSubtitleTracks: skipping native track '\(opt.displayName)' — external VTT for lang '\(lang)' already present")
                    continue
                }
                let label = opt.displayName.isEmpty ? "Субтитры \(index + 1)" : opt.displayName
                let nativeId = "native_\(index)"
                if !self.availableSubtitles.contains(where: { $0.url == nativeId || $0.label.lowercased() == label.lowercased() }) {
                    self.availableSubtitles.append(PlaybackSubtitle(url: nativeId, label: label, lang: lang))
                }
            }
            logDebug("syncNativeSubtitleTracks: updated availableSubtitles count=\(self.availableSubtitles.count)")
        }

        // Apply current subtitle selection if user previously chose one, or ensure subtitles stay off
        if let current = self.currentSubtitle {
            applySubtitleToPlayer(current)
        } else if group.allowsEmptySelection {
            item.select(nil, in: group)
        }
    }

    
    private func extractAudioIndex(from name: String) -> Int? {
        let patterns = [
            #"(?:^|[^a-z0-9])(?:[a-z]{2,4}|audio[_-]?|track[_-]?)(\d+)(?:$|[^a-z0-9])"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(name.startIndex..<name.endIndex, in: name)
            guard let match = regex.firstMatch(in: name, options: [], range: range),
                  let idxRange = Range(match.range(at: 1), in: name),
                  let idx = Int(name[idxRange]) else {
                continue
            }
            return idx
        }
        return nil
    }

    func extractSubtitleFile(for url: URL) -> URL? {
        return nil
    }

    private func logDebug(_ message: String) {
        AppDiagnostics.shared.log("[PlayerDebug] \(message)")
    }

    private func persistVoiceoverSelection(_ name: String?) {
        let normalized = normalizedAllohaTranslationName(name)
        let finalName = normalized.isEmpty ? name : normalized
        let sourceKey = isCollapsStream ? "collaps" : "alloha"
        if let root = rootMediaKey {
            PlaybackProgressStore.shared.saveLastVoiceover(
                mediaKey: root,
                source: sourceKey,
                voiceover: finalName
            )
        } else if let kpId = currentKpId, kpId > 0 {
            PlaybackProgressStore.shared.saveLastVoiceover(
                kpId: kpId,
                source: sourceKey,
                voiceover: finalName
            )
        }
        if let finalName, !finalName.isEmpty, !isOriginalOrEnglishTranslation(finalName) {
            UserDefaults.standard.set(finalName, forKey: "\(sourceKey)_last_translation_name")
        }
        if let voice = finalName, !voice.isEmpty {
            PlaybackAnalyticsService.shared.updateWatching(
                season: currentSeason,
                episode: currentEpisode,
                translation: voice
            )
        }
    }

    private func appendQualityVariants(_ variants: [[String: Any]], masterUrl: URL, to qualities: inout [PlaybackQualityOption], seenKeys: inout Set<String>) {
        for variant in variants {
            let label = normalizedQualityLabel(from: variant["label"] as? String)
            
            // Фильтруем AV1 кодек, так как iOS/AVPlayer его не поддерживает
            let lowerLabel = label.lowercased()
            let urlString = (variant["url"] as? String) ?? ""
            let lowerUrl = urlString.lowercased()
            if lowerLabel.contains("av1") || lowerLabel.contains("av01") || lowerUrl.contains("av1") || lowerUrl.contains("av01") {
                continue
            }
            
            guard seenKeys.insert(label).inserted else { continue }
            
            let isMp4 = lowerUrl.contains(".mp4") && !lowerUrl.contains(".m3u8")
            let qualityUrl = absoluteQualityURL(from: urlString)
            let hasDistinctQualityUrl = qualityUrl != nil
            let targetUrl = qualityUrl ?? masterUrl
            let bitrate = bitrateValue(from: variant) ?? resolvedBitrate(forQualityKey: label)
            
            qualities.append(
                makeQualityOption(
                    key: label,
                    url: targetUrl,
                    preferredPeakBitRate: bitrate,
                    isAuto: false,
                    shouldReloadOnSelect: isMp4 || hasDistinctQualityUrl
                )
            )
        }
    }

    private func normalizedQualityLabel(from rawLabel: String?) -> String {
        let label = (rawLabel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return "Поток" }
        if label.lowercased().hasSuffix("p") { return label }
        if Int(label) != nil { return "\(label)p" }
        return label
    }
}

private final class LegibleOutputDelegate: NSObject, AVPlayerItemLegibleOutputPushDelegate, @unchecked Sendable {
    private let onStrings: @Sendable ([String]) -> Void

    init(onStrings: @escaping @Sendable ([String]) -> Void) {
        self.onStrings = onStrings
        super.init()
    }

    func legibleOutput(
        _ output: AVPlayerItemLegibleOutput,
        didOutputAttributedStrings strings: [NSAttributedString],
        nativeDurationForSampleRanges nativeDurationProvider: [NSValue],
        forItemTime itemTime: CMTime
    ) {
        let plain = strings
            .map { $0.string.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        onStrings(plain)
    }
}


