import Foundation
import SwiftUI
import Combine

// MARK: - Firebase Auth Repository via Identity Toolkit REST API
// Используем прямые HTTP-запросы к Firebase Identity Toolkit вместо Firebase iOS SDK,
// так как SDK не подключён через SPM в проекте.

@MainActor
public final class AuthRepository: ObservableObject {
    public static let shared = AuthRepository()

    @Published public private(set) var currentUser: UserProfile?
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var lastError: String?

    private let userDefaultsKey = "sloosh_user_profile"

    // API_KEY читается из GoogleService-Info.plist, который уже есть в проекте
    private var firebaseApiKey: String {
        if let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
           let dict = NSDictionary(contentsOfFile: path),
           let key = dict["API_KEY"] as? String, !key.isEmpty {
            return key
        }
        return ""
    }

    public var isAuthenticated: Bool {
        guard let user = currentUser else { return false }
        return !user.isAnonymous
    }

    public var isAnonymous: Bool {
        currentUser?.isAnonymous ?? true
    }

    private init() {
        loadStoredUser()
    }

    public func clearError() {
        lastError = nil
    }

    private func loadStoredUser() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let user = try? JSONDecoder().decode(UserProfile.self, from: data) {
            self.currentUser = user
        } else {
            let guest = UserProfile(
                id: "guest_\(UUID().uuidString.prefix(8))",
                isAnonymous: true,
                provider: "anonymous"
            )
            self.currentUser = guest
            saveUser(guest)
        }
    }

    private func saveUser(_ user: UserProfile) {
        self.currentUser = user
        if let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }

    // MARK: - Регистрация (Firebase accounts:signUp)
    // Создаёт реального пользователя в вашем Firebase проекте

    public func signUp(email: String, password: String, displayName: String? = nil) async -> Bool {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard isValidEmail(cleanEmail) else {
            lastError = "Введите корректный Email (например, name@domain.com)"
            return false
        }

        guard password.count >= 6 else {
            lastError = "Пароль должен содержать не менее 6 символов"
            return false
        }

        guard !firebaseApiKey.isEmpty else {
            lastError = "Ошибка конфигурации: не найден GoogleService-Info.plist"
            return false
        }

        guard let url = URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=\(firebaseApiKey)") else {
            lastError = "Ошибка конфигурации Firebase"
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let body: [String: Any] = [
            "email": cleanEmail,
            "password": password,
            "returnSecureToken": true
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                lastError = parseFirebaseError(json)
                return false
            }

            guard let idToken = json["idToken"] as? String,
                  let refreshToken = json["refreshToken"] as? String,
                  let localId = json["localId"] as? String else {
                lastError = "Неожиданный ответ от Firebase"
                return false
            }

            let finalName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

            if let name = finalName {
                await updateDisplayName(idToken: idToken, name: name)
            }

            let newUser = UserProfile(
                id: localId,
                email: cleanEmail,
                displayName: finalName ?? cleanEmail.components(separatedBy: "@").first?.capitalized,
                isAnonymous: false,
                provider: "email",
                idToken: idToken,
                refreshToken: refreshToken
            )
            saveUser(newUser)

            ToastManager.shared.show(
                title: "Добро пожаловать! 🎉",
                subtitle: "Аккаунт создан для \(cleanEmail)",
                icon: "checkmark.circle.fill"
            )

            CloudSyncService.shared.syncAllData()
            return true

        } catch {
            if (error as NSError).code == NSURLErrorNotConnectedToInternet {
                lastError = "Нет соединения с интернетом"
            } else if (error as NSError).code == NSURLErrorTimedOut {
                lastError = "Превышено время ожидания. Повторите попытку."
            } else {
                lastError = "Ошибка сети: \(error.localizedDescription)"
            }
            return false
        }
    }

    // MARK: - Вход по паролю (Firebase accounts:signInWithPassword)

    public func signIn(email: String, password: String) async -> Bool {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard isValidEmail(cleanEmail) else {
            lastError = "Введите корректный Email"
            return false
        }

        guard !password.isEmpty else {
            lastError = "Введите пароль"
            return false
        }

        guard !firebaseApiKey.isEmpty else {
            lastError = "Ошибка конфигурации: не найден GoogleService-Info.plist"
            return false
        }

        guard let url = URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=\(firebaseApiKey)") else {
            lastError = "Ошибка конфигурации Firebase"
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let body: [String: Any] = [
            "email": cleanEmail,
            "password": password,
            "returnSecureToken": true
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                lastError = parseFirebaseError(json)
                return false
            }

            guard let idToken = json["idToken"] as? String,
                  let refreshToken = json["refreshToken"] as? String,
                  let localId = json["localId"] as? String else {
                lastError = "Неожиданный ответ от Firebase"
                return false
            }

            let displayName = (json["displayName"] as? String)?.nilIfEmpty
                ?? cleanEmail.components(separatedBy: "@").first?.capitalized

            let user = UserProfile(
                id: localId,
                email: cleanEmail,
                displayName: displayName,
                isAnonymous: false,
                provider: "email",
                idToken: idToken,
                refreshToken: refreshToken
            )
            saveUser(user)

            ToastManager.shared.show(
                title: "С возвращением! 👋",
                subtitle: "Авторизован как \(user.displayTitle)",
                icon: "checkmark.circle.fill"
            )

            CloudSyncService.shared.syncAllData()
            return true

        } catch {
            if (error as NSError).code == NSURLErrorNotConnectedToInternet {
                lastError = "Нет соединения с интернетом"
            } else if (error as NSError).code == NSURLErrorTimedOut {
                lastError = "Превышено время ожидания. Повторите попытку."
            } else {
                lastError = "Ошибка сети: \(error.localizedDescription)"
            }
            return false
        }
    }

    // MARK: - Сброс пароля (Firebase accounts:sendOobCode)
    // Firebase отправляет письмо со ссылкой для сброса пароля (не код!)

    public func resetPassword(email: String) async -> Bool {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard isValidEmail(cleanEmail) else {
            lastError = "Введите корректный Email"
            return false
        }

        guard !firebaseApiKey.isEmpty else {
            lastError = "Ошибка конфигурации Firebase"
            return false
        }

        guard let url = URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key=\(firebaseApiKey)") else {
            lastError = "Ошибка конфигурации Firebase"
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let body: [String: Any] = [
            "requestType": "PASSWORD_RESET",
            "email": cleanEmail
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                lastError = parseFirebaseError(json)
                return false
            }

            ToastManager.shared.show(
                title: "Письмо отправлено 📩",
                subtitle: "Ссылка для сброса пароля отправлена на \(cleanEmail)",
                icon: "envelope.fill"
            )
            return true

        } catch {
            if (error as NSError).code == NSURLErrorNotConnectedToInternet {
                lastError = "Нет соединения с интернетом"
            } else {
                lastError = "Ошибка сети: \(error.localizedDescription)"
            }
            return false
        }
    }

    // MARK: - Выход из аккаунта

    public func signOut() {
        let guest = UserProfile(
            id: "guest_\(UUID().uuidString.prefix(8))",
            isAnonymous: true,
            provider: "anonymous"
        )
        saveUser(guest)
        lastError = nil
        ToastManager.shared.show(
            title: "Выход выполнен",
            subtitle: "Переход в гостевой режим",
            icon: "arrow.right.square"
        )
    }

    // MARK: - Вспомогательные методы

    private func updateDisplayName(idToken: String, name: String) async {
        guard !firebaseApiKey.isEmpty,
              let url = URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:update?key=\(firebaseApiKey)") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        let body: [String: Any] = [
            "idToken": idToken,
            "displayName": name,
            "returnSecureToken": false
        ]

        if let data = try? JSONSerialization.data(withJSONObject: body) {
            request.httpBody = data
            _ = try? await URLSession.shared.data(for: request)
        }
    }

    private func parseFirebaseError(_ json: [String: Any]) -> String {
        guard let errorDict = json["error"] as? [String: Any],
              let message = errorDict["message"] as? String else {
            return "Неизвестная ошибка. Попробуйте ещё раз."
        }

        switch true {
        case message.contains("EMAIL_EXISTS"):
            return "Этот Email уже зарегистрирован. Войдите в аккаунт."
        case message.contains("INVALID_PASSWORD"), message.contains("INVALID_LOGIN_CREDENTIALS"), message.contains("INVALID_EMAIL"):
            return "Неверный Email или пароль"
        case message.contains("EMAIL_NOT_FOUND"):
            return "Пользователь с таким Email не найден"
        case message.contains("USER_DISABLED"):
            return "Учётная запись заблокирована"
        case message.contains("TOO_MANY_ATTEMPTS_TRY_LATER"):
            return "Слишком много попыток. Попробуйте позже."
        case message.contains("WEAK_PASSWORD"):
            return "Пароль слишком слабый (минимум 6 символов)"
        case message.contains("OPERATION_NOT_ALLOWED"):
            return "Вход по Email/паролю не включён в Firebase Console"
        case message.contains("USER_NOT_FOUND"):
            return "Пользователь не найден"
        default:
            return message
        }
    }

    private func isValidEmail(_ email: String) -> Bool {
        let pattern = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        return NSPredicate(format: "SELF MATCHES %@", pattern).evaluate(with: email)
    }
}

// MARK: - String helper

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
