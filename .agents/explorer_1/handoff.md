# Handoff Report: Sloosh Channels & Messenger Tag & Privacy Architecture (R1)

**From:** Explorer 1  
**To:** Orchestrator & Worker (M1)  
**Date:** 2026-08-25  
**Working Directory:** `W:\iOS-sloosh\.agents\explorer_1\`  
**Analysis Reference:** `W:\iOS-sloosh\.agents\explorer_1\analysis.md`

---

## 1. Observation

Direct code inspection of the `sloosh-iOS` repository revealed the following concrete findings:

1. **Email Leaks in User Search Row**:
   - In `W:\iOS-sloosh\sloosh-iOS\sloosh\Sources\UI\Messenger\MessengerView.swift`, lines 749–754:
     ```swift
     if !user.email.isEmpty {
         Text(user.email)
             .font(.system(size: 14))
             .foregroundColor(.secondary)
     }
     ```
     Raw user emails are directly rendered to all users in Messenger search results.

2. **Email and Internal UUID Leaks in Chat Info Header**:
   - In `W:\iOS-sloosh\sloosh-iOS\sloosh\Sources\UI\Messenger\ChatDetailView.swift`, lines 740–774:
     ```swift
     if !peerUser.email.isEmpty {
         HStack(spacing: 14) {
             Image(systemName: "envelope.fill")
             VStack(alignment: .leading, spacing: 2) {
                 Text("Email")
                 Text(peerUser.email)
             }
         }
     }
     HStack(spacing: 14) {
         Image(systemName: "person.fill")
         VStack(alignment: .leading, spacing: 2) {
             Text("ID пользователя")
             Text(peerUser.id)
                 .font(.system(size: 14, design: .monospaced))
         }
     }
     ```
     Both peer email and raw internal Firebase Auth UID are rendered on the peer info page.

3. **Public Profile Upload Leaks Email to Firebase RTDB**:
   - In `W:\iOS-sloosh\sloosh-iOS\sloosh\Sources\Data\Repositories\MessengerRepository.swift`, lines 131–159:
     ```swift
     let slooshUser = SlooshUser(
         id: user.id,
         displayName: user.displayTitle,
         email: user.email ?? "",
         avatarUrl: user.photoURL,
         isOnline: true
     )
     ...
     // 1. Сохраняем в публичный каталог профилей /user_profiles/{uid}.json
     ```
     `SlooshUser` containing `email` is written to the world-readable `/user_profiles` node.

4. **Missing Unique Channel Tag System**:
   - In `W:\iOS-sloosh\sloosh-iOS\sloosh\Sources\Data\Models\MessengerModels.swift`, lines 134–248:
     `ChannelModel` contains only generated `id` (e.g. `ch_172...`), `name`, `description`, `avatarEmoji`, `ownerId`. It lacks any `tag` field.
   - In `W:\iOS-sloosh\sloosh-iOS\sloosh\Sources\UI\Messenger\CreateChannelSheet.swift`, lines 10–324:
     Channel creation takes only `name`, `description`, `selectedEmoji`, `selectedColorHex`. There is no handle/tag input or availability validation.

5. **Search Inefficiency & Lack of @Tag Lookup**:
   - In `W:\iOS-sloosh\sloosh-iOS\sloosh\Sources\Data\Repositories\MessengerRepository.swift`, lines 179–248:
     `searchUsers(query:)` downloads all `/user_profiles.json` and `/users.json` and performs brute-force substring matching on `name`, `email`, and `id`.

---

## 2. Logic Chain

1. **Premise 1 (Privacy Mandate)**: Product specifications strictly forbid exposing email addresses and internal Firebase UIDs to peers across all UI screens and public network APIs.
2. **Premise 2 (Tag Identity)**: Users and channels must be identifiable via public `@tag` handles that are unique, human-readable, and sanitized (`[a-z0-9_]{3,30}`).
3. **Deduction 1 (Data Model & Storage Changes)**:
   - `SlooshUser` must replace `email: String` with `tag: String?`.
   - `ChannelModel` must include `tag: String`.
   - `UserProfile` must include `tag: String?`.
   - Public RTDB node `/user_profiles/{uid}` must not store `email`.
4. **Deduction 2 (Index & Lookup Architecture)**:
   - To guarantee global uniqueness with $O(1)$ verification, two index nodes must be added in Firebase RTDB: `/channelTags/{tag}` and `/userTags/{tag}`.
   - Channel creation in `CreateChannelSheet` and user tag claiming in `ProfileView` must check availability against these index nodes before persisting.
5. **Deduction 3 (Search Routing)**:
   - When a search query starts with `@`, `MessengerRepository` executes an exact $O(1)$ lookup via `/channelTags/{cleanTag}` and `/userTags/{cleanTag}`, eliminating brute-force full database parsing and providing instantaneous results.
6. **Deduction 4 (UI Sanitization)**:
   - In `ChatInfoView`, remove the email and user ID rows, showing `@peerUser.tag`.
   - In `PeakUserSearchRow`, replace the email display with `@user.tag`.
   - In `ChannelInfoView`, replace fake links (`sloosh.app/...`) with `@channel.tag`.

---

## 3. Caveats

1. **Legacy Channel & User Migration**:
   - Existing channels in the database lack a `tag` property. In `ChannelModel.init(from: Decoder)`, a fallback must be provided (e.g. converting `name` or `id` into a default sanitized tag) so existing channels decode seamlessly without crashes.
   - Existing users without a tag should have a default handle suggested from their `displayName` upon login.
2. **Security Rules in Firebase**:
   - Firebase Realtime Database rules should permit authenticated users to write to `/channelTags/{tag}` when claiming a new tag, and ensure idempotency.
3. **No Direct Simulator/Local Build**:
   - Local builds via Xcode are not used; compilation and execution are verified via GitHub Actions CI pipeline.

---

## 4. Conclusion

The R1 requirements (Unique @tags, complete privacy, instant @tag lookup) are fully designed and ready for implementation.

The required changes span 7 core files:
1. `Data/Models/MessengerModels.swift`: Update `SlooshUser` (add `tag`, remove public `email`), update `ChannelModel` (add `tag`, `formattedTag`).
2. `Data/Models/UserProfile.swift`: Add `tag: String?` to `UserProfile`.
3. `Data/Repositories/MessengerRepository.swift`: Implement `/channelTags` and `/userTags` availability check, claim, release, and instant search methods; purge `email` from `user_profiles` sync and `user_chats` payloads.
4. `UI/Messenger/CreateChannelSheet.swift`: Add tag input field with `@` prefix, live availability check indicator, and pass sanitized tag to creation.
5. `UI/Messenger/MessengerView.swift`: Update search row to display `@tag` instead of email; route `@tag` queries to instant lookup.
6. `UI/Messenger/ChatDetailView.swift`: Purge email and internal UUID rows in `ChatInfoView`, display `@tag`.
7. `UI/Messenger/ChannelInfoView.swift`: Purge fake domain link, display `@channel.tag`.

---

## 5. Verification Method

To independently verify the implementation:

1. **Tag Indexing & Collision Prevention**:
   - Attempt creating a channel with tag `@cinema`.
   - Inspect Firebase RTDB at `https://sloosh-77434-default-rtdb.firebaseio.com/channelTags/cinema.json` to verify value equals `channelId`.
   - Attempt creating another channel with tag `@cinema` → verify the sheet shows "Тег @cinema уже занят" and disables creation.
2. **Instant Search Test**:
   - In `MessengerView` search bar, type `@cinema`.
   - Verify that the channel with handle `@cinema` is immediately resolved and displayed in the search section without full table scanning.
3. **Privacy Inspection**:
   - Trigger `syncCurrentUserProfile()` and inspect `user_profiles/{uid}.json` in Firebase → verify `email` is not written.
   - Open `ChatDetailView` → `ChatInfoView` → verify that no email address and no raw UUID are present on screen.
   - Search users in `MessengerView` → verify `PeakUserSearchRow` displays `displayName` and `@tag`, and never an email address.
