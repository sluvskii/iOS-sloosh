import Foundation
import SwiftUI
import Combine
import UIKit

// MARK: - Firebase Auth Repository via Identity Toolkit REST API

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

    public var isAdmin: Bool {
        guard let user = currentUser, !user.isAnonymous else { return false }
        let tag = (user.tag ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (user.displayName ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let email = (user.email ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Known admin handles and developer emails
        let adminTags = ["sluvskii", "admin", "sloosh", "creator", "owner"]
        if adminTags.contains(tag) || adminTags.contains(name) {
            return true
        }
        if email.contains("sluvskii") || email.contains("sloosh") || email.contains("admin") {
            return true
        }

        return UserDefaults.standard.bool(forKey: "sloosh_is_admin_\(user.id)")
    }

    public func setAdminStatus(userId: String, isAdmin: Bool) {
        UserDefaults.standard.set(isAdmin, forKey: "sloosh_is_admin_\(userId)")
        objectWillChange.send()
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

    public func saveUser(_ user: UserProfile) {
        self.currentUser = user
        if let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }

    // MARK: - Google Sign-In (ASWebAuthenticationSession + PKCE + Firebase signInWithIdp)

    public func signInWithGoogle() async -> Bool {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        // Получаем rootViewController для презентации браузерного окна
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            lastError = "Не удалось получить контекст приложения"
            return false
        }

        // Находим самый верхний presented ViewController
        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }

        // Устанавливаем ASWebAuthenticationPresentationContextProviding
        let contextProvider = WebAuthContextProvider(window: windowScene.windows.first { $0.isKeyWindow }!)

        do {
            let result = try await GoogleOAuthService.shared.signIn(
                presentingViewController: topVC,
                contextProvider: contextProvider
            )

            let displayName = result.displayName?.nilIfEmpty
                ?? result.email?.components(separatedBy: "@").first?.capitalized

            let user = UserProfile(
                id: result.localId,
                email: result.email,
                displayName: displayName,
                tag: nil,
                photoURL: result.photoURL,
                isAnonymous: false,
                provider: "google",
                idToken: result.idToken,
                refreshToken: result.refreshToken
            )
            saveUser(user)

            ToastManager.shared.show(
                title: "Вход через Google ✅",
                subtitle: "Добро пожаловать, \(user.displayTitle)!",
                icon: "checkmark.circle.fill"
            )

            CloudSyncService.shared.syncAllData()
            return true

        } catch let error as GoogleOAuthError {
            // Не показываем ошибку если пользователь сам отменил
            if case .userCancelled = error { return false }
            lastError = error.errorDescription
            ToastManager.shared.show(
                title: "Ошибка Google",
                subtitle: error.errorDescription ?? "Неизвестная ошибка",
                icon: "xmark.circle.fill"
            )
            return false
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    // MARK: - Регистрация (Firebase accounts:signUp)

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
                tag: nil,
                photoURL: nil,
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
                tag: nil,
                photoURL: nil,
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

    // MARK: - Обновление профиля пользователя

    public func updateUserProfile(displayName: String?, tag: String?, photoURL: String?) async -> (success: Bool, message: String) {
        guard let user = currentUser, !user.isAnonymous else {
            return (false, "Требуется авторизация")
        }

        let newName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let oldTag = user.tag
        let rawTag = tag?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let newTag = TagValidator.sanitize(rawTag)

        // 1. Validate Tag if changed
        if !newTag.isEmpty && newTag != oldTag {
            let validation = TagValidator.validate(newTag)
            guard validation.isValid else {
                return (false, validation.message)
            }

            let check = await MessengerRepository.shared.checkUserTagAvailability(tag: newTag)
            guard check.isAvailable else {
                return (false, check.message)
            }

            // Release old tag if existed
            if let old = oldTag, !old.isEmpty && old != newTag {
                await MessengerRepository.shared.releaseUserTag(old)
            }

            // Claim new tag
            await MessengerRepository.shared.claimUserTag(newTag, userId: user.id)
        } else if newTag.isEmpty && oldTag != nil && !oldTag!.isEmpty {
            // User cleared tag
            await MessengerRepository.shared.releaseUserTag(oldTag!)
        }

        // 2. Update Firebase Auth display name if token exists
        if let idToken = await ensureFreshToken(), let name = newName, name != user.displayName {
            await updateDisplayName(idToken: idToken, name: name)
        }

        // 3. Update local user profile state
        let finalTag = newTag.isEmpty ? nil : newTag
        let finalPhoto = photoURL?.nilIfEmpty ?? user.photoURL

        let updatedUser = UserProfile(
            id: user.id,
            email: user.email,
            displayName: newName ?? user.displayName,
            tag: finalTag,
            photoURL: finalPhoto,
            isAnonymous: false,
            provider: user.provider,
            idToken: user.idToken,
            refreshToken: user.refreshToken,
            createdAt: user.createdAt
        )

        saveUser(updatedUser)

        // 4. Synchronize sanitized profile to Firebase Realtime Database
        await MessengerRepository.shared.syncCurrentUserProfile()

        return (true, "Профиль успешно обновлен")
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

    public func ensureFreshToken() async -> String? {
        guard let user = currentUser, !user.isAnonymous, let refreshToken = user.refreshToken, !refreshToken.isEmpty else {
            return currentUser?.idToken
        }

        guard let url = URL(string: "https://securetoken.googleapis.com/v1/token?key=\(firebaseApiKey)") else {
            return user.idToken
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        let bodyString = "grant_type=refresh_token&refresh_token=\(refreshToken)"
        request.httpBody = bodyString.data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let newIdToken = json["id_token"] as? String else {
                return user.idToken
            }

            let newRefreshToken = (json["refresh_token"] as? String) ?? refreshToken

            let updatedUser = UserProfile(
                id: user.id,
                email: user.email,
                displayName: user.displayName,
                tag: user.tag,
                photoURL: user.photoURL,
                isAnonymous: user.isAnonymous,
                provider: user.provider,
                idToken: newIdToken,
                refreshToken: newRefreshToken,
                createdAt: user.createdAt
            )
            saveUser(updatedUser)
            return newIdToken
        } catch {
            return user.idToken
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
