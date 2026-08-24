# Analysis Report: Sloosh Channels & Messenger Tag & Privacy Architecture (R1)

**Author:** Explorer 1  
**Date:** 2026-08-25  
**Working Directory:** `W:\iOS-sloosh\.agents\explorer_1\`  
**Target Projects:** `sloosh-iOS` (primary), `neomovies-mobile` (reference)

---

## 1. Executive Summary

This investigation covers the architectural foundation for **R1 (Unique Tags & Complete Privacy)** of the Sloosh Channels and Messenger refactor. 

Currently, the Sloosh Messenger operates without a dedicated tag indexing system. Channels and users are identified primarily by generated strings or Firebase Auth UIDs, and raw user emails are leaked in multiple screens (user search rows, chat detail info headers, and Firebase RTDB public nodes).

To achieve R1, this report details:
1. A **Two-Tier Tag Index Architecture** in Firebase Realtime Database (`/channelTags/{tag}` and `/userTags/{tag}`) ensuring global uniqueness with $O(1)$ availability validation and lookup.
2. An **Instant @Tag Search Engine** integrated into `MessengerRepository` and `MessengerView`, distinguishing between instant tag lookup (for queries starting with `@`) and fuzzy text search.
3. A **Zero-Leak Privacy Architecture** that completely purges raw emails and internal UUIDs from public models, network payloads, and UI views, replacing them exclusively with Display Names and `@tag` handles.
4. Concrete code specifications and line-by-line file audits across all data models, repositories, and UI components.

---

## 2. Current State vs. Target Architecture

| Component | Current State | Target State (R1) |
|---|---|---|
| **Channel Identifier** | Auto-generated ID (`ch_172...`) only; no unique tag index. | Unique `@tag` chosen at creation (e.g. `@cinema_club`), indexed in `/channelTags/{tag}`. |
| **User Identifier** | Display Name + raw `email` fallback; internal UID visible in info screen. | Display Name + unique `@username` / `@tag`, indexed in `/userTags/{tag}`. Zero UID exposure. |
| **Email Privacy** | Exposed in `PeakUserSearchRow`, `ChatInfoView`, and Firebase public nodes `/user_profiles`. | **Strictly hidden** from peers across all UI screens, message payloads, and public RTDB nodes. |
| **Messenger Search** | Scans all downloaded profiles and filters by name/email/ID substring. | Instant $O(1)$ lookup for `@tag` queries; name/tag substring search for plain queries. Zero email matching. |
| **Tag Validation** | None. | Alphanumeric + underscore regex (`^[a-z0-9_]{3,30}$`), lowercase normalized, availability check before save. |

---

## 3. Firebase Realtime Database Schema & Tag Indexing

### 3.1 New Tag Index Nodes

#### 1. `/channelTags/{tag}`
- **Purpose**: Global uniqueness index mapping a normalized channel handle directly to its `channelId`.
- **Path**: `https://sloosh-77434-default-rtdb.firebaseio.com/channelTags/{tag}.json`
- **Key**: Normalized tag (lowercase, without leading `@`, e.g. `"cinema_club"`).
- **Value**: Channel ID string (e.g. `"ch_1724541234_abc123"`).
- **Operations**:
  - **Check Availability**: `GET /channelTags/{tag}.json` → returns `null` if available, or `"ch_..."` if taken.
  - **Claim Tag (Create)**: `PUT /channelTags/{tag}.json` with `"channelId"`.
  - **Release Tag (Delete)**: `DELETE /channelTags/{tag}.json`.
  - **Direct Lookup**: `GET /channelTags/{tag}.json` → returns `channelId` for instant resolution.

#### 2. `/userTags/{tag}`
- **Purpose**: Global uniqueness index mapping a normalized user handle directly to their `userId` (UID).
- **Path**: `https://sloosh-77434-default-rtdb.firebaseio.com/userTags/{tag}.json`
- **Key**: Normalized tag (lowercase, without leading `@`, e.g. `"alex_sloosh"`).
- **Value**: Firebase Auth UID string (e.g. `"uid_98765"`).
- **Operations**:
  - **Check Availability**: `GET /userTags/{tag}.json` → returns `null` if available, or `"uid_..."` if taken.
  - **Claim / Update Tag**: `PUT /userTags/{tag}.json` with `"userId"`. If updating, `DELETE /userTags/{oldTag}.json`.
  - **Direct Lookup**: `GET /userTags/{tag}.json` → returns `userId` for instant profile resolution.

### 3.2 Modified Public Data Nodes

