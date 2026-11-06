import Foundation
import DeviceCheck

/// Firebase App Check (DeviceCheck provider) без Firebase SDK.
///
/// Зачем: бэкенд принимает запросы только с валидным Firebase ID токеном; App Check добавляет
/// уровень device-attestation — подтверждение, что запрос идёт с реального iPhone, а не со скрипта.
/// Приложение работает и без него (бэкенд стартует в monitor-режиме и лишь логирует отсутствие).
///
/// Важно: Apple ограничивает генерацию DeviceCheck-токенов двумя в сутки на устройство,
/// поэтому токен DC генерируется ОДИН раз и персистится, а для обмена используется повторно.
/// Сам App Check-токен короткоживущий (~1 час) и обновляется прозрачно в фоне.
final class AppCheckService: @unchecked Sendable {
    static let shared = AppCheckService()

    private let deviceCheckTokenKey = "sloosh_devicecheck_token"
    private let lock = NSLock()
    private let session: URLSession

    // Публичные Firebase-идентификаторы приложения (by design не секреты — лежат в GoogleService-Info.plist)
    private var projectId: String?
    private var appId: String?
    private var webApiKey: String?

    private struct CacheState {
        var token: String?
        var expiresAt: Date
    }

    private var cache = CacheState(token: nil, expiresAt: .distantPast)
    private var refreshTask: Task<String?, Never>?
    private var isDeviceCheckAvailable: Bool

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        self.session = URLSession(configuration: config)
        self.isDeviceCheckAvailable = DCDevice.current.isSupported

        if let plistPath = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
           let plist = NSDictionary(contentsOfFile: plistPath) as? [String: Any] {
            self.projectId = plist["PROJECT_ID"] as? String
            self.appId = plist["GOOGLE_APP_ID"] as? String
            self.webApiKey = plist["API_KEY"] as? String
        }
    }

    private var isConfigured: Bool {
        guard let projectId, let appId, let webApiKey else { return false }
        return !projectId.isEmpty && !appId.isEmpty && !webApiKey.isEmpty
    }

    /// Токен для заголовка X-Firebase-AppCheck. Неблокирующий: если кэша нет —
    /// запускает фоновый обмен и возвращает nil (monitor-режим бэкенда это терпит).
    func currentToken() async -> String? {
        guard isConfigured, isDeviceCheckAvailable else { return nil }

        lock.lock()
        let cached = cache
        lock.unlock()

        if let token = cached.token, Date() < cached.expiresAt {
            return token
        }

        lock.lock()
        if refreshTask == nil {
            refreshTask = Task { [weak self] in
                await self?.refreshToken()
            }
        }
        lock.unlock()
        return nil
    }

    private func refreshToken() async -> String? {
        defer {
            lock.lock()
            refreshTask = nil
            lock.unlock()
        }

        guard let deviceCheckToken = await ensureDeviceCheckToken() else { return nil }
        guard let projectId, let appId, let webApiKey,
              let url = URL(string: "https://firebaseappcheck.googleapis.com/v1/projects/\(projectId)/apps/\(appId):exchangeDeviceCheckToken?key=\(webApiKey)") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["device_check_token": deviceCheckToken])

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = json["token"] as? String, !token.isEmpty else {
                #if DEBUG
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                print("[AppCheck] Exchange failed (\(code)) — работа продолжается без attestation")
                #endif
                return nil
            }

            // TTL приходит в формате "3600s"; обновляем заранее (80% срока)
            let ttlSeconds: TimeInterval
            if let ttlString = json["ttl"] as? String, ttlString.hasSuffix("s"),
               let parsed = Double(ttlString.dropLast()) {
                ttlSeconds = parsed
            } else {
                ttlSeconds = 3600
            }

            lock.lock()
            cache = CacheState(token: token, expiresAt: Date().addingTimeInterval(ttlSeconds * 0.8))
            lock.unlock()
            return token
        } catch {
            #if DEBUG
            print("[AppCheck] Exchange error: \(error.localizedDescription)")
            #endif
            return nil
        }
    }

    /// Персистентный DeviceCheck-токен: генерируется один раз (лимит Apple — 2/сутки), затем переиспользуется.
    private func ensureDeviceCheckToken() async -> String? {
        if let stored = UserDefaults.standard.string(forKey: deviceCheckTokenKey), !stored.isEmpty {
            return stored
        }

        let token: String? = await withCheckedContinuation { continuation in
            DCDevice.current.generateToken { data, error in
                if let data, error == nil {
                    continuation.resume(returning: data.base64EncodedString())
                } else {
                    #if DEBUG
                    print("[AppCheck] DeviceCheck generateToken failed: \(error?.localizedDescription ?? "unknown")")
                    #endif
                    continuation.resume(returning: nil)
                }
            }
        }

        if let token {
            UserDefaults.standard.set(token, forKey: deviceCheckTokenKey)
        }
        return token
    }
}
