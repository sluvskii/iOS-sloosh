import Foundation
import AVFoundation

/// Manages asset loading for AVPlayer
final class CollapsAVAssetLoader {
    
    // MARK: - Dependencies
    private weak var player: AVPlayer?
    private weak var playlistManager: CollapsAVPlaylistManager?
    private weak var audioManager: CollapsAVAudioManager?
    private weak var allohaManager: CollapsAVAllohaManager?
    private weak var progressManager: CollapsAVProgressManager?
    
    // MARK: - State
    private var currentBridge: CollapsAVAssetBridge?
    private var playbackProxy: AllohaHLSProxyServer?
    private var kpId: Int?
    private var pendingSeekSeconds: Double?
    private var itemStatusObservation: NSKeyValueObservation?
    
    // MARK: - Callbacks
    var onProxyFailure: ((CollapsAVPlaylistItem) -> Void)?
    var onAssetLoaded: (() -> Void)?
    
    // MARK: - Initialization
    init(
        player: AVPlayer,
        playlistManager: CollapsAVPlaylistManager,
        audioManager: CollapsAVAudioManager,
        allohaManager: CollapsAVAllohaManager,
        progressManager: CollapsAVProgressManager
    ) {
        self.player = player
        self.playlistManager = playlistManager
        self.audioManager = audioManager
        self.allohaManager = allohaManager
        self.progressManager = progressManager
    }
    
    // MARK: - Public API
    
    func setKinopoiskId(_ id: Int) {
        kpId = id
    }
    
    @MainActor
    func loadCurrentItem(
        autoplay: Bool,
        overrideStartSec: Double?,
        overrideUrlString: String? = nil
    ) async throws {
        guard let itemMeta = playlistManager?.currentItem else {
            throw NSError(domain: "NeomoviesCore", code: 1003, userInfo: [NSLocalizedDescriptionKey: "No current episode"])
        }
        
        let resolvedItem = try await allohaManager?.resolveAllohaItemIfNeeded(itemMeta) ?? itemMeta
        if let idx = playlistManager?.currentIndex {
            playlistManager?.updateItem(at: idx, with: resolvedItem)
        }
        let selectedVariantIndex = audioManager?.selectedAudioVariantIndexByMediaId[resolvedItem.mediaId] ?? 0
        let resolvedUrlString = resolveURL(for: resolvedItem, selectedVariantIndex: selectedVariantIndex, overrideUrlString: overrideUrlString)

        guard let url = URL(string: resolvedUrlString) else {
            throw URLError(.badURL)
        }

        cancelPendingSeek()
        stopProxy()

        let playerItem = try createPlayerItem(url: url, itemMeta: resolvedItem)
        player?.replaceCurrentItem(with: playerItem)
        player?.automaticallyWaitsToMinimizeStalling = true
        player?.isMuted = false

        restorePlaybackPosition(itemMeta: resolvedItem, overrideStartSec: overrideStartSec)

        if autoplay {
            player?.play()
        }

        if let kpId = kpId {
            CollapsPlaybackProgressStore.shared.saveLastPlayed(kpId: kpId, season: resolvedItem.season, episode: resolvedItem.episode)
        }

        onAssetLoaded?()
    }

    @MainActor
    func loadCurrentItemAsync(
        autoplay: Bool,
        overrideStartSec: Double?,
        overrideUrlString: String? = nil,
        expectedLoadToken: UUID? = nil
    ) async throws {
        guard let itemMeta = playlistManager?.currentItem else {
            throw NSError(domain: "NeomoviesCore", code: 1003, userInfo: [NSLocalizedDescriptionKey: "No current episode"])
        }
        
        let currentIdx = playlistManager?.currentIndex ?? 0
        let resolvedItem = try await allohaManager?.resolveAllohaItemIfNeeded(itemMeta) ?? itemMeta

        if let expectedLoadToken,
           !(playlistManager?.isLoadTokenValid(expectedLoadToken) ?? false) {
            throw CancellationError()
        }

        playlistManager?.updateItem(at: currentIdx, with: resolvedItem)
        
        let selectedVariantIndex = audioManager?.selectedAudioVariantIndexByMediaId[resolvedItem.mediaId] ?? 0
        let resolvedUrlString = resolveURL(for: resolvedItem, selectedVariantIndex: selectedVariantIndex, overrideUrlString: overrideUrlString)

        guard let url = URL(string: resolvedUrlString) else {
            throw URLError(.badURL)
        }

        cancelPendingSeek()
        stopProxy()

        let playerItem = try createPlayerItem(url: url, itemMeta: resolvedItem)
        player?.replaceCurrentItem(with: playerItem)
        player?.automaticallyWaitsToMinimizeStalling = true
        player?.isMuted = false

        restorePlaybackPosition(itemMeta: resolvedItem, overrideStartSec: overrideStartSec)
        
        if autoplay {
            player?.play()
        }

        if let kpId = kpId {
            CollapsPlaybackProgressStore.shared.saveLastPlayed(kpId: kpId, season: resolvedItem.season, episode: resolvedItem.episode)
        }
        
        onAssetLoaded?()
    }
    
