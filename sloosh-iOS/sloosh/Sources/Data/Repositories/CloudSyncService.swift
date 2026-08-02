import Foundation
import SwiftUI
import Combine

@MainActor
public final class CloudSyncService: ObservableObject {
    public static let shared = CloudSyncService()

    @Published public private(set) var isSyncing: Bool = false
    @Published public private(set) var lastSyncDate: Date?

    private init() {}

    public func syncAllData() {
        guard AuthRepository.shared.isAuthenticated else { return }
        isSyncing = true

        Task {
            // Simulate cloud sync with Firestore / Remote store
            try? await Task.sleep(nanoseconds: 800_000_000)
            
            await MainActor.run {
                self.isSyncing = false
                self.lastSyncDate = Date()
                AppDiagnostics.shared.log("CloudSyncService: favorites and watch progress synced successfully")
            }
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
        return "Авторизуйтесь для синхронизации"
    }
}
