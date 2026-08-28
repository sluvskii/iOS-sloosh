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

## 2026-08-27T15:29:02Z

Fix voiceover selection and video quality discrepancies across the playback stack (`PlayerView`, `SourceSelectionView`, `DetailsView`, `AllohaRuntimeResolver`, and `DownloadManager`) so that user choices (e.g., Dubbed voiceover, 1080p quality) are strictly honored during both online streaming and offline downloads.

Working directory: W:\iOS-sloosh\sloosh-iOS
Integrity mode: development

## Requirements

### R1. Complete Synchronization & Fidelity of Voiceovers in Player
- In `PlayerView` and `PlayerViewModel`, preserve the authentic list of translation voiceovers provided by `AllohaApiResult` (`epObj.translations` for TV shows, `movie.translations` for movies) in `availableVoiceovers`.
- Prevent `applyResolvedAllohaStream` from overwriting `availableVoiceovers` with internal/partial WKWebView `audioVariants`.
- Ensure that selecting a voiceover (e.g., "Дублированный" for "Локи") in `SourceSelectionView` opens `PlayerView` with that exact translation's stream and displays the correct active voiceover in the in-player sheet.
- When the user switches voiceovers inside the player via `VoiceoverPickerSheet`, look up the target translation in `AllohaApiResult` to load its exact `iframeUrl` / stream, updating playback seamlessly at the current playback position.

### R2. Voiceover Consistency Across Episode Navigation & Autoplay
- When advancing to the next episode (via autoplay, next episode button, or episode picker in player), automatically look up and select the matching voiceover in the new episode (matching the user's current choice).
- If the current voiceover is unavailable in the next episode, fall back gracefully to the preferred voiceover order and update `currentTranslationName` and player UI accordingly.

### R3. Strict Quality Selection & Download Fidelity in DownloadManager
- In `DownloadManager.prepareAndEnqueue`, use the resolved stream URL directly for the chosen `translation.iframeUrl` without erroneous overrides from unrelated `audioVariants`.
- In `DownloadManager.chooseMediaPlaylistUrl`, accurately parse HLS master playlists (`#EXT-X-STREAM-INF` resolutions `RESOLUTION=...`, variant URLs like `1080.m3u8`, and bitrates) and evaluate `resolved["qualityVariants"]` so that requested qualities (e.g., `1080p`, `720p`) download at the highest matching resolution up to the user's preference without downgrading.
- Save and verify downloaded media metadata (`translationName`, `quality`, `key.bin`, `local.m3u8`) ensuring offline playback in `PlayerView` plays the exact downloaded audio and video stream.

## Acceptance Criteria

### Player Voiceover & Quality
- [ ] Selecting "Дублированный" (or any chosen voiceover) on multi-voice titles like "Локи" plays that exact voiceover in `PlayerView`.
- [ ] The in-player voiceover sheet (`VoiceoverPickerSheet`) displays the full, accurate list of available voiceovers matching the episode's translations.
- [ ] Switching voiceovers in `VoiceoverPickerSheet` reloads the correct translation stream and preserves current playback time.
- [ ] Transitioning to the next episode preserves the active voiceover.

### Downloads Fidelity
- [ ] Downloading a movie or series episode with a chosen voiceover downloads the exact audio stream corresponding to that translation.
- [ ] Downloading in 1080p selects the 1080p stream variant from the master playlist (or highest available up to 1080p) rather than defaulting to 720p.
- [ ] Offline playback of completed downloads via `PlayerView` reflects the downloaded voiceover and video quality.

