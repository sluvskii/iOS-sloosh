import Foundation
import UIKit
import SwiftUI

// MARK: - Tag Validation Helper

public enum TagValidator {
    public static func sanitize(_ rawTag: String) -> String {
        var clean = rawTag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while clean.hasPrefix("@") {
            clean.removeFirst()
        }
        return clean.filter { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    public static func validate(_ tag: String) -> (isValid: Bool, message: String) {
        let clean = sanitize(tag)
        if clean.count < 3 {
            return (false, "Тег должен содержать минимум 3 символа")
        }
        if clean.count > 30 {
            return (false, "Тег не должен превышать 30 символов")
        }
        let pattern = "^[a-z0-9_]{3,30}$"
        guard clean.range(of: pattern, options: .regularExpression) != nil else {
            return (false, "Разрешены только латинские буквы, цифры и символ _")
        }
        let reserved: Set<String> = ["sloosh", "admin", "support", "official", "channel", "user", "help"]
        if reserved.contains(clean) {
            return (false, "Этот тег зарезервирован системой")
        }
        return (true, "Формат тега корректен")
    }
}

// MARK: - Message Types & Media Payload

public enum MessageType: String, Codable, Sendable, Hashable {
    case text
    case media
}

public struct MediaCardPayload: Identifiable, Codable, Sendable, Equatable, Hashable {
    public var id: String { mediaId }
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

// MARK: - Sloosh User Model (Privacy Sanitized)

public struct SlooshUser: Identifiable, Codable, Sendable, Equatable, Hashable {
    public let id: String
    public let displayName: String
    public let tag: String?
    public let avatarUrl: String?
    public let isOnline: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case tag
        case avatarUrl
        case isOnline
        case email // Decoded for backward compatibility only
    }

    public var displayTitle: String {
        if !displayName.isEmpty { return displayName }
        if let tag = tag, !tag.isEmpty { return "@\(tag)" }
        return "Пользователь Sloosh"
    }

    public var displayTag: String {
        if let tag = tag, !tag.isEmpty { return "@\(tag)" }
        return ""
    }

    public var avatarInitials: String {
        let name = displayName.isEmpty ? (tag ?? "S") : displayName
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(1)).uppercased()
    }

    public init(
        id: String,
        displayName: String,
        tag: String? = nil,
        avatarUrl: String? = nil,
        isOnline: Bool? = true
    ) {
        self.id = id
        self.displayName = displayName
        self.tag = tag
        self.avatarUrl = avatarUrl
        self.isOnline = isOnline
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decodeIfPresent(String.self, forKey: .id)) ?? ""
        self.displayName = (try? container.decodeIfPresent(String.self, forKey: .displayName)) ?? ""
        self.tag = try? container.decodeIfPresent(String.self, forKey: .tag)
        self.avatarUrl = try? container.decodeIfPresent(String.self, forKey: .avatarUrl)
        self.isOnline = try? container.decodeIfPresent(Bool.self, forKey: .isOnline)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encodeIfPresent(tag, forKey: .tag)
        try container.encodeIfPresent(avatarUrl, forKey: .avatarUrl)
        try container.encodeIfPresent(isOnline, forKey: .isOnline)
    }
}

// MARK: - Chat Message Model

public struct ChatMessage: Identifiable, Codable, Sendable, Equatable, Hashable {
    public let id: String
    public let senderId: String
    public let receiverId: String
    public let type: MessageType
    public let text: String?
    public let media: MediaCardPayload?
    public let timestampMs: Int64
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

// MARK: - Chat Conversation Model

public struct ChatConversation: Identifiable, Codable, Sendable, Equatable, Hashable {
    public var id: String { chatId }
    public let chatId: String
    public let peerUser: SlooshUser
    public let lastMessageText: String
    public let unreadCount: Int
    public let updatedAtMs: Int64

    public init(
        chatId: String,
        peerUser: SlooshUser,
        lastMessageText: String,
        unreadCount: Int = 0,
        updatedAtMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) {
        self.chatId = chatId
        self.peerUser = peerUser
        self.lastMessageText = lastMessageText
        self.unreadCount = unreadCount
        self.updatedAtMs = updatedAtMs
    }
}

// MARK: - Channel Model

public struct ChannelModel: Identifiable, Codable, Sendable, Equatable, Hashable {
    public let id: String
    public var tag: String
    public var name: String
    public var description: String
    public var avatarEmoji: String?
    public var avatarUrl: String?
    public var accentColorHex: String?
    public let ownerId: String
    public var ownerName: String
    public let createdAtMs: Int64
    public var updatedAtMs: Int64
    public var subscriberCount: Int
    public var pinnedPostId: String?
    public var isPublic: Bool
    public var lastPostText: String?
    public var lastPostTimestampMs: Int64?

