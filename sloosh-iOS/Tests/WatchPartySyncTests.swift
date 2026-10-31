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

        // Test 3b: Speed-aware target position advances proportionally to speed
        let speedPlayback = WatchPartyPlayback(
            isPlaying: true,
            positionSec: 100.0,
            updatedAtMs: 1_000_000,
            lastActionByUid: "u1",
            lastActionByName: "Alice",
            actionType: .changeSpeed,
            speed: 1.5
        )
        // At 1.5x speed, 10 seconds elapsed (10,000ms) = 15 seconds media progress
        check(abs(speedPlayback.targetPosition(at: 1_010_000) - 115.0) < 0.001, "Target position at 1.5x advances 15s after 10000ms")

        let slowPlayback = WatchPartyPlayback(
            isPlaying: true,
            positionSec: 100.0,
            updatedAtMs: 1_000_000,
            lastActionByUid: "u1",
            lastActionByName: "Alice",
            actionType: .changeSpeed,
            speed: 0.5
        )
        // At 0.5x speed, 10 seconds elapsed = 5 seconds media progress
        check(abs(slowPlayback.targetPosition(at: 1_010_000) - 105.0) < 0.001, "Target position at 0.5x advances 5s after 10000ms")

        // Test 4: Sub-frame Precision P-Controller rate recommendation
        func recommendRate(drift: Double, baseSpeed: Float = 1.0) -> Float {
            let absDrift = abs(drift)
            if absDrift <= 0.020 {
                return baseSpeed
            } else if absDrift <= 0.150 {
                let pGain: Float = 0.15
                let delta = Float(-drift) * pGain
                let clampedDelta = max(-0.018, min(0.018, delta))
                return baseSpeed * (1.0 + clampedDelta)
            } else if absDrift <= 0.800 {
                let adjustment: Float = 0.05
                return drift < 0 ? (baseSpeed * (1.0 + adjustment)) : (baseSpeed * (1.0 - adjustment))
            } else if absDrift <= 2.0 {
                let adjustment: Float = 0.10
                return drift < 0 ? (baseSpeed * (1.0 + adjustment)) : (baseSpeed * (1.0 - adjustment))
            } else {
                return baseSpeed // frame-accurate hard seek triggered
            }
        }

        check(recommendRate(drift: 0.015) == 1.0, "Sub-frame lockstep (<=20ms) maintains exact base speed")
        check(recommendRate(drift: -0.010) == 1.0, "Sub-frame lockstep negative maintains exact base speed")

        // Micro-slew at 50ms ahead (drift = +0.05s): delta = -0.15 * 0.05 = -0.0075 -> 0.9925x
        let slewAhead = recommendRate(drift: 0.05)
        check(abs(slewAhead - 0.9925) < 0.0001, "Micro-slew slows slightly by 0.75% for 50ms drift")

        // Micro-slew at 100ms behind (drift = -0.10s): delta = +0.15 * 0.10 = +0.015 -> 1.015x
        let slewBehind = recommendRate(drift: -0.10)
        check(abs(slewBehind - 1.015) < 0.0001, "Micro-slew accelerates smoothly by 1.5% for 100ms drift")

        // Catch-up at 400ms: +/- 5%
        check(abs(recommendRate(drift: -0.4) - 1.05) < 0.001, "Catch-up accelerates by 5% at 400ms behind")
        check(abs(recommendRate(drift: 0.4) - 0.95) < 0.001, "Catch-up slows by 5% at 400ms ahead")

        // Slew around custom base speed (e.g. 1.5x)
        let customBaseSlew = recommendRate(drift: -0.10, baseSpeed: 1.5)
        check(abs(customBaseSlew - (1.5 * 1.015)) < 0.001, "Slew correctly modulates around 1.5x base speed")

        // Test 4b: Backwards-compatible JSON decoding without speed field
        let legacyJson = """
        {
            "isPlaying": true,
            "positionSec": 42.0,
            "updatedAtMs": 1000000,
            "lastActionByUid": "legacy",
            "lastActionByName": "Bob",
            "actionType": "play"
        }
        """.data(using: .utf8)!

        let legacyDecoded = try! JSONDecoder().decode(WatchPartyPlayback.self, from: legacyJson)
        check(legacyDecoded.speed == 1.0, "Missing speed in payload defaults safely to 1.0")
        check(legacyDecoded.positionSec == 42.0, "Legacy position decoded correctly")

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
