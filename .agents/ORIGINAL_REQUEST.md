# Original User Request

## 2026-08-25T01:41:58Z

Refactor and polish the Sloosh Channels and Messenger system: replace emojis/gradients with real compressed image avatars, enforce unique @tags for channels and users (hiding email/IDs completely), unify the design with clean Liquid Glass capsules, and remove redundant buttons/fake links.

Working directory: W:\iOS-sloosh\sloosh-iOS
Integrity mode: development

## Requirements

### R1. Unique Tags (@handle) for Channels & Users
- Channels require a unique `@tag` specified during creation (e.g. `@cinema_club`), validated against Firebase `/channelTags/{tag}` before creation.
- Users receive an editable `@username` / `@tag` in their profile. Raw email addresses and internal UUIDs are strictly hidden from other users across all screens (chat details, profile, search).
- Messenger search supports instant lookup by `@tag` for both channels and users.

### R2. Real Compressed Image Avatars
- Remove emoji pickers and decorative glow/gradients.
- Add photo picker (`PhotosPicker`) for channel creation and channel editing. Compress selected image client-side to an optimized JPEG thumbnail (max 256x256, < 50KB) before storing in Firebase Realtime Database.
- Fallback avatar: Clean monochrome/accent Liquid Glass circle with the first letter of the name if no photo is uploaded.

### R3. Design System & UI Simplification
- Use pure `.glassEffect(in: Capsule())` or `.glassEffect(in: Circle())` across all messenger buttons, chips, and input bars.
- In `ChannelInfoView`: Remove duplicate settings gear / redundant buttons; keep a single clean "Изменить" button for the author.
- Remove fake `sloosh.app` links and remove the share button.
- Match standard 1-on-1 chat design system: minimalistic, premium, consistent typography and spacing.

### R4. Data Consistency & Performance
- Real-time sync with Firebase Realtime Database REST API.
- Instant offline cache loading for channels, profiles, and posts.
- Zero usage of `.ultraThinMaterial`. Zero leaks of provider names or raw user emails.

## Acceptance Criteria

### Tags & Privacy
- [ ] Channel creation enforces a unique `@tag` (letters, numbers, underscores) and checks availability in Firebase.
- [ ] User profile and chat header display `@username` and display name; email is 100% invisible to peers.
- [ ] Searching `@tag` in `MessengerView` instantly finds the channel or user.

### Avatars & Visuals
- [ ] Channels use real uploaded photos compressed to lightweight thumbnails, with no emojis or flashy gradients.
- [ ] All interactive elements and action buttons use native capsules (`Capsule()`) with `.glassEffect()`.

### Clean Screens
- [ ] `ChannelInfoView` has only one "Изменить" button for owners, no duplicate settings buttons, no fake domain links, and no share button.
- [ ] Post feed and chat experience match the visual style of private chats seamlessly.
