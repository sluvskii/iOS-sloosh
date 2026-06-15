import SwiftUI
import AVFoundation

class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock = UIInterfaceOrientationMask.all

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return AppDelegate.orientationLock
    }
}

@main
struct slooshApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        // Запускаем скрытый отлов крашей
        AppDiagnostics.shared.startCrashMonitoring()
        AppDiagnostics.shared.markRunning()
        AppDiagnostics.shared.log("App launched")
        
        // Настраиваем кэш для AsyncImage и URLSession
        let memoryCapacity = 50 * 1024 * 1024 // 50 MB
        let diskCapacity = 200 * 1024 * 1024 // 200 MB
        let cache = URLCache(memoryCapacity: memoryCapacity, diskCapacity: diskCapacity, diskPath: "sloosh_image_cache")
        URLCache.shared = cache
        
        // Настраиваем аудиосессию, чтобы звук работал даже в беззвучном режиме
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to set audio session category: \(error)")
        }
    }
    
    @StateObject private var diagnostics = AppDiagnostics.shared
    @State private var showShareSheet = false
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .alert("Приложение было закрыто из-за ошибки", isPresented: $diagnostics.hasCrashLog) {
                    Button("Отправить логи") {
                        showShareSheet = true
                    }
                    Button("Игнорировать", role: .cancel) {
                        diagnostics.clearCrashLog()
                    }
                } message: {
                    Text("Мы зафиксировали краш в прошлой сессии. Пожалуйста, отправьте лог разработчику, чтобы мы могли это исправить.")
                }
                .sheet(isPresented: $showShareSheet, onDismiss: {
                    diagnostics.clearCrashLog()
                }) {
                    ShareSheet(items: [diagnostics.getCrashURL()])
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .background {
                        AppDiagnostics.shared.markGracefulExit()
                    } else if newPhase == .active {
                        AppDiagnostics.shared.markRunning()
                    }
                }
        }
    }
}