    func cancelPendingSeek() {
        itemStatusObservation = nil
        pendingSeekSeconds = nil
    }

    func stopProxy() {
        playbackProxy?.stop()
        playbackProxy = nil
    }

    func cleanup() {
        cancelPendingSeek()
        stopProxy()
        currentBridge = nil
    }
    
    // MARK: - Private Helper Methods

    private func resolveURL(for item: CollapsAVPlaylistItem, selectedVariantIndex: Int, overrideUrlString: String?) -> String {
        if let override = overrideUrlString, !override.isEmpty {
            return override
        }
        if !item.audioVariants.isEmpty, item.audioVariants.indices.contains(selectedVariantIndex) {
            let variant = item.audioVariants[selectedVariantIndex]
            // If this variant only has AV1/1440p+ quality options, fall back to base URL
            let hasPlayableQuality = variant.qualityVariants.isEmpty || variant.qualityVariants.contains { option in
                let label = option.label.lowercased()
                let height = option.height ?? 0
                return !label.contains("av1") && !label.contains("av01") && height <= 1080
            }
            if hasPlayableQuality {
                return variant.url
            }
            return item.url
        }
        return item.url
    }

    private func createPlayerItem(url: URL, itemMeta: CollapsAVPlaylistItem) throws -> AVPlayerItem {
        let playerItem: AVPlayerItem
        
        if CollapsAVHelper.shouldUseProxy(url: url, headers: itemMeta.headers) {
            do {
                let proxy = AllohaHLSProxyServer(
                    masterURL: url,
                    headers: itemMeta.headers,
                    routeBase: CollapsAVHelper.localProxyRouteBase(for: itemMeta)
                )
                if allohaManager?.isAllohaPlaylistItem(itemMeta) == true {
                    proxy.onRecoverableUpstreamFailure = { [weak self] in
                        self?.onProxyFailure?(itemMeta)
                    }
                }
                let localURL = try proxy.start()
                playbackProxy = proxy
                allohaManager?.startAllohaSessionRefreshIfNeeded(itemMeta: itemMeta)
                currentBridge = nil
                playerItem = AVPlayerItem(url: localURL)
            } catch {
                currentBridge = CollapsAVAssetBridge(sourceURL: url, headers: itemMeta.headers, rewrittenMaster: nil)
                playerItem = AVPlayerItem(asset: currentBridge!.asset)
            }
        } else {
            currentBridge = CollapsAVAssetBridge(sourceURL: url, headers: itemMeta.headers, rewrittenMaster: nil)
            playerItem = AVPlayerItem(asset: currentBridge!.asset)
        }
        
        return playerItem
    }
    
    private func restorePlaybackPosition(itemMeta: CollapsAVPlaylistItem, overrideStartSec: Double?) {
        let progressKey = progressManager?.progressKey(kpId: kpId, episode: itemMeta.episode, season: itemMeta.season) ?? ""
        let legacyKey = progressManager?.progressKey(kpId: kpId, episode: itemMeta.episode) ?? ""
        let isWatched = CollapsPlaybackProgressStore.shared.loadWatched(mediaId: itemMeta.mediaId)
        let startAt: Double
        if isWatched {
            startAt = 0
        } else if let override = overrideStartSec {
            startAt = override
        } else {
            let saved = CollapsPlaybackProgressStore.shared.load(mediaId: progressKey)
            let legacySaved = saved > 0 ? saved : CollapsPlaybackProgressStore.shared.load(mediaId: legacyKey)
            // For movies (no episode), progressKey is empty — fall back to mediaId directly
            startAt = legacySaved > 0 ? legacySaved : (progressKey.isEmpty ? CollapsPlaybackProgressStore.shared.load(mediaId: itemMeta.mediaId) : 0)
        }
        guard startAt > 0, let item = player?.currentItem else { return }
        if item.status == .readyToPlay {
            seekPlayer(to: startAt)
        } else {
            pendingSeekSeconds = startAt
            itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] observedItem, _ in
                guard let self, observedItem.status == .readyToPlay else { return }
                self.itemStatusObservation = nil
                if let sec = self.pendingSeekSeconds {
                    self.pendingSeekSeconds = nil
                    self.seekPlayer(to: sec)
                }
            }
        }
    }

    private func seekPlayer(to seconds: Double) {
        player?.seek(
            to: CMTime(seconds: seconds, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }
}
