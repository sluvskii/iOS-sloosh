import Foundation
import SwiftUI
import Combine

public extension Notification.Name {
    static let mediaArtworkOverridesDidChange = Notification.Name("sloosh_media_artwork_overrides_did_change")
}

@MainActor
public final class MediaOverridesRepository: ObservableObject {
    public static let shared = MediaOverridesRepository()

    @Published public private(set) var overrides: [String: MediaArtworkOverride] = [:]
    @Published public private(set) var isLoading: Bool = false

    private let cacheKey = "sloosh_media_artwork_overrides"
    private let databaseBaseURL = "https://sloosh-77434-default-rtdb.firebaseio.com/mediaOverrides"

    // MARK: - Built-in Flagship Overrides
    // "Сокол и Зимний Солдат" (TMDB 88396 / KP 1236041) — эталонная белая версия логотипа вместо тёмной
    private static let falconWhiteLogoUrl = "https://api.sloosh.workers.dev/api/v1/images/tmdb/original/wdeUFbBoznI6G8cnA4tJTc5J7QV.png"

    private init() {
        loadFromCache()
        seedDefaultsIfNeeded()
    }

    // MARK: - In-Memory & Local Cache

    private static let lock = NSLock()
    nonisolated(unsafe) private static var threadSafeOverrides: [String: MediaArtworkOverride] = [:]

    private func syncThreadSafe() {
        Self.lock.withLock {
            Self.threadSafeOverrides = self.overrides
        }
    }

    private func loadFromCache() {
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode([String: MediaArtworkOverride].self, from: data) {
            self.overrides = cached
        }
        syncThreadSafe()
    }

    private func saveToCache() {
        if let data = try? JSONEncoder().encode(overrides) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
        syncThreadSafe()
        NotificationCenter.default.post(name: .mediaArtworkOverridesDidChange, object: nil)
    }

    private func seedDefaultsIfNeeded() {
        let falconSeed = MediaArtworkOverride(
            mediaId: "88396",
            kpId: 1236041,
            tmdbId: 88396,
            title: "Сокол и Зимний Солдат",
            logoUrl: Self.falconWhiteLogoUrl,
            updatedAt: 1728312000,
            updatedBy: "system"
        )

        var changed = false
        for key in ["88396", "kp_1236041", "1236041"] {
            if overrides[key] == nil {
                overrides[key] = falconSeed
                changed = true
            }
        }
        if changed {
            saveToCache()
        }
    }

    // MARK: - Resolution Lookup

    nonisolated public func override(for rawId: String?, tmdbId: Int? = nil, kpId: Int? = nil) -> MediaArtworkOverride? {
        Self.lock.withLock {
            let map = Self.threadSafeOverrides
            // 1. Direct raw ID match (e.g. "kp_1236041", "88396")
            if let rawId = rawId, !rawId.isEmpty {
                if let found = map[rawId] { return found }
                let clean = rawId.replacingOccurrences(of: "kp_", with: "").replacingOccurrences(of: "tmdb_", with: "")
                if let found = map[clean] { return found }
            }

            // 2. TMDB ID match
            if let tmdbId = tmdbId, tmdbId > 0 {
                if let found = map["\(tmdbId)"] ?? map["tmdb_\(tmdbId)"] {
                    return found
                }
            }

            // 3. Kinopoisk ID match
            if let kpId = kpId, kpId > 0 {
                if let found = map["kp_\(kpId)"] ?? map["\(kpId)"] {
                    return found
                }
            }

            return nil
        }
    }

    // MARK: - Cloud Sync (Firebase Realtime Database)

    private func makeURL(path: String = "") async -> URL? {
        let cleanPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let urlString: String
        if cleanPath.isEmpty {
            urlString = "\(databaseBaseURL).json"
        } else {
            let safe = cleanPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? cleanPath
            urlString = "\(databaseBaseURL)/\(safe).json"
        }

        var fullUrl = urlString
        if let token = await AuthRepository.shared.ensureFreshToken(), !token.isEmpty {
            fullUrl += "?auth=\(token)"
        }
        return URL(string: fullUrl)
    }

