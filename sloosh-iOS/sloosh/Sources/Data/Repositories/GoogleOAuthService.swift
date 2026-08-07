import Foundation
import AuthenticationServices
import CryptoKit
import UIKit

// MARK: - Google OAuth 2.0 via ASWebAuthenticationSession (без GoogleSignIn SDK)
//
// Полная схема (PKCE + Authorization Code Flow):
//   1. Генерируем PKCE code_verifier + code_challenge (SHA-256)
//   2. Открываем ASWebAuthenticationSession → пользователь выбирает Google-аккаунт в Safari
//   3. Получаем authorization_code из redirect URL (callbackURLScheme = REVERSED_CLIENT_ID)
//   4. Обмениваем code → id_token через oauth2.googleapis.com/token
//   5. Передаём id_token в Firebase accounts:signInWithIdp
//
// Требования в Firebase Console:
//   - Authentication → Sign-in method → Google → ВКЛЮЧИТЬ
//   - OAuth Client ID уже прописан в GoogleService-Info.plist (CLIENT_ID + REVERSED_CLIENT_ID)

@MainActor
public final class GoogleOAuthService: NSObject {

    public static let shared = GoogleOAuthService()
    private override init() {}

    // MARK: - Config from GoogleService-Info.plist

    private var clientId: String {
        plistValue(for: "CLIENT_ID") ?? ""
    }

    private var reversedClientId: String {
        plistValue(for: "REVERSED_CLIENT_ID") ?? ""
    }

    private var firebaseApiKey: String {
        plistValue(for: "API_KEY") ?? ""
    }

    private func plistValue(for key: String) -> String? {
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path),
              let value = dict[key] as? String, !value.isEmpty else {
            return nil
        }
        return value
    }

    // MARK: - Public entry point

    /// Запускает полный Google OAuth поток.
    /// - Parameter contextProvider: Объект, который предоставляет UIWindow для ASWebAuthenticationSession
    public func signIn(
        presentingViewController: UIViewController,
        contextProvider: WebAuthContextProvider
    ) async throws -> GoogleSignInResult {
        guard !clientId.isEmpty, !reversedClientId.isEmpty else {
            throw GoogleOAuthError.missingConfiguration
        }

        // 1. PKCE
        let codeVerifier = generateCodeVerifier()
        let codeChallenge = generateCodeChallenge(from: codeVerifier)

        // 2. Redirect URI — кастомная схема из GoogleService-Info.plist
        // ASWebAuthenticationSession перехватывает этот redirect автоматически,
        // регистрация в Info.plist не нужна
        let redirectURI = "\(reversedClientId):/oauth2redirect"

        // 3. Google OAuth URL
        let authURL = buildAuthorizationURL(
            codeChallenge: codeChallenge,
            redirectURI: redirectURI
        )

        // 4. ASWebAuthenticationSession — открывает системный Safari с аккаунтами Google
        let callbackURL = try await performWebAuthSession(
            url: authURL,
            callbackScheme: reversedClientId,
            contextProvider: contextProvider
        )

        // 5. Извлекаем authorization_code
        let code = try extractAuthCode(from: callbackURL)

        // 6. Обмениваем code → Google токены (id_token + access_token)
        let (idToken, accessToken) = try await exchangeCodeForTokens(
            code: code,
            codeVerifier: codeVerifier,
            redirectURI: redirectURI
        )

        // 7. Firebase signInWithIdp — создаём/входим в Firebase-аккаунт через Google
        let result = try await signInWithFirebase(idToken: idToken, accessToken: accessToken)
        return result
    }

    // MARK: - Step 3: Build Google Authorization URL

    private func buildAuthorizationURL(codeChallenge: String, redirectURI: String) -> URL {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "prompt", value: "select_account"), // Всегда показываем выбор аккаунта
            URLQueryItem(name: "access_type", value: "offline")
        ]
        return components.url!
    }

    // MARK: - Step 4: ASWebAuthenticationSession

    private func performWebAuthSession(
        url: URL,
        callbackScheme: String,
        contextProvider: WebAuthContextProvider
    ) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            var session: ASWebAuthenticationSession?
            session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let error = error {
                    let nsError = error as NSError
                    // Пользователь закрыл браузер
                    if nsError.domain == ASWebAuthenticationSessionErrorDomain,
                       nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        continuation.resume(throwing: GoogleOAuthError.userCancelled)
                    } else {
                        continuation.resume(throwing: GoogleOAuthError.webSessionFailed(error.localizedDescription))
                    }
                } else if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: GoogleOAuthError.noCallbackURL)
                }
                _ = session // сохраняем ссылку
            }
            session?.presentationContextProvider = contextProvider
            // false = Safari покажет уже вошедшие аккаунты Google (не ephemeral/инкогнито)
            session?.prefersEphemeralWebBrowserSession = false
            session?.start()
        }
    }

    // MARK: - Step 5: Extract authorization code from redirect URL

    private func extractAuthCode(from url: URL) throws -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw GoogleOAuthError.noAuthCode
        }

        // Проверяем на ошибку OAuth
        if let errorParam = components.queryItems?.first(where: { $0.name == "error" })?.value {
            throw GoogleOAuthError.oauthError(errorParam)
        }

        guard let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw GoogleOAuthError.noAuthCode
        }
        return code
    }

    // MARK: - Step 6: Exchange authorization code for Google tokens

    private func exchangeCodeForTokens(
        code: String,
        codeVerifier: String,
        redirectURI: String
    ) async throws -> (idToken: String, accessToken: String) {
        guard let url = URL(string: "https://oauth2.googleapis.com/token") else {
            throw GoogleOAuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let params: [(String, String)] = [
            ("code", code),
            ("client_id", clientId),
            ("redirect_uri", redirectURI),
            ("code_verifier", codeVerifier),
            ("grant_type", "authorization_code")
        ]

        request.httpBody = params
            .map { "\($0.0)=\($0.1.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.1)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Неизвестная ошибка"
            throw GoogleOAuthError.tokenExchangeFailed(errorText)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let idToken = json["id_token"] as? String else {
            throw GoogleOAuthError.missingIdToken
        }

        let accessToken = json["access_token"] as? String ?? ""
        return (idToken, accessToken)
    }

    // MARK: - Step 7: Firebase signInWithIdp

    private func signInWithFirebase(idToken: String, accessToken: String) async throws -> GoogleSignInResult {
        guard !firebaseApiKey.isEmpty else {
            throw GoogleOAuthError.missingConfiguration
        }
        guard let url = URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=\(firebaseApiKey)") else {
            throw GoogleOAuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        // postBody — формат Firebase для Google IdP
        let postBody = "id_token=\(idToken)&access_token=\(accessToken)&providerId=google.com"

        let body: [String: Any] = [
            "postBody": postBody,
            "requestUri": "http://localhost",
            "returnIdpCredential": true,
            "returnSecureToken": true
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorDict = json["error"] as? [String: Any]
            let message = errorDict?["message"] as? String ?? "Firebase signInWithIdp failed"
            throw GoogleOAuthError.firebaseError(message)
        }

        guard let firebaseIdToken = json["idToken"] as? String,
              let refreshToken = json["refreshToken"] as? String,
              let localId = json["localId"] as? String else {
            throw GoogleOAuthError.missingFirebaseTokens
        }

        return GoogleSignInResult(
            localId: localId,
            email: json["email"] as? String,
            displayName: json["displayName"] as? String,
            photoURL: json["photoUrl"] as? String,
            idToken: firebaseIdToken,
            refreshToken: refreshToken
        )
    }

    // MARK: - PKCE Helpers

    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64URLEncodedString()
    }
}