#### 1. `/user_profiles/{uid}` (Public User Directory)
- **Current Payload (LEAKS EMAIL)**:
  ```json
  {
    "id": "abc123uid",
    "displayName": "Alex",
    "email": "alex@example.com",
    "avatarUrl": "https://...",
    "isOnline": true
  }
  ```
- **Target R1 Payload (PRIVACY PROTECTED)**:
  ```json
  {
    "id": "abc123uid",
    "displayName": "Alex",
    "tag": "alex_sloosh",
    "avatarUrl": "https://...",
    "isOnline": true
  }
  ```
  *(Note: `email` is completely removed from `/user_profiles/{uid}`!)*

#### 2. `/channels/{channelId}` (Channel Document)
- **Target R1 Payload**:
  ```json
  {
    "id": "ch_1724541234_abc123",
    "tag": "cinema_club",
    "name": "Киноклуб Sloosh",
    "description": "Обсуждаем новинки кино",
    "avatarUrl": "https://...",
    "accentColorHex": "#FF9F0A",
    "ownerId": "abc123uid",
    "ownerName": "Alex",
    "createdAtMs": 1724541234000,
    "updatedAtMs": 1724541234000,
    "subscriberCount": 1,
    "pinnedPostId": null,
    "isPublic": true,
    "lastPostText": null,
    "lastPostTimestampMs": null
  }
  ```

#### 3. `/user_chats/{uid}/{chatId}` (Direct Conversation Summary)
- **Target R1 Payload**:
  ```json
  {
    "chatId": "uidA_uidB",
    "peerUser": {
      "id": "peerUid",
      "displayName": "Alex",
      "tag": "alex_sloosh",
      "avatarUrl": "https://..."
    },
    "lastMessageText": "Привет!",
    "unreadCount": 0,
    "updatedAtMs": 1724541234000
  }
  ```
  *(Note: `peerUser.email` is purged from chat entries).*

---

## 4. Tag Validation & Lifecycle Engine

### 4.1 Tag Sanitization Rules
1. **Allowed Characters**: Latin letters `a-z`, digits `0-9`, and underscore `_`.
2. **Length Limit**: 3 to 30 characters inclusive (`^[a-z0-9_]{3,30}$`).
3. **Normalization**: Automatic lowercasing and trimming of leading/trailing whitespaces and `@` symbol.
4. **Reserved Words**: `sloosh`, `admin`, `support`, `official`, `channel`, `user`, `help`.

```swift
public enum TagValidator {
    public static func sanitize(_ rawTag: String) -> String {
        var clean = rawTag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if clean.hasPrefix("@") {
            clean.removeFirst()
        }
        return clean.filter { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    public static func validate(_ tag: String) -> TagValidationResult {
        let clean = sanitize(tag)
        if clean.count < 3 {
            return .invalid("Тег должен содержать не менее 3 символов")
        }
        if clean.count > 30 {
            return .invalid("Тег не должен превышать 30 символов")
        }
        let pattern = "^[a-z0-9_]{3,30}$"
        guard clean.range(of: pattern, options: .regularExpression) != nil else {
            return .invalid("Разрешены только латинские буквы, цифры и символ _")
        }
        let reserved: Set<String> = ["sloosh", "admin", "support", "official", "channel", "user"]
        if reserved.contains(clean) {
            return .invalid("Этот тег зарезервирован системой")
        }
        return .valid(clean)
    }
}
```

---

## 5. Instant @Tag Search Architecture

### 5.1 Dual-Mode Search Strategy in `MessengerRepository`

When the user enters a search query in `MessengerView`:

```
User types query in SearchBar
         │
         ├── Query starts with "@" or looks like tag (e.g. "@cinema", "cinema_club")
         │     │
         │     ├── 1. Direct O(1) REST lookup: GET /channelTags/{cleanTag}.json
         │     │      └─ If match found → fetch /channels/{channelId}.json
         │     │
         │     ├── 2. Direct O(1) REST lookup: GET /userTags/{cleanTag}.json
         │     │      └─ If match found → fetch /user_profiles/{userId}.json
         │     │
         │     └── 3. Local filter on cached channels and users by `tag.contains(cleanTag)`
         │
         └── Plain text query (e.g. "кино", "алексей")
               │
               ├── Local + Remote search on channels: `name` & `description` contains query
               └── Local + Remote search on users: `displayName` & `tag` contains query
               (Zero matching by email or internal UUID!)
```

### 5.2 Benefits
- **Zero Latency**: Direct tag lookup completes in a single lightweight HTTP request (< 80ms), rather than scanning the entire Firebase tree.
- **Privacy Guaranteed**: No searching by email or internal user ID.

