import Foundation
import AppIntents
import SwiftUI

@available(iOS 16.0, *)
struct PlayMovieIntent: AppIntent {
    static var title: LocalizedStringResource = "Включить в Sloosh"
    static var description = IntentDescription("Продолжить просмотр или включить фильм в Sloosh.")

    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        // Post notification so ContentView can intercept and navigate
        NotificationCenter.default.post(name: NSNotification.Name("SlooshIntentPlayMovie"), object: nil)
        
        return .result()
    }
}

@available(iOS 16.0, *)
struct ContinueWatchingIntent: AppIntent {
    static var title: LocalizedStringResource = "Продолжить просмотр в Sloosh"
    static var description = IntentDescription("Открыть вкладку Продолжить просмотр в Sloosh.")

    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: NSNotification.Name("SlooshIntentContinueWatching"), object: nil)
        return .result()
    }
}

@available(iOS 16.0, *)
struct SlooshShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PlayMovieIntent(),
            phrases: [
                "Включить \(.applicationName)",
                "Открыть \(.applicationName)"
            ],
            shortTitle: "Открыть Sloosh",
            systemImageName: "play.tv.fill"
        )
        
        AppShortcut(
            intent: ContinueWatchingIntent(),
            phrases: [
                "Продолжить просмотр в \(.applicationName)"
            ],
            shortTitle: "Продолжить просмотр",
            systemImageName: "play.tv.fill"
        )
    }
}
