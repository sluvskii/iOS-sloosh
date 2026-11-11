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
        
        // Сбрасываем глобальную настройку озвучки, если там сохранён оригинал/английский
        if let savedGlobal = UserDefaults.standard.string(forKey: "alloha_last_translation_name"),
           isOriginalOrEnglishTranslation(savedGlobal) {
            UserDefaults.standard.removeObject(forKey: "alloha_last_translation_name")
        }
        
        // Configure TipKit
        if #available(iOS 17.0, *) {
            try? Tips.configure([
                .displayFrequency(.immediate),
                .datastoreLocation(.applicationDefault)
            ])
        }
        
        // Упреждающе подгружаем актуальный адрес бэкенда и разогреваем WebKit.
        // API-зависимый прогрев (стрим-токены, скрейперы, overrides) требует валидного Firebase ID
        // токена и выполняется только после входа — сразу при активной сцене (см. onChange ниже).
        // Конфиг и разогрев WebKit идут параллельно: раньше запуск ждал загрузку endpoint.json
        // с внешних хостов, которые в России часто недоступны.
        Task { @MainActor in
            SharedWebViewProvider.shared.prewarm()
            async let configLoad: Void = MoviesApi.shared.loadRemoteConfig()
            if AuthRepository.shared.isAuthenticated {
                await Self.warmupAuthenticatedServices()
            }
            await configLoad
            PlaybackAnalyticsService.shared.sendSessionHeartbeat()
            await ClipsRepository.shared.fetchFeed()
        }
    }

    /// Прогрев сервисов, требующих авторизации: пул стрим-токенов, скрейперы, кураторские overrides
    @MainActor
    private static func warmupAuthenticatedServices() async {
        await AllohaRepository.shared.warmup()
        await ScraperEngine.shared.warmup()
        await MediaOverridesRepository.shared.fetchOverrides()
    }
    
    @ObservedObject private var diagnostics = AppDiagnostics.shared
    @ObservedObject private var authRepo = AuthRepository.shared
    @State private var showShareSheet = false
    @State private var isSplashActive = true
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                if authRepo.isAuthenticated {
                    ContentView()
                        .transition(.opacity)
                } else {
                    CinematicAuthView()
                        .transition(.opacity)
                }
                
                if isSplashActive {
                    LaunchSplashView(isPresented: $isSplashActive)
                        .transition(.opacity)
                        .zIndex(999)
                }
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: authRepo.isAuthenticated)
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
                        PlaybackProgressStore.shared.scheduleCloudProgressPush(force: true)
                        MessengerRepository.shared.stopConversationsPolling()
                    } else if newPhase == .active {
                        AppDiagnostics.shared.markRunning()
                        UserPresenceService.shared.startHeartbeat()
                        PlaybackAnalyticsService.shared.sendSessionHeartbeat()
                        MessengerRepository.shared.startConversationsPolling()
                        Task {
                            await MoviesApi.shared.loadRemoteConfigIfNeeded()
                            await CloudSyncService.shared.syncAllDataAsync()
                            // После входа сцена становится active — догреваем авторизованные сервисы,
                            // если прогрев при старте ещё не выполнялся
                            if AuthRepository.shared.isAuthenticated {
                                await Self.warmupAuthenticatedServices()
                            }
                            await ClipsRepository.shared.fetchFeed()
                        }
                    }
                }
                .task {
                    UserPresenceService.shared.startHeartbeat()
                    PlaybackAnalyticsService.shared.sendSessionHeartbeat()
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
