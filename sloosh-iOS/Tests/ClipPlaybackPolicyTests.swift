import Foundation

// PlaybackFocus only needs the revocation interface; no AVPlayer/network/UI is
// needed to exercise arbitration. The app's coordinator performs real teardown.
@MainActor
final class ClipPlaybackCoordinator {
    private(set) var enabled = false
    private(set) var revocations = 0

    func setPlaybackEnabled(_ enabled: Bool) {
        if enabled {
            guard PlaybackFocus.shared.claimMoment(self) else { return }
            self.enabled = true
        } else {
            self.enabled = false
            revocations += 1
            PlaybackFocus.shared.releaseMoment(self)
        }
    }
}

@main
struct ClipPlaybackPolicyTests {
    @MainActor
    static func main() {
        // Exhaustive screen eligibility: only one of the 32 combinations may
        // play. Covers hidden tab + foreground, navigation, sheets and movies.
        var permitted = 0
        for mask in 0..<32 {
            let state = ClipPlaybackEligibility(
                isVisible: mask & 1 != 0,
                isSelected: mask & 2 != 0,
                isSceneActive: mask & 4 != 0,
                isCovered: mask & 8 != 0,
                hasMainPlayer: mask & 16 != 0
            )
            precondition(state.allowsPlayback == (mask == 7), "Invalid eligibility: \(mask)")
            if state.allowsPlayback { permitted += 1 }
        }
        precondition(permitted == 1)

        var session = ClipPlaybackSession()
        let initial = session.generation
        precondition(!session.accepts(initial), "A newly created hidden feed must not autoplay")
        session.setEnabled(true)
        let first = session.generation
        precondition(session.accepts(first))
        session.setEnabled(true)
        precondition(session.accepts(first), "Repeated visibility updates must be idempotent")
        session.setEnabled(false)
        precondition(!session.accepts(first), "Late resolution/seek/KVO must be ignored after exit")
        session.setEnabled(true)
        precondition(!session.accepts(first), "Reopening the same clip must not revive its old work")
        let reopened = session.generation
        session.invalidate()
        precondition(!session.accepts(reopened), "Retry/item replacement must invalidate old work")
        precondition(session.accepts(session.generation))

        let focus = PlaybackFocus.shared
        let feed = ClipPlaybackCoordinator()
        let modal = ClipPlaybackCoordinator()
        feed.setPlaybackEnabled(true)
        precondition(focus.ownsMoment(feed))
        modal.setPlaybackEnabled(true)
        precondition(!feed.enabled && feed.revocations == 1)
        precondition(focus.ownsMoment(modal) && !focus.ownsMoment(feed))
        feed.setPlaybackEnabled(false)
        precondition(focus.ownsMoment(modal), "A stale owner cannot release the new owner")

        let movie = UUID()
        let secondMovie = UUID()
        focus.beginMainPlayer(movie)
        precondition(!modal.enabled && focus.hasMainPlayer)
        precondition(!focus.ownsMoment(modal))
        feed.setPlaybackEnabled(true)
        modal.setPlaybackEnabled(true)
        precondition(!feed.enabled && !modal.enabled, "A movie must block every feed")
        focus.beginMainPlayer(movie) // Presenter and stream startup acquire the same lock.
        focus.beginMainPlayer(secondMovie)
        focus.endMainPlayer(movie)
        precondition(focus.hasMainPlayer, "An older player's cleanup cannot unlock another player")
        precondition(!focus.claimMoment(feed))
        focus.endMainPlayer(secondMovie)
        precondition(!focus.hasMainPlayer)
        precondition(!feed.enabled && !modal.enabled, "Unlocking alone must not autoplay a hidden feed")
        modal.setPlaybackEnabled(true)
        precondition(focus.ownsMoment(modal), "A visible modal may play after main-player teardown")
        modal.setPlaybackEnabled(false)
        precondition(!focus.ownsMoment(modal))

        print("Clip playback regression tests passed (32 eligibility states, session invalidation, exclusive focus).")
    }
}