---

## 6. Comprehensive Privacy Leak Audit & Remediation

| File | Line(s) | Current Leak / Flaw | Remediation Action |
|---|---|---|---|
| `Data/Models/MessengerModels.swift` | 39, 46, 53, 60, 69 | `SlooshUser.email` is stored and used in `displayTitle` fallback. | Remove `email` from public peer structure. Add `tag: String?`. Update `displayTitle` fallback to `@tag` or `"Пользователь Sloosh"`. |
| `Data/Models/MessengerModels.swift` | 134-248 | `ChannelModel` has no `tag` field; relies solely on internal `id`. | Add `tag: String` (with `@tag` formatted accessor). |
| `Data/Models/UserProfile.swift` | 3, 26, 43-45, 53 | `UserProfile` lacks `tag: String?`. `displaySubtitle` returns raw email. | Add `tag: String?`. In public contexts, never expose `email`. |
| `Data/Repositories/MessengerRepository.swift` | 134, 145-159 | `syncCurrentUserProfile` uploads `email` to `/user_profiles/{uid}`. | Purge `email` from public upload payload. Upload `tag` instead. |
| `Data/Repositories/MessengerRepository.swift` | 221-223 | `searchUsers` matches against `slooshUser.email` and `slooshUser.id`. | Remove email and ID matching. Match only `displayName` and `tag`. |
| `Data/Repositories/MessengerRepository.swift` | 583, 611 | `postMessageToFirebase` writes `"email": peerUser.email` to `user_chats`. | Remove `"email"` field from `senderEntry` and `receiverEntry`. Write `"tag"` instead. |
| `Data/Repositories/MessengerRepository.swift` | 700-778 | `createChannel` creates channel without unique `@tag` and without updating `/channelTags`. | Add `tag` parameter, check `/channelTags/{tag}`, claim `/channelTags/{tag}`, and store `tag` in `ChannelModel`. |
| `Data/Repositories/MessengerRepository.swift` | 820-866 | `deleteChannel` does not delete `/channelTags/{tag}`. | Delete `/channelTags/{channel.tag}` during channel deletion. |
| `UI/Messenger/MessengerView.swift` | 39 | `unifiedFeedItems` filters conversations by `peerUser.email`. | Remove `email` filtering. Filter by `peerUser.displayTitle` and `peerUser.tag`. |
| `UI/Messenger/MessengerView.swift` | 749-753 | `PeakUserSearchRow` displays `user.email` under the user's name. | Replace with `Text("@\(user.tag ?? "")").foregroundColor(.slooshAccent)`. Never display email! |
| `UI/Messenger/ChatDetailView.swift` | 740-759 | `ChatInfoView` displays peer's raw email in an "Email" info row. | **Remove Email info row completely.** |
| `UI/Messenger/ChatDetailView.swift` | 761-776 | `ChatInfoView` displays `peerUser.id` (internal UUID) in "ID пользователя" row. | **Remove UUID info row completely.** Display `@peerUser.tag` instead. |
| `UI/Messenger/ChannelInfoView.swift` | 588-615 | `ChannelInfoView` renders fake domain link `sloosh.app/\(channel.id.prefix(10))`. | Replace with `@\(channel.tag)` handle badge. |
| `UI/Messenger/CreateChannelSheet.swift` | 10-184 | Channel creation lacks `@tag` input and availability check. | Add Tag text field with `@` prefix, realtime availability validator against `/channelTags/{tag}`, and submit validated tag. |
| `UI/Profile/ProfileView.swift` | 116, 145 | Profile header / sign out alert references email. | Display `@tag` and provide username/tag editing capability. |

---

## 7. File-by-File Technical Specification for Implementation

### 7.1 `Data/Models/MessengerModels.swift`

#### `SlooshUser`
```swift
public struct SlooshUser: Identifiable, Codable, Equatable, Hashable {
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
    }

    public var displayTitle: String {
        if !displayName.isEmpty { return displayName }
        if let tag = tag, !tag.isEmpty { return "@\(tag)" }
        return "Пользователь Sloosh"
    }

    public var formattedTag: String {
        if let tag = tag, !tag.isEmpty { return "@\(tag)" }
        return ""
    }

    public init(id: String, displayName: String, tag: String? = nil, avatarUrl: String? = nil, isOnline: Bool? = true) {
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
}
```

#### `ChannelModel`
```swift
public struct ChannelModel: Identifiable, Codable, Equatable, Hashable {
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

    public var formattedTag: String {
        "@\(tag)"
    }
    
    // CodingKeys, custom decoder with fallback if tag is missing in legacy channels
}
```

