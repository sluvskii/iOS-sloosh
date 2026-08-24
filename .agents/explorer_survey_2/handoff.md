# Handoff Report — Channels Data Layer, Firebase Realtime Database REST Integration, User Identity & Caching

## 1. Observation

Direct examination of the codebase (`sloosh-iOS/sloosh/Sources/Data/` and `sloosh-iOS/sloosh/Sources/UI/Messenger/`) revealed the following existing state:

### 1.1 Existing Network & Firebase Architecture
- **Location**: `sloosh-iOS/sloosh/Sources/Data/Repositories/MessengerRepository.swift:13`
  - Firebase Realtime Database Base URL: `https://sloosh-77434-default-rtdb.firebaseio.com`.
  - HTTP client: Native `URLSession.shared` performing standard REST calls (`GET`, `PUT`, `DELETE`) with JSON serialization.
  - Auth token mechanism (`MessengerRepository.swift:69-76`):
    ```swift
    private func makeURL(path: String) async -> URL? {
        let safePath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        var urlString = "\(databaseBaseURL)/\(safePath).json"
        if let token = await AuthRepository.shared.ensureFreshToken(), !token.isEmpty {
            urlString += "?auth=\(token)"
        }
        return URL(string: urlString)
    }
    ```
  - Firebase Auth REST endpoints are managed in `AuthRepository.swift:165,260` via `identitytoolkit.googleapis.com/v1/accounts:*` with API Key loaded from `GoogleService-Info.plist`.
  - Token refresh occurs via `securetoken.googleapis.com/v1/token` (`AuthRepository.swift:430-474`).

### 1.2 User Identity & Roles
- **Location**: `sloosh-iOS/sloosh/Sources/Data/Models/UserProfile.swift` and `Data/Models/MessengerModels.swift:34-71`
  - `UserProfile`: Contains `id` (Firebase UID or `"guest_\(UUID().prefix(8))"`), `email`, `displayName`, `photoURL`, `isAnonymous`, `provider`, `idToken`, `refreshToken`.
  - `SlooshUser`: Public messenger profile model (`id`, `displayName`, `email`, `avatarUrl`, `isOnline`).
  - Profiles are synchronized to Firebase REST under `/user_profiles/{uid}.json` and `/users/{uid}/profile.json` (`MessengerRepository.swift:80-129`).
  - Search queries fetch and merge `/user_profiles.json` and local cache (`MessengerRepository.swift:131-200`).
  - **Channel Roles Status**: Currently, no Channel or Group Chat models exist in the repository; only 1-to-1 direct chats (`ChatConversation`, `ChatMessage`) are implemented.

### 1.3 Message & Direct Chat Models
- **Location**: `sloosh-iOS/sloosh/Sources/Data/Models/MessengerModels.swift`
  - `MessageType`: Enum (`.text`, `.media`).
  - `MediaCardPayload`: Model for attached movie cards (`mediaId`, `type`, `title`, `posterUrl`, `rating`, `year`).
  - `ChatMessage`: Contains `id`, `senderId`, `receiverId`, `type`, `text`, `media`, `timestampMs`, `replyToId`, `reactions: [String: String]?` (mapped as `userId -> emoji`), `isEdited: Bool?`, `isRead: Bool?`.
  - `ChatConversation`: Direct conversation entry (`chatId`, `peerUser`, `lastMessageText`, `unreadCount`, `updatedAtMs`).

### 1.4 Persistence & Caching Strategy
- **Location**: `MessengerRepository.swift:19-50`
  - `loadConversationsFromDisk()` / `saveConversationsToDisk()`: Uses `UserDefaults` with key `sloosh_messenger_conversations_v1` for 0ms instant cold start.
  - `loadMessagesFromDisk(chatId:)` / `saveMessagesToDisk(_:chatId:)`: Uses `UserDefaults` with key `sloosh_messenger_messages_v1_{chatId}`.
  - `MediaDetailsDiskCache` & `MediaListDiskCache` in `MoviesRepository.swift:328-383`: Uses `CachesDirectory` with JSON files and TTL.

---

## 2. Logic Chain

