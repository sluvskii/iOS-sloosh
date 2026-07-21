import SwiftUI
import AVKit
import AVFoundation
import MediaPlayer
import GroupActivities

// MARK: - UIViewControllerRepresentable: запускает PlayerHostingController
// Это точка входа из SwiftUI fullScreenCover → UIKit-контроллер, который управляет landscape-ориентацией

struct PlayerPresenter: UIViewControllerRepresentable {
    @ObservedObject var vm: PlayerViewModel
    var onDismiss: () -> Void

    func makeUIViewController(context: Context) -> PlayerHostingController<PlayerContainerView> {
        let container = PlayerContainerView(vm: vm, onDismiss: {
            context.coordinator.dismissPlayer()
        })
        let hc = PlayerHostingController(rootView: container)
        hc.onDismissed = {
            context.coordinator.didDismiss()
        }
        context.coordinator.hostingController = hc
        return hc
    }

    func updateUIViewController(_ uiViewController: PlayerHostingController<PlayerContainerView>, context: Context) {
        // vm обновляется через @ObservedObject, перерисовка SwiftUI-view автоматическая
    }

    func makeCoordinator() -> Coordinator { Coordinator(onDismiss: onDismiss) }

    class Coordinator {
        weak var hostingController: UIViewController?
        private let onDismiss: () -> Void
        private var dismissCalled = false

        init(onDismiss: @escaping () -> Void) { self.onDismiss = onDismiss }

        func dismissPlayer() {
            guard !dismissCalled else { return }
            hostingController?.dismiss(animated: true)
        }

        func didDismiss() {
            guard !dismissCalled else { return }
            dismissCalled = true
            onDismiss()
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

    @StateObject private var viewModel = PlayerViewModel()

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
        seriesResult: AllohaApiResult? = nil
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
    }

    var body: some View {
        PlayerPresenter(vm: viewModel) {
            viewModel.cleanup()
        }
        .ignoresSafeArea()
        .onAppear {
            guard viewModel.player == nil else { return }
            viewModel.player = AVPlayer()
            viewModel.fallbackTitle = fallbackTitle
            viewModel.targetQualityPreference = initialQuality
            viewModel.seriesResult = seriesResult

            if iframeUrl != nil || directStreamUrl != nil {
                viewModel.load(
                    iframeUrl: iframeUrl,
                    kpId: kpId,
                    season: season,
                    episode: episode,
                    selectedVoiceover: selectedVoiceover,
                    directStreamUrl: directStreamUrl,
                    voices: voices,
                    subtitles: subtitles
                )
            } else {
                viewModel.error = "Нет URL для воспроизведения"
                viewModel.isLoading = false
            }
        }
        .onDisappear {
            AppDelegate.lockToPortrait()
        }
    }
}


@MainActor
class PlayerViewModel: ObservableObject {
    struct PlaybackQualityOption {
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
    
    // SharePlay
    @Published var groupSession: GroupSession<WatchTogetherActivity>?
    private var sharePlayTasks = Set<Task<Void, Never>>()

    var isUserSeeking = false

    var isMovie: Bool {
        return seriesResult?.isSerial == false || seriesResult?.movie != nil
    }

    var hasNextEpisode: Bool {
        return nextEpisodeCandidate() != nil
    }

    var hasPreviousEpisode: Bool {
        return previousEpisodeCandidate() != nil
    }

    // MARK: - Timing
    @Published var currentTime: Double = 0
    @Published var currentDuration: Double = 0
    @Published var bufferedProgress: Double = 0
    @Published var screenScrubTime: Double?
    @Published var introRange: ClosedRange<Double>?
    @Published var outroRange: ClosedRange<Double>?
    @Published var showSkipIntro = false
    @Published var showSkipOutro = false

    // MARK: - Quality & Rate
    @Published var availableQualities: [PlaybackQualityOption] = []
    @Published var currentQualityKey: String?
    @Published var playbackRate: Float = 1.0

    // MARK: - Voiceovers
    @Published var availableVoiceovers: [String] = []
    var currentTranslationName: String? { _currentTranslationName }
    private var _currentTranslationName: String?

    // MARK: - Subtitles
    @Published var availableSubtitles: [PlaybackSubtitle] = []
    @Published var currentSubtitle: PlaybackSubtitle?

    // MARK: - PiP
    @Published var isPiPActive = false
    var pipController: AVPictureInPictureController?

    // MARK: - Meta
    var fallbackTitle: String = ""

    private var resolver: AllohaRuntimeResolver?
    private var resolveTask: Task<Void, Never>?
    private var currentHeaders: [String: String] = [:]
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var bufferObserver: NSKeyValueObservation?
    private var itemObservation: NSKeyValueObservation?
    private var playbackEndObserver: NSObjectProtocol?
    private var resignActiveObserver: NSObjectProtocol?
    private var foregroundObserver: NSObjectProtocol?
    private var audioInterruptionObserver: NSObjectProtocol?
    private var rateObserver: NSKeyValueObservation?
    /// Оригинальный upstream URL стрима (без 127.0.0.1 прокси). Используется для перезапуска после фона.
    private var originalStreamURL: URL?
    /// Проксированный URL который дали в AVPlayer (может быть 127.0.0.1).
    private var currentPlaybackSourceURL: URL?

