import Foundation

public struct UserProfile: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let email: String?
    public let displayName: String?
    public let tag: String?
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
        tag: String? = nil,
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
        self.tag = tag
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
        if let tag = tag, !tag.isEmpty {
            return "@\(tag)"
        }
        if let email = email, !email.isEmpty {
            return email.components(separatedBy: "@").first ?? email
        }
        return "Пользователь sloosh"
    }

    public var displayTag: String {
        if let tag = tag, !tag.isEmpty {
            return "@\(tag)"
        }
        return ""
    }

    public var displaySubtitle: String {
        if isAnonymous {
            return "Войдите для синхронизации"
        }
        if let tag = tag, !tag.isEmpty {
            return "@\(tag)"
        }
        return "Аккаунт sloosh"
    }

    public var avatarInitials: String {
        if isAnonymous { return "👤" }
        if let name = displayName, !name.isEmpty {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return String(trimmed.prefix(1)).uppercased()
        }
        if let tag = tag, !tag.isEmpty {
            let clean = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            return String(clean.prefix(1)).uppercased()
        }
        return "S"
    }
}
