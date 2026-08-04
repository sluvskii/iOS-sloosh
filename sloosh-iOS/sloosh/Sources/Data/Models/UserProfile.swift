import Foundation

public struct UserProfile: Codable, Identifiable, Equatable {
    public let id: String
    public let email: String?
    public let displayName: String?
    public let photoURL: String?
    public let isAnonymous: Bool
    public let provider: String // "email", "google", "anonymous"
    public let idToken: String?
    public let refreshToken: String?
    public let createdAt: Date

    public init(
        id: String,
        email: String? = nil,
        displayName: String? = nil,
        photoURL: String? = nil,
        isAnonymous: Bool = true,
        provider: String = "anonymous",
        idToken: String? = nil,
        refreshToken: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.photoURL = photoURL
        self.isAnonymous = isAnonymous
        self.provider = provider
        self.idToken = idToken
        self.refreshToken = refreshToken
        self.createdAt = createdAt
    }

    public var displayTitle: String {
        if isAnonymous {
            return "Гостевой аккаунт"
        }
        if let displayName = displayName, !displayName.isEmpty {
            return displayName
        }
        if let email = email, !email.isEmpty {
            return email.components(separatedBy: "@").first ?? email
        }
        return "Пользователь sloosh"
    }

    public var displaySubtitle: String {
        if isAnonymous {
            return "Войдите для синхронизации Избранного"
        }
        return email ?? "Аккаунт sloosh"
    }

    public var avatarInitials: String {
        if isAnonymous { return "👤" }
        if let name = displayName, !name.isEmpty {
            let parts = name.split(separator: " ")
            if parts.count >= 2 {
                return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
            }
            return String(name.prefix(2)).uppercased()
        }
        if let email = email, !email.isEmpty {
            return String(email.prefix(2)).uppercased()
        }
        return "SL"
    }
}
