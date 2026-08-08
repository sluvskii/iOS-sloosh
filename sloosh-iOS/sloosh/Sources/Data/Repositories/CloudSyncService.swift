import Foundation
import SwiftUI
import Combine

@MainActor
public final class CloudSyncService: ObservableObject {
    public static let shared = CloudSyncService()

    @Published public private(set) var isSyncing: Bool = false
    @Published public private(set) var lastSyncDate: Date?

    private let databaseBaseURL = "https://sloosh-77434-default-rtdb.firebaseio.com/users"

    private init() {}

    /// Загружает избранное аккаунта с сервера Firebase
    public func fetchRemoteFavorites(userId: String, idToken: String? = nil) async -> [FavoriteDto]? {
        guard !userId.isEmpty, userId != "guest" else { return nil }
        
        var urlString = "\(databaseBaseURL)/\(userId)/favorites.json"
        if let idToken = idToken, !idToken.isEmpty {
            urlString += "?auth=\(idToken)"
        }
        
        guard let url = URL(string: urlString) else { return nil }

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

        var urlString = "\(databaseBaseURL)/\(userId)/favorites.json"
        if let idToken = idToken, !idToken.isEmpty {
            urlString += "?auth=\(idToken)"
        }

        guard let url = URL(string: urlString) else { return }

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
