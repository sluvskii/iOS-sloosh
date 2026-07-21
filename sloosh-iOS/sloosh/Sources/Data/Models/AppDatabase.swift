import Foundation
import SwiftData

@MainActor
public final class AppDatabase {
    public static let shared = AppDatabase()
    
    public let container: ModelContainer
    
    private init() {
        let schema = Schema([
            ProgressRecordModel.self,
            PlaybackMetadataModel.self,
            LastPlayedVoiceoverModel.self,
            LastPlayedEpisodeModel.self,
            FavoriteModel.self
        ])
        
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        
        do {
            container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }
}
