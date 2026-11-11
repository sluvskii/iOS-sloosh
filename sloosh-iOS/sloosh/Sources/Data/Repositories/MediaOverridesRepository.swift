import Foundation
import SwiftUI
import Combine
import UIKit

public extension Notification.Name {
    static let mediaArtworkOverridesDidChange = Notification.Name("sloosh_media_artwork_overrides_did_change")
    static let posterQualityDidChange = Notification.Name("sloosh_poster_quality_did_change")
    static let useLogosInCatalogDidChange = Notification.Name("sloosh_use_logos_in_catalog_did_change")
}

@MainActor
public final class MediaOverridesRepository: ObservableObject {
    public static let shared = MediaOverridesRepository()
    @Published public private(set) var overrides: [String: MediaArtworkOverride] = [:]
    @Published public private(set) var isLoading = false
    private let cacheKey = "sloosh_media_artwork_overrides"
    private let firebaseOverridesUrl = "https://sloosh-77434-default-rtdb.firebaseio.com/media_stats/media_artwork_overrides"
    private var store = ArtworkOverrideStore()
    private var generation = 0
    private var isWriting = false
    private var streamTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private static let lock = NSLock()
    nonisolated(unsafe) private static var threadSafeOverrides: [String: MediaArtworkOverride] = [:]

