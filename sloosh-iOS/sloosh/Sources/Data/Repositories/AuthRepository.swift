import Foundation
import SwiftUI
import Combine

@MainActor
public final class AuthRepository: ObservableObject {
    public static let shared = AuthRepository()

    @Published public private(set) var currentUser: UserProfile?
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var lastError: String?

    private let userDefaultsKey = "sloosh_user_profile"

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

    private func loadStoredUser() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let user = try? JSONDecoder().decode(UserProfile.self, from: data) {
            self.currentUser = user
        } else {
            // Default to Anonymous Guest Mode
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

    // MARK: - Email & Password Authentication

    public func signUp(email: String, password: String, displayName: String? = nil) async -> Bool {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard isValidEmail(cleanEmail) else {
            lastError = "Введите корректный адрес Email"
            ToastManager.shared.show(title: "Ошибка", subtitle: "Некорректный Email", icon: "exclamationmark.triangle.fill")
            return false
        }

        guard password.count >= 6 else {
            lastError = "Пароль должен быть не менее 6 символов"
            ToastManager.shared.show(title: "Ошибка", subtitle: "Пароль слишком короткий (мин. 6 символов)", icon: "exclamationmark.triangle.fill")
            return false
        }

        // Simulate fast secure register & cloud sync
        try? await Task.sleep(nanoseconds: 600_000_000)

        let newUser = UserProfile(
            id: "user_\(UUID().uuidString.prefix(10))",
            email: cleanEmail,
            displayName: displayName?.isEmpty == false ? displayName : nil,
            isAnonymous: false,
            provider: "email"
        )
        saveUser(newUser)

        ToastManager.shared.show(
            title: "Регистрация успешна 🎉",
            subtitle: "Добро пожаловать в sloosh, \(newUser.displayTitle)!",
            icon: "checkmark.circle.fill"
        )

        CloudSyncService.shared.syncAllData()
        return true
    }

    public func signIn(email: String, password: String) async -> Bool {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard isValidEmail(cleanEmail) else {
            lastError = "Введите корректный адрес Email"
            ToastManager.shared.show(title: "Ошибка", subtitle: "Некорректный Email", icon: "exclamationmark.triangle.fill")
            return false
        }

        guard !password.isEmpty else {
            lastError = "Введите пароль"
            ToastManager.shared.show(title: "Ошибка", subtitle: "Введите пароль", icon: "exclamationmark.triangle.fill")
            return false
        }

        try? await Task.sleep(nanoseconds: 500_000_000)

        let user = UserProfile(
            id: "user_\(cleanEmail.hashValue)",
            email: cleanEmail,
            isAnonymous: false,
            provider: "email"
        )
        saveUser(user)

        ToastManager.shared.show(
            title: "Успешный вход 👋",
            subtitle: "С возвращением, \(user.displayTitle)!",
            icon: "checkmark.circle.fill"
        )

        CloudSyncService.shared.syncAllData()
        return true
    }

    public func resetPassword(email: String) async -> Bool {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard isValidEmail(cleanEmail) else {
            lastError = "Введите корректный адрес Email"
            ToastManager.shared.show(title: "Ошибка", subtitle: "Некорректный Email", icon: "exclamationmark.triangle.fill")
            return false
        }

        try? await Task.sleep(nanoseconds: 400_000_000)

        ToastManager.shared.show(
            title: "Письмо отправлено 📩",
            subtitle: "Инструкции по сбросу пароля отправлены на \(cleanEmail)",
            icon: "envelope.fill"
        )
        return true
    }

    // MARK: - Sign in with Apple

    public func signInWithApple(idToken: String, rawNonce: String, email: String? = nil, fullName: PersonNameComponents? = nil) async -> Bool {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        var nameStr: String? = nil
        if let name = fullName {
            let formatter = PersonNameComponentsFormatter()
            nameStr = formatter.string(from: name)
        }

        let user = UserProfile(
            id: "apple_\(idToken.prefix(12))",
            email: email,
            displayName: nameStr,
            isAnonymous: false,
            provider: "apple"
        )
        saveUser(user)

        ToastManager.shared.show(
            title: "Вход через Apple ID 🍏",
            subtitle: "Добро пожаловать, \(user.displayTitle)!",
            icon: "checkmark.circle.fill"
        )

        CloudSyncService.shared.syncAllData()
        return true
    }

    // MARK: - Sign Out & Delete Account

    public func signOut() {
        let guest = UserProfile(
            id: "guest_\(UUID().uuidString.prefix(8))",
            isAnonymous: true,
            provider: "anonymous"
        )
        saveUser(guest)

        ToastManager.shared.show(
            title: "Вы вышли из аккаунта",
            subtitle: "Включен гостевой режим",
            icon: "rectangle.portrait.and.arrow.right"
        )
    }

    private func isValidEmail(_ email: String) -> Bool {
        let emailRegEx = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPred = NSPredicate(format: "SELF MATCHES %@", emailRegEx)
        return emailPred.evaluate(with: email)
    }
}
