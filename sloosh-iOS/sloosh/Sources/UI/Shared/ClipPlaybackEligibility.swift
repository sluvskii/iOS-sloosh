import Foundation

/// Fail closed: loading data, receiving a notification or completing a seek is
/// never evidence that a moment screen is actually on screen.
struct ClipPlaybackEligibility {
    var isVisible: Bool
    var isSelected: Bool
    var isSceneActive: Bool
    var isCovered: Bool
    var hasMainPlayer: Bool

    var allowsPlayback: Bool {
        isVisible && isSelected && isSceneActive && !isCovered && !hasMainPlayer
    }
}

/// Invalidate asynchronous work even when the same clip is reopened (an ID check
/// alone cannot distinguish two successive playback sessions of that clip).
struct ClipPlaybackSession {
    private(set) var generation = UUID()
    private(set) var isEnabled = false

    mutating func setEnabled(_ enabled: Bool) {
        if isEnabled != enabled {
            invalidate()
            isEnabled = enabled
        }
    }

    mutating func invalidate() {
        generation = UUID()
    }

    func accepts(_ generation: UUID) -> Bool {
        isEnabled && self.generation == generation
    }
}
