import Foundation
import UIKit
import AVFoundation

/// Manages UI-related functionality for AVPlayer
final class CollapsAVUIManager {
    
    // MARK: - Dependencies
    
    private weak var playerVC: CollapsNativePlayerViewController?
    private weak var player: AVPlayer?
    
    // MARK: - State
    
    private(set) var playlist: [CollapsAVPlaylistItem] = []
    private(set) var currentIndex: Int = 0
    private(set) var currentQualityOptions: [CollapsAVQualityOption] = []
    private(set) var selectedQualityIndex: Int = 0
    private(set) var selectedAudioVariantIndexByMediaId: [String: Int] = [:]
    private(set) var isCustomAllohaVoiceoverPlaylist: Bool = false
    
    // MARK: - Initialization
    
    init(playerVC: CollapsNativePlayerViewController?, player: AVPlayer) {
        self.playerVC = playerVC
        self.player = player
    }
    
    // MARK: - Public API
    
    /// Updates the player view controller reference
    func updatePlayerVC(_ playerVC: CollapsNativePlayerViewController?) {
        self.playerVC = playerVC
    }
    
    /// Updates the playlist state
    func updatePlaylist(_ playlist: [CollapsAVPlaylistItem], currentIndex: Int) {
        self.playlist = playlist
        self.currentIndex = currentIndex
        self.isCustomAllohaVoiceoverPlaylist = Self.checkIsCustomAllohaVoiceoverPlaylist(playlist)
    }
    
    /// Updates the quality options
    func updateQualityOptions(_ options: [CollapsAVQualityOption]) {
        currentQualityOptions = options
    }
    
    /// Updates the selected quality index
    func updateSelectedQualityIndex(_ index: Int) {
        selectedQualityIndex = index
    }
    
    /// Updates the selected audio variant index
    func updateSelectedAudioVariantIndex(_ index: Int, for mediaId: String) {
        selectedAudioVariantIndexByMediaId[mediaId] = index
    }
    
    /// Refreshes the overlay UI with state updates
    func refreshOverlayUI(
        currentTime: Double,
        duration: Double,
        isPlaying: Bool,
        normalizedOverlayLabel: (String, String) -> String
    ) {
        guard let vc = playerVC else { return }
        let dur = max(duration, 0)
        let current = min(max(currentTime, 0), dur > 0 ? dur : currentTime)
        let item = playlist.indices.contains(currentIndex) ? playlist[currentIndex] : nil
        let rawTitle = (item?.title.isEmpty == false) ? item!.title : "NeoMovies"
        let title = normalizedOverlayLabel(rawTitle, "NeoMovies")
        let subtitle: String
        if let season = item?.season, let episode = item?.episode {
            subtitle = "Season \(season), Episode \(episode)"
        } else {
            subtitle = "NeoMovies"
        }
        let audioLabel = currentAudioTrackLabel(normalizedOverlayLabel: normalizedOverlayLabel)
        let qualityLabel = currentQualityOptions.first(where: { $0.index == selectedQualityIndex })?.label ?? "Auto"
        let useEpisodeNav = !isCustomAllohaVoiceoverPlaylist
        Task { @MainActor in
            vc.updateOverlay(
                title: title,
                subtitle: subtitle,
                isPlaying: isPlaying,
                currentTime: current,
                duration: dur,
                audioLabel: audioLabel,
                qualityLabel: qualityLabel,
                canGoPreviousEpisode: useEpisodeNav && currentIndex > 0,
                canGoNextEpisode: useEpisodeNav && currentIndex < playlist.count - 1
            )
        }
    }
    
