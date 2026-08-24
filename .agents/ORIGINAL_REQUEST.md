# Original User Request

## 2026-08-25T00:53:37+05:00

Implement Telegram-style Channels in Sloosh built-in Messenger, providing seamless broadcast channel creation, posting with movie cards, pinned messages, reactions, and public discovery.

Working directory: W:\iOS-sloosh\sloosh-iOS
Integrity mode: development

## Requirements

### R1. Top Action Menu & Channel Creation Sheet
- Transform the top-right button (`square.and.pencil`) in `MessengerView` into a Liquid Glass `Menu` offering "Создать канал" and "Создать беседу" (marked coming soon).
- Present a dedicated "Создание канала" sheet where the user can specify Channel Name, Description, and select an avatar / emoji symbol / accent color.
- Persist channel metadata and ownership in Firebase Realtime Database and register creator as Admin/Owner.

### R2. Channel Feed Experience & Role Separation
- Implement a dedicated channel feed screen (`ChannelDetailView`):
  - **For Channel Owner/Author:** Display an interactive broadcasting input bar with text composing, a movie selector sheet to attach Sloosh media cards, and post management (edit, pin, delete).
  - **For Subscribers / Viewers:** Display a read-only post stream with a bottom Liquid Glass banner ("Подписаться" / "Отписаться", Mute/Unmute toggle).
- Support emoji reactions on channel posts for all viewers.
- Implement a top Pinned Message banner (`PinnedPostBar`) that jumps directly to the pinned post upon tap.
- Support interactive rich Media Cards inside posts with one-tap playback (`PlayerView`) and full details sheet (`DetailsView`).

### R3. Channel Discovery, Search & List Integration
- Display subscribed and owned channels inside `MessengerView` alongside direct chats with a distinct 📢 channel badge.
- Enhance the search bar in `MessengerView` to return public channels under a dedicated "КАНАЛЫ" section with a quick "Подписаться" button.
- Provide a `ChannelInfoView` showing subscriber count, description, pinned posts, and channel management settings for the author.

### R4. Architecture & iOS 26+ Guidelines
- Native SwiftUI MVVM using `MessengerRepository` and Firebase Realtime Database REST API.
- Instant cold-start rendering via local disk caching of channel lists and post history.
- Strictly adhere to iOS 26+ Liquid Glass style (`.glassEffect()`), forbidding `.ultraThinMaterial`. Zero leaks of internal provider names.

## Acceptance Criteria

### Creation & Management
- [ ] Tapping the top-right button in `MessengerView` opens a menu with "Создать канал".
- [ ] Completing the creation form creates the channel on Firebase and immediately opens `ChannelDetailView` with Owner permissions.
- [ ] Author can pin, edit, and delete channel posts, or delete the entire channel.

### Feed & Interactions
- [ ] Subscribers cannot send messages; they only see the channel posts, can add/toggle emoji reactions, and can tap "Подписаться" / "Отписаться".
- [ ] Posts with attached movies render high-quality media cards with poster, rating, and direct play functionality.
- [ ] Pinned post banner shows at the top of the channel when a post is pinned, and tapping it scrolls directly to that post.

### Search & Home List
- [ ] Search query in `MessengerView` shows matching public channels under "КАНАЛЫ" with subscriber counts.
- [ ] Channels appear in the main `MessengerView` list with latest post previews and unread badges.