1. **Channels Requirement**: The application requires Telegram-style broadcasting channels where:
   - Only the Channel Owner / Author can publish, edit, pin, and delete posts.
   - Subscribers / Viewers receive a read-only stream with emoji reactions, direct movie playback, details sheet navigation, and subscription toggles.
   - Public channels can be searched and discovered in `MessengerView`.
2. **Schema Design Rationale**:
   - Storing channel metadata at `/channels/{channelId}.json` allows both single-channel fetching and querying all public channels at `/channels.json`.
   - Storing posts at `/channel_posts/{channelId}/{postId}.json` isolates high-frequency post operations from metadata updates.
   - Storing subscriptions symmetrically at `/user_channel_subscriptions/{userId}/{channelId}.json` allows 1-query instant loading of all user channels without scanning the entire database.
   - Storing subscriber counts directly on `/channels/{channelId}/subscriberCount` allows instant O(1) display in search results and feeds.
3. **Data Model Compatibility**:
   - Reusing `MediaCardPayload` ensures 100% interoperability with `MediaMessageCardView`, `PlayerView`, and `DetailsView`.
   - Aligning `ChannelPost.reactions` as `[String: String]` (mapping `userId -> emoji`) maintains identical semantics to `ChatMessage.reactions`, preventing multi-vote duplicate exploits per user and enabling simple aggregation into pill counters `(emoji, count, isReactedByMe)`.
4. **Instant Cold-Start Caching**:
   - Storing subscribed channels in `UserDefaults` (`sloosh_messenger_subscribed_channels_v1`) and channel posts (`sloosh_channel_posts_v1_{channelId}`) matches the existing proven pattern in `MessengerRepository`, giving 0ms cold-start render upon app launch.

---

## 3. Detailed Data Architecture Specification

### 3.1 Firebase Realtime Database REST Schema Proposal

```
Firebase Root (https://sloosh-77434-default-rtdb.firebaseio.com)
├── channels/
│   └── {channelId}/
│       ├── id: string (e.g. "ch_1724543940123_a1b2")
│       ├── name: string (e.g. "Киноновинки 2026")
│       ├── description: string (e.g. "Главные премьеры и подборки Sloosh")
│       ├── avatarEmoji: string? (e.g. "🎬")
│       ├── avatarUrl: string? (optional)
│       ├── accentColorHex: string (e.g. "#FF453A")
│       ├── ownerId: string (UID of creator)
│       ├── ownerName: string (display name of creator)
│       ├── createdAtMs: number (timestamp in ms)
│       ├── updatedAtMs: number (timestamp in ms)
│       ├── subscriberCount: number
│       ├── pinnedPostId: string? (id of currently pinned post, if any)
│       ├── isPublic: boolean (true by default)
│       ├── lastPostText: string? (preview text for list row)
│       └── lastPostTimestampMs: number?
│
├── channel_posts/
│   └── {channelId}/
│       └── {postId}/
│           ├── id: string (e.g. "post_1724544000123_c3d4")
│           ├── channelId: string
│           ├── authorId: string
│           ├── text: string?
│           ├── media: {
│           │     mediaId: string,
│           │     type: string,
│           │     title: string,
│           │     posterUrl: string?,
│           │     rating: number?,
│           │     year: string?
│           │   }?
│           ├── reactions: {
│           │     "{userId}": "🔥",
│           │     "{userId2}": "❤️"
│           │   }?
│           ├── timestampMs: number
│           ├── isPinned: boolean
│           ├── isEdited: boolean?
│           └── viewsCount: number?
│
├── channel_subscribers/
│   └── {channelId}/
│       └── {userId}: {
│             "subscribedAtMs": number
│           }
│
└── user_channel_subscriptions/
    └── {userId}/
        └── {channelId}: {
              "channelId": string,
              "channel": { ...ChannelModel snapshot... },
              "subscribedAtMs": number,
              "isMuted": boolean
            }
```

---

### 3.2 Swift Data Models & DTOs to Add/Update (`MessengerModels.swift`)

