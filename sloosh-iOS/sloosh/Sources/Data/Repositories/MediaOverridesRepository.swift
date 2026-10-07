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

    private init() {
        loadFromCache()
        Task {
            await fetchOverrides()
        }
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
            // Очищаем устаревшие зашитые системные сиды, если они присутствовали
            self.overrides = cached.filter { $0.value.updatedBy != "system" }
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

    // MARK: - Resolution Lookup

    nonisolated public func override(for rawId: String?, tmdbId: Int? = nil, kpId: Int? = nil) -> MediaArtworkOverride? {
        Self.lock.withLock {
            let map = Self.threadSafeOverrides
            // 1. Direct raw ID match (e.g. "kp_12345", "67890")
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

    // MARK: - Dedicated Backend API Sync (sloosh-api)

    public func fetchOverrides() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let envelope = try await MoviesApi.shared.getMediaOverrides()
            if let dict = envelope.data {
                for (k, v) in dict {
                    self.overrides[k] = v
                    if let tmdb = v.tmdbId, tmdb > 0 {
                        self.overrides["\(tmdb)"] = v
                        self.overrides["tmdb_\(tmdb)"] = v
                    }
                    if let kp = v.kpId, kp > 0 {
                        self.overrides["\(kp)"] = v
                        self.overrides["kp_\(kp)"] = v
                    }
                }
                saveToCache()
                AppDiagnostics.shared.log("MediaOverridesRepository: synchronized \(dict.count) overrides from backend")
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
        backdropUrl: String? = nil,
        backdropUrls: [String]? = nil
    ) async throws {
        let item = MediaArtworkOverride(
            mediaId: mediaId,
            kpId: kpId,
            tmdbId: tmdbId,
            title: title,
            posterUrl: posterUrl,
            logoUrl: logoUrl,
            backdropUrl: backdropUrl,
            backdropUrls: backdropUrls,
            updatedAt: Date().timeIntervalSince1970,
            updatedBy: AuthRepository.shared.currentUser?.displayName ?? "admin"
        )

        // 1. Немедленно обновляем локальный кэш для мгновенного отклика UI
        self.overrides[mediaId] = item
        if let tmdb = tmdbId, tmdb > 0 {
            self.overrides["\(tmdb)"] = item
            self.overrides["tmdb_\(tmdb)"] = item
        }
        if let kp = kpId, kp > 0 {
            self.overrides["kp_\(kp)"] = item
            self.overrides["\(kp)"] = item
        }
        saveToCache()

        // 2. Отправляем на бэкенд sloosh-api (который инвалидирует кэш и сохраняет изменения)
        _ = try await MoviesApi.shared.saveMediaOverride(item)

        AppDiagnostics.shared.log("MediaOverridesRepository: saved override to backend for mediaId=\(mediaId)")
    }

    public func deleteOverride(mediaId: String, kpId: Int? = nil, tmdbId: Int? = nil) async throws {
        // 1. Удаляем из локального кэша
        self.overrides.removeValue(forKey: mediaId)
        if let tmdb = tmdbId, tmdb > 0 {
            self.overrides.removeValue(forKey: "\(tmdb)")
            self.overrides.removeValue(forKey: "tmdb_\(tmdb)")
        }
        if let kp = kpId, kp > 0 {
            self.overrides.removeValue(forKey: "kp_\(kp)")
            self.overrides.removeValue(forKey: "\(kp)")
        }
        saveToCache()

        // 2. Удаляем на бэкенде sloosh-api
        _ = try await MoviesApi.shared.deleteMediaOverride(id: mediaId)
        if let tmdb = tmdbId, tmdb > 0, "\(tmdb)" != mediaId {
            _ = try? await MoviesApi.shared.deleteMediaOverride(id: "\(tmdb)")
        }
        if let kp = kpId, kp > 0, "kp_\(kp)" != mediaId {
            _ = try? await MoviesApi.shared.deleteMediaOverride(id: "kp_\(kp)")
        }

        AppDiagnostics.shared.log("MediaOverridesRepository: deleted override on backend for mediaId=\(mediaId)")
    }
}
