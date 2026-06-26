import AVFoundation
import AVKit
import Foundation
import UIKit

extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

public final class CollapsAVPlayerController: NSObject {
    public static let shared = CollapsAVPlayerController()

    public var onStateChanged: ((CollapsAVPlayerState) -> Void)?
    public var onProgress: ((CollapsAVPlayerState) -> Void)?
    public var onEpisodeChanged: ((CollapsAVPlayerState) -> Void)?
    public var onPlayerDismissed: (() -> Void)?

    private let player = AVPlayer()
    private var playerVC: CollapsNativePlayerViewController?
    private var kpId: Int?
    
    // Managers
    private let orientationManager = CollapsAVOrientationManager()
    private lazy var progressManager = CollapsAVProgressManager(player: player)
    private lazy var qualityManager = CollapsAVQualityManager(player: player)
    private lazy var audioManager = CollapsAVAudioManager(player: player)
    private let playlistManager = CollapsAVPlaylistManager()
    private lazy var allohaManager = CollapsAVAllohaManager()
    private lazy var uiManager = CollapsAVUIManager(playerVC: nil, player: player)
    
    // Helper classes
    private lazy var assetLoader = CollapsAVAssetLoader(
        player: player,
        playlistManager: playlistManager,
        audioManager: audioManager,
        allohaManager: allohaManager,
        progressManager: progressManager
    )
    private lazy var playerPresenter = CollapsAVPlayerPresenter(
        player: player,
        orientationManager: orientationManager,
        uiManager: uiManager
    )

    public func setKinopoiskId(_ id: Int) {
        kpId = id
        assetLoader.setKinopoiskId(id)
    }

    private override init() {
        super.init()
        configureAudioSession()
        observeItemEnd()
        observeAppLifecycle()
        setupHelperCallbacks()
    }
    
    private func setupHelperCallbacks() {
        assetLoader.onProxyFailure = { [weak self] itemMeta in
            self?.scheduleImmediateAllohaRecovery(for: itemMeta)
        }
        assetLoader.onAssetLoaded = { [weak self] in
            self?.progressManager.installProgressObserver { [weak self] currentTime, duration in
                guard let self else { return }
                let state = self.snapshot()
                if let mediaId = state.mediaId {
                    let scopedMediaId = self.currentScopedPlaybackMediaId()
                    self.progressManager.persistCurrentProgress(mediaId: mediaId, scopedMediaId: scopedMediaId)
                    if let kpId = self.kpId, let currentItem = self.playlistManager.currentItem {
                        print("[AVPlayer] Saving progress: kpId=\(kpId), season=\(currentItem.season ?? 0), episode=\(currentItem.episode ?? 0), position=\(currentTime)s, duration=\(duration)s")
                    }
                }
                self.onProgress?(state)
                self.refreshOverlayUI()
            }
            Task {
                _ = await self?.refreshQualityOptions()
            }
            self?.emitState()
        }
        
        playerPresenter.onCloseTapped = { [weak self] in
            self?.onPlayerDismissed?()
        }
        playerPresenter.onPlayPauseTapped = { [weak self] in
            guard let self else { return }
            _ = self.player.rate > 0 ? self.pause() : self.play()
        }
        playerPresenter.onSeekTapped = { [weak self] seconds in
            _ = self?.seek(to: seconds)
        }
        playerPresenter.onQualityTapped = { [weak self] sourceView in
            guard let self, let controller = self.topViewController() else { return }
            Task { @MainActor in
                self.showQualitySheet(from: controller, sourceView: sourceView)
            }
        }
        playerPresenter.onAudioTapped = { [weak self] sourceView in
            guard let self, let controller = self.topViewController() else { return }
            Task { @MainActor in
                self.showAudioSheet(from: controller, sourceView: sourceView)
            }
        }
    }
    