    public func fetchOverrides() async {
        guard let url = await makeURL() else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 10.0

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                return
            }

            if data.isEmpty || String(data: data, encoding: .utf8) == "null" {
                return
            }

            if let dict = try? JSONDecoder().decode([String: MediaArtworkOverride].self, from: data) {
                for (k, v) in dict {
                    self.overrides[k] = v
                }
                saveToCache()
                AppDiagnostics.shared.log("MediaOverridesRepository: synchronized \(dict.count) overrides from cloud")
            }
        } catch {
            AppDiagnostics.shared.log("MediaOverridesRepository fetch error: \(error.localizedDescription)")
        }
    }

    // MARK: - Save & Delete Overrides

    public func saveOverride(
        mediaId: String,
        kpId: Int? = nil,
        tmdbId: Int? = nil,
        title: String? = nil,
        posterUrl: String? = nil,
        logoUrl: String? = nil,
        backdropUrl: String? = nil
    ) async throws {
        let item = MediaArtworkOverride(
            mediaId: mediaId,
            kpId: kpId,
            tmdbId: tmdbId,
            title: title,
            posterUrl: posterUrl,
            logoUrl: logoUrl,
            backdropUrl: backdropUrl,
            updatedAt: Date().timeIntervalSince1970,
            updatedBy: AuthRepository.shared.currentUser?.displayName ?? "admin"
        )

        // 1. Update local cache immediately
        self.overrides[mediaId] = item
        if let tmdb = tmdbId, "\(tmdb)" != mediaId {
            self.overrides["\(tmdb)"] = item
        }
        if let kp = kpId, "kp_\(kp)" != mediaId {
            self.overrides["kp_\(kp)"] = item
            self.overrides["\(kp)"] = item
        }
        saveToCache()

        // 2. Push to Firebase RTDB
        let data = try JSONEncoder().encode(item)
        var keysToPush = [mediaId]
        if let tmdb = tmdbId, "\(tmdb)" != mediaId { keysToPush.append("\(tmdb)") }
        if let kp = kpId, "kp_\(kp)" != mediaId { keysToPush.append("kp_\(kp)") }

        for key in keysToPush {
            if let url = await makeURL(path: key) {
                var request = URLRequest(url: url)
                request.httpMethod = "PUT"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = data
                _ = try? await URLSession.shared.data(for: request)
            }
        }

        AppDiagnostics.shared.log("MediaOverridesRepository: saved override for mediaId=\(mediaId)")
    }

    public func deleteOverride(mediaId: String, kpId: Int? = nil, tmdbId: Int? = nil) async throws {
        // 1. Remove from local cache
        self.overrides.removeValue(forKey: mediaId)
        if let tmdb = tmdbId {
            self.overrides.removeValue(forKey: "\(tmdb)")
            self.overrides.removeValue(forKey: "tmdb_\(tmdb)")
        }
        if let kp = kpId {
            self.overrides.removeValue(forKey: "kp_\(kp)")
            self.overrides.removeValue(forKey: "\(kp)")
        }
        saveToCache()

        // 2. Remove from Firebase RTDB
        var keysToDelete = [mediaId]
        if let tmdb = tmdbId, "\(tmdb)" != mediaId { keysToDelete.append("\(tmdb)") }
        if let kp = kpId, "kp_\(kp)" != mediaId { keysToDelete.append("kp_\(kp)") }

        for key in keysToDelete {
            if let url = await makeURL(path: key) {
                var request = URLRequest(url: url)
                request.httpMethod = "DELETE"
                _ = try? await URLSession.shared.data(for: request)
            }
        }

        AppDiagnostics.shared.log("MediaOverridesRepository: deleted override for mediaId=\(mediaId)")
    }
}
