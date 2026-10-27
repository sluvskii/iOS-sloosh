import Foundation

@main
struct RemoteCampaignTests {
    static func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    static func encode(_ value: Any) -> Data { try! JSONSerialization.data(withJSONObject: value) }
    static func envelope(_ items: [Any], enabled: Bool = true, version: Int = 1) -> Data {
        encode(["version": version, "enabled": enabled, "items": items])
    }

    @MainActor
    static func main() throws {
        let endpoint = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let root = try JSONSerialization.jsonObject(with: endpoint) as! [String: Any]
        // Validate existing content without requiring it: removing the entire
        // section is a supported kill switch, not a reason to fail CI.
        // Behavioral tests use a deterministic fixture, independent of live copy.
        if let configuration = root["campaigns"] as? [String: Any],
           configuration["enabled"] as? Bool == true {
            let productionItems = configuration["items"] as! [[String: Any]]
            precondition(RemoteCampaignConfig.decode(encode(configuration)).count == productionItems.count)
        }
        let entries: [[String: Any]] = [[
            "id": "doomsday-fixture", "enabled": true, "kind": "countdown",
            "title": "Дум приближается", "subtitle": "До дня мировой премьеры",
            "mediaId": "movie_1003596", "theme": "emerald",
            "startsAt": "2026-10-27T00:00:00Z", "expiresAt": "2026-12-18T05:00:00Z",
            "countdownTo": "2026-12-18T05:00:00Z", "timeZone": "America/New_York",
            "afterCountdown": "hide", "priority": 100
        ]]
        let payload = envelope(entries)
        let campaigns = RemoteCampaignConfig.decode(payload)
        precondition(campaigns.count == 1)
        let campaign = campaigns[0]
        let now = date("2026-11-01T12:00:00Z")
        precondition(campaign.mediaId == "movie_1003596")
        precondition(campaign.isActive(at: now))
        precondition(!campaign.isActive(at: date("2026-10-26T00:00:00Z")))
        precondition(!campaign.isActive(at: date("2026-12-18T05:00:00Z")))
        precondition(campaign.premiereDateLabel() == "18 декабря 2026")
        precondition(campaign.matches(mediaId: "movie_1003596", mediaType: "movie", tmdbId: nil))
        precondition(campaign.matches(mediaId: "1003596", mediaType: nil, tmdbId: nil))
        precondition(campaign.matches(mediaId: "kp_123", mediaType: "movie", tmdbId: 1003596))
        precondition(!campaign.matches(mediaId: "1003596", mediaType: "tv", tmdbId: 1003596))
        precondition(!campaign.matches(mediaId: "movie_1003596", mediaType: "movie", tmdbId: 123))
        precondition(!campaign.matches(mediaId: "kp_1003596", mediaType: "movie", tmdbId: nil))
        precondition(!campaign.matches(mediaId: "movie_123", mediaType: "movie", tmdbId: nil))

        precondition(RemoteCampaignConfig.decode(nil).isEmpty)
        precondition(RemoteCampaignConfig.decode(Data("broken".utf8)).isEmpty)
        precondition(RemoteCampaignConfig.decode(envelope(entries, enabled: false)).isEmpty)
        precondition(RemoteCampaignConfig.decode(envelope(entries, version: 2)).isEmpty)
        precondition(RemoteCampaignConfig.decode(Data(repeating: 32, count: 65_537)).isEmpty)
        precondition(RemoteCampaignConfig.decode(envelope(["invalid", 42, entries[0]])).count == 1)
        precondition(RemoteCampaignConfig.decode(envelope([entries[0], entries[0]])).count == 1)
        var invalid = entries[0]
        invalid["artworkURL"] = "javascript:alert(1)"
        precondition(RemoteCampaignConfig.decode(envelope([invalid, entries[0]])).count == 1)
        for (key, value) in [
            ("mediaId", "../../admin"), ("timeZone", "not-a-timezone"),
            ("countdownTo", "not-a-date"), ("theme", "unknown"),
            ("title", String(repeating: "x", count: 101)),
            ("artworkURL", "http://example.com/image.jpg"),
            ("artworkURL", "https://user:pass@example.com/image.jpg"),
            ("expiresAt", "2020-01-01T00:00:00Z")
        ] {
            var item = entries[0]; item[key] = value
            precondition(RemoteCampaignConfig.decode(envelope([item])).isEmpty, "Invalid field accepted: \(key)")
        }
        var completed = entries[0]
        completed["expiresAt"] = "2026-12-20T05:00:00Z"
        completed["afterCountdown"] = "message"
        completed["completedText"] = "Премьера состоялась"
        let completedCampaign = RemoteCampaignConfig.decode(envelope([completed]))[0]
        precondition(completedCampaign.isActive(at: date("2026-12-18T05:00:00Z")))
        precondition(!completedCampaign.isActive(at: date("2026-12-20T05:00:00Z")))

        let target = date("2026-12-18T05:00:00Z")
        let value = CampaignCountdown(until: target, now: target.addingTimeInterval(-90_061))
        precondition(value == CampaignCountdown(until: target.addingTimeInterval(123), now: target.addingTimeInterval(-89_938)))
        precondition(value.days == 1 && value.hours == 1 && value.minutes == 1 && value.seconds == 1)
        let last = CampaignCountdown(until: target, now: target.addingTimeInterval(-0.1))
        precondition(last.seconds == 1)
        let zero = CampaignCountdown(until: target, now: target.addingTimeInterval(1))
        precondition(zero.days == 0 && zero.hours == 0 && zero.minutes == 0 && zero.seconds == 0)
        precondition(RemoteCampaignConfig.isCacheFresh(fetchedAt: now, now: now))
        precondition(!RemoteCampaignConfig.isCacheFresh(fetchedAt: now, now: now.addingTimeInterval(259_201)))
        precondition(!RemoteCampaignConfig.isCacheFresh(fetchedAt: now.addingTimeInterval(10), now: now))

        let suite = "sloosh.campaign-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = RemoteCampaignStore(defaults: defaults)
        precondition(store.campaigns.isEmpty)
        store.apply(payload, now: now)
        precondition(store.detailsCampaign(id: "1003596", type: "movie", tmdbId: nil, at: now)?.id == campaign.id)
        precondition(store.detailsCampaign(id: "123", type: "movie", tmdbId: nil, at: now) == nil)
        precondition(store.detailsCampaign(id: "1003596", type: "tv", tmdbId: nil, at: now) == nil)
        precondition(store.detailsCampaign(id: "1003596", type: "movie", tmdbId: nil, at: now.addingTimeInterval(259_201)) == nil)
        var upcoming = entries[0]
        upcoming["id"] = "future-event"
        upcoming["priority"] = 200
        upcoming["startsAt"] = "2026-11-02T00:00:00Z"
        store.apply(envelope([upcoming, entries[0]]), now: now)
        precondition(store.detailsCampaign(id: "1003596", type: "movie", tmdbId: nil, at: now)?.id == campaign.id,
                     "A scheduled event must not mask an active event")
        var disabled = entries[0]
        disabled["enabled"] = false
        store.apply(envelope([disabled]), now: now)
        precondition(store.detailsCampaign(id: "1003596", type: "movie", tmdbId: nil, at: now) == nil)
        store.apply(envelope(entries, enabled: false), now: now)
        precondition(store.campaigns.isEmpty, "Global kill switch must clear cached content")
        store.apply(payload, now: Date())
        precondition(RemoteCampaignStore(defaults: defaults).campaigns == campaigns, "Fresh cache must survive restart")
        store.apply(nil)
        precondition(store.campaigns.isEmpty, "Removing campaigns must restore original UI")
        precondition(RemoteCampaignStore(defaults: defaults).campaigns.isEmpty)
        print("Remote campaign tests passed: scoped matching, boundaries, countdown, parsing, cache, kill switch.")
    }
}