    enum CodingKeys: String, CodingKey {
        case id
        case tag
        case name
        case description
        case avatarEmoji
        case avatarUrl
        case accentColorHex
        case ownerId
        case ownerName
        case createdAtMs
        case updatedAtMs
        case subscriberCount
        case pinnedPostId
        case isPublic
        case lastPostText
        case lastPostTimestampMs
    }

    public init(
        id: String = "ch_\(Int64(Date().timeIntervalSince1970 * 1000))_\(UUID().uuidString.prefix(6).lowercased())",
        tag: String,
        name: String,
        description: String = "",
        avatarEmoji: String? = nil,
        avatarUrl: String? = nil,
        accentColorHex: String? = "#FF9F0A",
        ownerId: String,
        ownerName: String,
        createdAtMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        updatedAtMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        subscriberCount: Int = 1,
        pinnedPostId: String? = nil,
        isPublic: Bool = true,
        lastPostText: String? = nil,
        lastPostTimestampMs: Int64? = nil
    ) {
        self.id = id
        let clean = TagValidator.sanitize(tag)
        self.tag = clean.isEmpty ? "channel_\(id.prefix(6))" : clean
        self.name = name
        self.description = description
        self.avatarEmoji = avatarEmoji
        self.avatarUrl = avatarUrl
        self.accentColorHex = accentColorHex
        self.ownerId = ownerId
        self.ownerName = ownerName
        self.createdAtMs = createdAtMs
        self.updatedAtMs = updatedAtMs
        self.subscriberCount = subscriberCount
        self.pinnedPostId = pinnedPostId
        self.isPublic = isPublic
        self.lastPostText = lastPostText
        self.lastPostTimestampMs = lastPostTimestampMs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedId = (try? container.decodeIfPresent(String.self, forKey: .id)) ?? ""
        self.id = decodedId

        let decodedTag = try? container.decodeIfPresent(String.self, forKey: .tag)
        if let t = decodedTag, !t.isEmpty {
            self.tag = TagValidator.sanitize(t)
        } else {
            self.tag = "channel_\(decodedId.prefix(6))"
        }

        self.name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? ""
        self.description = (try? container.decodeIfPresent(String.self, forKey: .description)) ?? ""
        self.avatarEmoji = try? container.decodeIfPresent(String.self, forKey: .avatarEmoji)
        self.avatarUrl = try? container.decodeIfPresent(String.self, forKey: .avatarUrl)
        self.accentColorHex = try? container.decodeIfPresent(String.self, forKey: .accentColorHex)
        self.ownerId = (try? container.decodeIfPresent(String.self, forKey: .ownerId)) ?? ""
        self.ownerName = (try? container.decodeIfPresent(String.self, forKey: .ownerName)) ?? ""
        self.createdAtMs = (try? container.decodeIfPresent(Int64.self, forKey: .createdAtMs)) ?? Int64(Date().timeIntervalSince1970 * 1000)
        self.updatedAtMs = (try? container.decodeIfPresent(Int64.self, forKey: .updatedAtMs)) ?? self.createdAtMs
        self.subscriberCount = (try? container.decodeIfPresent(Int.self, forKey: .subscriberCount)) ?? 1
        self.pinnedPostId = try? container.decodeIfPresent(String.self, forKey: .pinnedPostId)
        self.isPublic = (try? container.decodeIfPresent(Bool.self, forKey: .isPublic)) ?? true
        self.lastPostText = try? container.decodeIfPresent(String.self, forKey: .lastPostText)
        self.lastPostTimestampMs = try? container.decodeIfPresent(Int64.self, forKey: .lastPostTimestampMs)
    }

    public var displayTag: String {
        "@\(tag)"
    }

    public var formattedTag: String {
        "@\(tag)"
    }

    public var avatarInitials: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(1)).uppercased()
    }

    public var displayAvatarEmoji: String {
        if let emoji = avatarEmoji, !emoji.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return emoji
        }
        return "📢"
    }

    public var displayAccentColor: Color {
        if let hex = accentColorHex, let uiColor = UIColor(hex: hex) {
            return Color(uiColor)
        }
        return Color.slooshAccent
    }

    public var formattedSubscriberCount: String {
        let count = max(0, subscriberCount)
        let mod10 = count % 10
        let mod100 = count % 100
        if mod10 == 1 && mod100 != 11 {
            return "\(count) подписчик"
        } else if (2...4).contains(mod10) && !(12...14).contains(mod100) {
            return "\(count) подписчика"
        } else {
            return "\(count) подписчиков"
        }
    }
}

// MARK: - Channel Post Model

