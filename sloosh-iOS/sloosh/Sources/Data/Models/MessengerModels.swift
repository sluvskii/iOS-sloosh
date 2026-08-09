import Foundation

public enum MessageType: String, Codable, Hashable {
    case text
    case media
}

public struct MediaCardPayload: Codable, Equatable, Hashable {
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

public struct SlooshUser: Identifiable, Codable, Equatable, Hashable {
    public let id: String
    public let displayName: String
    public let email: String
    public let avatarUrl: String?
    public let isOnline: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case email
        case avatarUrl
        case isOnline
    }

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

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decodeIfPresent(String.self, forKey: .id)) ?? ""
        self.displayName = (try? container.decodeIfPresent(String.self, forKey: .displayName)) ?? ""
        self.email = (try? container.decodeIfPresent(String.self, forKey: .email)) ?? ""
        self.avatarUrl = try? container.decodeIfPresent(String.self, forKey: .avatarUrl)
        self.isOnline = try? container.decodeIfPresent(Bool.self, forKey: .isOnline)
    }
}

public struct ChatMessage: Identifiable, Codable, Equatable, Hashable {
    public let id: String
    public let senderId: String
    public let receiverId: String
    public let type: MessageType
    public let text: String?
    public let media: MediaCardPayload?
    public let replyToId: String?
    public let reactions: [String: String]?
    public let isEdited: Bool?
    public let isRead: Bool?

    public init(
        id: String = UUID().uuidString,
        senderId: String,
        receiverId: String,
        type: MessageType = .text,
        text: String? = nil,
        media: MediaCardPayload? = nil,
        timestampMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        replyToId: String? = nil,
        reactions: [String: String]? = nil,
        isEdited: Bool? = nil,
        isRead: Bool? = nil
    ) {
        self.id = id
        self.senderId = senderId
        self.receiverId = receiverId
        self.type = type
        self.text = text
        self.media = media
        self.timestampMs = timestampMs
        self.replyToId = replyToId
        self.reactions = reactions
        self.isEdited = isEdited
        self.isRead = isRead
    }
}

public struct ChatConversation: Identifiable, Equatable, Hashable {
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

