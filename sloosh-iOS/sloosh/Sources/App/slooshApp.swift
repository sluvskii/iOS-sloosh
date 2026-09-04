import SwiftUI
import AVFoundation
import TipKit

class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock = UIInterfaceOrientationMask.portrait

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return AppDelegate.orientationLock
    }

    static func lockToLandscape() {
        AppDelegate.orientationLock = .landscape
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let windowScene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first {
            windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape)) { _ in }
            for window in windowScene.windows {
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
        }
    }

    static func lockToPortrait() {
        AppDelegate.orientationLock = .portrait
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let windowScene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first {
            windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { _ in }
            for window in windowScene.windows {
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
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
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    
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
        
        // Настраиваем категории аудиосессии, не перехватывая фоновую музыку пользователя при старте
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
        } catch {
            print("Failed to set audio session category: \(error)")
        }
        
        // Configure TipKit
        if #available(iOS 17.0, *) {
            try? Tips.configure([
                .displayFrequency(.immediate),
                .datastoreLocation(.applicationDefault)
            ])
        }
        
        // Упреждающе разогреваем WebKit для мгновенного разбора Alloha-токенов
        Task { @MainActor in
            SharedWebViewProvider.shared.prewarm()
        }
    }
    
    @ObservedObject private var diagnostics = AppDiagnostics.shared
    @State private var showShareSheet = false
    @State private var isSplashActive = true
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                
                if isSplashActive {
                    LaunchSplashView(isPresented: $isSplashActive)
                        .transition(.opacity)
                        .zIndex(999)
                }
            }
                .modelContainer(AppDatabase.shared.container)
                .preferredColorScheme(appTheme.colorScheme)
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
                .onOpenURL { url in
                    DeepLinkManager.shared.handleURL(url)
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .background {
                        AppDiagnostics.shared.markGracefulExit()
                        UserPresenceService.shared.setOffline()
                    } else if newPhase == .active {
                        AppDiagnostics.shared.markRunning()
                        UserPresenceService.shared.startHeartbeat()
                    }
                }
                .task {
                    UserPresenceService.shared.startHeartbeat()
                }
        }
    }
}

extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        
        guard let interactivePopGestureRecognizer = interactivePopGestureRecognizer,
              let targets = interactivePopGestureRecognizer.value(forKey: "targets") as? [NSObject],
              let targetObjc = targets.first,
              let target = targetObjc.value(forKey: "target") else {
            return
        }
        
        interactivePopGestureRecognizer.isEnabled = false
        
        let fullWidthPanGesture = UIPanGestureRecognizer(target: target, action: Selector(("handleNavigationTransition:")))
        fullWidthPanGesture.delegate = self
        view.addGestureRecognizer(fullWidthPanGesture)
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard viewControllers.count > 1 else { return false }
        
        if let topVC = viewControllers.last {
            let typeString = String(describing: type(of: topVC))
            if typeString.contains("DetailsView") {
                return false
            }
        }
        
        if let pan = gestureRecognizer as? UIPanGestureRecognizer {
            let velocity = pan.velocity(in: view)
            return velocity.x > 0 && abs(velocity.x) > abs(velocity.y)
        }
        
        return true
    }
}
