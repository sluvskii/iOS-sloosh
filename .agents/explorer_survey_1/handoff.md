# Handoff Report: Messenger UI & Navigation Architecture Survey for Channels

## 1. Observation

### Code Inventory & Existing Architecture

Direct code inspection of the Sloosh iOS Messenger codebase revealed the following components, files, and navigation patterns:

#### A. Main Messenger Entry: `W:\iOS-sloosh\sloosh-iOS\sloosh\Sources\UI\Messenger\MessengerView.swift`
- **Navigation & Search Bar Structure** (lines 25–53):
  ```swift
  NavigationStack {
      ZStack {
          Color(UIColor.systemBackground).ignoresSafeArea()
          if !authRepo.isAuthenticated {
              guestView
          } else if repo.isLoading && repo.conversations.isEmpty {
              skeletonList
          } else if repo.conversations.isEmpty && searchQuery.isEmpty {
              emptyState
          } else {
              chatList
          }
      }
      .navigationTitle("Чаты")
      .navigationBarTitleDisplayMode(.large)
      .searchable(text: $searchQuery, prompt: "Поиск")
      .onChange(of: searchQuery) { _, newValue in
          if !newValue.isEmpty {
              Task { await repo.searchUsers(query: newValue) }
          }
      }
      .toolbar { toolbarContent }
      .navigationDestination(item: $selectedPeerUser) { peer in
          ChatDetailView(peerUser: peer)
      }
  }
  ```
- **Top-Right Toolbar Item** (lines 229–242):
  ```swift
  @ToolbarContentBuilder
  private var toolbarContent: some ToolbarContent {
      if authRepo.isAuthenticated {
          ToolbarItem(placement: .navigationBarTrailing) {
              Button {
                  searchQuery = ""
              } label: {
                  Image(systemName: "square.and.pencil")
                      .font(.system(size: 18, weight: .bold))
                      .foregroundColor(.slooshAccent)
              }
          }
      }
  }
  ```
- **Search Results & Chat List Rows** (lines 86–133):
  - When `!searchQuery.isEmpty && !repo.searchResults.isEmpty`, renders a `Section` with header `"ПОЛЬЗОВАТЕЛИ"` containing `PeakUserSearchRow(user:)`.
  - Conversation rows: `PeakChatRow(chat: chat, onDelete: { ... })` using `PeakAvatarView` (line 362), `displayTitle`, `lastMessageText`, `formatTime`, and unread count badge capsule (`Capsule().fill(Color.slooshAccent)`).

#### B. Chat Detail & Feed: `W:\iOS-sloosh\sloosh-iOS\sloosh\Sources\UI\Messenger\ChatDetailView.swift`
- **Screen & Background Structure** (lines 25–83):
  - Uses `Color(UIColor.systemGroupedBackground).ignoresSafeArea()` for native grouped styling.
  - `safeAreaInset(edge: .bottom)` hosts the input bar with reply/edit banners.
  - Navigation destinations & fullScreenCovers for `ChatInfoView`, `DetailsView`, `HomeDirectPlayWrapper`, and `PlayerView` (lines 87–122).
- **Liquid Glass Input Bar & Reactions** (lines 288–337, 456–481):
  - Floating morphing text field capsule with `.glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: inputBarCornerRadius, style: .continuous))`.
  - Pop-in send button circle with `.glassEffect(.regular.interactive(), in: Circle())`.
  - Floating iMessage reaction picker with `.glassEffect(.regular.interactive(), in: Capsule())`.

#### C. Rich Media Card: `W:\iOS-sloosh\sloosh-iOS\sloosh\Sources\UI\Messenger\MediaMessageCardView.swift`
- Renders attached movie/series with 2:3 aspect ratio poster, dynamic background derived from `image.averageColor.blended(with: .black, fraction: 0.65)`, rating badge (`Color.rating(rating)`), title, year, and a glass button "Смотреть" (`.glassEffect(in: Capsule())`).

#### D. Tab & Root Navigation: `W:\iOS-sloosh\sloosh-iOS\sloosh\Sources\UI\Home\ContentView.swift`
- Tab index: `AppTab.messenger` (line 7), icon `"bubble.left.and.bubble.right.fill"`, title `"Чаты"`.
- Uses `.tabBarMinimizeBehavior(.onScrollDown)` and `.tint(Color.slooshAccent)`.

