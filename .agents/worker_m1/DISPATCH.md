## 2026-08-25T00:57:00Z
Assignment for Milestone 1 (Data Layer & Firebase RTDB):
1. **Data Models & DTOs**:
   - Update `W:\iOS-sloosh\sloosh-iOS\sloosh\Sources\Data\Models\MessengerModels.swift`:
     - Add `ChannelModel`: `id`, `name`, `description`, `avatarEmoji`, `avatarUrl`, `accentColorHex`, `ownerId`, `ownerName`, `createdAtMs`, `updatedAtMs`, `subscriberCount`, `pinnedPostId`, `isPublic`, `lastPostText`, `lastPostTimestampMs`. Include helper properties: `displayAvatarEmoji`, `displayAccentColor` (using `UIColor(hex:)`), `formattedSubscriberCount` (Russian grammar for subscribers count: 1 подписчик, 2 подписчика, 5 подписчиков).
     - Add `ChannelPost`: `id`, `channelId`, `authorId`, `text`, `media` (`MediaCardPayload?`), `reactions` (`[String: String]?` mapping userId -> emoji), `timestampMs`, `isPinned`, `isEdited`, `viewsCount`. Include helper method `reactionSummary(currentUserId:)`.
     - Add `ChannelSubscription`: `channelId`, `channel: ChannelModel?`, `subscribedAtMs`, `isMuted`.
     - Add `MessengerFeedItem`: enum with `.directChat(ChatConversation)` and `.channel(ChannelModel)` cases, conforming to `Identifiable, Hashable`.
2. **Color+Theme Extension**:
   - In `W:\iOS-sloosh\sloosh-iOS\sloosh\Sources\UI\Color+Theme.swift` (or suitable theme file), add the `UIColor(hex: String)` initializer helper.
3. **Repository Methods in `MessengerRepository.swift`**:
   - Update `W:\iOS-sloosh\sloosh-iOS\sloosh\Sources\Data\Repositories\MessengerRepository.swift`:
     - Add `@Published public private(set) var subscribedChannels: [ChannelModel] = []`
     - Add `@Published public private(set) var publicChannels: [ChannelModel] = []`
     - Implement disk caching with `UserDefaults` keys (`sloosh_messenger_subscribed_channels_v1`, `sloosh_channel_posts_v1_{channelId}`, etc.) for instant 0ms cold start.
     - In `init()`, load subscribed channels from disk immediately.
     - Implement `createChannel(name:description:avatarEmoji:accentColorHex:) async -> ChannelModel?` creating `/channels/{channelId}.json` and `/user_channel_subscriptions/{userId}/{channelId}.json` and `/channel_subscribers/{channelId}/{userId}.json`.
     - Implement `fetchSubscribedChannels() async -> [ChannelModel]` (fetching user's subscriptions and resolving channels).
     - Implement `fetchPublicChannels(query: String?) async -> [ChannelModel]` (fetching public channels from `/channels.json`, filtering by query if provided).
     - Implement `subscribeToChannel(channel: ChannelModel) async -> Bool` and `unsubscribeFromChannel(channelId: String) async -> Bool` (updating subscription node and incrementing/decrementing `subscriberCount`).
     - Implement `isSubscribed(channelId: String) -> Bool`.
     - Implement `fetchChannelPosts(channelId: String) async -> [ChannelPost]` with disk caching.
     - Implement `publishChannelPost(channelId: String, text: String?, mediaPayload: MediaCardPayload?, isPinned: Bool) async -> ChannelPost?` (writing to `/channel_posts/{channelId}/{postId}.json` and updating `/channels/{channelId}/lastPostText` & `lastPostTimestampMs`).
     - Implement `editChannelPost(channelId: String, postId: String, newText: String?, mediaPayload: MediaCardPayload?) async -> Bool`.
     - Implement `deleteChannelPost(channelId: String, postId: String) async -> Bool`.
     - Implement `togglePinChannelPost(channelId: String, postId: String, isPinned: Bool) async -> Bool` (updating post `isPinned` and channel `pinnedPostId`).
     - Implement `toggleChannelPostReaction(channelId: String, postId: String, emoji: String) async -> Bool` (updating `/channel_posts/{channelId}/{postId}/reactions/{userId}.json`).
     - Implement `deleteChannel(channelId: String) async -> Bool` (removing channel, its posts, and user subscriptions).
     - Implement `updateChannelMetadata(channel: ChannelModel) async -> Bool`.
