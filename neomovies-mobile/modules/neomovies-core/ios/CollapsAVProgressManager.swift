import Foundation
import AVFoundation

/// Manages playback progress for AVPlayer
final class CollapsAVProgressManager {
    
    // MARK: - Dependencies
    
    private weak var player: AVPlayer?
    
    // MARK: - State
    
    private var timeObserver: Any?
    
    // MARK: - Initialization
    
    init(player: AVPlayer) {
        self.player = player
    }
    
    // MARK: - Public API
    
    /// Installs the progress observer
    func installProgressObserver(onProgress: @escaping (Double, Double) -> Void) {
        if let timeObserver {
            player?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }

        let interval = CMTime(seconds: 1, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            guard let self else { return }
            let seconds = self.player?.currentTime().seconds ?? 0
            let duration = self.player?.currentItem?.duration.seconds ?? 0
            onProgress(seconds, duration)
        }
    }
    
    /// Removes the progress observer
    func removeProgressObserver() {
        if let timeObserver {
            player?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
    }
    
    /// Persists the current playback progress
    func persistCurrentProgress(mediaId: String, scopedMediaId: String? = nil) {
        guard !mediaId.isEmpty else { return }

        let seconds = player?.currentTime().seconds ?? 0
        guard seconds.isFinite, seconds >= 0 else { return }
        let rawDur = player?.currentItem?.duration.seconds
        let dur: Double? = (rawDur?.isFinite == true && (rawDur ?? 0) > 0) ? rawDur : nil
        
        CollapsPlaybackProgressStore.shared.save(mediaId: mediaId, positionSec: seconds, durationSec: dur)
        if let scopedMediaId = scopedMediaId {
            CollapsPlaybackProgressStore.shared.save(mediaId: scopedMediaId, positionSec: seconds, durationSec: dur)
        }
    }
    
    /// Calculates normalized relative progress
    func normalizedRelativeProgress(currentTime: Double, duration: Double) -> Double? {
        guard currentTime.isFinite, duration.isFinite, duration > 0 else { return nil }
        let progress = currentTime / duration
        guard progress.isFinite else { return nil }
        return max(0, min(progress, 0.999))
    }
    
    /// Generates a scoped playback media ID
    func scopedPlaybackMediaId(baseMediaId: String, urlString: String) -> String {
        var hash: UInt64 = 5381
        for scalar in urlString.unicodeScalars {
            hash = ((hash << 5) &+ hash) &+ UInt64(scalar.value)
        }
        return "\(baseMediaId)__src_\(String(hash, radix: 16))"
    }
    
    /// Generates a progress key for Alloha items (season-scoped for series)
    func progressKey(kpId: Int?, episode: Int?, season: Int? = nil) -> String {
        if let kpId, let episode {
            if let season {
                return "pos_alloha_\(kpId)_s\(season)_ep\(episode)"
            }
            return "pos_alloha_\(kpId)_ep\(episode)"
        }
        return ""
    }
}
