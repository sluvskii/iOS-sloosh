import Foundation
import AVFoundation

/// Manages playlist and episode navigation for AVPlayer
final class CollapsAVPlaylistManager {
    
    // MARK: - State
    
    private(set) var playlist: [CollapsAVPlaylistItem] = []
    private(set) var currentIndex: Int = 0
    private(set) var qualityRecoveryCursorByMediaId: [String: Int] = [:]
    private(set) var episodeLoadToken: UUID = UUID()
    
    // MARK: - Public API
    
    /// Configures the playlist with the given items
    func configurePlaylist(items: [CollapsAVPlaylistItem], startIndex: Int) throws {
        guard !items.isEmpty else {
            throw NSError(domain: "NeomoviesCore", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Playlist is empty"])
        }
        playlist = items
        currentIndex = min(max(0, startIndex), items.count - 1)
        qualityRecoveryCursorByMediaId = [:]
        episodeLoadToken = UUID()
    }
    
    /// Selects a specific episode by index
    func selectEpisode(index: Int) throws {
        guard index >= 0, index < playlist.count else {
            throw NSError(domain: "NeomoviesCore", code: 1002, userInfo: [NSLocalizedDescriptionKey: "Episode index out of range"])
        }
        let _ = currentIndex
        currentIndex = index
        // Don't reset selectedQualityIndex - preserve user's quality choice
        if let mediaId = playlist[safe: index]?.mediaId {
            qualityRecoveryCursorByMediaId[mediaId] = 0
        }
    }
    
    /// Reverts to previous index if selection failed
    func revertSelection(to previousIndex: Int) {
        currentIndex = previousIndex
    }
    
    /// Moves to the next episode
    func nextEpisode() throws {
        try selectEpisode(index: min(currentIndex + 1, max(playlist.count - 1, 0)))
    }
    
    /// Moves to the previous episode
    func previousEpisode() throws {
        try selectEpisode(index: max(currentIndex - 1, 0))
    }
    
    /// Selects a specific episode by index (async version)
    func selectEpisodeAsync(index: Int) throws {
        guard index >= 0, index < playlist.count else {
            throw NSError(domain: "NeomoviesCore", code: 1002, userInfo: [NSLocalizedDescriptionKey: "Episode index out of range"])
        }
        let loadToken = UUID()
        episodeLoadToken = loadToken
        let _ = currentIndex
        currentIndex = index
        // Don't reset selectedQualityIndex - preserve user's quality choice
        if let mediaId = playlist[safe: index]?.mediaId {
            qualityRecoveryCursorByMediaId[mediaId] = 0
        }
    }
    
    /// Checks if the load token is still valid (no newer episode load was started)
    func isLoadTokenValid(_ token: UUID) -> Bool {
        episodeLoadToken == token
    }
    
    /// Moves to the next episode (async version)
    func nextEpisodeAsync() throws {
        try selectEpisodeAsync(index: min(currentIndex + 1, max(playlist.count - 1, 0)))
    }
    
    /// Moves to the previous episode (async version)
    func previousEpisodeAsync() throws {
        try selectEpisodeAsync(index: max(currentIndex - 1, 0))
    }
    
    /// Returns the current playlist item
    var currentItem: CollapsAVPlaylistItem? {
        playlist.indices.contains(currentIndex) ? playlist[currentIndex] : nil
    }
    
    /// Returns whether there is a next episode
    var hasNextEpisode: Bool {
        currentIndex < playlist.count - 1
    }
    
    /// Returns whether there is a previous episode
    var hasPreviousEpisode: Bool {
        currentIndex > 0
    }
    
    /// Replaces a playlist item in-place (used to back-fill resolved audio/quality variants)
    func updateItem(at index: Int, with item: CollapsAVPlaylistItem) {
        guard index >= 0, index < playlist.count else { return }
        playlist[index] = item
    }

    /// Resets quality recovery cursor for a media ID
    func resetQualityRecoveryCursor(for mediaId: String) {
        qualityRecoveryCursorByMediaId[mediaId] = 0
    }
    
    /// Gets quality recovery cursor for a media ID
    func qualityRecoveryCursor(for mediaId: String) -> Int {
        qualityRecoveryCursorByMediaId[mediaId] ?? 0
    }
}