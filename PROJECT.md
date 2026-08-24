# Project: Telegram-style Channels in Sloosh Built-in Messenger

## Architecture
- **Layer 1: Data Models & DTOs** (`sloosh-iOS/sloosh/Sources/Data/Models/`):
  - `ChannelModel`: Channel metadata (id, name, description, avatarEmoji, avatarUrl, accentColorHex, ownerId, ownerName, subscriberCount, pinnedPostId, isPublic, lastPostText, lastPostTimestampMs).
  - `ChannelPost`: Post entity (id, channelId, authorId, text, media: MediaCardPayload?, reactions: [userId: emoji], timestampMs, isPinned, isEdited, viewsCount).
  - `ChannelSubscription`: Subscription record (channelId, channel, subscribedAtMs, isMuted).
  - `MessengerFeedItem`: Unified enum for chat list (`.directChat(ChatConversation)`, `.channel(ChannelModel)`).
  - `UIColor(hex:)` helper extension in `Color+Theme.swift`.
- **Layer 2: Data Repository & Firebase Realtime DB REST** (`sloosh-iOS/sloosh/Sources/Data/Repositories/`):
  - `MessengerRepository`: Extended with channel CRUD, subscriptions, post publishing/editing/pinning/deletion, reaction toggling, and Firebase REST endpoints (`/channels`, `/channel_posts`, `/channel_subscribers`, `/user_channel_subscriptions`).
  - Local Disk Caching: `UserDefaults` caching for subscribed channels and channel post histories for 0ms cold-start.
- **Layer 3: UI & Navigation** (`sloosh-iOS/sloosh/Sources/UI/Messenger/`):
  - `MessengerView.swift`: Liquid Glass Top Menu ("Создать канал", "Создать беседу"), integrated channel list rows with 📢 badge, public channel search section ("КАНАЛЫ") with quick subscribe button.
  - `CreateChannelSheet.swift`: Liquid Glass modal sheet for channel creation (Name, Description, Emoji Picker, Color Palette).
  - `ChannelDetailView.swift`: Broadcast channel stream with role separation:
    - Author/Owner: Composer bar with text input, `MovieSelectorSheet` trigger, post context actions (edit, pin, delete).
    - Subscribers: Read-only bottom action bar (Subscribe/Unsubscribe, Mute/Unmute).
  - `PinnedPostBar.swift`: Floating Liquid Glass top banner for pinned messages with tap-to-scroll.
  - `ChannelPostRowView.swift`: Broadcast post container with rich media card and emoji reaction pills.
  - `MovieSelectorSheet.swift`: Interactive Kinopoisk search & trending picker to attach `MediaCardPayload`.
  - `ChannelMediaCardView.swift`: Full-width interactive media card with 2:3 poster, rating badge, dynamic average-color background, one-tap "Смотреть" button (`HomeDirectPlayWrapper` -> `PlayerView`), and "Подробнее" (`DetailsView`).
  - `ChannelInfoView.swift`: Channel info screen with subscriber stats, description, pinned posts, and author management actions.

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | Channel Data Models & DTOs | `ChannelModel`, `ChannelPost`, `ChannelSubscription`, `MessengerFeedItem`, `UIColor(hex:)` | M1 | Survey |
| 2 | Firebase Realtime DB REST API | CRUD for channels, posts, subscriptions, reactions, and pin status via Firebase REST API | M1 | Survey |
| 3 | Local Disk Caching & Cold-Start | Instant 0ms cold-start rendering via `UserDefaults` disk caching for channels and post histories | M1 | Survey |
| 4 | Top Action Menu & Creation Sheet | Liquid Glass Menu in `MessengerView` and `CreateChannelSheet` with visual identity picker | M2 | Survey / R1 |
| 5 | Channel List Integration | Subscribed/owned channels displayed in `MessengerView` chat list with distinct 📢 badge and unread badge | M2 | Survey / R3 |
| 6 | Public Channel Search & Discovery | Dedicated "КАНАЛЫ" search section in `MessengerView` with quick "Подписаться" button | M2 | Survey / R3 |
| 7 | Channel Feed Screen & Role Separation | `ChannelDetailView` with Owner broadcasting bar vs Subscriber read-only stream and bottom banner | M3 | Survey / R2 |
| 8 | Pinned Post Banner | `PinnedPostBar` floating Liquid Glass banner with tap-to-scroll to pinned post | M3 | Survey / R2 |
| 9 | Interactive Media Cards & Movie Picker | `MovieSelectorSheet` for Kinopoisk search and `ChannelMediaCardView` with one-tap `PlayerView` and `DetailsView` | M3 | Survey / R2 |
| 10 | Emoji Reactions on Channel Posts | Per-post reaction picker and aggregated pills with counts and active user reaction highlight | M3 | Survey / R2 |
| 11 | Channel Info & Management View | `ChannelInfoView` with subscriber stats, description, pinned posts, author settings (edit, delete) | M4 | Survey / R3 |
| 12 | Architecture, Guidelines & CI Validation | Strict `.glassEffect()`, strictly ZERO `.ultraThinMaterial`, no provider leaks, commit and push to git | M4 | Survey / R4 |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| 1 | M1: Data Layer & Firebase RTDB | Channel models, DTOs, Firebase REST methods in `MessengerRepository`, local disk caching | none | DONE |
| 2 | M2: Creation Flow & Discovery | Top Action Menu, `CreateChannelSheet`, `PeakChannelRow` in `MessengerView`, Channel Search | M1 | DONE |
| 3 | M3: Channel Feed, Roles, Media & Reactions | `ChannelDetailView`, broadcasting bar, `PinnedPostBar`, `MovieSelectorSheet`, `ChannelMediaCardView`, reactions | M1, M2 | DONE |
| 4 | M4: Channel Info, Management & Verification | `ChannelInfoView`, author settings, full verification, audit, git commit and push | M1, M2, M3 | DONE |

