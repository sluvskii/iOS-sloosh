import Foundation
import SwiftUI
import Combine

@MainActor
public final class CloudSyncService: ObservableObject {
    public static let shared = CloudSyncService()

    @Published public private(set) var isSyncing: Bool = false
    public private(set) var lastSyncDate: Date?

    private var lastSyncAttempt: Date = .distantPast
    private let minSyncInterval: TimeInterval = 30.0

    private let databaseBaseURL = "https://sloosh-77434-default-rtdb.firebaseio.com/users"

    private init() {}

    /// Запускает полную синхронизацию данных при входе в аккаунт или обновлении
    public func syncAllData(force: Bool = false) {
        Task {
            await syncAllDataAsync(force: force)
        }
    }

    public func syncAllDataAsync(force: Bool = false) async {
        guard AuthRepository.shared.isAuthenticated, let user = AuthRepository.shared.currentUser else { return }
        let now = Date()
        if !force && now.timeIntervalSince(lastSyncAttempt) < minSyncInterval {
            return
        }
        lastSyncAttempt = now

        // 1. Синхронизируем избранное с облаком Firebase
        if let remoteFavorites = await fetchRemoteFavorites(userId: user.id, idToken: user.idToken) {
            await FavoritesRepository.shared.syncRemoteFavoritesToLocal(remoteFavorites, userId: user.id)
        }

        // 2. Синхронизируем прогресс просмотров ("Продолжить смотреть") с облаком Firebase
        if let remoteProgress = await fetchRemoteProgress(userId: user.id, idToken: user.idToken) {
            await PlaybackProgressStore.shared.syncRemoteProgressToLocal(remoteProgress, userId: user.id)
        }

        // 3. Синхронизируем метаданные (постеры, названия) с облаком Firebase
        if let remoteMetadata = await fetchRemoteMetadata(userId: user.id, idToken: user.idToken) {
            await PlaybackProgressStore.shared.syncRemoteMetadataToLocal(remoteMetadata, userId: user.id)
        }

        // 4. Синхронизируем профиль пользователя для мессенджера
        await MessengerRepository.shared.syncCurrentUserProfile()
    }

    public func makeURL(path: String, idToken: String? = nil) async -> URL? {
        let safePath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        var urlString = "\(databaseBaseURL)/\(safePath).json"
        
        let token = await AuthRepository.shared.ensureFreshToken() ?? idToken
        if let token = token, !token.isEmpty {
            urlString += "?auth=\(token)"
        }
        return URL(string: urlString)
    }

    /// Загружает избранное аккаунта с сервера Firebase
    public func fetchRemoteFavorites(userId: String, idToken: String? = nil) async -> [FavoriteDto]? {
        guard !userId.isEmpty, userId != "guest" else { return nil }
        guard let url = await makeURL(path: "\(userId)/favorites", idToken: idToken) else { return nil }

        isSyncing = true
        defer { isSyncing = false }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 10.0

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                return nil
            }

            if data.isEmpty || String(data: data, encoding: .utf8) == "null" {
                return []
            }

            let favorites = try? JSONDecoder().decode([FavoriteDto].self, from: data)
            lastSyncDate = Date()
            AppDiagnostics.shared.log("CloudSyncService: fetched \(favorites?.count ?? 0) remote favorites for user \(userId)")
            return favorites
        } catch {
            AppDiagnostics.shared.log("CloudSyncService fetch error: \(error.localizedDescription)")
            return nil
        }
    }

    /// Сохраняет избранное аккаунта на сервер Firebase
    public func pushRemoteFavorites(_ favorites: [FavoriteDto], userId: String, idToken: String? = nil) async {
        guard !userId.isEmpty, userId != "guest" else { return }
        guard let url = await makeURL(path: "\(userId)/favorites", idToken: idToken) else { return }

        isSyncing = true
        defer { isSyncing = false }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "PUT"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(favorites)
            request.timeoutInterval = 10.0

            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) {
                lastSyncDate = Date()
                AppDiagnostics.shared.log("CloudSyncService: pushed \(favorites.count) favorites to cloud for user \(userId)")
            }
        } catch {
            AppDiagnostics.shared.log("CloudSyncService push error: \(error.localizedDescription)")
        }
    }

    /// Загружает прогресс просмотров ("Продолжить смотреть") с сервера Firebase
    public func fetchRemoteProgress(userId: String, idToken: String? = nil) async -> [PlaybackProgressRecord]? {
        guard !userId.isEmpty, userId != "guest" else { return nil }
        guard let url = await makeURL(path: "\(userId)/progress", idToken: idToken) else { return nil }

        isSyncing = true
        defer { isSyncing = false }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 10.0

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                return nil
            }

            if data.isEmpty || String(data: data, encoding: .utf8) == "null" {
                return []
            }

            let records = try? JSONDecoder().decode([PlaybackProgressRecord].self, from: data)
            lastSyncDate = Date()
            AppDiagnostics.shared.log("CloudSyncService: fetched \(records?.count ?? 0) remote progress records for user \(userId)")
            return records
        } catch {
            AppDiagnostics.shared.log("CloudSyncService fetch progress error: \(error.localizedDescription)")
            return nil
        }
    }

    /// Сохраняет прогресс просмотров ("Продолжить смотреть") на сервер Firebase
    public func pushRemoteProgress(_ records: [PlaybackProgressRecord], userId: String, idToken: String? = nil) async {
        guard !userId.isEmpty, userId != "guest" else { return }
        guard let url = await makeURL(path: "\(userId)/progress", idToken: idToken) else { return }

        isSyncing = true
        defer { isSyncing = false }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "PUT"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(records)
            request.timeoutInterval = 10.0

            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) {
                lastSyncDate = Date()
                AppDiagnostics.shared.log("CloudSyncService: pushed \(records.count) progress records to cloud for user \(userId)")
            }
        } catch {
            AppDiagnostics.shared.log("CloudSyncService push progress error: \(error.localizedDescription)")
        }
    }

    /// Загружает метаданные видео (название, постер, лого) с сервера Firebase
    public func fetchRemoteMetadata(userId: String, idToken: String? = nil) async -> [PlaybackMediaMetadata]? {
        guard !userId.isEmpty, userId != "guest" else { return nil }
        guard let url = await makeURL(path: "\(userId)/metadata", idToken: idToken) else { return nil }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 10.0

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                return nil
            }

            if data.isEmpty || String(data: data, encoding: .utf8) == "null" {
                return []
            }

            return try? JSONDecoder().decode([PlaybackMediaMetadata].self, from: data)
        } catch {
            return nil
        }
    }

    /// Сохраняет метаданные видео на сервер Firebase
    public func pushRemoteMetadata(_ metadata: [PlaybackMediaMetadata], userId: String, idToken: String? = nil) async {
        guard !userId.isEmpty, userId != "guest" else { return }
        guard let url = await makeURL(path: "\(userId)/metadata", idToken: idToken) else { return }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "PUT"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(metadata)
            request.timeoutInterval = 10.0

            _ = try await URLSession.shared.data(for: request)
        } catch {
            AppDiagnostics.shared.log("CloudSyncService push metadata error: \(error.localizedDescription)")
        }
    }

    public var statusText: String {
        if isSyncing {
            return "Синхронизация..."
        }
        if let lastSync = lastSyncDate {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            formatter.locale = Locale(identifier: "ru_RU")
            return "Синхронизировано (\(formatter.localizedString(for: lastSync, relativeTo: Date())))"
        }
        if AuthRepository.shared.isAuthenticated {
            return "Облако подключено ☁️"
        }
        return "Локальный режим"
    }
}
