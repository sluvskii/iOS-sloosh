## 2026-08-24T20:45:00Z
You are Worker 1 for the Sloosh Channels & Messenger refactoring project.
Your working directory is W:\iOS-sloosh\.agents\worker_1\
Project Root: W:\iOS-sloosh\sloosh-iOS\

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Context and References:
- Read Explorer 1 findings: W:\iOS-sloosh\.agents\explorer_1\analysis.md and handoff.md
- Read Explorer 2 findings: W:\iOS-sloosh\.agents\explorer_2\analysis.md and handoff.md
- Read Explorer 3 findings: W:\iOS-sloosh\.agents\explorer_3\analysis.md and handoff.md
- Read project rules in W:\iOS-sloosh\AGENTS.md (STRICT: Liquid Glass, NO .ultraThinMaterial, NO leaks of provider names or raw emails).

Implementation Scope:

1. Data Models & Privacy (R1, R4):
   - `Data/Models/MessengerModels.swift`:
     - Update `SlooshUser`: add `tag: String?`, remove public email serialization or mask it, add computed `displayTag` (e.g. `@johndoe`).
     - Update `ChannelModel`: add `tag: String` (with fallback sanitization in Decodable for backward compatibility), `avatarUrl: String?`, remove/deprecate `avatarEmoji` dependencies and radial glow shadows, add computed `displayTag` (`@channelTag`).
     - Ensure all models conform to `Codable`, `Sendable`, `Identifiable`.
   - `Data/Models/UserProfile.swift`:
     - Add `tag: String?` to `UserProfile`, update computed initial logic for `avatarInitials` and `displayHandle`.
   - `Data/Repositories/MessengerRepository.swift`:
     - Add methods for checking tag availability and claiming/releasing tags in Firebase RTDB: `/channelTags/{tag}.json` and `/userTags/{tag}.json`.
     - Sanitize user profile sync: when writing to `/user_profiles/{uid}.json`, DO NOT include raw email or private fields.
     - Implement instant $O(1)$ @tag search routing when query starts with `@` in `searchUsers(query:)` and `searchChannels(query:)`.
     - Update channel creation/editing to persist `tag` and `avatarUrl` and register `/channelTags/{tag}`.
   - `Data/Repositories/AuthRepository.swift`:
     - Add support for updating `tag` and `photoURL` (avatar) in `UserProfile` and syncing to Firebase RTDB.

2. Avatar Pipeline & PhotosPicker (R2):
   - Create `UI/Shared/AvatarImageProcessor.swift`:
     - Center-square crop, resize to max 256x256, iterative JPEG compression to ensure < 50KB payload.
     - Base64 Data URI conversion (`data:image/jpeg;base64,...`) and UIImage decoding helper.
   - Create `UI/Shared/SlooshAvatarView.swift`:
     - Clean modern SwiftUI avatar component using `.glassEffect(in: Circle())`.
     - Supports Base64 Data URIs (`data:image/jpeg;base64,...`), remote HTTP URLs, and clean monochrome/accent fallback circle with the first uppercase letter (monogram).
     - No emojis, no radial glowing drop shadows, no multi-color linear gradients.
   - Create `UI/Profile/EditProfileSheet.swift`:
     - Clean Liquid Glass sheet with `PhotosPicker` for picking an avatar image, name input, and `@tag` input with availability checking.
   - Update `UI/Profile/ProfileView.swift`:
     - Display `@tag` in header instead of email; tapping avatar or edit button opens `EditProfileSheet`.

3. UI Simplification & ChannelInfoView Cleanup (R3):
   - `UI/Messenger/CreateChannelSheet.swift`:
     - Replace emoji picker grid and glowing color circles with:
       - PhotosPicker avatar selector with `SlooshAvatarView` preview.
       - `@tag` input field with real-time format validation (`[a-z0-9_]{3,30}`) and availability check indicator.
       - Clean Liquid Glass inputs and Capsule create button.
   - `UI/Messenger/ChannelInfoView.swift`:
     - Single `"Изменить"` button in top toolbar (`ToolbarItem(placement: .topBarTrailing)`) for channel owner.
     - Remove duplicate "Настройки" pencil button from quick action buttons.
     - Remove fake `sloosh.app` links (ShareLink and settings row).
     - Clean Liquid Glass styling with subscriber count, channel tag `@channel.tag`, and clean settings list.
   - `UI/Messenger/ChatDetailView.swift`:
     - In `ChatInfoView`, remove raw email row and raw internal UUID row, displaying only `@peerUser.displayTag`.
     - Use `SlooshAvatarView` for peer avatar.
   - `UI/Messenger/MessengerView.swift`:
     - In `PeakUserSearchRow` and channel rows, use `SlooshAvatarView` and display `@tag` instead of raw email.
     - Ensure instant search for `@tag` queries works cleanly.
   - `UI/Messenger/ChannelDetailView.swift` & `UI/Details/ShareToFriendSheet.swift`:
     - Replace legacy emoji/gradient avatars with `SlooshAvatarView`.

4. Project Rules & Verification:
     - STRICTLY NO `.ultraThinMaterial` anywhere in the project.
     - Ensure all floating elements use `.glassEffect(in: ...)`.
     - Zero leaks of provider names or raw user emails.
     - Document all changed and created files.
     - Provide a complete handoff report in `W:\iOS-sloosh\.agents\worker_1\handoff.md`.