```swift
import Foundation
import SwiftUI

// MARK: - Channel Model

public struct ChannelModel: Identifiable, Codable, Equatable, Hashable {
    public let id: String
    public let name: String
    public let description: String
    public let avatarEmoji: String?
    public let avatarUrl: String?
    public let accentColorHex: String?
    public let ownerId: String
    public let ownerName: String
    public let createdAtMs: Int64
    public var updatedAtMs: Int64
    public var subscriberCount: Int
    public var pinnedPostId: String?
    public var isPublic: Bool
    public var lastPostText: String?
    public var lastPostTimestampMs: Int64?

    public init(
        id: String = "ch_\(Int64(Date().timeIntervalSince1970 * 1000))_\(UUID().uuidString.prefix(6))",
        name: String,
        description: String = "",
        avatarEmoji: String? = "📢",
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

    public var displayAvatarEmoji: String {
        avatarEmoji?.isEmpty == false ? avatarEmoji! : "📢"
    }

    public var displayAccentColor: Color {
        if let hex = accentColorHex, let uiColor = UIColor(hex: hex) {
            return Color(uiColor)
        }
        return Color.slooshAccent
    }

    public var formattedSubscriberCount: String {
        if subscriberCount <= 1 {
            return "1 подписчик"
        }
        let remainder10 = subscriberCount % 10
        let remainder100 = subscriberCount % 100
        if remainder10 == 1 && remainder100 != 11 {
            return "\(subscriberCount) подписчик"
        } else if [2, 3, 4].contains(remainder10) && ![12, 13, 14].contains(remainder100) {
            return "\(subscriberCount) подписчика"
        } else {
            return "\(subscriberCount) подписчиков"
        }
    }
}

// MARK: - Channel Post Model

public struct ChannelPost: Identifiable, Codable, Equatable, Hashable {
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

    public init(
        id: String = "post_\(Int64(Date().timeIntervalSince1970 * 1000))_\(UUID().uuidString.prefix(6))",
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

    /// Aggregates reactions into distinct emojis with total count and current user reaction flag
    public func reactionSummary(currentUserId: String) -> [(emoji: String, count: Int, isMine: Bool)] {
        guard let reactions = reactions, !reactions.isEmpty else { return [] }
        var counts: [String: Int] = [:]
        for (_, emoji) in reactions {
            counts[emoji, default: 0] += 1
        }
        let myEmoji = reactions[currentUserId]
        return counts.map { (emoji, count) in
            (emoji: emoji, count: count, isMine: myEmoji == emoji)
        }.sorted { $0.count > $1.count }
    }
}

// MARK: - Channel User Subscription

public struct ChannelSubscription: Codable, Equatable, Hashable {
    public let channelId: String
    public let channel: ChannelModel?
    public let subscribedAtMs: Int64
    public var isMuted: Bool

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
}

// MARK: - Unified Messenger Feed Item

public enum MessengerFeedItem: Identifiable, Hashable {
    case directChat(ChatConversation)
    case channel(ChannelModel)

    public var id: String {
        switch self {
        case .directChat(let chat): return "chat_\(chat.chatId)"
        case .channel(let ch): return "ch_\(ch.id)"
        }
    }

    public var timestampMs: Int64 {
        switch self {
        case .directChat(let chat): return chat.updatedAtMs
        case .channel(let ch): return ch.lastPostTimestampMs ?? ch.updatedAtMs
        }
    }
}
```

---

### 3.3 Proposed Repository Method Signatures (`MessengerRepository.swift`)

