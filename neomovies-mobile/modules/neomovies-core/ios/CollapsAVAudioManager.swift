import Foundation
import AVFoundation

/// Manages audio track selection for AVPlayer
final class CollapsAVAudioManager {
    
    // MARK: - Dependencies
    
    private weak var player: AVPlayer?
    
    // MARK: - State
    
    private(set) var selectedAudioVariantIndexByMediaId: [String: Int] = [:]
    private(set) var isCustomAllohaVoiceoverPlaylist: Bool = false
    private(set) var playlist: [CollapsAVPlaylistItem] = []
    private(set) var currentIndex: Int = 0
    
    // MARK: - Initialization
    
    init(player: AVPlayer) {
        self.player = player
    }
    
    // MARK: - Public API
    
    /// Updates the playlist state
    func updatePlaylist(_ playlist: [CollapsAVPlaylistItem], currentIndex: Int) {
        self.playlist = playlist
        self.currentIndex = currentIndex
        self.isCustomAllohaVoiceoverPlaylist = Self.checkIsCustomAllohaVoiceoverPlaylist(playlist)
    }
    
    /// Lists available audio tracks
    func listAudioTracks(normalizedOverlayLabel: (String, String) -> String) -> [[String: Any]] {
        if let current = playlist[safe: currentIndex], !current.audioVariants.isEmpty {
            return current.audioVariants.enumerated().map { index, variant in
                CollapsAVTrack(
                    index: index,
                    id: "alloha-\(index)",
                    label: normalizedOverlayLabel(variant.title, "Unknown"),
                    language: ""
                ).asDictionary()
            }
        }

        if isCustomAllohaVoiceoverPlaylist {
            var used: [String: Int] = [:]
            return playlist.enumerated().map { index, item in
                let raw = (item.voiceoverLabel ?? item.title).trimmingCharacters(in: .whitespacesAndNewlines)
                let baseLabel = raw.isEmpty ? "Unknown" : raw
                used[baseLabel, default: 0] += 1
                let suffix = used[baseLabel] ?? 1
                let label = suffix > 1 ? "\(baseLabel) \(suffix)" : baseLabel
                return CollapsAVTrack(
                    index: index,
                    id: "alloha-\(index)",
                    label: label,
                    language: ""
                ).asDictionary()
            }
        }

        guard let group = player?.currentItem?.asset.mediaSelectionGroup(forMediaCharacteristic: .audible) else {
            return []
        }
        return group.options.enumerated().map { index, option in
            CollapsAVTrack(
                index: index,
                id: option.extendedLanguageTag ?? option.locale?.identifier ?? "",
                label: option.displayName,
                language: option.locale?.identifier ?? ""
            ).asDictionary()
        }
    }

    /// Selects an audio track by index.
    /// Returns the playlist index to switch to when this is a voiceover-playlist dub switch;
    /// returns nil for all other cases (handled internally).
    func selectAudioTrack(index: Int?, emitState: @escaping () -> Void) -> Int? {
        if let current = playlist[safe: currentIndex], !current.audioVariants.isEmpty {
            guard let index, index >= 0, index < current.audioVariants.count else { return nil }
            selectedAudioVariantIndexByMediaId[current.mediaId] = index
            emitState()
            return nil
        }

        if isCustomAllohaVoiceoverPlaylist {
            guard let index, index >= 0, index < playlist.count else { return nil }
            if index == currentIndex { return nil }
            return index  // Caller must switch to this playlist item
        }

        guard let item = player?.currentItem,
              let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .audible) else {
            return nil
        }
        if let index, index >= 0, index < group.options.count {
            item.select(group.options[index], in: group)
        } else {
            item.select(nil, in: group)
        }
        emitState()
        return nil
    }
    
    /// Lists available subtitle tracks
    func listSubtitleTracks() -> [[String: Any]] {
        guard let group = player?.currentItem?.asset.mediaSelectionGroup(forMediaCharacteristic: .legible) else {
            return []
        }
        return group.options.enumerated().map { index, option in
            CollapsAVTrack(
                index: index,
                id: option.extendedLanguageTag ?? option.locale?.identifier ?? "",
                label: option.displayName,
                language: option.locale?.identifier ?? ""
            ).asDictionary()
        }
    }
    
    /// Selects a subtitle track by index
    func selectSubtitleTrack(index: Int?, emitState: @escaping () -> Void) {
        guard let item = player?.currentItem,
              let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible) else {
            return
        }
        if let index, index >= 0, index < group.options.count {
            item.select(group.options[index], in: group)
        } else {
            item.select(nil, in: group)
        }
        emitState()
    }
    
    /// Sets the selected audio variant index for a media ID
    func setSelectedAudioVariantIndex(_ index: Int, for mediaId: String) {
        selectedAudioVariantIndexByMediaId[mediaId] = index
    }
    
    /// Gets the current audio track label
    func currentAudioTrackLabel(normalizedOverlayLabel: (String, String) -> String) -> String {
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
    
    // MARK: - Private Helper Methods
    
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