public struct ChannelPost: Identifiable, Codable, Sendable, Equatable, Hashable {
    public let id: String
    public let channelId: String
    public let authorId: String
    public var text: String?
    public var media: MediaCardPayload?
    public var reactions: [String: String]? // [userId: emoji]
    public let timestampMs: Int64
    public var isPinned: Bool
    public var isEdited: Bool?
    public var viewsCount: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case channelId
        case authorId
        case text
        case media
        case reactions
        case timestampMs
        case isPinned
        case isEdited
        case viewsCount
    }

    public init(
        id: String = "post_\(Int64(Date().timeIntervalSince1970 * 1000))_\(UUID().uuidString.prefix(6).lowercased())",
        channelId: String,
        authorId: String,
        text: String? = nil,
        media: MediaCardPayload? = nil,
        reactions: [String: String]? = nil,
        timestampMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        isPinned: Bool = false,
        isEdited: Bool? = nil,
        viewsCount: Int? = nil
    ) {
        self.id = id
        self.channelId = channelId
        self.authorId = authorId
        self.text = text
        self.media = media
        self.reactions = reactions
        self.timestampMs = timestampMs
        self.isPinned = isPinned
        self.isEdited = isEdited
        self.viewsCount = viewsCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decodeIfPresent(String.self, forKey: .id)) ?? ""
        self.channelId = (try? container.decodeIfPresent(String.self, forKey: .channelId)) ?? ""
        self.authorId = (try? container.decodeIfPresent(String.self, forKey: .authorId)) ?? ""
        self.text = try? container.decodeIfPresent(String.self, forKey: .text)
        self.media = try? container.decodeIfPresent(MediaCardPayload.self, forKey: .media)
        self.reactions = try? container.decodeIfPresent([String: String].self, forKey: .reactions)
        self.timestampMs = (try? container.decodeIfPresent(Int64.self, forKey: .timestampMs)) ?? Int64(Date().timeIntervalSince1970 * 1000)
        self.isPinned = (try? container.decodeIfPresent(Bool.self, forKey: .isPinned)) ?? false
        self.isEdited = try? container.decodeIfPresent(Bool.self, forKey: .isEdited)
        self.viewsCount = try? container.decodeIfPresent(Int.self, forKey: .viewsCount)
    }

    public func reactionSummary(currentUserId: String) -> [(emoji: String, count: Int, isMine: Bool)] {
        guard let reactions = reactions, !reactions.isEmpty else { return [] }
        var counts: [String: Int] = [:]
        for (_, emoji) in reactions {
            counts[emoji, default: 0] += 1
        }
        let myEmoji = reactions[currentUserId]
        return counts.map { (emoji, count) in
            (emoji: emoji, count: count, isMine: myEmoji == emoji)
        }.sorted { first, second in
            if first.count != second.count {
                return first.count > second.count
            }
            return first.emoji < second.emoji
        }
    }
}

// MARK: - Channel User Subscription

public struct ChannelSubscription: Codable, Sendable, Equatable, Hashable {
    public let channelId: String
    public var channel: ChannelModel?
    public let subscribedAtMs: Int64
    public var isMuted: Bool

    enum CodingKeys: String, CodingKey {
        case channelId
        case channel
        case subscribedAtMs
        case isMuted
    }

    public init(
        channelId: String,
        channel: ChannelModel? = nil,
        subscribedAtMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        isMuted: Bool = false
    ) {
        self.channelId = channelId
        self.channel = channel
        self.subscribedAtMs = subscribedAtMs
        self.isMuted = isMuted
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.channelId = (try? container.decodeIfPresent(String.self, forKey: .channelId)) ?? ""
        self.channel = try? container.decodeIfPresent(ChannelModel.self, forKey: .channel)
        self.subscribedAtMs = (try? container.decodeIfPresent(Int64.self, forKey: .subscribedAtMs)) ?? Int64(Date().timeIntervalSince1970 * 1000)
        self.isMuted = (try? container.decodeIfPresent(Bool.self, forKey: .isMuted)) ?? false
    }
}

// MARK: - Unified Messenger Feed Item

public enum MessengerFeedItem: Identifiable, Sendable, Hashable {
    case directChat(ChatConversation)
    case channel(ChannelModel)

    public var id: String {
        switch self {
        case .directChat(let chat):
            return "chat_\(chat.chatId)"
        case .channel(let ch):
            return "channel_\(ch.id)"
        }
    }

    public var timestampMs: Int64 {
        switch self {
        case .directChat(let chat):
            return chat.updatedAtMs
        case .channel(let ch):
            return ch.lastPostTimestampMs ?? ch.updatedAtMs
        }
    }
}