    private init() {
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode([String: MediaArtworkOverride].self, from: data) {
            store = ArtworkOverrideStore(records: cached)
            publish()
        }
        Task { await fetchOverrides(); startRealtimeStream() }
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                await self?.fetchOverrides()
            }
        }
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { await self?.fetchOverrides(); self?.startRealtimeStream() }
            }.store(in: &cancellables)
    }

    private func publish() {
        let next = store.records
        guard next != overrides else { return }
        // Update nonisolated readers before publishing objectWillChange.
        Self.lock.withLock { Self.threadSafeOverrides = next }
        overrides = next
        CatalogLogoRepository.shared.invalidate()
        if let data = try? JSONEncoder().encode(next) { UserDefaults.standard.set(data, forKey: cacheKey) }
        NotificationCenter.default.post(name: .mediaArtworkOverridesDidChange, object: nil)
    }

    nonisolated func catalogOverride(id: String?, type: String?, kpId: Int?) -> MediaArtworkOverride? {
        override(for: id, kpId: kpId, type: type)
    }

    nonisolated public func override(for rawId: String?, tmdbId: Int? = nil, kpId: Int? = nil, type: String? = nil) -> MediaArtworkOverride? {
        Self.lock.withLock {
            ArtworkOverrideStore.resolve(Array(Self.threadSafeOverrides.values), id: rawId, type: type, tmdbId: tmdbId, kpId: kpId)
        }
    }

    private func firebaseRequest(path: String = "", method: String = "GET", body: Data? = nil) async throws -> URLRequest {
        var components = URLComponents(string: firebaseOverridesUrl + path + ".json")!
        if let token = await AuthRepository.shared.ensureFreshToken(), !token.isEmpty {
            components.queryItems = [URLQueryItem(name: "auth", value: token)]
        } else if method != "GET" { throw URLError(.userAuthenticationRequired) }
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 8
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func checkedData(for request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            let message = http.statusCode == 401 || http.statusCode == 403
                ? "Нет доступа к изменению оформления. Войдите в аккаунт администратора и повторите попытку."
                : "Сервис оформления временно недоступен. Повторите попытку позже."
            throw NSError(domain: "sloosh.artwork", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
        }
        return data
    }

    public func fetchOverrides() async {
        guard !isLoading, !isWriting else { return }
        isLoading = true
        defer { isLoading = false }
        let started = generation
        var snapshot: ArtworkOverrideStore?
        // Read the durable source first. Empty/null is a successful snapshot, not
        // a reason to resurrect stale cache/backend records or upload local ghosts.
        do {
            let request = try await firebaseRequest()
            let data = try await checkedData(for: request)
            snapshot = try ArtworkOverrideStore(data: data)
        } catch {
            do {
                let response = try await MoviesApi.shared.getMediaOverrides()
                if response.success != false, let records = response.data { snapshot = ArtworkOverrideStore(records: records) }
            } catch { AppDiagnostics.shared.log("Artwork snapshot unavailable; retaining last confirmed state") }
        }
        guard let snapshot, started == generation, !isWriting else { return }
        store = snapshot
        publish()
    }

    private func startRealtimeStream() {
        streamTask?.cancel()
        streamTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    var request = try await self.firebaseRequest()
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.timeoutInterval = 300
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
                    var event = ""
                    for try await line in bytes.lines {
                        guard !Task.isCancelled else { return }
                        if line.hasPrefix("event:") { event = line.dropFirst(6).trimmingCharacters(in: .whitespaces) }
                        else if line.hasPrefix("data:"), !self.isWriting {
                            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                            if self.store.apply(event: event, payload: payload) {
                                self.generation += 1
                                self.publish()
                            }
                        }
                    }
                } catch { /* Reconnect without logging authenticated URLs. */ }
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
            }
        }
    }

    public func saveOverride(mediaId: String, mediaType: String? = nil, kpId: Int? = nil, tmdbId: Int? = nil,
                             title: String? = nil, posterUrl: String? = nil, textlessPosterUrl: String? = nil,
                             logoUrl: String? = nil, backdropUrl: String? = nil, backdropUrls: [String]? = nil) async throws {
        guard AuthRepository.shared.isAdmin else { throw URLError(.userAuthenticationRequired) }
        guard !isWriting else { throw URLError(.resourceUnavailable) }
        guard let identity = CatalogArtworkIdentity(id: mediaId, type: mediaType) else { throw URLError(.badURL) }
        isWriting = true
        generation += 1
        defer { isWriting = false; generation += 1; startRealtimeStream() }
        let item = MediaArtworkOverride(mediaId: identity.requestId, mediaType: identity.mediaType, kpId: kpId, tmdbId: tmdbId,
                                        title: title, posterUrl: posterUrl, textlessPosterUrl: textlessPosterUrl,
                                        logoUrl: logoUrl, backdropUrl: backdropUrl, backdropUrls: backdropUrls,
                                        updatedAt: Date().timeIntervalSince1970,
                                        updatedBy: AuthRepository.shared.currentUser?.displayName ?? "admin")
        let body = try JSONEncoder().encode(item)
        let request = try await firebaseRequest(path: "/\(identity.requestId)", method: "PUT", body: body)
        _ = try await checkedData(for: request)
        // No optimistic success: publish only after durable HTTP success.
        store.put(item)
        publish()
        do { _ = try await MoviesApi.shared.saveMediaOverride(item) }
        catch { AppDiagnostics.shared.log("Artwork saved durably; backend cache refresh pending") }
    }

    public func deleteOverride(mediaId: String, mediaType: String? = nil, kpId: Int? = nil, tmdbId: Int? = nil) async throws {
        guard AuthRepository.shared.isAdmin else { throw URLError(.userAuthenticationRequired) }
        guard !isWriting else { throw URLError(.resourceUnavailable) }
        guard let identity = CatalogArtworkIdentity(id: mediaId, type: mediaType) else { throw URLError(.badURL) }
        isWriting = true
        generation += 1
        defer { isWriting = false; generation += 1; startRealtimeStream() }
        // Remove every proven source key atomically, never guessed numeric aliases.
        let keys = Set(store.sourceKeys(matching: identity, kpId: kpId) + [identity.requestId])
        let patch = Dictionary(uniqueKeysWithValues: keys.map { ($0, NSNull()) })
        let request = try await firebaseRequest(method: "PATCH", body: JSONSerialization.data(withJSONObject: patch))
        _ = try await checkedData(for: request)
        store.remove(keys: Array(keys))
        publish()
        for key in keys {
            do { _ = try await MoviesApi.shared.deleteMediaOverride(id: key) }
            catch { AppDiagnostics.shared.log("Artwork reset durably; backend cache refresh pending") }
        }
    }
}
