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
            AppDiagnostics.shared.log("AppDatabase: Failed to create ModelContainer on first attempt: \(error)")
            Self.purgeDatabaseFiles()
            
            do {
                container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                print("AppDatabase: Failed to create ModelContainer after purge: \(error). Falling back to in-memory store.")
                AppDiagnostics.shared.log("AppDatabase: ModelContainer purge failed: \(error). Falling back to in-memory store.")
                let fallbackConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                if let memoryContainer = try? ModelContainer(for: schema, configurations: [fallbackConfig]) {
                    container = memoryContainer
                } else {
                    print("AppDatabase: Emergency fallback to empty in-memory schema container.")
                    let emergencySchema = Schema([])
                    let emergencyConfig = ModelConfiguration(schema: emergencySchema, isStoredInMemoryOnly: true)
                    container = (try? ModelContainer(for: emergencySchema, configurations: [emergencyConfig]))
                        ?? (try! ModelContainer(for: Schema([FavoriteModel.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]))
                }
            }
        }
    }
    
    private static func purgeDatabaseFiles() {
        let fileManager = FileManager.default
        let searchDirectories: [FileManager.SearchPathDirectory] = [.applicationSupportDirectory, .documentDirectory]
        
        let fileNames = [
            "default.store", "default.store-wal", "default.store-shm",
            "default.sqlite", "default.sqlite-wal", "default.sqlite-shm"
        ]
        
        for searchDir in searchDirectories {
            guard let dirUrl = fileManager.urls(for: searchDir, in: .userDomainMask).first else { continue }
            
            for fileName in fileNames {
                let fileUrl = dirUrl.appendingPathComponent(fileName)
                if fileManager.fileExists(atPath: fileUrl.path) {
                    let backupUrl = dirUrl.appendingPathComponent("\(fileName).corrupted.\(Int(Date().timeIntervalSince1970)).bak")
                    try? fileManager.moveItem(at: fileUrl, to: backupUrl)
                    try? fileManager.removeItem(at: fileUrl)
                }
            }
        }
    }
}
