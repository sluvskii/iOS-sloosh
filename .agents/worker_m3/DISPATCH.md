## 2026-08-25T01:07:19Z

Assignment for Milestone 3 (Channel Feed, Roles, Media & Reactions):
1. **Create `MovieSelectorSheet.swift`** in `W:\iOS-sloosh\sloosh-iOS\sloosh\Sources\UI\Messenger\MovieSelectorSheet.swift`:
   - Liquid Glass presentation background: `.presentationBackground { Color.clear.glassEffect(in: .rect) }`.
   - Debounced search using `MoviesRepository.shared.searchMovies(query:page:)`.
   - Popular / trending grid on cold open (`MoviesRepository.shared.getPopularMovies(page: 1)`).
   - Selecting a movie packages it as `MediaCardPayload` and passes to `onSelect(MediaCardPayload)`.
2. **Create `ChannelMediaCardView.swift`** in `W:\iOS-sloosh\sloosh-iOS\sloosh\Sources\UI\Messenger\ChannelMediaCardView.swift`:
   - Full-width card with 2:3 poster, rating badge (`Color.rating(...)`), title, year/type, dynamic average-color background extracted from poster.
   - Prominent "Смотреть" button with Liquid Glass capsule, calling `onPlayDirectly(media)` which triggers `HomeDirectPlayWrapper` -> `PlayerView`.
   - Poster / title / "Подробнее" tap calling `onOpenDetails(media.mediaId)` which triggers `DetailsView(movieId:)`.
3. **Create `PinnedPostBar.swift`** in `W:\iOS-sloosh\sloosh-iOS\sloosh\Sources\UI\Messenger\PinnedPostBar.swift`:
   - Top floating Liquid Glass banner below navigation bar (`.glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 14, style: .continuous))`).
   - Displays `pin.fill` icon, post preview text or movie title.
   - Tapping invokes `onTap(postId)` to scroll `ScrollViewReader` directly to the pinned post.
4. **Create `ChannelPostRowView.swift`** in `W:\iOS-sloosh\sloosh-iOS\sloosh\Sources\UI\Messenger\ChannelPostRowView.swift`:
   - Broadcast post layout with post text, embedded `ChannelMediaCardView` (if media attached), timestamp, edit badge, views count.
   - Emoji reaction bar rendering aggregated pills with counters and active user reaction highlight.
   - Plus (+) reaction picker popup allowing viewers/subscribers to add emoji reactions (🔥, ❤️, 🍿, 🎬, 👏, 😱, ⚡️, ⭐️).
   - Context menu with Author actions (Edit, Pin/Unpin, Delete) and Viewer actions (Copy, Share, React).
5. **Update `ChannelDetailView.swift`** in `W:\iOS-sloosh\sloosh-iOS\sloosh\Sources\UI\Messenger\ChannelDetailView.swift`:
   - Full screen feed integrating `ScrollViewReader`, post list using `ChannelPostRowView`, and top `PinnedPostBar`.
   - **Role Separation**:
     - **Channel Owner/Author**:
       - Broadcasting input bar (`BroadcastInputBar`) at the bottom: text field with Liquid Glass morphing capsule, movie selector button opening `MovieSelectorSheet`, attached movie preview chip with remove button, and send button.
       - Support editing existing posts (editing banner & state).
       - Support pinning/unpinning posts (`MessengerRepository.shared.togglePinChannelPost`).
       - Support deleting posts (`MessengerRepository.shared.deleteChannelPost`).
     - **Subscribers / Viewers**:
       - Read-only post stream (no text input bar).
       - Bottom floating Liquid Glass banner with:
         - "Подписаться" / "Отписаться" toggle button.
         - Mute / Unmute toggle button (`bell.fill` / `bell.slash.fill`).
   - Deep linking presentations:
     - `.sheet(item: $selectedMediaForDirectPlay)` presenting `HomeDirectPlayWrapper` -> `.fullScreenCover(item: $activePlayerConfig) { PlayerView(...) }`.
     - `.navigationDestination(item: $selectedMovieIdForDetails) { DetailsView(movieId: $0, ...) }`.
     - Navigation to `ChannelInfoView(channel: channel)` via info button in toolbar.
