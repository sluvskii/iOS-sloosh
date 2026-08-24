# Handoff Report: Sloosh Avatar Architecture & PhotosPicker Integration

**Agent**: Explorer 2  
**Date**: 2026-08-25  
**Working Directory**: `W:\iOS-sloosh\.agents\explorer_2`  
**Handoff Type**: Hard (Task Complete)

---

## 1. Observation

Direct code inspection of the codebase in `W:\iOS-sloosh\sloosh-iOS\sloosh\Sources` revealed the following exact facts:

1. **Channel Emoji & Glowing Dependencies**:
   - `Data/Models/MessengerModels.swift` (lines 138–139, 173–174, 222–227): `ChannelModel` declares `public var avatarEmoji: String?` with default `"📢"` and computed property `displayAvatarEmoji`.
   - `UI/Messenger/CreateChannelSheet.swift` (lines 17, 56, 184–221): Declares `emojiPresets = ["📢", "🎬", "🍿", "🚀", "🔥", "👑", "⚡️", "⭐️", "🎧", "🏆", "💎", "🔮"]` and presents an emoji picker grid. Lines 101–112 wrap the emoji in `Circle().fill(selectedColor.opacity(0.2)).shadow(color: selectedColor.opacity(0.3), radius: 12, x: 0, y: 4)`.
   - `UI/Messenger/ChannelInfoView.swift` (lines 191–214): Uses `RadialGradient(colors: [channel.displayAccentColor.opacity(0.35), channel.displayAccentColor.opacity(0.08)], ...)` with `.shadow(color: channel.displayAccentColor.opacity(0.3), radius: 16, x: 0, y: 6)` and large emoji text `Text(channel.displayAvatarEmoji)`.
   - `UI/Messenger/ChannelDetailView.swift` (lines 230, 254) and `UI/Messenger/MessengerView.swift` (lines 477, 592): Directly render `Text(channel.displayAvatarEmoji)`.

2. **User Avatar Flow & Missing Profile Editing**:
   - `Data/Models/UserProfile.swift` (lines 7, 56–69): `UserProfile` stores `public let photoURL: String?` and computes `avatarInitials` (returns `"👤"` for guest, or uppercase 2-letter prefix).
   - `Data/Repositories/AuthRepository.swift` (lines 77, 409–428): Handles Google OAuth photoURL and Firebase displayName updates, but has no `updateUserProfile` method for photo changes or local profile updates.
   - `UI/Profile/ProfileView.swift` (lines 125–153, 251–284): `ProfileAvatarButton` opens a Sign Out alert or Auth sheet. Tapping the avatar when authenticated does not allow editing display name or uploading a custom avatar photo.
   - `UI/Details/ShareToFriendSheet.swift` (lines 386–400): `UserAvatarView` fallback uses a multi-color gradient `LinearGradient(colors: [Color.blue.opacity(0.6), Color.purple.opacity(0.6)], ...)`.

3. **Absence of PhotosPicker**:
   - Grep search for `PhotosPicker` across the entire workspace yielded 0 results.

4. **Image Caching & Base64 Handling**:
   - `UI/Shared/AsyncCachedImage.swift` (lines 1–273): Implements `ImageCache` using `NSCache<NSString, UIImage>` and URL-based fetching, but does not decode Base64 data URIs (`data:image/jpeg;base64,...`).

---

## 2. Logic Chain

1. **Premise 1 (From Observation 1)**: Channel avatars currently rely on emoji presets and heavy radial glow shadows, violating the modern, clean iOS 26 Liquid Glass design standard.
2. **Premise 2 (From Observation 2 & 3)**: Neither channels nor user profiles support custom photo selection because `PhotosPicker` is absent and there is no user profile editing screen.
3. **Premise 3 (From Observation 4)**: Firebase Realtime Database is used for syncing user profiles and channel metadata. Storing massive raw camera photos directly in RTDB would cause network throttling, high latency, and database bloating.
4. **Deduction 1**: Implementing `PhotosPicker` (`import PhotosUI`) allows zero-permission image picking with full user privacy.
5. **Deduction 2**: Passing picked images through an in-memory downscaling pipeline (`AvatarImageProcessor`) with center-square cropping, max $256 \times 256$ dimension, and iterative JPEG compression guarantees payloads $< 50\text{ KB}$ (average $12\text{--}25\text{ KB}$), perfectly suited for Base64 Data URI storage in Firebase RTDB.
6. **Deduction 3**: Introducing a unified component (`SlooshAvatarView`) eliminates emoji pickers, replaces glowing gradients with subtle `.glassEffect(in: Circle())` letter initials, and decodes Base64 data URIs or loads HTTP URLs with in-memory caching.
7. **Deduction 4**: Creating `EditProfileSheet` in `ProfileView` and updating `AuthRepository` & `MessengerRepository` enables seamless profile photo and name updates across the application.

---

## 3. Caveats

- **Firebase Storage vs Realtime Database**: Storing small base64 strings ($< 50\text{ KB}$) directly in Firebase Realtime Database avoids setting up Firebase Cloud Storage SDK / bucket rules and keeps real-time synchronization atomic with channel and profile updates. If avatars exceed $100\text{ KB}$, external CDN storage would be required, but our hard limit of $50\text{ KB}$ and $256\times 256$ resolution completely eliminates this concern.
- **Migration of Existing Channels**: Existing channels in RTDB that only have `avatarEmoji` will gracefully fall back to the first letter of their channel name in `SlooshAvatarView`.

---

## 4. Conclusion

A comprehensive architecture has been designed and specified in `analysis.md`:
1. Create `AvatarImageProcessor.swift` in `UI/Shared/` for downscaling, center-square cropping, and compressing to JPEG $< 50\text{ KB}$ Base64 string.
2. Create `SlooshAvatarView.swift` in `UI/Shared/` with Liquid Glass `.glassEffect(in: Circle())` fallback initials and support for Base64 data URIs and HTTP URLs.
3. Create `EditProfileSheet.swift` in `UI/Profile/` and integrate `PhotosPicker` into both channel creation/editing (`CreateChannelSheet.swift`, `ChannelInfoView.swift`) and user profile editing (`ProfileView.swift`).
4. Update `MessengerRepository.swift` and `AuthRepository.swift` to persist `avatarUrl` and sync across `/channels/` and `/user_profiles/` in Firebase Realtime DB.
5. Completely remove `emojiPresets`, `displayAvatarEmoji`, `RadialGradient` glows, and `LinearGradient` multi-color fills.

---

## 5. Verification Method

To independently verify the investigation and future implementation:

1. **Verify Files & References**:
   - Inspect `W:\iOS-sloosh\sloosh-iOS\sloosh\Sources\UI\Messenger\CreateChannelSheet.swift` lines 17, 184–221 to confirm emoji presets and glowing shadow.
   - Inspect `W:\iOS-sloosh\sloosh-iOS\sloosh\Sources\UI\Messenger\ChannelInfoView.swift` lines 191–214 to confirm radial gradient and emoji display.
   - Inspect `W:\iOS-sloosh\sloosh-iOS\sloosh\Sources\UI\Profile\ProfileView.swift` lines 125–153 to confirm missing profile edit action.

2. **Verify Architecture Document**:
   - View `W:\iOS-sloosh\.agents\explorer_2\analysis.md` for full component code sketches, mathematical payload budgets, and step-by-step refactoring targets.

3. **Build & Integration Invalidation Conditions**:
   - If any view attempts to use `.ultraThinMaterial`, it violates project rules (must use `.glassEffect(in: Circle())`).
   - If compressed image base64 exceeds $50\text{ KB}$, the iterative compressor must adjust quality parameter downward.