#### E. Strict Guidelines & Liquid Glass Verification
- Ripgrep search for `ultraThinMaterial` across entire `sloosh-iOS/sloosh/Sources` produced **0 matches**.
- Project strictly follows `.glassEffect(...)` and forbids `.ultraThinMaterial`.
- Accent color: `Color.slooshAccent` (neon lime `#B2FF00` in dark mode, vibrant green `#73CC00` in light mode).

---

## 2. Logic Chain

1. **Top Action Menu & Creation Sheet (R1)**:
   - *Observation*: `MessengerView.swift:232-241` has a placeholder trailing button `square.and.pencil` that currently just sets `searchQuery = ""`.
   - *Inference*: This toolbar item can be transformed into a native SwiftUI `Menu` (or custom Liquid Glass menu) presenting two options:
     1. "Создать канал" (`systemImage: "megaphone.fill"`) -> sets `@State private var showCreateChannelSheet = true`.
     2. "Создать беседу" (`systemImage: "person.2.fill"`) -> disabled / marked "Скоро".
   - *Creation Sheet (`CreateChannelSheet`)*:
     - Presented via `.sheet(isPresented: $showCreateChannelSheet)` with `.presentationBackground { Color.clear.glassEffect(in: .rect) }`.
     - Fields: Channel Name, Channel Description, Visual identity selector (Emoji picker: 📢, 🎬, 🍿, 🚀, 🔥, 👑, ⚡️, ⭐️; Accent color palette).
     - Action: "Создать канал" (`Color.slooshAccent` button).
     - Upon creation: dismisses sheet and immediately pushes `ChannelDetailView` with Owner permissions.

2. **Channel Feed Experience & Role Separation (R2)**:
   - *Observation*: `ChatDetailView.swift` provides an established pattern for message streaming, optimistic sending, media card rendering (`MediaMessageCardView`), player presentation (`HomeDirectPlayWrapper` -> `PlayerView`), and reaction overlays.
   - *Inference*: `ChannelDetailView` should be a dedicated channel feed screen with:
     - **Author / Owner Role**:
       - Broadcasting input bar at the bottom: text composition + movie selector button (`film.stack.fill` / `plus.circle.fill`) that opens `ChannelMoviePickerSheet` (instant search of Sloosh movie catalog).
       - Post actions (via context menu): "Закрепить / Открепить" (Pin/Unpin), "Редактировать" (Edit), "Удалить" (Delete).
     - **Subscriber / Viewer Role**:
       - Read-only stream (no message text input).
       - Bottom floating Liquid Glass action bar with:
         - "Подписаться" / "Вы подписаны" toggle button.
         - Mute / Unmute notification toggle (`bell.fill` / `bell.slash.fill`).
     - **Pinned Post Banner (`PinnedPostBar`)**:
       - Top floating Liquid Glass bar pinned below the navigation bar (`.glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 14))`).
       - Displays `pin.fill`, author/post preview text.
       - Tapping it smoothly scrolls `ScrollViewReader` directly to the pinned post ID.
     - **Emoji Reactions**:
       - Aggregated reaction bar beneath each channel post (e.g. `🔥 34  ❤️ 12  🍿 8`), tap to toggle reaction with haptic feedback.
     - **Rich Media Cards**:
       - Embeds `MediaMessageCardView` with direct play (`PlayerView`) and details navigation (`DetailsView`).

3. **Channel Discovery, Search & List Integration (R3)**:
   - *Observation*: `MessengerView.swift:116` currently iterates through direct user conversations only (`filteredConversations: [ChatConversation]`).
   - *Inference*: `MessengerView` should support a unified conversation feed combining 1-on-1 direct chats and channels:
     - Channel row (`PeakChannelRow`):
       - Avatar: Channel emoji or avatar image with a distinct 📢 badge overlay.
       - Title: Channel Name (with owner badge / icon if creator).
       - Last message preview: `📢 [Текст поста]` or `🎬 [Название фильма]`.
       - Timestamp and unread counter badge (`Capsule().fill(Color.slooshAccent)`).
     - Search Integration:
       - When searching (`searchQuery` non-empty), `MessengerView` displays:
         1. Section `"КАНАЛЫ"` (matching public channels from Firebase `/public_channels`) with avatar, subscriber count, and quick "Подписаться" button.
         2. Section `"ПОЛЬЗОВАТЕЛИ"` (existing user search).
         3. Section `"ЧАТЫ"` (matching local conversations).
     - `ChannelInfoView`:
       - Screen displaying channel avatar, title, description, subscriber count, creator info.
       - Shared media catalog / pinned posts history.
       - Author settings (Edit, Delete Channel) & Subscriber settings (Unsubscribe, Notifications).