// MARK: - WebAuthContextProvider

/// Предоставляет UIWindow для ASWebAuthenticationSession.
/// Передаётся в GoogleOAuthService.shared.signIn(contextProvider:)
public final class WebAuthContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let window: UIWindow

    public init(window: UIWindow) {
        self.window = window
    }

    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return window
    }
}

// MARK: - Result Type

public struct GoogleSignInResult {
    public let localId: String
    public let email: String?
    public let displayName: String?
    public let photoURL: String?
    public let idToken: String
    public let refreshToken: String
}

// MARK: - Error Type

public enum GoogleOAuthError: LocalizedError {
    case missingConfiguration
    case userCancelled
    case webSessionFailed(String)
    case noCallbackURL
    case noAuthCode
    case oauthError(String)
    case invalidURL
    case tokenExchangeFailed(String)
    case missingIdToken
    case firebaseError(String)
    case missingFirebaseTokens

    public var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "Ошибка конфигурации: не найден CLIENT_ID в GoogleService-Info.plist"
        case .userCancelled:
            return nil // Не показываем пользователю
        case .webSessionFailed(let msg):
            return "Ошибка браузерной сессии: \(msg)"
        case .noCallbackURL:
            return "Google не вернул URL обратного вызова"
        case .noAuthCode:
            return "Google не вернул код авторизации"
        case .oauthError(let error):
            return "Ошибка Google OAuth: \(error)"
        case .invalidURL:
            return "Внутренняя ошибка конфигурации"
        case .tokenExchangeFailed(let msg):
            return "Не удалось получить токен Google: \(msg)"
        case .missingIdToken:
            return "Google не вернул id_token"
        case .firebaseError(let msg):
            return parseFirebaseErrorMessage(msg)
        case .missingFirebaseTokens:
            return "Firebase не вернул токены авторизации"
        }
    }

    private func parseFirebaseErrorMessage(_ msg: String) -> String {
        if msg.contains("OPERATION_NOT_ALLOWED") {
            return "Вход через Google не включён в Firebase Console (Authentication → Sign-in method → Google)"
        }
        if msg.contains("USER_DISABLED") {
            return "Учётная запись заблокирована"
        }
        return "Ошибка Firebase: \(msg)"
    }
}

// MARK: - Data+Base64URL

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