    private(set) var currentKpId: Int?
    private(set) var currentSeason: Int?
    private(set) var currentEpisode: Int?
    private var targetVoiceover: String?
    /// Pre-resolved direct stream URL; bypasses audioVariant matching when set.
    private var targetDirectStreamUrl: String?
    private var isAdvancingToNextEpisode = false
    /// Оригинальный iframeUrl Alloha. Нужен для корректного переключения озвучки в плеере.
    private var currentIframeUrl: String?
    /// Все audioVariants из последнего resolve. Нужны для мгновенного переключения озвучки без re-resolve.
    private var resolvedAudioVariants: [[String: Any]] = []

    var targetQualityPreference: VideoQualityPreference?
    var seriesResult: AllohaApiResult?
    private var hasStartedLoading = false
    private var hasRetriedPlayback = false

    var displayLogoUrl: URL? {
        guard let kpId = currentKpId, kpId > 0 else { return nil }
        return URL(string: "https://api.neome.uk/api/v1/images/logos/\(kpId)/original")
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
    
    func load(iframeUrl: String?, kpId: Int?, season: Int?, episode: Int?, selectedVoiceover: String?, directStreamUrl: String? = nil, voices: [String] = [], subtitles: [PlaybackSubtitle] = []) {
        if hasStartedLoading { return } // Защита от двойного вызова
        hasStartedLoading = true
        logDebug("load called with iframeUrl=\(iframeUrl ?? "nil"), selectedVoiceover=\(selectedVoiceover ?? "nil"), directStreamUrl=\(directStreamUrl ?? "nil")")
        beginLoad(iframeUrl: iframeUrl, kpId: kpId, season: season, episode: episode, selectedVoiceover: selectedVoiceover, directStreamUrl: directStreamUrl, voices: voices, subtitles: subtitles)
    }

    /// Повторная попытка воспроизведения после ошибки. Пробует сначала через originalStreamURL (мгновенно),
    /// и только если его нет — перезапускает полный resolve через iframe.
    func retryPlayback() {
        error = nil
        isLoading = true
        hasRetriedPlayback = false

        if let url = originalStreamURL {
            // Оригинальный URL известен — переподключаемся без re-resolve
            print("retryPlayback: reloading from originalStreamURL")
            HlsProxyServer.shared.start(
                headers: currentHeaders,
                voices: [],
                subtitles: availableSubtitles,
                mediaId: currentKpId.map { "kp_\($0)" } ?? "unknown"
            )
            reloadPlayback(to: url, preferredPeakBitRate: player?.currentItem?.preferredPeakBitRate)
        } else {
            // URL неизвестен — нужен полный перезапуск (например первичная ошибка resolve)
            hasStartedLoading = false
            isLoading = false
            error = "Не удалось восстановить воспроизведение. Закройте плеер и откройте заново."
        }
    }

    private func beginLoad(iframeUrl: String?, kpId: Int?, season: Int?, episode: Int?, selectedVoiceover: String?, directStreamUrl: String? = nil, voices: [String] = [], subtitles: [PlaybackSubtitle] = []) {
        self.currentKpId = kpId
        self.currentSeason = season
        self.currentEpisode = episode
        self.targetVoiceover = selectedVoiceover
        self._currentTranslationName = selectedVoiceover
        self.targetDirectStreamUrl = directStreamUrl
        self.isAdvancingToNextEpisode = false
        self.hasRetriedPlayback = false
        // Сохраняем iframeUrl — нужен для переключения озвучки внутри плеера
        if let iframeUrl, !iframeUrl.isEmpty {
            self.currentIframeUrl = iframeUrl
        }
        // Сбрасываем кэш audioVariants — будет обновлён после resolve нового стрима
        self.resolvedAudioVariants = []

        if let seriesResult = self.seriesResult, let s = season, let e = episode {
            if let seasonObj = seriesResult.seasons.first(where: { $0.season == s }),
               let epObj = seasonObj.episodes.first(where: { $0.episode == e }) {
                self.availableVoiceovers = epObj.translations.map { $0.name }
            }
        } else if !voices.isEmpty {
            self.availableVoiceovers = voices
        }

        if kpId != nil, let selectedVoiceover, !selectedVoiceover.isEmpty {
            persistVoiceoverSelection(selectedVoiceover)
        }

        isLoading = true
        isPlaying = false
        error = nil

        if let directUrlString = directStreamUrl, let directUrl = URL(string: directUrlString) {
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
        } else if let iframe = iframeUrl, !iframe.isEmpty {
            startParsing(iframeUrl: iframe, voices: voices, subtitles: subtitles)
        } else {
            error = "Нет URL для воспроизведения"
            isLoading = false
        }
    }
    
    private func parseMasterPlaylist(content: String, baseUrl: URL) {
        var qualities: [PlaybackQualityOption] = [
            PlaybackQualityOption(
                key: "Авто",
                url: baseUrl,
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
                var resStr = "Поток"
                currentBandwidth = nil
                if let range = line.range(of: "RESOLUTION=([^,\\s]+)", options: .regularExpression) {
                    let match = String(line[range])
                    let res = match.replacingOccurrences(of: "RESOLUTION=", with: "")
                    let components = res.components(separatedBy: "x")
                    if components.count == 2, let height = Int(components[1]) {
                        resStr = "\(height)p"
                    }
                } else if let range = line.range(of: "BANDWIDTH=([^,\\s]+)", options: .regularExpression) {
                    let match = String(line[range])
                    let bw = match.replacingOccurrences(of: "BANDWIDTH=", with: "")
                    if let bandwidth = Double(bw) {
                        currentBandwidth = bandwidth
                        resStr = "\(bandwidth / 1000) kbps"
                    }
                }
                currentResolution = resStr
            } else if !line.hasPrefix("#") && !line.isEmpty {
                if let res = currentResolution {
                    let variantUrl: URL
                    if line.hasPrefix("http") {
                        guard let u = URL(string: line)?.absoluteURL else { continue }
                        variantUrl = u
                    } else {
                        guard let u = URL(string: line, relativeTo: baseUrl)?.absoluteURL else { continue }
                        variantUrl = u
                    }
                    if !qualities.contains(where: { $0.key == res }) {
                        qualities.append(
                            PlaybackQualityOption(
                                key: res,
                                url: variantUrl,
                                preferredPeakBitRate: currentBandwidth,
                                isAuto: false,
                                shouldReloadOnSelect: false
                            )
                        )
                    } else {
                        // Prevent duplicate keys
                        let uniqueRes = "\(res) (\(qualities.count))"
                        qualities.append(
                            PlaybackQualityOption(
                                key: uniqueRes,
                                url: variantUrl,
                                preferredPeakBitRate: currentBandwidth,
                                isAuto: false,
                                shouldReloadOnSelect: false
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
                
                // Keep the direct MP4 qualities (like 1440p, 2160p) from JSON that were not in the m3u8
                var mergedQualities = qualities
                let existingKeys = Set(qualities.map { $0.key })
                for originalQuality in self.availableQualities {
                    if !existingKeys.contains(originalQuality.key) {
                        mergedQualities.append(originalQuality)
                    }
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
    
    private func applyInitialQuality() {
        let prefRaw = UserDefaults.standard.string(forKey: "preferredVideoQuality") ?? VideoQualityPreference.ask.rawValue
        let globalPref = VideoQualityPreference(rawValue: prefRaw) ?? .ask
        let targetQuality = self.targetQualityPreference ?? globalPref
        
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
        let prefVal = Int(targetKey.replacingOccurrences(of: "p", with: "")) ?? 0
        guard prefVal > 0 else { return }
        
        var closest: String?
        var minDiff = Int.max
        for q in availableQualities {
            let val = Int(q.key.replacingOccurrences(of: "p", with: "")) ?? 0
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
                self.error = error.localizedDescription
                self.isLoading = false
            }
        }
    }
    
    func cleanup() {
        hasStartedLoading = false
        currentPlaybackSourceURL = nil
        originalStreamURL = nil
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        if let playbackEndObserver {
            NotificationCenter.default.removeObserver(playbackEndObserver)
            self.playbackEndObserver = nil
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
        itemObservation?.invalidate()
        itemObservation = nil
        statusObserver?.invalidate()
        statusObserver = nil
        bufferObserver?.invalidate()
        bufferObserver = nil
        rateObserver?.invalidate()
        rateObserver = nil

        // Final progress save before cleanup
        saveCurrentProgress()
        clearNowPlaying()


        resolveTask?.cancel()
        resolveTask = nil
        resolver?.cancel()
        resolver = nil
        player?.pause()
        player = nil
        HlsProxyServer.shared.stop()
    }

    // MARK: - Playback actions

    func togglePlayPause() {
        guard let player else { return }
        if player.timeControlStatus == .playing {
            player.pause()
        } else {
            player.play()
        }
        updateNowPlaying()
    }

    func seek(by seconds: Double) {
        guard let player else { return }
        let current = player.currentTime().seconds
        let target = max(0, min(currentDuration, current + seconds))
        seek(to: target)
    }

    func seek(to seconds: Double) {
        guard let player else { return }
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        isUserSeeking = true
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isUserSeeking = false
            }
        }
        currentTime = seconds
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

    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        player?.rate = rate
        updateNowPlaying()
    }

    func setSubtitle(_ subtitle: PlaybackSubtitle?) {
        currentSubtitle = subtitle
        // TODO: инъекция субтитров через HlsProxyServer в следующей фазе
    }

    /// Переключает озвучку без закрытия плеера
    func switchVoiceover(to name: String) {
        logDebug("switchVoiceover: switching to '\(name)'")
        // 1. Пробуем переключить нативно в текущем AVPlayer (если дорожка встроена в HLS)
        if let player = player,
           let item = player.currentItem,
           let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .audible) {
            let options = group.options
            logDebug("switchVoiceover: native tracks available: \(options.map { $0.displayName })")
            if let option = options.first(where: { allohaTranslationNamesMatch($0.displayName, name, exactOnly: true) }) {
                _currentTranslationName = name
                targetVoiceover = name
                persistVoiceoverSelection(name)
                item.select(option, in: group)
                logDebug("switchVoiceover: switched audio natively to '\(option.displayName)'")
                return
            }
        }

        let isSerial = seriesResult?.isSerial == true

        // Ищем новый iframeUrl для нужной озвучки
        var targetIframeUrl: String?
        
        if isMovie {
            if let movie = seriesResult?.movie,
               let translation = movie.translations.first(where: { allohaTranslationNamesMatch($0.name, name, exactOnly: true) }) {
                targetIframeUrl = translation.iframeUrl
            }
        } else {
            if let seriesResult, let season = currentSeason, let episode = currentEpisode,
               let seasonObj = seriesResult.seasons.first(where: { $0.season == season }),
               let epObj = seasonObj.episodes.first(where: { $0.episode == episode }),
               let translation = epObj.translations.first(where: { allohaTranslationNamesMatch($0.name, name, exactOnly: true) }) {
                targetIframeUrl = translation.iframeUrl
            }
        }
        
        guard let iframeUrl = targetIframeUrl, !iframeUrl.isEmpty else {
            logDebug("switchVoiceover error: failed to find translation iframeUrl for '\(name)'")
            return
        }

        logDebug("switchVoiceover: reloading from translation iframeUrl=\(iframeUrl)")
        _currentTranslationName = name
        targetVoiceover = name
        persistVoiceoverSelection(name)
        
        // Инвалидируем кэш перед re-resolve
        AllohaRuntimeResolver.invalidateCache(for: iframeUrl)
        resolveTask?.cancel()
        resolver?.cancel()
        hasStartedLoading = false
        beginLoad(
            iframeUrl: iframeUrl,
            kpId: currentKpId,
            season: currentSeason,
            episode: currentEpisode,
            selectedVoiceover: name
        )
        return
    }

    /// Сохраняет текущую позицию воспроизведения. Вызывается и по таймеру, и при сворачивании приложения.
    private func saveCurrentProgress() {
        guard let player = player, let currentKpId = currentKpId else { return }
        let mediaId: String
        if let season = currentSeason, let episode = currentEpisode {
            mediaId = "kp_\(currentKpId)_s\(season)_e\(episode)"
        } else {
            mediaId = "kp_\(currentKpId)"
        }
        let pos = player.currentTime().seconds
        guard pos.isFinite, !pos.isNaN else { return }
        let duration = player.currentItem?.duration.seconds
        PlaybackProgressStore.shared.save(
            mediaId: mediaId,
            positionSec: pos,
            durationSec: duration?.isFinite == true && duration?.isNaN == false ? duration : nil
        )
    }
    
    func changeQuality(to key: String) {
        logDebug("changeQuality: called with key='\(key)'")
        guard let quality = availableQualities.first(where: { $0.key == key }) else {
            logDebug("changeQuality: quality key '\(key)' not found in availableQualities!")
            return
        }
        self.currentQualityKey = key
        
        // Сохраняем выбор пользователя для текущего сеанса просмотра,
        // чтобы при переключении озвучки качество не сбрасывалось на авто.
        if let newPreference = VideoQualityPreference(rawValue: key) {
            self.targetQualityPreference = newPreference
        }
        
        let isHls = quality.url.pathExtension.lowercased() == "m3u8" || quality.url.absoluteString.contains(".m3u8")
        logDebug("changeQuality: quality='\(key)', url=\(quality.url.absoluteString), isHls=\(isHls), isAuto=\(quality.isAuto), shouldReload=\(quality.shouldReloadOnSelect)")
        
        if quality.isAuto {
            if shouldReloadForAutoSelection(autoURL: quality.url) {
                logDebug("changeQuality: reloading for auto selection")
                reloadPlayback(to: quality.url, preferredPeakBitRate: 0)
            } else {
                logDebug("changeQuality: updating preferredPeakBitRate to 0 (auto)")
                player?.currentItem?.preferredPeakBitRate = 0
            }
            return
        }

        if quality.shouldReloadOnSelect {
            logDebug("changeQuality: shouldReloadOnSelect is true, calling reloadPlayback")
            reloadPlayback(to: quality.url, preferredPeakBitRate: quality.preferredPeakBitRate)
            return
        }

        if isHls, let currentItem = self.player?.currentItem {
            logDebug("changeQuality: updating preferredPeakBitRate for HLS to \(resolvedBitrate(for: quality))")
            currentItem.preferredPeakBitRate = resolvedBitrate(for: quality)
            return
        }

        logDebug("changeQuality: fallback, calling reloadPlayback")
        reloadPlayback(to: quality.url, preferredPeakBitRate: quality.preferredPeakBitRate)
    }

    private func reloadPlayback(to sourceURL: URL, preferredPeakBitRate: Double?) {
        logDebug("reloadPlayback: called with sourceURL=\(sourceURL.absoluteString), preferredPeakBitRate=\(preferredPeakBitRate ?? -1)")
        let savedTime = self.currentTime
        let wasPlaying = player?.timeControlStatus == .playing || player?.timeControlStatus == .waitingToPlayAtSpecifiedRate

        // Обновляем originalStreamURL если пришёл не прокси-URL
        if !isLocalProxyUrl(sourceURL) {
            originalStreamURL = sourceURL.absoluteURL
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
            guard let proxyUrl = proxiedPlaybackURL(for: sourceURL) else { return }
            logDebug("reloadPlayback: Proxied HLS stream URL: \(proxyUrl.absoluteString)")
            currentPlaybackSourceURL = proxyUrl
            asset = AVURLAsset(url: proxyUrl)
        }

        let playerItem = AVPlayerItem(asset: asset)
        playerItem.preferredPeakBitRate = max(0, preferredPeakBitRate ?? 0)
        hasRetriedPlayback = true

        self.isLoading = true

        self.player?.replaceCurrentItem(with: playerItem)
        setupPlayerItemObservers(for: playerItem)

        // Дожидаемся готовности перед seek и play
        itemObservation = playerItem.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if item.status == .readyToPlay {
                    self.itemObservation?.invalidate()
                    self.itemObservation = nil
                    
                    self.player?.seek(to: CMTime(seconds: savedTime, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                        if wasPlaying {
                            self.player?.play()
                        }
                    }
                }
            }
        }
    }

    private func proxiedPlaybackURL(for sourceURL: URL) -> URL? {
        let absoluteUrlString = sourceURL.absoluteURL.absoluteString
        guard let encodedData = absoluteUrlString.data(using: .utf8) else { return nil }
        let encoded = encodedData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        let ext = sourceURL.pathExtension
        let pathSuffix = ext.isEmpty ? "stream.m3u8" : "stream.\(ext)"

        return URL(string: "http://127.0.0.1:\(HlsProxyServer.shared.port.rawValue)/proxy/\(pathSuffix)?url=\(encoded)")
    }

    private func shouldReloadForAutoSelection(autoURL: URL) -> Bool {
        guard let currentPlaybackSourceURL else { return false }
        return currentPlaybackSourceURL.absoluteURL.absoluteString != autoURL.absoluteURL.absoluteString
    }

    private func resolvedBitrate(for quality: PlaybackQualityOption) -> Double {
        if let preferredPeakBitRate = quality.preferredPeakBitRate, preferredPeakBitRate > 0 {
            return preferredPeakBitRate
        }

        let height = Int(quality.key.replacingOccurrences(of: "p", with: "")) ?? 0
        switch height {
        case 2160...: return 20_000_000 // 4K UHD
        case 1440..<2160: return 12_000_000 // 2K/1440p
        case 1080..<1440: return 8_000_000 // Full HD
        case 720..<1080: return 4_000_000 // HD
        case 480..<720: return 2_000_000
        case 360..<480: return 1_000_000
        case 1..<360: return 700_000
        default: return 0
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

    private func makeResolvedQualityOption(label: String, url: URL, preferredPeakBitRate: Double?) -> PlaybackQualityOption {
        makeQualityOption(
            key: label,
            url: url,
            preferredPeakBitRate: preferredPeakBitRate,
            isAuto: false,
            shouldReloadOnSelect: true
        )
    }

    private func makeMasterPlaylistQualityOption(label: String, url: URL, preferredPeakBitRate: Double?) -> PlaybackQualityOption {
        makeQualityOption(
            key: label,
            url: url,
            preferredPeakBitRate: preferredPeakBitRate,
            isAuto: false,
            shouldReloadOnSelect: false
        )
    }

    private func makeResolvedQualityOptions(
        resolvedUrl: URL,
        qualityVariants: [[String: Any]],
        audioVariants: [[String: Any]]
    ) -> [PlaybackQualityOption] {
        var qualities = [makeAutoQualityOption(url: resolvedUrl)]
        var seenKeys = Set<String>(["Авто"])

        appendQualityVariants(qualityVariants, to: &qualities, seenKeys: &seenKeys)

        if qualities.count == 1,
           let firstAudio = audioVariants.first,
           let nestedQualityVariants = firstAudio["qualityVariants"] as? [[String: Any]] {
            appendQualityVariants(nestedQualityVariants, to: &qualities, seenKeys: &seenKeys)
        }

        if qualities.count > 1 {
            let autoQuality = qualities.removeFirst()
            qualities.sort { lhs, rhs in
                let valA = Int(lhs.key.replacingOccurrences(of: "p", with: "")) ?? 0
                let valB = Int(rhs.key.replacingOccurrences(of: "p", with: "")) ?? 0
                return valA > valB
            }
            qualities.insert(autoQuality, at: 0)
        }
        
        let originalLabels = qualityVariants.compactMap { $0["label"] as? String }.joined(separator: ", ")
        logDebug("makeResolvedQualityOptions: server returned qualities = [\(originalLabels)]")
        logDebug("makeResolvedQualityOptions: final qualities for player = [\(qualities.map { $0.key }.joined(separator: ", "))]")

        return qualities
    }
    
    
    private func playVideo(url: URL, headers: [String: String], voices: [String] = [], subtitles: [PlaybackSubtitle] = []) {
        logDebug("playVideo: starting playback, url=\(url.absoluteString)")
        // Сохраняем оригинальный URL ДО проксирования — нужен для перезапуска после фона
        originalStreamURL = url.absoluteURL
        currentHeaders = headers

        let asset: AVURLAsset
        let urlStringLower = url.absoluteString.lowercased()
        let isMp4 = url.pathExtension.lowercased() == "mp4" || (!urlStringLower.contains(".m3u8") && urlStringLower.contains(".mp4"))

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
            guard let proxyUrl = proxiedPlaybackURL(for: url) else {
                logDebug("playVideo error: failed to form proxy URL")
                self.error = "Ошибка формирования URL"
                self.isLoading = false
                return
            }

            let mediaId: String
            if let kpId = currentKpId {
                if let season = currentSeason, let episode = currentEpisode {
                    mediaId = "kp_\(kpId)_s\(season)_e\(episode)"
                } else {
                    mediaId = "kp_\(kpId)"
                }
            } else {
                mediaId = "unknown"
            }

            HlsProxyServer.shared.start(headers: headers, voices: voices, subtitles: subtitles, mediaId: mediaId)
            // currentPlaybackSourceURL — прокси URL (127.0.0.1); для перезапуска используем originalStreamURL
            currentPlaybackSourceURL = proxyUrl
            asset = AVURLAsset(url: proxyUrl)
        }

        let playerItem = AVPlayerItem(asset: asset)
        
        if self.player == nil { 
            let newPlayer = AVPlayer()
            self.player = newPlayer
        }
        self.player?.replaceCurrentItem(with: playerItem)

        // SharePlay Coordination
        if let session = groupSession {
            self.player?.playbackCoordinator.coordinateWithSession(session)
        }
        self.player?.automaticallyWaitsToMinimizeStalling = true
        self.player?.rate = playbackRate

        setupPlayerItemObservers(for: playerItem)

        rateObserver = self.player?.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let status = player.timeControlStatus
                self.isPlaying = (status == .playing)
                self.isBuffering = (status == .waitingToPlayAtSpecifiedRate)
                
                self.updateNowPlaying()
            }
        }

        self.isLoading = false
        self.startTrackingProgress()
        self.player?.play()
    }
    
    private func setupPlayerItemObservers(for playerItem: AVPlayerItem) {
        statusObserver?.invalidate()
        bufferObserver?.invalidate()
        itemObservation?.invalidate()
        
        if let playbackEndObserver {
            NotificationCenter.default.removeObserver(playbackEndObserver)
            self.playbackEndObserver = nil
        }

        statusObserver = playerItem.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if item.status == .failed {
                    let nsError = item.error as NSError?
                    self.logDebug("setupPlayerItemObservers: item failed! Domain=\(nsError?.domain ?? ""), Code=\(nsError?.code ?? 0), Desc=\(nsError?.localizedDescription ?? "")")
                    print("PlayerItem failed: \(nsError?.localizedDescription ?? "Unknown error")")
                    
                    if nsError?.domain == AVFoundationErrorDomain, nsError?.code == -11848 {
                        self.logDebug("setupPlayerItemObservers: Cannot Open (-11848) detected. Likely AV1 codec issue.")
                        
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
                    }
                    
                    if !self.hasRetriedPlayback, let url = self.originalStreamURL ?? self.currentPlaybackSourceURL {
                        print("Auto-retrying playback after failure with originalStreamURL...")
                        // Перезапускаем прокси перед retry, так как именно он мог упасть
                        if let origUrl = self.originalStreamURL {
                            HlsProxyServer.shared.start(
                                headers: self.currentHeaders,
                                voices: [],
                                subtitles: self.availableSubtitles,
                                mediaId: self.currentKpId.map { "kp_\($0)" } ?? "unknown"
                            )
                            self.reloadPlayback(to: origUrl, preferredPeakBitRate: self.player?.currentItem?.preferredPeakBitRate)
                        } else {
                            self.reloadPlayback(to: url, preferredPeakBitRate: self.player?.currentItem?.preferredPeakBitRate)
                        }
                    } else {
                        self.error = item.error?.localizedDescription ?? "Ошибка воспроизведения"
                        self.isLoading = false
                    }
                } else if item.status == .readyToPlay {
                    self.isLoading = false
                    self.logDebug("setupPlayerItemObservers: playerItem is readyToPlay")
                    Task {
                        do {
                            _ = try await item.asset.loadMediaSelectionGroup(for: .audible)
                        } catch {
                            self.logDebug("setupPlayerItemObservers: failed to load audible group \(error)")
                        }
                        await MainActor.run {
                            self.syncNativeAudioTracks()
                            if let targetVoice = self.targetVoiceover ?? self._currentTranslationName {
                                self.selectAudioTrackInPlayer(named: targetVoice)
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
    }
    
    private func startTrackingProgress() {
        guard let player = player else { return }
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }

        let mediaId: String
        if let kpId = currentKpId {
            if let season = currentSeason, let episode = currentEpisode {
                mediaId = "kp_\(kpId)_s\(season)_e\(episode)"
            } else {
                mediaId = "kp_\(kpId)"
            }
        } else {
            return
        }

        let savedPosition = PlaybackProgressStore.shared.load(mediaId: mediaId)
        if savedPosition > 0 {
            player.seek(to: CMTime(seconds: savedPosition, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            currentTime = savedPosition
        }

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self, weak player] time in
            guard let self, let player else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.isUserSeeking { return }
                let t = time.seconds
                self.currentTime = t.isFinite && !t.isNaN ? t : 0
                let d = player.currentItem?.duration.seconds ?? 0
                if d.isFinite && !d.isNaN && d > 0 {
                    self.currentDuration = d
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
                
                // Сохраняем прогресс каждые 5 секунд (только если позиция > 1 секунды, чтобы избежать сброса в ноль)
                if Int(t) % 5 == 0 && t > 1 {
                    let dur = self.currentDuration > 0 ? self.currentDuration : nil
                    PlaybackProgressStore.shared.save(
                        mediaId: mediaId,
                        positionSec: t,
                        durationSec: dur
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
                self.hasRetriedPlayback = false // Сбрасываем флаг ретрая, чтобы при возврате из фона авто-ретрай мог сработать
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
                
                // 1. Восстанавливаем аудиосессию — могла быть сброшена звонком/другим приложением
                try? AVAudioSession.sharedInstance().setActive(true)
                
                // 2. Пинаем прокси (он сам проверит isListenerAlive)
                HlsProxyServer.shared.appWillEnterForeground()
                
                // 3. Возобновляем воспроизведение, если оно шло до ухода в фон.
                // Если стрим завис (прокси отпал), сработает 5.5с таймаут в rateObserver
                // и стрим принудительно перезагрузится через originalStreamURL.
                let wasPlaying = UserDefaults.standard.bool(forKey: "sloosh_was_playing_before_bg")
                if wasPlaying && self.player?.timeControlStatus != .playing {
                    self.player?.play()
                }
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
            self?.player?.play(); return .success
        }
        cc.pauseCommand.isEnabled = true
        cc.pauseCommand.addTarget { [weak self] _ in
            self?.player?.pause(); return .success
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
            info[MPMediaItemPropertyArtist] = "Сезон \(season), Серия \(episode)"
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
            return
        }

        isAdvancingToNextEpisode = true
        defer { isAdvancingToNextEpisode = false }
        
        playNextEpisode()
    }

    func playNextEpisode() {
        guard let nextEpisode = nextEpisodeCandidate() else { return }
        playEpisode(nextEpisode)
    }

    func playPreviousEpisode() {
        guard let prevEpisode = previousEpisodeCandidate() else { return }
        playEpisode(prevEpisode)
    }

    private func playEpisode(_ episode: (season: Int, episode: Int, translation: AllohaTranslation)) {
        currentSeason = episode.season
        currentEpisode = episode.episode
        _currentTranslationName = episode.translation.name
        targetVoiceover = episode.translation.name

        if let kpId = currentKpId {
            PlaybackProgressStore.shared.saveLastPlayed(kpId: kpId, season: episode.season, episode: episode.episode)
        }

        beginLoad(
            iframeUrl: episode.translation.iframeUrl,
            kpId: currentKpId,
            season: episode.season,
            episode: episode.episode,
            selectedVoiceover: episode.translation.name
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
        if let name = _currentTranslationName,
           let exactMatch = episode.translations.first(where: { allohaTranslationNamesMatch($0.name, name) }) {
            return exactMatch
        }

        if let targetVoiceover,
           let voiceMatch = episode.translations.first(where: { allohaTranslationNamesMatch($0.name, targetVoiceover) }) {
            return voiceMatch
        }

        return episode.translations.first
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
            // The iframeUrl already has translation=ID injected for both movies and series, 
            // so CDN delivers the correct voiceover stream as the default. 
            // No audioVariant name matching needed.
            logDebug("applyResolvedAllohaStream: using default resolved url (translation embedded in iframe)")
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

        // Заполняем список доступных озвучек из audioVariants
        let voices = resolvedVoiceovers(from: resolved)
        if !voices.isEmpty {
            if self.isMovie || self.availableVoiceovers.isEmpty {
                self.availableVoiceovers = voices
            }
        }

        let qualityVariants = (resolved["qualityVariants"] as? [[String: Any]]) ?? []

        availableQualities = makeResolvedQualityOptions(
            resolvedUrl: resolvedUrl,
            qualityVariants: qualityVariants,
            audioVariants: audioVariants
        )
        currentQualityKey = "Авто"
        playVideo(url: resolvedUrl, headers: headers, voices: voices, subtitles: resolvedSubtitles)
        NotificationCenter.default.post(name: NSNotification.Name("QualitiesUpdated"), object: nil)

        applyInitialQuality()
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


    private func selectAudioTrackInPlayer(named name: String) {
        guard let player = player,
              let item = player.currentItem,
              let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .audible) else {
            logDebug("selectAudioTrackInPlayer: no player, currentItem or audible mediaSelectionGroup")
            return
        }
        
        let options = group.options
        logDebug("selectAudioTrackInPlayer: target='\(name)', options=\(options.map { $0.displayName })")
        
        // Exact match
        if let option = options.first(where: { allohaTranslationNamesMatch($0.displayName, name, exactOnly: true) }) {
            item.select(option, in: group)
            persistVoiceoverSelection(name)
            logDebug("selectAudioTrackInPlayer: selected exact match option='\(option.displayName)'")
            return
        }
        
        // Fuzzy match
        if let option = options.first(where: { allohaTranslationNamesMatch($0.displayName, name, exactOnly: false) }) {
            item.select(option, in: group)
            persistVoiceoverSelection(name)
            logDebug("selectAudioTrackInPlayer: selected fuzzy match option='\(option.displayName)'")
            return
        }
        
        // Match by index or language tag if name represents a standard language
        let lowerName = name.lowercased()
        let targetLang: String? = {
            if lowerName.contains("eng") || lowerName.contains("original") || lowerName.contains("англ") || lowerName.contains("ori") {
                return "en"
            }
            if lowerName.contains("rus") || lowerName.contains("рус") || lowerName.contains("дуб") {
                return "ru"
            }
            if lowerName.contains("ukr") || lowerName.contains("укр") {
                return "uk"
            }
            return nil
        }()
        
        if let targetLang {
            if let option = options.first(where: { 
                $0.extendedLanguageTag?.lowercased().hasPrefix(targetLang) == true ||
                $0.locale?.identifier.lowercased().hasPrefix(targetLang) == true 
            }) {
                item.select(option, in: group)
                persistVoiceoverSelection(name)
                logDebug("selectAudioTrackInPlayer: selected by language tag '\(targetLang)', option='\(option.displayName)'")
                return
            }
        }
        
        if let targetIndex = extractAudioIndex(from: name), targetIndex < options.count {
            item.select(options[targetIndex], in: group)
            persistVoiceoverSelection(name)
            logDebug("selectAudioTrackInPlayer: selected by index \(targetIndex), option='\(options[targetIndex].displayName)'")
            return
        }
        logDebug("selectAudioTrackInPlayer: failed to match any track for '\(name)'")
    }
    
    private func syncNativeAudioTracks() {
        guard let player = player,
              let item = player.currentItem,
              let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .audible) else {
            return
        }
        
        let nativeNames = group.options.map { $0.displayName }
        logDebug("syncNativeAudioTracks: nativeNames=\(nativeNames)")
        guard nativeNames.count > 1 else { return }
        
        var updatedVoiceovers = self.availableVoiceovers
        
        for name in nativeNames {
            let cleanName = normalizedAllohaTranslationName(name)
            let finalName = cleanName.isEmpty ? name : cleanName
            if !updatedVoiceovers.contains(where: { allohaTranslationNamesMatch($0, finalName) }) {
                updatedVoiceovers.append(finalName)
            }
        }
        
        if updatedVoiceovers != self.availableVoiceovers {
            self.availableVoiceovers = updatedVoiceovers
            logDebug("syncNativeAudioTracks: updated availableVoiceovers=\(self.availableVoiceovers)")
        }
    }
    
    private func extractAudioIndex(from name: String) -> Int? {
        let patterns = [
            #"(?:^|[^a-z0-9])(?:rus|ru|eng|en)(\d+)(?:$|[^a-z0-9])"#,
            #"(?:^|[^a-z0-9])audio[_-]?(\d+)(?:$|[^a-z0-9])"#
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

    // MARK: - SharePlay Logic
    func setupSharePlay() {
        let task = Task { @MainActor in
            for await session in WatchTogetherActivity.sessions() {
                self.groupSession = session
                if let player = self.player {
                    player.playbackCoordinator.coordinateWithSession(session)
                }
                session.join()
            }
        }
        sharePlayTasks.insert(task)
    }

    func startSharePlay() {
        let title = fallbackTitle
        let mediaId = currentKpId != nil ? String(currentKpId!) : "unknown"
        let activity = WatchTogetherActivity(mediaId: mediaId, title: title)
        Task {
            do {
                _ = try await activity.activate()
            } catch {
                print("SharePlay activation failed: \(error)")
            }
        }
    }

    private func logDebug(_ message: String) {
        AppDiagnostics.shared.log("[PlayerDebug] \(message)")
    }

    private func persistVoiceoverSelection(_ name: String?) {
        guard let kpId = currentKpId else { return }
        let normalized = normalizedAllohaTranslationName(name)
        let finalName = normalized.isEmpty ? name : normalized
        PlaybackProgressStore.shared.saveLastVoiceover(
            kpId: kpId,
            source: "alloha",
            voiceover: finalName
        )
        if let finalName, !finalName.isEmpty {
            UserDefaults.standard.set(finalName, forKey: "alloha_last_translation_name")
        }
    }

    private func appendQualityVariants(_ variants: [[String: Any]], to qualities: inout [PlaybackQualityOption], seenKeys: inout Set<String>) {
        for variant in variants {
            guard let urlString = variant["url"] as? String,
                  let url = absoluteQualityURL(from: urlString) else {
                continue
            }
            let label = normalizedQualityLabel(from: variant["label"] as? String)
            
            // Фильтруем AV1 кодек, так как iOS/AVPlayer его не поддерживает
            let lowerLabel = label.lowercased()
            let lowerUrl = urlString.lowercased()
            if lowerLabel.contains("av1") || lowerLabel.contains("av01") || lowerUrl.contains("av1") || lowerUrl.contains("av01") {
                continue
            }
            
            guard seenKeys.insert(label).inserted else { continue }
            qualities.append(
                makeResolvedQualityOption(
                    label: label,
                    url: url,
                    preferredPeakBitRate: bitrateValue(from: variant)
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
