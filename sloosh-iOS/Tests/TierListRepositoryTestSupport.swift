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
    var isAdmin = false
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
                let sent = try JSONDecoder().decode(Int.self, from: requestBody(request))
                precondition(sent == value + repoCounterDirection(writes: writes))
                value = sent
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
        list.likesCount = 10; list.viewsCount = 20
        TierTestURLProtocol.handle = { request in
            if request.httpMethod == "GET" {
                return (200, ["ETag": "\"publication\""], try JSONSerialization.data(withJSONObject: list.publishDocument))
            }
            publicationMethod = request.httpMethod
            let sent = try JSONSerialization.jsonObject(with: requestBody(request)) as! [String: Any]
            precondition((sent["likesCount"] as? Int) == 10 && (sent["viewsCount"] as? Int) == 20)
            precondition(request.value(forHTTPHeaderField: "if-match") == "\"publication\"")
            return (200, [:], Data("null".utf8))
        }
        let saved = try await repo.publish(list)
        check(saved?.id == "published_id" && publicationMethod == "PUT", "A locally saved edit updates its published ID, never creates a duplicate")

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
        count += try await templateTests(repo)
        return count
    }

    @MainActor
    private static func templateTests(_ repo: TierListsRepository) async throws -> Int {
        var count = 0
        func check(_ value: Bool, _ message: String) { precondition(value, message); count += 1 }
        let items = (1...4).map { TierListItem(mediaId: "movie_\($0)", mediaType: "movie", title: "Film \($0)", year: nil, posterUrl: "https://example.com/\($0).jpg") }
        let template = TierTemplate(id: "test-template", title: "Original", subtitle: "Description", priority: 5, items: items)
        var remote: [String: Any]?
        var revision = 0
        var failWrite: Int?
        var writes = 0
        var requests = 0
        TierTestURLProtocol.handle = { request in
            requests += 1
            if request.url!.path == "/tier_templates.json" {
                return (200, [:], try JSONSerialization.data(withJSONObject: remote.map { [template.id: $0] } ?? [:]))
            }
            if request.httpMethod == "GET" {
                return (200, ["ETag": "\"template-\(revision)\""], try JSONSerialization.data(withJSONObject: remote as Any? ?? NSNull(), options: [.fragmentsAllowed]))
            }
            writes += 1
            precondition(request.value(forHTTPHeaderField: "if-match") == "\"template-\(revision)\"")
            if let failWrite { return (failWrite, [:], Data()) }
            if request.httpMethod == "DELETE" { remote = nil }
            else {
                remote = try JSONSerialization.jsonObject(with: requestBody(request)) as? [String: Any]
                precondition(remote?["id"] == nil && remote?["rows"] == nil)
            }
            revision += 1
            return (200, [:], Data("null".utf8))
        }
        AuthRepository.shared.isAdmin = false
        do { try await repo.saveTemplate(template, expected: nil); preconditionFailure("Non-admin wrote a template") }
        catch { check(requests == 0, "Client gates template writes before transport; Firebase still enforces admin rules") }
        AuthRepository.shared.isAdmin = true
        defer { AuthRepository.shared.isAdmin = false }
        try await repo.saveTemplate(template, expected: nil)
        check(repo.templates == [template] && writes == 1, "Create publishes only after checked durable success")
        let userDraft = repo.makeDraft(from: template)
        var edited = template
        edited.title = "Edited"; edited.items.reverse(); edited.subtitle = nil
        try await repo.saveTemplate(edited, expected: template)
        check(repo.templates == [edited] && remote?["subtitle"] == nil, "Edit persists title, poster order and description removal")
        check(userDraft.unranked == template.items && userDraft.title == template.title, "Template edit never rewrites existing user drafts")
        let previousWrites = writes
        do { try await repo.saveTemplate(template, expected: template); preconditionFailure("Stale template overwrote another admin") }
        catch { check(writes == previousWrites, "Stale original fails before mutation") }
        failWrite = 403
        do { try await repo.saveTemplate(template, expected: edited); preconditionFailure("Denied save reported success") }
        catch { check(repo.templates == [edited], "Denied save retains confirmed local state") }
        failWrite = 412
        do { try await repo.deleteTemplate(edited); preconditionFailure("Conflicting delete reported success") }
        catch { check(repo.templates == [edited], "Conditional delete conflict retains template") }
        failWrite = nil
        try await repo.deleteTemplate(edited)
        check(repo.templates.isEmpty && remote == nil, "Successful deletion updates gallery cache")
        do { try await repo.saveTemplate(edited, expected: edited); preconditionFailure("Deleted template resurrected") }
        catch { check(remote == nil, "Deleted original cannot be silently recreated") }
        var invalid = template; invalid.items.removeLast()
        let beforeInvalid = requests
        do { try await repo.saveTemplate(invalid, expected: nil); preconditionFailure("Invalid template saved") }
        catch { check(requests == beforeInvalid, "Four-film minimum is checked before network") }
        TierTestURLProtocol.handle = { _ in (200, [:], Data("null".utf8)) }
        _ = await repo.fetchTemplates(force: true)
        check(repo.templates.isEmpty && repo.templatesError == nil, "Root null is authoritative empty templates")
        TierTestURLProtocol.handle = { _ in (403, [:], Data()) }
        _ = await repo.fetchTemplates(force: true)
        check(repo.templatesError != nil, "Template read errors are visible, not endless loading")
        var indexFallbackCalls = 0
        var source = repo.makeDraft(title: "Fallback")
        source.rows[0].items = items
        TierTestURLProtocol.handle = { request in
            indexFallbackCalls += 1
            let order = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "orderBy" }?.value
            if order == "\"createdAtMs\"" { return (400, [:], Data(#"{"error":"Index not defined, add .indexOn"}"#.utf8)) }
            precondition(order == "\"$key\"")
            return (200, [:], try JSONSerialization.data(withJSONObject: ["fallback": source.publishDocument]))
        }
        let feed = await repo.fetchPublicLists(force: true)
        check(feed.count == 1 && indexFallbackCalls == 2 && repo.lastError == nil, "Missing Firebase date index falls back to key paging rather than breaking gallery")
        return count
    }

    private static func requestBody(_ request: URLRequest) throws -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { throw URLError(.zeroByteResource) }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 2048)
        while true {
            let size = stream.read(&buffer, maxLength: buffer.count)
            if size < 0 { throw URLError(.cannotDecodeRawData) }
            if size == 0 { break }
            data.append(contentsOf: buffer.prefix(size))
        }
        return data
    }

    private static func repoCounterDirection(writes: Int) -> Int { writes <= 2 ? 1 : -1 }
}