    /// Unified refresh method that takes state directly
    func refreshOverlayUI(
        currentTime: Double,
        duration: Double,
        isPlaying: Bool,
        playlist: [CollapsAVPlaylistItem],
        currentIndex: Int,
        qualityOptions: [CollapsAVQualityOption],
        selectedQualityIndex: Int,
        selectedAudioVariantIndexByMediaId: [String: Int],
        currentItemMediaId: String
    ) {
        updatePlaylist(playlist, currentIndex: currentIndex)
        updateQualityOptions(qualityOptions)
        updateSelectedQualityIndex(selectedQualityIndex)
        updateSelectedAudioVariantIndex(selectedAudioVariantIndexByMediaId[currentItemMediaId] ?? 0, for: currentItemMediaId)
        refreshOverlayUI(
            currentTime: currentTime,
            duration: duration,
            isPlaying: isPlaying,
            normalizedOverlayLabel: CollapsAVHelper.normalizedOverlayLabel
        )
    }
    
    /// Shows the quality selection sheet
    @MainActor
    func showQualitySheet(from controller: UIViewController, sourceView: UIView, onSelectQuality: @escaping (Int) -> Void) {
        let sheet = UIAlertController(title: "Quality", message: nil, preferredStyle: .actionSheet)
        for option in currentQualityOptions {
            sheet.addAction(
                UIAlertAction(title: option.label, style: .default, handler: { _ in
                    onSelectQuality(option.index)
                })
            )
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popover = sheet.popoverPresentationController {
            popover.sourceView = sourceView
            popover.sourceRect = sourceView.bounds
        }
        controller.present(sheet, animated: true)
    }
    
    /// Shows the audio track selection sheet
    @MainActor
    func showAudioSheet(
        from controller: UIViewController,
        sourceView: UIView,
        tracks: [[String: Any]],
        onSelectAudio: @escaping (Int) -> Void
    ) {
        let sheet = UIAlertController(title: "Audio Track", message: nil, preferredStyle: .actionSheet)
        for track in tracks {
            let label = track["label"] as? String ?? "Unknown"
            sheet.addAction(
                UIAlertAction(title: label, style: .default, handler: { _ in
                    guard let index = track["index"] as? Int else { return }
                    onSelectAudio(index)
                })
            )
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popover = sheet.popoverPresentationController {
            popover.sourceView = sourceView
            popover.sourceRect = sourceView.bounds
        }
        controller.present(sheet, animated: true)
    }
    
    // MARK: - Private Helper Methods
    
    private func currentAudioTrackLabel(normalizedOverlayLabel: (String, String) -> String) -> String {
        if let current = playlist[safe: currentIndex], !current.audioVariants.isEmpty {
            let selected = selectedAudioVariantIndexByMediaId[current.mediaId] ?? 0
            if current.audioVariants.indices.contains(selected) {
                return normalizedOverlayLabel(current.audioVariants[selected].title, "Audio")
            }
            return "Audio"
        }

        if isCustomAllohaVoiceoverPlaylist {
            guard playlist.indices.contains(currentIndex) else { return "Audio" }
            let label = playlist[currentIndex].voiceoverLabel ?? playlist[currentIndex].title
            return normalizedOverlayLabel(label, "Audio")
        }
        guard let item = player?.currentItem,
              let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .audible) else {
            return "Audio"
        }
        if let selected = item.currentMediaSelection.selectedMediaOption(in: group) {
            return normalizedOverlayLabel(selected.displayName, "Audio")
        }
        return "Audio"
    }
    
    private static func checkIsCustomAllohaVoiceoverPlaylist(_ playlist: [CollapsAVPlaylistItem]) -> Bool {
        guard playlist.count > 1, let first = playlist.first else { return false }

        // Case 1: same season/episode, different URLs (series dub playlist)
        if let season = first.season, let episode = first.episode {
            let allSameEpisode = playlist.allSatisfy { $0.season == season && $0.episode == episode }
            guard allSameEpisode else { return false }
            return Set(playlist.map { $0.url }).count > 1
        }

        // Case 2: no season/episode, same mediaId, different URLs (movie dub playlist)
        guard playlist.allSatisfy({ $0.season == nil && $0.episode == nil }) else { return false }
        guard playlist.allSatisfy({ $0.mediaId == first.mediaId }) else { return false }
        return Set(playlist.map { $0.url }).count > 1
    }
}