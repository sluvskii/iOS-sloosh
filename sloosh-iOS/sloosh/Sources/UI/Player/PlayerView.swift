import SwiftUI
import AVKit
import AVFoundation
import MediaPlayer

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

    // MARK: - Timing
    @Published var currentTime: Double = 0
    @Published var currentDuration: Double = 0
    @Published var bufferedProgress: Double = 0

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
    private var rateObserver: NSKeyValueObservation?
    private var currentPlaybackSourceURL: URL?

    private var currentKpId: Int?
    private var currentSeason: Int?
    private var currentEpisode: Int?
    private var targetVoiceover: String?
    /// Pre-resolved direct stream URL; bypasses audioVariant matching when set.
    private var targetDirectStreamUrl: String?
    private var isAdvancingToNextEpisode = false

    var targetQualityPreference: VideoQualityPreference?
    var seriesResult: AllohaApiResult?
    private var hasStartedLoading = false

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
        beginLoad(iframeUrl: iframeUrl, kpId: kpId, season: season, episode: episode, selectedVoiceover: selectedVoiceover, directStreamUrl: directStreamUrl, voices: voices, subtitles: subtitles)
    }

    private func beginLoad(iframeUrl: String?, kpId: Int?, season: Int?, episode: Int?, selectedVoiceover: String?, directStreamUrl: String? = nil, voices: [String] = [], subtitles: [PlaybackSubtitle] = []) {
        self.currentKpId = kpId
        self.currentSeason = season
        self.currentEpisode = episode
        self.targetVoiceover = selectedVoiceover
        self._currentTranslationName = selectedVoiceover
        self.targetDirectStreamUrl = directStreamUrl
        self.isAdvancingToNextEpisode = false

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
                        variantUrl = URL(string: line)!.absoluteURL
                    } else {
                        variantUrl = URL(string: line, relativeTo: baseUrl)!.absoluteURL
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
            
            DispatchQueue.main.async {
                self.availableQualities = qualities
                NotificationCenter.default.post(name: NSNotification.Name("QualitiesUpdated"), object: nil)
                self.applyInitialQuality()
            }
        }
    }
    
    private func applyInitialQuality() {
        // Read global preference or the one passed from the sheet
        let prefRaw = UserDefaults.standard.string(forKey: "preferredVideoQuality") ?? VideoQualityPreference.ask.rawValue
        let globalPref = VideoQualityPreference(rawValue: prefRaw) ?? .ask
        let targetQuality = self.targetQualityPreference ?? globalPref
        
        guard targetQuality != .ask && targetQuality != .auto else { return }
        
        let targetKey = targetQuality.rawValue
        
        // Exact match (1080p -> 1080p)
        if let exact = availableQualities.first(where: { $0.key.hasPrefix(targetKey) }) {
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
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
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
        guard let seriesResult else {
            // Для фильма — перезапускаем текущий iframe с новой озвучкой
            if let iframeUrl = availableQualities.first?.url.absoluteString {
                _currentTranslationName = name
                targetVoiceover = name
                hasStartedLoading = false
                beginLoad(
                    iframeUrl: iframeUrl,
                    kpId: currentKpId,
                    season: nil,
                    episode: nil,
                    selectedVoiceover: name
                )
            }
            return
        }

        // Для сериала — ищем нужный iframe
        guard let season = currentSeason,
              let episode = currentEpisode,
              let seasonObj = seriesResult.seasons.first(where: { $0.season == season }),
              let epObj = seasonObj.episodes.first(where: { $0.episode == episode }),
              let translation = epObj.translations.first(where: { $0.name == name }) else { return }

        _currentTranslationName = name
        targetVoiceover = name
        hasStartedLoading = false
        beginLoad(
            iframeUrl: translation.iframeUrl,
            kpId: currentKpId,
            season: season,
            episode: episode,
            selectedVoiceover: name
        )
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
        let duration = player.currentItem?.duration.seconds
        PlaybackProgressStore.shared.save(
            mediaId: mediaId,
            positionSec: player.currentTime().seconds,
            durationSec: duration?.isNaN == false ? duration : nil
        )
    }
    
    func changeQuality(to key: String) {
        guard let quality = availableQualities.first(where: { $0.key == key }) else { return }
        self.currentQualityKey = key
        
        let isHls = quality.url.pathExtension.lowercased() == "m3u8" || quality.url.absoluteString.contains(".m3u8")
        
        if quality.isAuto {
            if shouldReloadForAutoSelection(autoURL: quality.url) {
                reloadPlayback(to: quality.url, preferredPeakBitRate: 0)
            } else {
                player?.currentItem?.preferredPeakBitRate = 0
            }
            return
        }

        if quality.shouldReloadOnSelect {
            reloadPlayback(to: quality.url, preferredPeakBitRate: quality.preferredPeakBitRate)
            return
        }

        if isHls, let currentItem = self.player?.currentItem {
            currentItem.preferredPeakBitRate = resolvedBitrate(for: quality)
            return
        }

        reloadPlayback(to: quality.url, preferredPeakBitRate: quality.preferredPeakBitRate)
    }

    private func reloadPlayback(to sourceURL: URL, preferredPeakBitRate: Double?) {
        let currentTime = player?.currentTime() ?? .zero
        let wasPlaying = player?.timeControlStatus == .playing

        let asset: AVURLAsset
        if sourceURL.isFileURL {
            asset = AVURLAsset(url: sourceURL)
        } else {
            guard let proxyUrl = proxiedPlaybackURL(for: sourceURL) else { return }
            asset = AVURLAsset(url: proxyUrl)
        }

        let playerItem = AVPlayerItem(asset: asset)
        playerItem.preferredPeakBitRate = max(0, preferredPeakBitRate ?? 0)
        currentPlaybackSourceURL = sourceURL.absoluteURL

        itemObservation?.invalidate()
        itemObservation = nil
        if let playbackEndObserver {
            NotificationCenter.default.removeObserver(playbackEndObserver)
            self.playbackEndObserver = nil
        }

        self.player?.replaceCurrentItem(with: playerItem)
        self.player?.seek(to: currentTime)
        if wasPlaying {
            self.player?.play()
        }
        observePlaybackCompletion(for: playerItem)

        self.itemObservation = playerItem.observe(\.status) { _, _ in }
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
        case 1080...: return 8_000_000
        case 720..<1080: return 4_000_000
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

        return qualities
    }
    
    
    private func playVideo(url: URL, headers: [String: String], voices: [String] = [], subtitles: [PlaybackSubtitle] = []) {
        currentPlaybackSourceURL = url.absoluteURL

        let asset: AVURLAsset
        if url.absoluteString.contains("127.0.0.1") || url.absoluteString.contains("localhost") {
            HlsProxyServer.shared.start(headers: [:], voices: [], subtitles: [], mediaId: "local")
            asset = AVURLAsset(url: url)
        } else if url.isFileURL {
            asset = AVURLAsset(url: url)
        } else {
            guard let proxyUrl = proxiedPlaybackURL(for: url) else {
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
            asset = AVURLAsset(url: proxyUrl)
        }

        let playerItem = AVPlayerItem(asset: asset)
        itemObservation?.invalidate()
        itemObservation = nil
        statusObserver?.invalidate()
        statusObserver = nil
        bufferObserver?.invalidate()
        bufferObserver = nil
        rateObserver?.invalidate()
        rateObserver = nil
        if let playbackEndObserver {
            NotificationCenter.default.removeObserver(playbackEndObserver)
            self.playbackEndObserver = nil
        }

        if self.player == nil { self.player = AVPlayer() }
        self.player?.replaceCurrentItem(with: playerItem)
        self.player?.automaticallyWaitsToMinimizeStalling = true
        self.player?.rate = playbackRate

        // Наблюдаем состояние плеера
        statusObserver = playerItem.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if item.status == .failed {
                    self.error = item.error?.localizedDescription ?? "Ошибка воспроизведения"
                    self.isLoading = false
                }
            }
        }

        rateObserver = self.player?.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let status = player.timeControlStatus
                self.isPlaying = (status == .playing)
                self.isBuffering = (status == .waitingToPlayAtSpecifiedRate)
                self.updateNowPlaying()
            }
        }

        // Наблюдаем буфер
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

        self.isLoading = false
        self.startTrackingProgress()
        self.player?.play()
        self.isPlaying = true
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
            player.seek(to: CMTime(seconds: savedPosition, preferredTimescale: 600))
            currentTime = savedPosition
        }

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self, weak player] time in
            // Closure доставляется на .main очереди — безопасно вызывать main-actor-isolated свойства
            MainActor.assumeIsolated {
                guard let self, let player else { return }
                let t = time.seconds
                self.currentTime = t.isFinite && !t.isNaN ? t : 0
                let d = player.currentItem?.duration.seconds ?? 0
                if d.isFinite && !d.isNaN && d > 0 {
                    self.currentDuration = d
                }
                // Сохраняем прогресс каждые 5 секунд
                if Int(t) % 5 == 0 {
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
                self?.saveCurrentProgress()
            }
        }
    }

    // MARK: - Now Playing

    private func setupRemoteCommands() {
        let cc = MPRemoteCommandCenter.shared()
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
              let nextEpisode = nextEpisodeCandidate() else {
            return
        }

        isAdvancingToNextEpisode = true
        defer { isAdvancingToNextEpisode = false }

        currentSeason = nextEpisode.season
        currentEpisode = nextEpisode.episode
        _currentTranslationName = nextEpisode.translation.name
        targetVoiceover = nextEpisode.translation.name

        if let kpId = currentKpId {
            PlaybackProgressStore.shared.saveLastPlayed(kpId: kpId, season: nextEpisode.season, episode: nextEpisode.episode)
        }

        beginLoad(
            iframeUrl: nextEpisode.translation.iframeUrl,
            kpId: currentKpId,
            season: nextEpisode.season,
            episode: nextEpisode.episode,
            selectedVoiceover: nextEpisode.translation.name
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

        if let directUrl = targetDirectStreamUrl, !directUrl.isEmpty {
            // Pre-resolved URL stored at fetch time: use directly, no name matching needed.
            resolvedUrlString = directUrl
        } else {
            // Pick the URL for the selected voiceover from audioVariants by name.
            // Exact match first, then fuzzy.
            let voiceToMatch = targetVoiceover ?? _currentTranslationName
            if let voiceToMatch, !voiceToMatch.isEmpty {
                let exactMatch = audioVariants.first(where: { variant in
                    let title = variant["title"] as? String
                    return allohaTranslationNamesMatch(title, voiceToMatch, exactOnly: true)
                })
                let match = exactMatch ?? audioVariants.first(where: { variant in
                    let title = variant["title"] as? String
                    return allohaTranslationNamesMatch(title, voiceToMatch, exactOnly: false)
                })
                if let validMatch = match, let matchedUrl = validMatch["url"] as? String, !matchedUrl.isEmpty {
                    resolvedUrlString = matchedUrl.trimmingCharacters(in: .whitespacesAndNewlines)
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

        // Заполняем список доступных озвучек из audioVariants
        let voices = resolvedVoiceovers(from: resolved)
        if !voices.isEmpty {
            self.availableVoiceovers = voices
        }

        let qualityVariants = (resolved["qualityVariants"] as? [[String: Any]]) ?? []

        availableQualities = makeResolvedQualityOptions(
            resolvedUrl: resolvedUrl,
            qualityVariants: qualityVariants,
            audioVariants: audioVariants
        )
        currentQualityKey = "Авто"
        playVideo(url: resolvedUrl, headers: headers, voices: [], subtitles: resolvedSubtitles)
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
