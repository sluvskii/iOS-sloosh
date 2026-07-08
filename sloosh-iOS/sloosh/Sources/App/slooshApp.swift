import SwiftUI
import AVFoundation

class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock = UIInterfaceOrientationMask.portrait

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return AppDelegate.orientationLock
    }

    static func lockToLandscape() {
        AppDelegate.orientationLock = .landscape
        if #available(iOS 16.0, *) {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            if let windowScene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first {
                windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape)) { _ in }
                for window in windowScene.windows {
                    window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
                }
            }
            UIViewController.attemptRotationToDeviceOrientation()
        } else {
            UIDevice.current.setValue(UIInterfaceOrientation.landscapeRight.rawValue, forKey: "orientation")
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }

    static func lockToPortrait() {
        AppDelegate.orientationLock = .portrait
        if #available(iOS 16.0, *) {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            if let windowScene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first {
                windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { _ in }
                for window in windowScene.windows {
                    window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
                }
            }
            UIViewController.attemptRotationToDeviceOrientation()
        } else {
            UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }
    
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        if identifier == "com.sloosh.downloads.bg" {
            DownloadManager.shared.backgroundCompletionHandler = completionHandler
        }
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
