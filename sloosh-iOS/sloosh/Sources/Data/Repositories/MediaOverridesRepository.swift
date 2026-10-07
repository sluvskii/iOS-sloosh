import Foundation
import SwiftUI
import Combine
import UIKit

public extension Notification.Name {
    static let mediaArtworkOverridesDidChange = Notification.Name("sloosh_media_artwork_overrides_did_change")
}

@MainActor
public final class MediaOverridesRepository: ObservableObject {
    public static let shared = MediaOverridesRepository()

    @Published public private(set) var overrides: [String: MediaArtworkOverride] = [:]
    @Published public private(set) var isLoading: Bool = false

    private let cacheKey = "sloosh_media_artwork_overrides"
    private let firebaseOverridesUrl = "https://sloosh-77434-default-rtdb.firebaseio.com/media_stats/media_artwork_overrides"

    private var streamTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        loadFromCache()
        Task {
            await fetchOverrides()
            startRealtimeStream()
            startHeartbeat()
        }
        setupLifecycleObservers()
    }

    private func setupLifecycleObservers() {
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.fetchOverrides()
                    self?.startRealtimeStream()
                }
            }
            .store(in: &cancellables)
    }

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000) // Every 30 seconds
                if Task.isCancelled { break }
                await self?.fetchOverrides()
            }
        }
    }

    private func startRealtimeStream() {
        streamTask?.cancel()
        streamTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let url = URL(string: "\(self?.firebaseOverridesUrl ?? "https://sloosh-77434-default-rtdb.firebaseio.com/media_stats/media_artwork_overrides").json") else { break }
                var req = URLRequest(url: url)
                req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                req.timeoutInterval = 300

                do {
                    let (asyncBytes, response) = try await URLSession.shared.bytes(for: req)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                        try? await Task.sleep(nanoseconds: 5_000_000_000)
                        continue
                    }

                    var currentEvent = ""
                    for try await line in asyncBytes.lines {
                        if Task.isCancelled { break }
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.hasPrefix("event: ") {
                            currentEvent = String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespaces)
                        } else if trimmed.hasPrefix("data: ") {
                            let dataStr = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                            if currentEvent == "put" || currentEvent == "patch" {
                                await self?.handleStreamPayload(dataStr)
                            }
                        }
                    }
                } catch {
                    // Stream dropped or network switched
                }

                if Task.isCancelled { break }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    private func handleStreamPayload(_ jsonString: String) {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let path = json["path"] as? String else {
            return
        }

        let rawData = json["data"]

        if path == "/" {
            if let dict = rawData as? [String: Any] {
                if let encoded = try? JSONSerialization.data(withJSONObject: dict),
                   let items = try? JSONDecoder().decode([String: MediaArtworkOverride].self, from: encoded) {
                    for (k, v) in items {
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
                    AppDiagnostics.shared.log("MediaOverridesRepository: live SSE initial sync (\(items.count) items)")
                }
            } else if rawData == nil || (rawData is NSNull) {
                self.overrides.removeAll()
                saveToCache()
            }
        } else {
            let key = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !key.isEmpty else { return }

            if rawData == nil || (rawData is NSNull) {
                self.overrides.removeValue(forKey: key)
                self.overrides.removeValue(forKey: "tmdb_\(key)")
                self.overrides.removeValue(forKey: "kp_\(key)")
                saveToCache()
                AppDiagnostics.shared.log("MediaOverridesRepository: live SSE deleted \(key)")
            } else if let dict = rawData as? [String: Any] {
                var finalDict = dict
                if finalDict["mediaId"] == nil {
                    finalDict["mediaId"] = key
                }
                if let encoded = try? JSONSerialization.data(withJSONObject: finalDict),
                   let item = try? JSONDecoder().decode(MediaArtworkOverride.self, from: encoded) {
                    self.overrides[item.mediaId] = item
                    if let tmdb = item.tmdbId, tmdb > 0 {
                        self.overrides["\(tmdb)"] = item
                        self.overrides["tmdb_\(tmdb)"] = item
                    }
                    if let kp = item.kpId, kp > 0 {
                        self.overrides["\(kp)"] = item
                        self.overrides["kp_\(kp)"] = item
                    }
                    saveToCache()
                    AppDiagnostics.shared.log("MediaOverridesRepository: live SSE updated \(item.mediaId)")
                }
            }
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

    // MARK: - Dedicated Backend & Durable Store Sync

    public func fetchOverrides() async {
        isLoading = true
        defer { isLoading = false }

        var remoteMap: [String: MediaArtworkOverride] = [:]

        // 1. Пытаемся получить оверрайды с бэкенда sloosh-api
        do {
            let envelope = try await MoviesApi.shared.getMediaOverrides()
            if let dict = envelope.data, !dict.isEmpty {
                remoteMap = dict
            }
        } catch {
            AppDiagnostics.shared.log("MediaOverridesRepository fetch from backend error: \(error.localizedDescription)")
        }

        // 2. Если бэкенд вернул пустоту или упал, используем прямое подключение к Firebase RTDB
        if remoteMap.isEmpty {
            if let fbMap = await fetchDirectFromFirebase(), !fbMap.isEmpty {
                remoteMap = fbMap
                AppDiagnostics.shared.log("MediaOverridesRepository: fallback loaded \(fbMap.count) overrides directly from Firebase")
            }
        }

        // 3. Сохраняем полученные с сервера оверрайды в локальную базу
        var updated = false
        for (k, v) in remoteMap {
            self.overrides[k] = v
            if let tmdb = v.tmdbId, tmdb > 0 {
                self.overrides["\(tmdb)"] = v
                self.overrides["tmdb_\(tmdb)"] = v
            }
            if let kp = v.kpId, kp > 0 {
                self.overrides["\(kp)"] = v
                self.overrides["kp_\(kp)"] = v
            }
            updated = true
        }

        // 4. Авто-миграция локальных правок: если на этом устройстве сохранены оверрайды,
        // которых еще нет в удаленном хранилище (например, настроенные ранее администратором),
        // автоматически выгружаем их на бэкенд и в Firebase, чтобы они появились на других телефонах и Android!
        let missingOnRemote = self.overrides.values.filter { localItem in
            let id = localItem.mediaId
            return remoteMap[id] == nil && remoteMap["\(localItem.tmdbId ?? 0)"] == nil
        }
        if !missingOnRemote.isEmpty {
            AppDiagnostics.shared.log("MediaOverridesRepository: uploading \(missingOnRemote.count) local unpushed overrides to backend...")
            for item in missingOnRemote {
                _ = try? await MoviesApi.shared.saveMediaOverride(item)
                await pushDirectToFirebase(item)
            }
        }

        if updated || !missingOnRemote.isEmpty {
            saveToCache()
            AppDiagnostics.shared.log("MediaOverridesRepository: synchronized \(self.overrides.count) overrides successfully")
        }
    }

    private func fetchDirectFromFirebase() async -> [String: MediaArtworkOverride]? {
        guard let url = URL(string: "\(firebaseOverridesUrl).json") else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 4.0
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                return try? JSONDecoder().decode([String: MediaArtworkOverride].self, from: data)
            }
        } catch {
            // Firebase direct read failed
        }
        return nil
    }

    private func pushDirectToFirebase(_ item: MediaArtworkOverride) async {
        guard let cleanId = item.mediaId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(firebaseOverridesUrl)/\(cleanId).json") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 4.0
        if let body = try? JSONEncoder().encode(item) {
            req.httpBody = body
            _ = try? await URLSession.shared.data(for: req)
        }
    }

    private func deleteDirectFromFirebase(_ id: String) async {
        guard let cleanId = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(firebaseOverridesUrl)/\(cleanId).json") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.timeoutInterval = 4.0
        _ = try? await URLSession.shared.data(for: req)
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
        _ = try? await MoviesApi.shared.saveMediaOverride(item)

        // 3. Дублируем напрямую в постоянное хранилище Firebase RTDB для гарантированной сохранности
        await pushDirectToFirebase(item)

        AppDiagnostics.shared.log("MediaOverridesRepository: saved override persistently for mediaId=\(mediaId)")
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
        _ = try? await MoviesApi.shared.deleteMediaOverride(id: mediaId)
        if let tmdb = tmdbId, tmdb > 0, "\(tmdb)" != mediaId {
            _ = try? await MoviesApi.shared.deleteMediaOverride(id: "\(tmdb)")
        }
        if let kp = kpId, kp > 0, "kp_\(kp)" != mediaId {
            _ = try? await MoviesApi.shared.deleteMediaOverride(id: "kp_\(kp)")
        }

        // 3. Удаляем напрямую из постоянного хранилища Firebase RTDB
        await deleteDirectFromFirebase(mediaId)
        if let tmdb = tmdbId, tmdb > 0, "\(tmdb)" != mediaId {
            await deleteDirectFromFirebase("\(tmdb)")
        }
        if let kp = kpId, kp > 0, "kp_\(kp)" != mediaId {
            await deleteDirectFromFirebase("kp_\(kp)")
        }

        AppDiagnostics.shared.log("MediaOverridesRepository: deleted override persistently for mediaId=\(mediaId)")
    }
}