---

## 3. Caveats

- **Network / Backend Protocol**: This survey focuses strictly on UI and Navigation architecture. The Firebase Realtime Database schema and repository endpoints (`/channels/`, `/user_channels/`, `/public_channels/`, `/channel_posts/`) are detailed in the backend survey.
- **Local vs Remote State**: Instant cold starts require local persistence in `UserDefaults` / disk for channels and channel posts, matching the existing `saveConversationsToDisk` / `saveMessagesToDisk` pattern.
- No other caveats.

---

## 4. Conclusion

The Sloosh iOS UI architecture is exceptionally well-structured and modular, making the integration of Telegram-style Channels clean, native, and fully compliant with iOS 26+ Liquid Glass guidelines:

1. **New UI Files & Components to Add in `sloosh-iOS/sloosh/Sources/UI/Messenger/`**:
   - `CreateChannelSheet.swift`: Sheet for creating channels (name, description, emoji/color picker).
   - `ChannelDetailView.swift`: Channel feed view with role separation (Owner broadcasting bar vs Subscriber read-only bar).
   - `PinnedPostBar.swift`: Liquid Glass floating pinned post banner with tap-to-scroll.
   - `ChannelPostRowView.swift`: Broadcast post bubble with emoji reaction bar and rich media cards.
   - `ChannelInfoView.swift`: Channel details, subscriber counts, shared media, and management actions.
   - `ChannelMoviePickerSheet.swift`: Interactive sheet to search and attach Sloosh movies to channel posts.

2. **Integration Points in `MessengerView.swift`**:
   - Transform `toolbarContent` trailing item to a Liquid Glass `Menu` ("Создать канал", "Создать беседу").
   - Support navigation destination for channels (`ChannelDetailView`).
   - Add `"КАНАЛЫ"` section to search results with quick subscribe button.
   - Add `PeakChannelRow` for channel items in the main chat list with distinct 📢 badges.

3. **Liquid Glass Styling Checklist**:
   - All floating capsules, buttons, bars, and sheets must use `.glassEffect(.regular.interactive(), in: ...)` or `.glassEffect(in: ...)`.
   - Modifiers on sheets: `.presentationBackground { Color.clear.glassEffect(in: .rect) }`.
   - Never use `.ultraThinMaterial`.
   - Primary accent color: `Color.slooshAccent`.

---

## 5. Verification Method

To independently verify this survey and findings:

1. **Check absence of forbidden materials**:
   ```powershell
   Select-String -Path "W:\iOS-sloosh\sloosh-iOS\sloosh\Sources\**\*.swift" -Pattern "ultraThinMaterial"
   ```
   *Expected result*: 0 occurrences.

2. **Verify existing Messenger UI entry points**:
   - Inspect `W:\iOS-sloosh\sloosh-iOS\sloosh\Sources\UI\Messenger\MessengerView.swift` lines 25–55.
   - Inspect `W:\iOS-sloosh\sloosh-iOS\sloosh\Sources\UI\Messenger\ChatDetailView.swift` lines 288–337.
   - Inspect `W:\iOS-sloosh\sloosh-iOS\sloosh\Sources\UI\Messenger\MediaMessageCardView.swift`.
   - Inspect `W:\iOS-sloosh\sloosh-iOS\sloosh\Sources\UI\Home\ContentView.swift` line 41 (`Tab(value: .messenger)`).

3. **Invalidation Conditions**:
   - If any new component attempts to use `.ultraThinMaterial`, this violates core project guidelines.
   - If user-facing copy mentions backend source names (Alloha, Collaps, NeoMovies), this violates product rules.