```swift
// MARK: - Channels State
@Published public private(set) var subscribedChannels: [ChannelModel] = []
@Published public private(set) var publicChannels: [ChannelModel] = []

// MARK: - Channel Disk Caching
public func saveSubscribedChannelsToDisk(_ list: [ChannelModel])
public func loadSubscribedChannelsFromDisk() -> [ChannelModel]
public func savePublicChannelsToDisk(_ list: [ChannelModel])
public func loadPublicChannelsFromDisk() -> [ChannelModel]
public func saveChannelPostsToDisk(_ posts: [ChannelPost], channelId: String)
public func loadChannelPostsFromDisk(channelId: String) -> [ChannelPost]

// MARK: - Channel Lifecycle (CRUD)
public func createChannel(
    name: String,
    description: String,
    avatarEmoji: String?,
    accentColorHex: String?
) async -> ChannelModel?

public func updateChannelMetadata(channel: ChannelModel) async -> Bool
public func deleteChannel(channelId: String) async -> Bool

// MARK: - Channel Subscriptions & Discovery
public func fetchSubscribedChannels() async -> [ChannelModel]
public func fetchPublicChannels(query: String? = nil) async -> [ChannelModel]
public func isSubscribed(channelId: String) -> Bool
public func subscribeToChannel(channel: ChannelModel) async -> Bool
public func unsubscribeFromChannel(channelId: String) async -> Bool

// MARK: - Channel Posts & Reactions
public func fetchChannelPosts(channelId: String) async -> [ChannelPost]
public func publishChannelPost(
    channelId: String,
    text: String?,
    mediaPayload: MediaCardPayload?,
    isPinned: Bool
) async -> ChannelPost?

public func editChannelPost(
    channelId: String,
    postId: String,
    newText: String?,
    mediaPayload: MediaCardPayload?
) async -> Bool

public func deleteChannelPost(channelId: String, postId: String) async -> Bool
public func togglePinChannelPost(channelId: String, postId: String, isPinned: Bool) async -> Bool
public func toggleChannelPostReaction(channelId: String, postId: String, emoji: String) async -> Bool
```

---

### 3.4 UIColor Hex Extension Helper
To support customizable channel accent colors (`accentColorHex`), add a standard hex initializer in `Color+Theme.swift`:
```swift
extension UIColor {
    convenience init?(hex: String) {
        var cleanHex = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleanHex.hasPrefix("#") { cleanHex.removeFirst() }
        guard cleanHex.count == 6, let rgbValue = UInt64(cleanHex, radix: 16) else { return nil }
        self.init(
            red: CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0,
            green: CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0,
            blue: CGFloat(rgbValue & 0x0000FF) / 255.0,
            alpha: 1.0
        )
    }
}
```

---

## 4. Caveats

1. **Firebase Security Rules**: Realtime Database rules must permit read/write on `/channels`, `/channel_posts`, `/channel_subscribers`, and `/user_channel_subscriptions`. If rules are configured with strict user auth, `auth != null` will be required.
2. **Atomic Subscriber Count Increment**: In Firebase RTDB REST API, there is no direct atomic transaction operator via plain `PUT`. Subscribing / unsubscribing updates the count by fetching current metadata, modifying `subscriberCount`, and saving. To ensure count stability, `subscriberCount` can also be calculated as `count(channel_subscribers/{channelId})`.
3. **No ultraThinMaterial**: In all channel UI implementations (`ChannelDetailView`, `CreateChannelSheet`, `ChannelInfoView`), only `.glassEffect()` and `Color.slooshAccent` must be used, adhering strictly to AGENTS.md rules.

---

## 5. Conclusion

- The existing Data Layer architecture in `MessengerRepository.swift` and `AuthRepository.swift` provides a reliable foundation using Firebase Realtime Database REST API and local disk persistence.
- The proposed schema cleanly integrates Channels, Posts, Media Attachments, Reactions, Pinned Posts, and Subscriptions with zero schema collisions.
- The data models and repository methods are fully specified and ready for implementation.

---

## 6. Verification Method

1. **Data Model Validation**: Verify that `ChannelModel`, `ChannelPost`, `ChannelSubscription`, and `MessengerFeedItem` compile without errors and satisfy `Codable`, `Identifiable`, `Equatable`, `Hashable`.
2. **REST Endpoint Testing**: Verify Firebase REST endpoints:
   - `PUT https://sloosh-77434-default-rtdb.firebaseio.com/channels/{channelId}.json`
   - `GET https://sloosh-77434-default-rtdb.firebaseio.com/channels.json`
   - `PUT https://sloosh-77434-default-rtdb.firebaseio.com/channel_posts/{channelId}/{postId}.json`
   - `GET https://sloosh-77434-default-rtdb.firebaseio.com/channel_posts/{channelId}.json`
3. **Disk Cache Cold-Start Validation**:
   - Verify that `loadSubscribedChannelsFromDisk()` returns stored channels instantly before network calls return.
   - Verify that `loadChannelPostsFromDisk(channelId:)` renders initial channel posts instantly.
