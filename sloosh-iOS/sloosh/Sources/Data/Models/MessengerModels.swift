import Foundation

public enum MessageType: String, Codable {
    case text
    case media
}

public struct MediaCardPayload: Codable, Equatable {
    public let mediaId: String
    public let type: String
    public let title: String
    public let posterUrl: String?
    public let rating: Double?
    public let year: String?

    public init(
        mediaId: String,
        type: String,
        title: String,
        posterUrl: String? = nil,
        rating: Double? = nil,
        year: String? = nil
    ) {
        self.mediaId = mediaId
        self.type = type
        self.title = title
        self.posterUrl = posterUrl
        self.rating = rating
        self.year = year
    }
}

public struct SlooshUser: Identifiable, Codable, Equatable {
    public let id: String
    public let displayName: String
    public let email: String
    public let avatarUrl: String?
    public let isOnline: Bool?

    public var displayTitle: String {
        if !displayName.isEmpty { return displayName }
        if !email.isEmpty { return email.components(separatedBy: "@").first ?? email }
        return "Пользователь Sloosh"
    }

    public init(id: String, displayName: String, email: String, avatarUrl: String? = nil, isOnline: Bool? = true) {
        self.id = id
        self.displayName = displayName
        self.email = email
        self.avatarUrl = avatarUrl
        self.isOnline = isOnline
    }
}

public struct ChatMessage: Identifiable, Codable, Equatable {
    public let id: String
    public let senderId: String
    public let receiverId: String
    public let type: MessageType
    public let text: String?
    public let media: MediaCardPayload?
    public let timestampMs: Int64

    public init(
        id: String = UUID().uuidString,
        senderId: String,
        receiverId: String,
        type: MessageType = .text,
        text: String? = nil,
        media: MediaCardPayload? = nil,
        timestampMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) {
        self.id = id
        self.senderId = senderId
        self.receiverId = receiverId
        self.type = type
        self.text = text
        self.media = media
        self.timestampMs = timestampMs
    }
}

public struct ChatConversation: Identifiable, Equatable {
    public var id: String { chatId }
    public let chatId: String
    public let peerUser: SlooshUser
    public let lastMessageText: String
    public let unreadCount: Int
    public let updatedAtMs: Int64

    public init(chatId: String, peerUser: SlooshUser, lastMessageText: String, unreadCount: Int = 0, updatedAtMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) {
        self.chatId = chatId
        self.peerUser = peerUser
        self.lastMessageText = lastMessageText
        self.unreadCount = unreadCount
        self.updatedAtMs = updatedAtMs
    }
}