    private func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.soloAmbient, mode: .default)
            try audioSession.setActive(true)
        } catch {
            print("[AVPlayer] Failed to configure audio session: \(error)")
        }
    }

    deinit {
        allohaManager.cancelAllohaTasks()
        assetLoader.cleanup()
        progressManager.removeProgressObserver()
        NotificationCenter.default.removeObserver(self)
    }

    public func configurePlaylist(items: [CollapsAVPlaylistItem], startIndex: Int, autoplay: Bool) async throws -> CollapsAVPlayerState {
        try playlistManager.configurePlaylist(items: items, startIndex: startIndex)
        qualityManager.resetQualitySelection()
        try await loadCurrentItem(autoplay: autoplay, overrideStartSec: nil)
        let state = snapshot()
        onEpisodeChanged?(state)
        return state
    }

    @MainActor
    public func presentNativePlayer() {
        if playerVC == nil {
            let vc = CollapsNativePlayerViewController()
            vc.player = player
            vc.showsPlaybackControls = false
            vc.allowsPictureInPicturePlayback = true
            vc.canStartPictureInPictureAutomaticallyFromInline = true
            vc.entersFullScreenWhenPlaybackBegins = true
            vc.exitsFullScreenWhenPlaybackEnds = false
            vc.onCloseTapped = { [weak self] in
                Task { @MainActor in
                    self?.dismissNativePlayer()
                }
            }
            vc.onPlayPauseTapped = { [weak self] in
                guard let self else { return }
                if self.player.rate > 0 {
                    _ = self.pause()
                } else {
                    _ = self.play()
                }
            }
            vc.onSeekRelative = { [weak self] delta in
                guard let self else { return }
                let now = self.player.currentTime().seconds
                let target = max(0, now + delta)
                _ = self.seek(to: target)
            }
            vc.onSliderSeek = { [weak self] value in
                guard let self else { return }
                _ = self.seek(to: value)
            }
            vc.onAudioTapped = { [weak self, weak vc] source in
                guard let self, let vc else { return }
                self.showAudioSheet(from: vc, sourceView: source)
            }
            vc.onQualityTapped = { [weak self, weak vc] source in
                guard let self, let vc else { return }
                self.showQualitySheet(from: vc, sourceView: source)
            }
            vc.onPreviousEpisodeTapped = { [weak self] in
                guard let self, self.playlistManager.currentIndex > 0 else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    do {
                        _ = try await self.previousEpisodeAsync(autoplay: true)
                    } catch {}
                }
            }
            vc.onNextEpisodeTapped = { [weak self] in
                guard let self, self.playlistManager.currentIndex < self.playlistManager.playlist.count - 1 else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    do {
                        _ = try await self.nextEpisodeAsync(autoplay: true)
                    } catch {}
                }
            }
            vc.onWillDisappearCallback = { [weak self] in
                self?.persistCurrentProgress()
            }
            playerVC = vc
            uiManager.updatePlayerVC(vc)
        }

        guard let presenter = topViewController(), let playerVC else { return }
        if presenter.presentedViewController === playerVC { return }
        presenter.present(playerVC, animated: true)
        refreshOverlayUI()
    }

    @MainActor
    public func dismissNativePlayer() {
        persistCurrentProgress()
        guard let vc = playerVC, vc.presentingViewController != nil else {
            // VC already dismissed (e.g. swipe-to-dismiss just completed) — fire immediately
            onPlayerDismissed?()
            return
        }
        vc.dismiss(animated: true) { [weak self] in
            self?.onPlayerDismissed?()
        }
    }

    public func play() -> CollapsAVPlayerState {
        player.play()
        let state = snapshot()
        onStateChanged?(state)
        refreshOverlayUI()
        return state
    }

    public func pause() -> CollapsAVPlayerState {
        player.pause()
        persistCurrentProgress()
        let state = snapshot()
        onStateChanged?(state)
        refreshOverlayUI()
        return state
    }

    public func stop() {
        persistCurrentProgress()
        player.pause()
        player.replaceCurrentItem(with: nil)
        assetLoader.cleanup()
        allohaManager.cancelAllohaTasks()
        emitState()
    }

    public func seek(to seconds: Double) -> CollapsAVPlayerState {
        assetLoader.cancelPendingSeek()
        player.seek(to: CMTime(seconds: max(0, seconds), preferredTimescale: 600))
        let state = snapshot()
        onStateChanged?(state)
        refreshOverlayUI()
        return state
    }

    public func setRate(_ rate: Float) -> CollapsAVPlayerState {
        player.rate = max(0.25, min(rate, 3.0))
        let state = snapshot()
        onStateChanged?(state)
        refreshOverlayUI()
        return state
    }

    public func setPreferredPeakBitRate(_ bitrate: Double) {
        player.currentItem?.preferredPeakBitRate = max(0, bitrate)
        refreshOverlayUI()
    }

    public func listQualityOptions() -> [[String: Any]] {
        return qualityManager.listQualityOptions()
    }

    public func selectQuality(index: Int?) {
        qualityManager.selectQuality(index: index)
        let option = index.flatMap { i in qualityManager.currentQualityOptions.first(where: { $0.index == i }) }
        let liveTime = player.currentTime().seconds
        let isPlaying = player.rate > 0
        // Fallback: if first load failed, currentTime() is 0 — use saved progress so we don't restart from 0
        let resumeAt: Double? = {
            if liveTime.isFinite, liveTime > 0.5 { return liveTime }
            return savedProgressForCurrentItem()
        }()
        if let option, !option.isAuto, let forcedUrl = option.url, !forcedUrl.isEmpty {
            // Explicit quality URL — reload with it
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    try await self.loadCurrentItem(
                        autoplay: isPlaying,
                        overrideStartSec: resumeAt,
                        overrideUrlString: forcedUrl
                    )
                } catch {}
            }
        } else if option?.isAuto == true {
            // Auto — reload with master URL so AVPlayer uses real ABR
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    try await self.loadCurrentItem(
                        autoplay: isPlaying,
                        overrideStartSec: resumeAt
                    )
                } catch {}
            }
        } else {
            emitState()
        }
    }

    /// Returns the most recent saved playback position for the current item, or nil.
    /// Used as a fallback when player.currentTime() is unavailable (e.g. first load failed).
    private func savedProgressForCurrentItem() -> Double? {
        guard let item = playlistManager.currentItem else { return nil }
        let store = CollapsPlaybackProgressStore.shared
        let progressKey = progressManager.progressKey(kpId: kpId, episode: item.episode, season: item.season)
        let legacyKey = progressManager.progressKey(kpId: kpId, episode: item.episode)
        let candidates: [Double] = [
            store.load(mediaId: progressKey),
            store.load(mediaId: legacyKey),
            store.load(mediaId: item.mediaId),
        ]
        let best = candidates.first(where: { $0 > 0.5 })
        return best
    }

    public func refreshQualityOptions() async -> [[String: Any]] {
        guard let current = playlistManager.currentItem else {
            qualityManager.setQualityOptions([CollapsAVQualityOption(index: 0, bitrate: 0, height: nil, label: "Auto", isAuto: true, url: nil)])
            return qualityManager.listQualityOptions()
        }
        let selectedVariantIndex = audioManager.selectedAudioVariantIndexByMediaId[current.mediaId] ?? 0
        // Use runtime quality variants when available (Alloha iframe items or items with explicit qualityVariants)
        let hasExplicitQuality = !current.qualityVariants.isEmpty
            || (!current.audioVariants.isEmpty
                && current.audioVariants.indices.contains(selectedVariantIndex)
                && !current.audioVariants[selectedVariantIndex].qualityVariants.isEmpty)
        if allohaManager.isAllohaPlaylistItem(current) || hasExplicitQuality {
            let options = makeAllohaQualityOptions(for: current)
            qualityManager.setQualityOptions(options)
            refreshOverlayUI()
            return qualityManager.listQualityOptions()
        }
        let activeUrlString: String
        if !current.audioVariants.isEmpty,
           current.audioVariants.indices.contains(selectedVariantIndex) {
            activeUrlString = current.audioVariants[selectedVariantIndex].url
        } else {
            activeUrlString = current.url
        }
        return await qualityManager.refreshQualityOptions(urlString: activeUrlString, headers: current.headers)
    }

    public func selectEpisode(index: Int, autoplay: Bool) async throws -> CollapsAVPlayerState {
        let previousIndex = playlistManager.currentIndex
        let previousItem = playlistManager.currentItem
        try playlistManager.selectEpisode(index: index)
        persistProgress(for: previousItem)
        do {
            try await loadCurrentItem(autoplay: autoplay, overrideStartSec: nil)
        } catch {
            playlistManager.revertSelection(to: previousIndex)
            throw error
        }
        let state = snapshot()
        onEpisodeChanged?(state)
        return state
    }

    public func nextEpisode(autoplay: Bool) async throws -> CollapsAVPlayerState {
        return try await selectEpisode(index: playlistManager.currentIndex + 1, autoplay: autoplay)
    }

    public func previousEpisode(autoplay: Bool) async throws -> CollapsAVPlayerState {
        return try await selectEpisode(index: playlistManager.currentIndex - 1, autoplay: autoplay)
    }

    @MainActor
    public func selectEpisodeAsync(index: Int, autoplay: Bool) async throws -> CollapsAVPlayerState {
        let previousIndex = playlistManager.currentIndex
        let previousItem = playlistManager.currentItem
        try playlistManager.selectEpisodeAsync(index: index)
        let loadToken = playlistManager.episodeLoadToken
        persistProgress(for: previousItem)
        do {
            try await loadCurrentItemAsync(autoplay: autoplay, overrideStartSec: nil, expectedLoadToken: loadToken)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            playlistManager.revertSelection(to: previousIndex)
            throw error
        }
        guard playlistManager.isLoadTokenValid(loadToken) else {
            return snapshot()
        }
        let state = snapshot()
        onEpisodeChanged?(state)
        return state
    }

    @MainActor
    public func nextEpisodeAsync(autoplay: Bool) async throws -> CollapsAVPlayerState {
        return try await selectEpisodeAsync(index: playlistManager.currentIndex + 1, autoplay: autoplay)
    }

    @MainActor
    public func previousEpisodeAsync(autoplay: Bool) async throws -> CollapsAVPlayerState {
        return try await selectEpisodeAsync(index: playlistManager.currentIndex - 1, autoplay: autoplay)
    }

    public func snapshot() -> CollapsAVPlayerState {
        let item = player.currentItem
        let duration = item?.duration.seconds
        let current = item != nil ? player.currentTime().seconds : 0
        let currentMeta = playlistManager.currentItem

        return CollapsAVPlayerState(
            isLoaded: item != nil,
            isPlaying: player.rate > 0,
            rate: player.rate,
            currentTimeSec: current.isFinite ? max(0, current) : 0,
            durationSec: (duration?.isFinite == true) ? max(0, duration ?? 0) : 0,
            currentIndex: playlistManager.currentIndex,
            totalItems: playlistManager.playlist.count,
            season: currentMeta?.season,
            episode: currentMeta?.episode,
            mediaId: currentMeta?.mediaId
        )
    }

    public func listAudioTracks() -> [[String: Any]] {
        audioManager.updatePlaylist(playlistManager.playlist, currentIndex: playlistManager.currentIndex)
        return audioManager.listAudioTracks(normalizedOverlayLabel: normalizedOverlayLabel)
    }

    public func selectAudioTrack(index: Int?) {
        audioManager.updatePlaylist(playlistManager.playlist, currentIndex: playlistManager.currentIndex)
        let result = audioManager.selectAudioTrack(index: index, emitState: emitState)
        if let episodeIndex = result {
            // Voiceover playlist: switch to a different playlist item (dub as separate episode)
            Task { @MainActor [weak self] in
                guard let self else { return }
                do { _ = try await self.selectEpisodeAsync(index: episodeIndex, autoplay: true) } catch {}
            }
        } else if let current = playlistManager.currentItem, !current.audioVariants.isEmpty {
            // Audio variant switch: reload current item with new variant URL, resuming at current time
            let liveTime = player.currentTime().seconds
            let resumeAt: Double? = {
                if liveTime.isFinite, liveTime > 0.5 { return liveTime }
                return savedProgressForCurrentItem()
            }()
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    try await self.loadCurrentItem(
                        autoplay: self.player.rate > 0,
                        overrideStartSec: resumeAt
                    )
                    _ = await self.refreshQualityOptions()
                } catch {}
            }
        }
    }

    public func listSubtitleTracks() -> [[String: Any]] {
        return audioManager.listSubtitleTracks()
    }

    public func selectSubtitleTrack(index: Int?) {
        audioManager.selectSubtitleTrack(index: index, emitState: emitState)
    }

    @MainActor
    private func loadCurrentItem(autoplay: Bool, overrideStartSec: Double?, overrideUrlString: String? = nil) async throws {
        try await assetLoader.loadCurrentItem(autoplay: autoplay, overrideStartSec: overrideStartSec, overrideUrlString: overrideUrlString)
    }

    @MainActor
    private func loadCurrentItemAsync(
        autoplay: Bool,
        overrideStartSec: Double?,
        overrideUrlString: String? = nil,
        expectedLoadToken: UUID? = nil
    ) async throws {
        try await assetLoader.loadCurrentItemAsync(
            autoplay: autoplay,
            overrideStartSec: overrideStartSec,
            overrideUrlString: overrideUrlString,
            expectedLoadToken: expectedLoadToken
        )
    }

    private func resolveAllohaItemIfNeeded(_ item: CollapsAVPlaylistItem, index: Int) async throws -> CollapsAVPlaylistItem {
        let resolved = try await allohaManager.resolveAllohaItemIfNeeded(item)
        return resolved
    }

    @MainActor
    private func resolveAllohaItemIfNeededAsync(_ item: CollapsAVPlaylistItem, index: Int) async throws -> CollapsAVPlaylistItem {
        let resolved = try await allohaManager.resolveAllohaItemIfNeeded(item)
        return resolved
    }

    private func awaitResolveAllohaStream(iframeUrl: String) throws -> [String: Any] {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<[String: Any], Error> = .failure(URLError(.cannotLoadFromNetwork))
        Task {
            do {
                let resolved = try await MainActor.run { AllohaRuntimeResolver() }.resolve(iframeUrl: iframeUrl)
                result = .success(resolved)
            } catch {
                result = .failure(error)
            }
            semaphore.signal()
        }
        semaphore.wait()
        return try result.get()
    }

    private func startAllohaSessionRefreshIfNeeded(itemMeta: CollapsAVPlaylistItem) {
        allohaManager.startAllohaSessionRefreshIfNeeded(itemMeta: itemMeta)
    }

    private func scheduleImmediateAllohaRecovery(for itemMeta: CollapsAVPlaylistItem) {
        allohaManager.scheduleImmediateAllohaRecovery(for: itemMeta) { [weak self] in
            Task { @MainActor in
                await self?.recoverPlaybackAfterAllohaRecovery()
            }
        }
    }

    private func refreshAllohaProxySession(proxy: AllohaHLSProxyServer, iframeUrl: String) async throws {
        try await allohaManager.refreshAllohaProxySession(proxy: proxy, iframeUrl: iframeUrl)
    }

    @MainActor
    private func recoverPlaybackAfterAllohaRecovery() async {
        guard let item = playlistManager.currentItem else { return }
        let wasPlaying = player.rate > 0
        let currentState = snapshot()
        let liveResume = currentState.currentTimeSec.isFinite ? max(0, currentState.currentTimeSec) : 0
        // If first load failed, currentTimeSec is 0 — fall back to saved progress
        let resumeAt: Double? = liveResume > 0.5 ? liveResume : savedProgressForCurrentItem()

        if qualityManager.selectedQualityIndex != 0 {
            qualityManager.resetQualitySelection()
            playlistManager.resetQualityRecoveryCursor(for: item.mediaId)
            player.currentItem?.preferredPeakBitRate = 0
            do {
                try await loadCurrentItem(
                    autoplay: wasPlaying,
                    overrideStartSec: resumeAt,
                    overrideUrlString: nil
                )
                return
            } catch {
                // Fall through to lower-quality ladder below if reload on Auto fails.
            }
        }

        let candidates = CollapsAVHelper.qualityRecoveryCandidates(from: qualityManager.currentQualityOptions)
        let cursor = playlistManager.qualityRecoveryCursor(for: item.mediaId)
        if candidates.indices.contains(cursor),
           let option = qualityManager.currentQualityOptions.first(where: { $0.index == candidates[cursor] }),
           let forcedUrl = option.url,
           !forcedUrl.isEmpty {
            qualityManager.selectQuality(index: option.index)
            do {
                try await loadCurrentItem(
                    autoplay: wasPlaying,
                    overrideStartSec: resumeAt,
                    overrideUrlString: forcedUrl
                )
                return
            } catch {
                // Fall through to seek-nudge if no fallback quality worked.
            }
        }

        let currentSeconds = player.currentTime().seconds
        let safeCurrent = currentSeconds.isFinite ? max(0, currentSeconds) : 0
        let target = max(0, safeCurrent - 0.15)

        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [player, wasPlaying] _ in
            if wasPlaying {
                player.play()
            }
        }
    }

    private func isAllohaPlaylistItem(_ item: CollapsAVPlaylistItem) -> Bool {
        return allohaManager.isAllohaPlaylistItem(item)
    }

    private func makeAllohaQualityOptions(for item: CollapsAVPlaylistItem) -> [CollapsAVQualityOption] {
        let selectedVariantIndex = audioManager.selectedAudioVariantIndexByMediaId[item.mediaId] ?? 0
        return qualityManager.makeAllohaQualityOptions(for: item, selectedAudioVariantIndex: selectedVariantIndex)
    }

    private func observeItemEnd() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleItemEnd),
            name: .AVPlayerItemDidPlayToEndTime,
            object: nil
        )
    }

    private func observeAppLifecycle() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }

    @objc private func handleAppWillResignActive() {
        persistCurrentProgress()
    }

    @objc private func handleAppDidEnterBackground() {
        persistCurrentProgress()
    }

    @objc private func handleItemEnd(notification: Notification) {
        guard let item = notification.object as? AVPlayerItem,
              item === player.currentItem else { return }

        persistCurrentProgress()
        
        if let currentItem = playlistManager.currentItem {
            CollapsPlaybackProgressStore.shared.markAsWatched(mediaId: currentItem.mediaId)
        }

        if playlistManager.hasNextEpisode {
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    _ = try await self.selectEpisodeAsync(index: self.playlistManager.currentIndex + 1, autoplay: true)
                } catch {
                    self.emitState()
                }
            }
            return
        }

        emitState()
    }

    private func emitState() {
        onStateChanged?(snapshot())
        refreshOverlayUI()
    }

    private func persistCurrentProgress() {
        persistProgress(for: playlistManager.currentItem)
    }

    private func persistProgress(for item: CollapsAVPlaylistItem?) {
        guard let item = item else { return }
        let mediaId = item.mediaId
        guard !mediaId.isEmpty else { return }

        let seconds = player.currentTime().seconds
        guard seconds.isFinite, seconds >= 0 else { return }
        let rawDur = player.currentItem?.duration.seconds
        let _: Double? = (rawDur?.isFinite == true && (rawDur ?? 0) > 0) ? rawDur : nil

        let progressKey = progressManager.progressKey(kpId: kpId, episode: item.episode, season: item.season)
        if !progressKey.isEmpty {
            progressManager.persistCurrentProgress(mediaId: progressKey, scopedMediaId: nil)
        }

        progressManager.persistCurrentProgress(mediaId: mediaId, scopedMediaId: nil)
    }

    private func normalizedRelativeProgress(currentTime: Double, duration: Double) -> Double? {
        return progressManager.normalizedRelativeProgress(currentTime: currentTime, duration: duration)
    }

    private func currentScopedPlaybackMediaId() -> String? {
        guard let item = playlistManager.currentItem else { return nil }
        let selectedVariantIndex = audioManager.selectedAudioVariantIndexByMediaId[item.mediaId] ?? 0
        let urlString: String
        if !item.audioVariants.isEmpty, item.audioVariants.indices.contains(selectedVariantIndex) {
            urlString = item.audioVariants[selectedVariantIndex].url
        } else {
            urlString = item.url
        }
        return progressManager.scopedPlaybackMediaId(baseMediaId: item.mediaId, urlString: urlString)
    }

    private func scopedPlaybackMediaId(baseMediaId: String, urlString: String) -> String {
        return progressManager.scopedPlaybackMediaId(baseMediaId: baseMediaId, urlString: urlString)
    }

    @MainActor
    private func showQualitySheet(from controller: UIViewController, sourceView: UIView) {
        uiManager.updatePlayerVC(playerVC)
        uiManager.updatePlaylist(playlistManager.playlist, currentIndex: playlistManager.currentIndex)
        uiManager.updateQualityOptions(qualityManager.currentQualityOptions)
        uiManager.updateSelectedQualityIndex(qualityManager.selectedQualityIndex)
        uiManager.showQualitySheet(from: controller, sourceView: sourceView, onSelectQuality: { [weak self] index in
            self?.selectQuality(index: index)
        })
    }

    @MainActor
    private func showAudioSheet(from controller: UIViewController, sourceView: UIView) {
        let tracks = listAudioTracks()
        uiManager.showAudioSheet(from: controller, sourceView: sourceView, tracks: tracks, onSelectAudio: { [weak self] index in
            self?.selectAudioTrack(index: index)
        })
    }


    private func topViewController(base: UIViewController? = nil) -> UIViewController? {
        CollapsAVHelper.topViewController(base: base)
    }

    private func refreshOverlayUI() {
        uiManager.updatePlayerVC(playerVC)
        let state = snapshot()
        uiManager.refreshOverlayUI(
            currentTime: state.currentTimeSec,
            duration: state.durationSec,
            isPlaying: state.isPlaying,
            playlist: playlistManager.playlist,
            currentIndex: playlistManager.currentIndex,
            qualityOptions: qualityManager.currentQualityOptions,
            selectedQualityIndex: qualityManager.selectedQualityIndex,
            selectedAudioVariantIndexByMediaId: audioManager.selectedAudioVariantIndexByMediaId,
            currentItemMediaId: playlistManager.currentItem?.mediaId ?? ""
        )
    }



    private func normalizedOverlayLabel(_ value: String, fallback: String = "") -> String {
        CollapsAVHelper.normalizedOverlayLabel(value, fallback: fallback)
    }
}
