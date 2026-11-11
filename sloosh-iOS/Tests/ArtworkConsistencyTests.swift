import Foundation

/// Real production reducer, identity resolver, revision URL and image request policy.
enum ArtworkConsistencyTests {
    static func run() throws -> Int {
        var count = 0
        func check(_ value: Bool, _ message: String) { precondition(value, message); count += 1 }
        let movie = MediaArtworkOverride(mediaId: "movie_42", kpId: 100, tmdbId: 42, posterUrl: "https://example.com/movie.jpg", updatedAt: 1)
        let tv = MediaArtworkOverride(mediaId: "tv_42", kpId: 200, tmdbId: 42, posterUrl: "https://example.com/tv.jpg", updatedAt: 2)
        let legacy = MediaArtworkOverride(mediaId: "42", kpId: 100, tmdbId: 42, posterUrl: "https://example.com/legacy.jpg", updatedAt: 0)
        var store = ArtworkOverrideStore(records: ["movie_42": movie, "tv_42": tv, "42": legacy, "tmdb_42": movie])
        check(store.records.count == 3, "Synthetic aliases do not create extra records")
        check(ArtworkOverrideStore.resolve(Array(store.records.values), id: "42", type: "movie", kpId: nil) == movie, "Typed favorite selects film")
        check(ArtworkOverrideStore.resolve(Array(store.records.values), id: "42", type: "tv", kpId: nil) == tv, "Same-number series has independent artwork")
        check(ArtworkOverrideStore.resolve([legacy], id: "42", type: "tv", kpId: nil) == nil, "Legacy numeric alias cannot prove type")
        check(ArtworkOverrideStore.resolve([movie], id: "tv_42", type: "tv", kpId: 100) == nil, "Explicit type disagreement wins over a bad external alias")
        check(ArtworkOverrideStore.resolve([legacy], id: "movie_42", type: "movie", kpId: 100) == legacy, "Proven external identity preserves safe old curator edits")
        check(store.sourceKeys(matching: CatalogArtworkIdentity(id: "movie_42", type: nil)!, kpId: 100).count == 3,
              "Reset targets proven aliases without guessing another title's number")
        check(store.apply(event: "put", payload: #"{"path":"/tv_42","data":null}"#), "SSE record deletion accepted")
        check(store.records["tv_42"] == nil, "Deleted record is gone, not retained under an alias")
        store.apply(event: "put", payload: #"{"path":"/","data":{"movie_7":{"posterUrl":"https://example.com/7.jpg","updatedAt":3}}}"#)
        check(store.records.count == 1 && store.records["movie_7"]?.mediaId == "movie_7", "Root snapshot replaces old records and missing IDs use source key")
        store.apply(event: "patch", payload: #"{"path":"/movie_7","data":{"posterUrl":"https://example.com/new.jpg","logoUrl":"https://example.com/logo.png"}}"#)
        check(store.records["movie_7"]?.posterUrl?.hasSuffix("new.jpg") == true && store.records["movie_7"]?.logoUrl != nil, "Field patch merges with identity metadata")
        store.apply(event: "put", payload: #"{"path":"/movie_7/logoUrl","data":null}"#)
        check(store.records["movie_7"]?.logoUrl == nil && store.records["movie_7"]?.posterUrl != nil, "Nested deletion removes only the field")
        store.apply(event: "patch", payload: #"{"path":"/","data":{"movie_7/posterUrl":"https://example.com/latest.jpg","movie_8":{"mediaId":"movie_8","posterUrl":"https://example.com/8.jpg"}}}"#)
        check(store.records.count == 2 && store.records["movie_7"]?.posterUrl?.hasSuffix("latest.jpg") == true, "Root multi-path patch is supported")
        store.apply(event: "put", payload: #"{"path":"/","data":null}"#)
        check(store.records.isEmpty, "Empty authoritative snapshot clears the last deletion")
        check(!store.apply(event: "keep-alive", payload: "null"), "Heartbeat is not a destructive snapshot")
        var oldAliases = ArtworkOverrideStore(records: ["42": movie, "movie_42": movie])
        oldAliases.remove(keys: oldAliases.sourceKeys(matching: CatalogArtworkIdentity(id: "movie_42", type: nil)!, kpId: 100))
        check(oldAliases.records.isEmpty, "Reset deletes all proven duplicates")
        var revised = movie
        revised.updatedAt = 10
        let url = revised.artworkURL("https://example.com/a.jpg?token=keep&size=large#preview")!
        let components = URLComponents(string: url)!
        check(components.queryItems?.contains(URLQueryItem(name: "token", value: "keep")) == true && components.fragment == "preview", "Revision preserves existing queries and fragment")
        check(components.queryItems?.first { $0.name == "sloosh_artwork_rev" }?.value == "10.0", "Exact revision reaches request identity")
        revised.updatedAt = 11
        check(revised.artworkURL(url) != url, "Same URL re-selection creates a new cache key")
        check(URLComponents(string: revised.artworkURL(url)!)?.queryItems?.filter { $0.name == "sloosh_artwork_rev" }.count == 1, "Version query is idempotent, not accumulated")
        let a = URL(string: "https://example.com/a.jpg")!, b = URL(string: "https://example.com/b.jpg")!
        let request = ImageRequestIdentity(primary: a, fallback: b, policy: 0, revision: 0)
        for other in [ImageRequestIdentity(primary: b, fallback: b, policy: 0, revision: 0),
                      ImageRequestIdentity(primary: a, fallback: a, policy: 0, revision: 0),
                      ImageRequestIdentity(primary: a, fallback: b, policy: 1, revision: 0),
                      ImageRequestIdentity(primary: a, fallback: b, policy: 0, revision: 1)] {
            check(request != other, "Primary/fallback/policy/revision changes replace image state")
        }
        let now = Date(timeIntervalSince1970: 1_000)
        var failure = ImageFailureBackoff()
        failure.insert(a.absoluteString, at: now)
        check(failure.contains(a.absoluteString, at: now.addingTimeInterval(30)), "Brief 404 suppression avoids a request storm")
        check(!failure.contains(a.absoluteString, at: now.addingTimeInterval(61)), "An image 404 cannot poison the cache forever")
        check(!failure.contains(b.absoluteString, at: now), "Different asset is not poisoned")
        failure.insert(a.absoluteString, at: now); failure.clear()
        check(!failure.contains(a.absoluteString, at: now), "Manual cache clearing resets failures")
        return count
    }
}
