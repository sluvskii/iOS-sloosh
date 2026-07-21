import Foundation
import AppIntents
import SwiftUI

@available(iOS 16.0, *)
struct PlayMovieIntent: AppIntent {
    static var title: LocalizedStringResource = "Включить в Sloosh"
    static var description = IntentDescription("Продолжить просмотр или включить фильм в Sloosh.")

    @Parameter(title: "Название фильма", description: "Например, Дюна")
    var movieQuery: String?

    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        // Post notification so ContentView can intercept and navigate
        NotificationCenter.default.post(name: NSNotification.Name("SlooshIntentPlayMovie"), object: nil, userInfo: ["query": movieQuery ?? ""])
        
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
                "Найди \(\.$movieQuery) в \(.applicationName)",
                "Продолжить просмотр в \(.applicationName)"
            ],
            shortTitle: "Включить фильм",
            systemImageName: "play.tv.fill"
        )
    }
}
