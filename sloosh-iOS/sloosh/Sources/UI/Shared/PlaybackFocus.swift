import Foundation
import Combine

/// Serializes all moment players on the main actor. Main-player ownership is a
/// durable lock, not a one-shot pause notification; it lasts through cleanup.
@MainActor
final class PlaybackFocus: ObservableObject {
    static let shared = PlaybackFocus()
    @Published private(set) var hasMainPlayer = false
    private var mainPlayers: Set<UUID> = []
    private weak var momentOwner: ClipPlaybackCoordinator?

    private init() {}

    func beginMainPlayer(_ id: UUID) {
        guard mainPlayers.insert(id).inserted else { return }
        momentOwner?.setPlaybackEnabled(false)
        hasMainPlayer = true
    }

    func endMainPlayer(_ id: UUID) {
        mainPlayers.remove(id)
        hasMainPlayer = !mainPlayers.isEmpty
    }

    func claimMoment(_ owner: ClipPlaybackCoordinator) -> Bool {
        guard !hasMainPlayer else { return false }
        if let previous = momentOwner, previous !== owner {
            previous.setPlaybackEnabled(false)
        }
        momentOwner = owner
        return true
    }

    func ownsMoment(_ owner: ClipPlaybackCoordinator) -> Bool {
        !hasMainPlayer && momentOwner === owner
    }

    func releaseMoment(_ owner: ClipPlaybackCoordinator) {
        if momentOwner === owner { momentOwner = nil }
    }
}
