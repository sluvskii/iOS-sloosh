import Foundation

@main
struct WatchPartySyncTests {
    static func main() {
        var count = 0
        func check(_ condition: Bool, _ description: String) {
            precondition(condition, description)
            count += 1
        }

        // Test 1: Paused target position remains constant regardless of time
        let pausedPlayback = WatchPartyPlayback(
            isPlaying: false,
            positionSec: 120.0,
            updatedAtMs: 1_000_000,
            lastActionByUid: "u1",
            lastActionByName: "Alice",
            actionType: .pause
        )
        check(pausedPlayback.targetPosition(at: 1_000_000) == 120.0, "Target position at updated time")
        check(pausedPlayback.targetPosition(at: 1_060_000) == 120.0, "Paused target position does not advance with time")
        check(pausedPlayback.drift(localCurrentTime: 120.0, currentTimestampMs: 1_060_000) == 0.0, "Zero drift when paused at target")

        // Test 2: Playing target position advances strictly with server timestamp
        let playingPlayback = WatchPartyPlayback(
            isPlaying: true,
            positionSec: 100.0,
            updatedAtMs: 1_000_000,
            lastActionByUid: "u1",
            lastActionByName: "Alice",
            actionType: .play
        )
        // 5 seconds elapsed (5000 ms)
        check(playingPlayback.targetPosition(at: 1_005_000) == 105.0, "Target position advances 5s after 5000ms")
        // 60 seconds elapsed (60000 ms)
        check(playingPlayback.targetPosition(at: 1_060_000) == 160.0, "Target position advances 60s after 60000ms")

        // Test 3: Drift calculation
        // Local is at 105.2s, target is at 105.0s -> drift is +0.2s (local ahead)
        let driftAhead = playingPlayback.drift(localCurrentTime: 105.2, currentTimestampMs: 1_005_000)
        check(abs(driftAhead - 0.2) < 0.001, "Positive drift indicates local player is ahead")

        // Local is at 104.5s, target is at 105.0s -> drift is -0.5s (local behind)
        let driftBehind = playingPlayback.drift(localCurrentTime: 104.5, currentTimestampMs: 1_005_000)
        check(abs(driftBehind - (-0.5)) < 0.001, "Negative drift indicates local player is behind")

        // Test 4: Rate adjustment thresholds
        func recommendRate(drift: Double) -> Float {
            if abs(drift) > 2.0 {
                return 1.0 // hard seek triggered
            } else if abs(drift) > 0.35 {
                return drift < 0 ? 1.04 : 0.96
            } else {
                return 1.0
            }
        }
        check(recommendRate(drift: 0.1) == 1.0, "In-sync drift (<0.35s) maintains normal rate 1.0")
        check(recommendRate(drift: -0.1) == 1.0, "In-sync negative drift maintains normal rate 1.0")
        check(recommendRate(drift: -0.8) == 1.04, "Behind by 0.8s accelerates rate to 1.04")
        check(recommendRate(drift: 0.8) == 0.96, "Ahead by 0.8s slows rate to 0.96")
        check(recommendRate(drift: 3.5) == 1.0, "Large drift (>2.0s) triggers seek rather than rate change")

        // Test 5: WatchPartySession encoding and decoding round-trip
        let session = WatchPartySession(
            id: "wp_test123",
            hostUid: "u_host",
            hostName: "HostUser",
            hostAvatarUrl: "https://example.com/avatar.jpg",
            guestUid: "u_guest",
            guestName: "GuestUser",
            mediaId: "movie_99",
            mediaType: "movie",
            title: "Интерстеллар",
            posterUrl: "https://example.com/poster.jpg",
            season: nil,
            episode: nil,
            translationId: 5,
            translationName: "Дубляж",
            streamSource: "source1",
            playback: playingPlayback,
            status: .active,
            createdAtMs: 1_000_000,
            updatedAtMs: 1_000_000
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        do {
            let data = try encoder.encode(session)
            let decoded = try decoder.decode(WatchPartySession.self, from: data)
            check(decoded.id == "wp_test123", "Session id preserved")
            check(decoded.title == "Интерстеллар", "Title preserved")
            check(decoded.status == .active, "Status preserved")
            check(decoded.playback.isPlaying == true, "Playback state preserved")
            check(decoded.playback.positionSec == 100.0, "Playback position preserved")
        } catch {
            preconditionFailure("Failed to encode/decode WatchPartySession: \(error)")
        }

        // Test 6: WatchPartyInvitePayload encoding and decoding
        let invitePayload = WatchPartyInvitePayload(
            partyId: "wp_test123",
            mediaId: "movie_99",
            mediaType: "movie",
            title: "Интерстеллар",
            posterUrl: "https://example.com/poster.jpg",
            season: 1,
            episode: 2,
            translationName: "Дубляж",
            status: .active
        )
        check(invitePayload.status.isPlayable, "Active status is playable")
        check(invitePayload.id == "wp_test123", "Payload id is partyId")

        do {
            let payloadData = try encoder.encode(invitePayload)
            let decodedPayload = try decoder.decode(WatchPartyInvitePayload.self, from: payloadData)
            check(decodedPayload.partyId == "wp_test123", "WatchParty payload preserved")
            check(decodedPayload.season == 1, "Season preserved")
            check(decodedPayload.episode == 2, "Episode preserved")
        } catch {
            preconditionFailure("Failed to encode/decode WatchPartyInvitePayload: \(error)")
        }

        // Test 7: Closed status transitions
        var closedPayload = invitePayload
        closedPayload.status = .closed
        check(!closedPayload.status.isPlayable, "Closed status is not playable")

        print("PASS: \(count) watch party sync & model test cases")
    }
}