## Interface Contracts
### Data Layer ↔ UI Views
- `MessengerRepository.shared.subscribedChannels: [ChannelModel]`
- `MessengerRepository.shared.publicChannels: [ChannelModel]`
- `MessengerRepository.shared.createChannel(name:description:avatarEmoji:accentColorHex:) async -> ChannelModel?`
- `MessengerRepository.shared.fetchSubscribedChannels() async -> [ChannelModel]`
- `MessengerRepository.shared.fetchPublicChannels(query:) async -> [ChannelModel]`
- `MessengerRepository.shared.subscribeToChannel(channel:) async -> Bool`
- `MessengerRepository.shared.unsubscribeFromChannel(channelId:) async -> Bool`
- `MessengerRepository.shared.fetchChannelPosts(channelId:) async -> [ChannelPost]`
- `MessengerRepository.shared.publishChannelPost(channelId:text:mediaPayload:isPinned:) async -> ChannelPost?`
- `MessengerRepository.shared.editChannelPost(channelId:postId:newText:mediaPayload:) async -> Bool`
- `MessengerRepository.shared.deleteChannelPost(channelId:postId:) async -> Bool`
- `MessengerRepository.shared.togglePinChannelPost(channelId:postId:isPinned:) async -> Bool`
- `MessengerRepository.shared.toggleChannelPostReaction(channelId:postId:emoji:) async -> Bool`
- `MessengerRepository.shared.deleteChannel(channelId:) async -> Bool`

### Media Integration ↔ Playback & Details
- `ChannelMediaCardView.onPlayDirectly: (MediaCardPayload) -> Void` -> triggers `HomeDirectPlayWrapper` -> `PlayerView`
- `ChannelMediaCardView.onOpenDetails: (String) -> Void` -> triggers `DetailsView(movieId:)`

## Code Layout
- `sloosh-iOS/sloosh/Sources/Data/Models/MessengerModels.swift`: Updated with `ChannelModel`, `ChannelPost`, `ChannelSubscription`, `MessengerFeedItem`.
- `sloosh-iOS/sloosh/Sources/Data/Repositories/MessengerRepository.swift`: Extended with Channel Firebase REST endpoints and caching.
- `sloosh-iOS/sloosh/Sources/UI/Color+Theme.swift`: Updated with `UIColor(hex:)` helper.
- `sloosh-iOS/sloosh/Sources/UI/Messenger/MessengerView.swift`: Updated with action menu, channel rows, channel search section.
- `sloosh-iOS/sloosh/Sources/UI/Messenger/CreateChannelSheet.swift`: New channel creation sheet.
- `sloosh-iOS/sloosh/Sources/UI/Messenger/ChannelDetailView.swift`: New channel feed view.
- `sloosh-iOS/sloosh/Sources/UI/Messenger/PinnedPostBar.swift`: New pinned post banner.
- `sloosh-iOS/sloosh/Sources/UI/Messenger/ChannelPostRowView.swift`: New channel post row view with reactions.
- `sloosh-iOS/sloosh/Sources/UI/Messenger/MovieSelectorSheet.swift`: New movie attachment sheet.
- `sloosh-iOS/sloosh/Sources/UI/Messenger/ChannelMediaCardView.swift`: New wide media card component.
- `sloosh-iOS/sloosh/Sources/UI/Messenger/ChannelInfoView.swift`: New channel info & settings view.
