import Foundation
import SwiftUI

struct TierTestUser {
    var id: String
    var isAnonymous = false
    var displayName: String? = "Test"
    var email: String? = nil
    var tag: String? = nil
    var photoURL: String? = nil
}

@MainActor
final class AuthRepository {
    static let shared = AuthRepository()
    @Published var currentUser: TierTestUser? = TierTestUser(id: "alice")
    func ensureFreshToken() async -> String? { "unit-test-token" }
}

final class TierTestURLProtocol: URLProtocol {
    static var handle: ((URLRequest) throws -> (Int, [String: String], Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handle = Self.handle else { throw URLError(.badServerResponse) }
            let (code, headers, body) = try handle(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

enum TierListRepositoryTests {
    @MainActor
    static func run() async throws -> Int {
        let suite = "sloosh.tier.network.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite); TierTestURLProtocol.handle = nil }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TierTestURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let repo = TierListsRepository(session: session, defaults: defaults)
        var count = 0
        func check(_ value: Bool, _ message: String) { precondition(value, message); count += 1 }
        var list = repo.makeDraft(title: "Test")
        list.unranked = [TierListItem(mediaId: "movie_1", mediaType: "movie", title: "Movie", year: nil, posterUrl: nil)]

        var value = 5
        var conflict = true
        var writes = 0
        TierTestURLProtocol.handle = { request in
            if request.url!.path.hasSuffix("likesCount.json") {
                if request.httpMethod == "GET" {
                    return (200, ["ETag": "\"v\(value)\""], Data("\(value)".utf8))
                }
                writes += 1
                if conflict { conflict = false; value += 1; return (412, [:], Data()) }
                precondition(request.value(forHTTPHeaderField: "if-match") == "\"v\(value)\"")
                // URLProtocol may expose an HTTP body stream rather than httpBody;
                // verify the resulting value on the next read instead of reading it.
                value += repoCounterDirection(writes: writes)
                return (200, [:], Data("\(value)".utf8))
            }
            return (200, [:], Data("null".utf8))
        }
        let liked = try await repo.toggleLike(list)
        check(liked.isLiked && liked.likesCount == 7 && writes == 2, "Counter retries a 412 using the fresh ETag, preserving the other writer")
        check(repo.isLiked(list.id), "Like state commits only after durable marker and counter")
        let unliked = try await repo.toggleLike(list)
        check(!unliked.isLiked && unliked.likesCount == 6, "Unlike decrements without losing concurrent count")
        TierTestURLProtocol.handle = { _ in (403, [:], Data()) }
        do { _ = try await repo.toggleLike(list); preconditionFailure("Failed writes must propagate") }
        catch { check(!repo.isLiked(list.id), "Failed like is not persisted locally") }

        var publicationMethod: String?
        list.id = "published_id"; list.isDraft = true
        TierTestURLProtocol.handle = { request in
            publicationMethod = request.httpMethod
            return (200, [:], Data("null".utf8))
        }
        let saved = try await repo.publish(list)
        check(saved?.id == "published_id" && publicationMethod == "PATCH", "A locally saved edit updates its published ID, never creates a duplicate")

        var pages = 0
        TierTestURLProtocol.handle = { request in
            pages += 1
            let cursor = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "startAt" }?.value
            let start = cursor == nil ? 0 : 200
            let end = cursor == nil ? 201 : 205
            var documents: [String: Any] = [:]
            for i in start..<end {
                var entry = list
                entry.authorId = i == 204 ? "bob" : "alice"
                documents[String(format: "id_%03d", i)] = entry.publishDocument
            }
            return (200, [:], try JSONSerialization.data(withJSONObject: documents))
        }
        let mine = await repo.fetchLists(forAuthorId: "alice")
        check(pages == 2 && mine.count == 204, "Author history spans global pages, filters other authors and removes inclusive cursor duplicate")

        TierTestURLProtocol.handle = { _ in (200, [:], Data("null".utf8)) }
        let empty = await repo.fetchPublicLists(force: true)
        check(empty.isEmpty && repo.publicLists.isEmpty, "Authoritative null feed clears cached ghosts")
        AuthRepository.shared.currentUser = TierTestUser(id: "bob")
        check(!repo.isLiked(list.id), "Social state is isolated after an account switch")
        AuthRepository.shared.currentUser = TierTestUser(id: "alice")
        return count
    }

    private static func repoCounterDirection(writes: Int) -> Int { writes <= 2 ? 1 : -1 }
}
