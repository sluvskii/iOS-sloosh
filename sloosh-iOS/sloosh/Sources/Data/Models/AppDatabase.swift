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
            print("AppDatabase: Failed to create ModelContainer on first attempt: \(error)")
            Self.purgeDatabaseFiles()
            
            do {
                container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                print("AppDatabase: Failed to create ModelContainer after purge: \(error). Falling back to in-memory store.")
                let fallbackConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                container = (try? ModelContainer(for: schema, configurations: [fallbackConfig])) ?? {
                    fatalError("Critical failure: unable to create in-memory ModelContainer: \(error)")
                }()
            }
        }
    }
    
    private static func purgeDatabaseFiles() {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let storeUrl = appSupport.appendingPathComponent("default.store")
        let walUrl = appSupport.appendingPathComponent("default.store-wal")
        let shmUrl = appSupport.appendingPathComponent("default.store-shm")
        
        try? FileManager.default.removeItem(at: storeUrl)
        try? FileManager.default.removeItem(at: walUrl)
        try? FileManager.default.removeItem(at: shmUrl)
    }
}