### 7.2 `Data/Repositories/MessengerRepository.swift`

New & updated methods:

```swift
// MARK: - Tag Management & Availability

public func checkChannelTagAvailability(tag: String) async -> (isAvailable: Bool, message: String) {
    let clean = TagValidator.sanitize(tag)
    let validation = TagValidator.validate(clean)
    guard case .valid = validation else {
        if case .invalid(let msg) = validation {
            return (false, msg)
        }
        return (false, "Некорректный тег")
    }

    guard let url = await makeURL(path: "channelTags/\(clean)") else {
        return (false, "Ошибка сети")
    }

    do {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode) else {
            return (false, "Ошибка сервера")
        }
        if data.isEmpty || String(data: data, encoding: .utf8) == "null" {
            return (true, "Тег свободен")
        } else {
            return (false, "Тег @\(clean) уже занят")
        }
    } catch {
        return (false, "Ошибка проверки тега")
    }
}

public func checkUserTagAvailability(tag: String) async -> (isAvailable: Bool, message: String) {
    let clean = TagValidator.sanitize(tag)
    let currentUserId = AuthRepository.shared.currentUser?.id ?? ""
    let validation = TagValidator.validate(clean)
    guard case .valid = validation else {
        if case .invalid(let msg) = validation {
            return (false, msg)
        }
        return (false, "Некорректный тег")
    }

    guard let url = await makeURL(path: "userTags/\(clean)") else {
        return (false, "Ошибка сети")
    }

    do {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode) else {
            return (false, "Ошибка сервера")
        }
        if data.isEmpty || String(data: data, encoding: .utf8) == "null" {
            return (true, "Тег свободен")
        }
        let occupantId = (try? JSONDecoder().decode(String.self, from: data)) ?? ""
        if occupantId == currentUserId {
            return (true, "Это ваш текущий тег")
        }
        return (false, "Тег @\(clean) уже занят")
    } catch {
        return (false, "Ошибка проверки тега")
    }
}

public func lookupChannelByTag(_ tag: String) async -> ChannelModel? {
    let clean = TagValidator.sanitize(tag)
    guard let tagUrl = await makeURL(path: "channelTags/\(clean)") else { return nil }
    guard let (data, resp) = try? await URLSession.shared.data(from: tagUrl),
          let httpResp = resp as? HTTPURLResponse, (200...299).contains(httpResp.statusCode),
          let channelId = try? JSONDecoder().decode(String.self, from: data) else { return nil }

    guard let chUrl = await makeURL(path: "channels/\(channelId)") else { return nil }
    guard let (chData, chResp) = try? await URLSession.shared.data(from: chUrl),
          let httpChResp = chResp as? HTTPURLResponse, (200...299).contains(httpChResp.statusCode) else { return nil }
    return try? JSONDecoder().decode(ChannelModel.self, from: chData)
}

public func lookupUserByTag(_ tag: String) async -> SlooshUser? {
    let clean = TagValidator.sanitize(tag)
    guard let tagUrl = await makeURL(path: "userTags/\(clean)") else { return nil }
    guard let (data, resp) = try? await URLSession.shared.data(from: tagUrl),
          let httpResp = resp as? HTTPURLResponse, (200...299).contains(httpResp.statusCode),
          let userId = try? JSONDecoder().decode(String.self, from: data) else { return nil }

    guard let userUrl = await makeURL(path: "user_profiles/\(userId)") else { return nil }
    guard let (userData, userResp) = try? await URLSession.shared.data(from: userUrl),
          let httpUserResp = userResp as? HTTPURLResponse, (200...299).contains(httpUserResp.statusCode) else { return nil }
    return try? JSONDecoder().decode(SlooshUser.self, from: userData)
}
```

---

## 8. Verification Strategy

1. **Tag Index Uniqueness**:
   - Create channel with tag `@cinema_club`.
   - Verify `/channelTags/cinema_club.json` contains the created `channelId`.
   - Attempt to create second channel with same tag `@cinema_club` → verify rejection.
2. **Instant Search by @Tag**:
   - In `MessengerView`, search `@cinema_club` → verify instant $O(1)$ resolution and display in search results.
3. **Privacy Audit**:
   - Inspect network traffic and `user_profiles` node → verify `email` is absent.
   - Open `ChatDetailView` → `ChatInfoView` for any peer user → verify email and UUID are not visible anywhere.
   - Search for a user in `MessengerView` → verify only `displayName` and `@tag` are shown.
4. **Offline Persistence**:
   - Close and restart app in airplane mode → verify cached channels and conversations display tags without errors.
