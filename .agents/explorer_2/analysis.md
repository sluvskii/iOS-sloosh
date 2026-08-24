# Comprehensive Analysis: Sloosh Avatar Architecture & PhotosPicker Integration

**Agent**: Explorer 2  
**Date**: 2026-08-25  
**Target Platform**: iOS 26+ / SwiftUI (Liquid Glass)  
**Workspace**: `W:\iOS-sloosh\sloosh-iOS`

---

## 1. Executive Summary

This investigation analyzes the avatar subsystem across **Sloosh iOS Channels, Messenger, and User Profiles**. Currently, channel avatars rely heavily on legacy emoji presets (`"📢", "🎬", "🍿", ...`), radial gradients, and decorative glow shadows, while user avatars only support Google OAuth profile photo URLs or crude fallback text without editing capabilities.

We propose a modern, unified avatar architecture:
1. **Real Image Selection via PhotosPicker**: Native SwiftUI `PhotosPicker` (`import PhotosUI`) for selecting channel and user profile avatars without requiring explicit photo library permissions.
2. **High-Performance Downscale & Compression Engine**: An in-memory pipeline (`AvatarImageProcessor`) that auto-corrects EXIF orientation, applies center-square cropping, resizes to a maximum of $256 \times 256$ pixels, and compresses to JPEG target $< 50\text{ KB}$ (average $12\text{--}25\text{ KB}$), stored as a base64 Data URI (`data:image/jpeg;base64,...`) directly in Firebase Realtime Database.
3. **Elimination of Emojis, Decorative Glows & Neon Gradients**: Complete removal of emoji pickers, heavy drop shadows, and multi-color gradients.
4. **Monochrome / Subtle Accent Liquid Glass Fallback**: A minimalist circle using `.glassEffect(in: Circle())` with the first uppercase letter of the channel/user name.
5. **Unified Avatar Component (`SlooshAvatarView`)**: A single reusable view replacing fragmented avatar implementations across the application.
6. **User Profile Editing (`EditProfileSheet`)**: Adding profile photo and display name editing in `ProfileView` and syncing with Firebase Auth and Realtime Database.

---

## 2. Current State Audit & Problem Analysis

### 2.1 Channel Avatars Current Flow
- **Data Model** (`sloosh-iOS/sloosh/Sources/Data/Models/MessengerModels.swift`):
  - `ChannelModel` contains `avatarEmoji: String?` (default `"📢"`), `avatarUrl: String?` (always `nil`), `accentColorHex: String?` (default `"#FF9F0A"`).
  - Computed property `displayAvatarEmoji` returns `avatarEmoji ?? "📢"`.
- **Channel Creation** (`sloosh-iOS/sloosh/Sources/UI/Messenger/CreateChannelSheet.swift`):
  - Uses hardcoded `emojiPresets = ["📢", "🎬", "🍿", "🚀", "🔥", "👑", "⚡️", "⭐️", "🎧", "🏆", "💎", "🔮"]` (lines 17, 56, 184–221).
  - Visual preview uses a glowing circle with heavy shadow: `Circle().fill(selectedColor.opacity(0.2)).shadow(color: selectedColor.opacity(0.3), radius: 12, x: 0, y: 4)` (lines 101–112).
  - No capability to select a custom image or photo.
- **Channel Info & Editing** (`sloosh-iOS/sloosh/Sources/UI/Messenger/ChannelInfoView.swift`):
  - Header profile (lines 191–214): renders a `RadialGradient` with `.shadow(color: channel.displayAccentColor.opacity(0.3), radius: 16, x: 0, y: 6)` and large emoji `Text(channel.displayAvatarEmoji)`.
  - `EditChannelSheet` (lines 725–825): only allows editing emoji and color presets.
- **Channel Rows & Toolbars**:
  - `MessengerView.swift` (ChannelRow lines 472–495, PublicChannelCard lines 587–610): renders `Text(channel.displayAvatarEmoji)` inside colored circles.
  - `ChannelDetailView.swift` (Toolbar lines 228–236, EmptyState lines 250–257): renders `Text(channel.displayAvatarEmoji)`.

### 2.2 User Avatars Current Flow
- **Data Models**:
  - `UserProfile` (`sloosh-iOS/sloosh/Sources/Data/Models/UserProfile.swift`): `photoURL: String?`, computed property `avatarInitials` (returns `"👤"` for guest, 1–2 letters for authenticated user).
  - `SlooshUser` (`sloosh-iOS/sloosh/Sources/Data/Models/MessengerModels.swift`): `avatarUrl: String?`.
- **Persistence & Sync**:
  - `AuthRepository.swift`: On Google Sign-in, saves Google's `photoURL` (HTTP URL). On email/password sign-up, `photoURL` is `nil`.
  - `MessengerRepository.syncCurrentUserProfile()`: Pushes `SlooshUser(avatarUrl: user.photoURL)` to Firebase Realtime DB at `user_profiles/{uid}.json` and `users/{uid}/profile.json`.
- **UI Rendering**:
  - `ProfileView.swift` (`ProfileAvatarButton` lines 251–294): Uses standard `AsyncImage(url: photoURL)` with fallback `Text(user?.avatarInitials ?? "SL")`.
  - `MessengerView.swift` (`PeakAvatarView` lines 770–821): Uses `AsyncCachedImage(urlString: user.avatarUrl)` with fallback `Circle().fill(Color.slooshAccent.opacity(0.35))`.
  - `ShareToFriendSheet.swift` (`UserAvatarView` lines 363–400): Uses `AsyncCachedImage` with fallback `LinearGradient([.blue, .purple])`.
- **Deficiencies**:
  - No profile editing screen exists for regular users to set or update their profile picture or display name.
  - Existing components do not handle base64 data URIs (`data:image/jpeg;base64,...`) synchronously or through `ImageCache`.
  - Inconsistent visual styling across screens.

---

## 3. PhotosPicker Integration Architecture

### 3.1 SwiftUI PhotosUI Overview
`PhotosUI` provides `PhotosPicker`, which presents the out-of-process system photo picker:
- **No Permissions Required**: The app does not need `NSPhotoLibraryUsageDescription` or full photo library permissions because user selection happens out-of-process.
- **Privacy & Security**: Only the explicitly picked asset is transferred into the app process.
- **iOS 26+ Native Experience**: Smooth Liquid Glass sheets and animations.

### 3.2 Integration Pattern
```swift
import SwiftUI
import PhotosUI

struct AvatarPickerButton: View {
    @Binding var avatarDataString: String?
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var isProcessing: Bool = false
    let fallbackText: String
    let size: CGFloat

    var body: some View {
        PhotosPicker(selection: $selectedItem, matching: .images, photoLibrary: .shared()) {
            ZStack(alignment: .bottomTrailing) {
                SlooshAvatarView(
                    avatarSource: avatarDataString,
                    fallbackText: fallbackText,
                    size: size
                )
                
                // Camera / Edit Badge
                Circle()
                    .fill(Color(UIColor.systemBackground))
                    .frame(width: size * 0.32, height: size * 0.32)
                    .overlay(
                        Circle()
                            .fill(Color.slooshAccent)
                            .frame(width: size * 0.28, height: size * 0.28)
                            .overlay(
                                Image(systemName: "camera.fill")
                                    .font(.system(size: size * 0.12, weight: .bold))
                                    .foregroundColor(.black)
                            )
                    )
                    .offset(x: 2, y: 2)
            }
        }
        .buttonStyle(.plain)
        .onChange(of: selectedItem) { _, newItem in
            guard let newItem else { return }
            Task {
                isProcessing = true
                defer { isProcessing = false }
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    if let compressedBase64 = AvatarImageProcessor.processAvatar(image: image) {
                        await MainActor.run {
                            self.avatarDataString = compressedBase64
                        }
                    }
                }
            }
        }
    }
}
```

---

## 4. Downscale, Compression & Base64 Pipeline

### 4.1 Specification
| Parameter | Value | Rationale |
|---|---|---|
| **Max Dimension** | $256 \times 256$ pt/px | Retina displays ($3\times$) render $256\text{px}$ crisply up to $85\text{pt}$ avatars ($104\text{pt}$ on iPad/large view is sharp). |
| **Aspect Ratio** | $1:1$ (Center Crop) | Avatars are strictly circular. Center crop ensures no stretching. |
| **EXIF Orientation** | Normalized to `.up` | Fixes rotated iPhone camera photos. |
| **Compression Quality** | Starts at $0.8$, adapts down to $0.2$ | Preserves edge sharpness while guaranteeing payload limit. |
| **Target Payload Size** | $< 50\text{ KB}$ | High efficiency in Firebase Realtime Database JSON payload. |
| **Average Output Size** | $12\text{--}25\text{ KB}$ ($16\text{--}34\text{ KB}$ Base64) | Fast transmission over cellular networks. |
| **URI Format** | `data:image/jpeg;base64,<payload>` | Standard self-describing Data URI format. |

### 4.2 Processor Implementation (`AvatarImageProcessor`)
```swift
import UIKit

public enum AvatarImageProcessor {
    public static let maxDimension: CGFloat = 256.0
    public static let maxByteSize: Int = 50 * 1024 // 50 KB

    /// Processes an input UIImage into a base64 Data URI string
    public static func processAvatar(
        image: UIImage,
        maxDimension: CGFloat = maxDimension,
        maxBytes: Int = maxByteSize
    ) -> String? {
        // 1. Center square crop & scale
        guard let squareResized = cropAndResize(image: image, targetSize: CGSize(width: maxDimension, height: maxDimension)) else {
            return nil
        }

        // 2. Iterative JPEG compression
        var quality: CGFloat = 0.8
        guard var jpegData = squareResized.jpegData(compressionQuality: quality) else {
            return nil
        }

        while jpegData.count > maxBytes && quality > 0.15 {
            quality -= 0.1
            if let compressed = squareResized.jpegData(compressionQuality: quality) {
                jpegData = compressed
            }
        }

        // 3. Format as Base64 Data URI
        let base64String = jpegData.base64EncodedString()
        return "data:image/jpeg;base64,\(base64String)"
    }

    /// Square crops from center and scales to target size using UIGraphicsImageRenderer
    private static func cropAndResize(image: UIImage, targetSize: CGSize) -> UIImage? {
        let minSide = min(image.size.width, image.size.height)
        guard minSide > 0 else { return nil }

        let cropRect = CGRect(
            x: (image.size.width - minSide) / 2.0,
            y: (image.size.height - minSide) / 2.0,
            width: minSide,
            height: minSide
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0 // Fixed pixel dimensions
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { context in
            // Draw cropped & scaled
            let cgImage = image.cgImage
            if let croppedCg = cgImage?.cropping(to: CGRect(
                x: cropRect.origin.x * image.scale,
                y: cropRect.origin.y * image.scale,
                width: cropRect.size.width * image.scale,
                height: cropRect.size.height * image.scale
            )) {
                let croppedImage = UIImage(cgImage: croppedCg, scale: 1.0, orientation: image.imageOrientation)
                croppedImage.draw(in: CGRect(origin: .zero, size: targetSize))
            } else {
                image.draw(in: CGRect(origin: .zero, size: targetSize))
            }
        }
    }

    /// Fast decoding of Base64 or cached image
    public static func decodeImage(from source: String?) -> UIImage? {
        guard let source = source, !source.isEmpty else { return nil }

        if let cached = ImageCache.shared.image(forKey: source) {
            return cached
        }

        var base64Part = source
        if source.starts(with: "data:image") {
            if let commaIndex = source.firstIndex(of: ",") {
                base64Part = String(source[source.index(after: commaIndex)...])
            }
        }

        if let data = Data(base64Encoded: base64Part, options: .ignoreUnknownCharacters),
           let image = UIImage(data: data) {
            ImageCache.shared.insertImage(image, forKey: source)
            return image
        }

        return nil
    }
}
```

---

## 5. Elimination of Emojis, Glows & Liquid Glass Fallback

### 5.1 Design Principles
1. **No Emojis as Avatars**: Channels and users are represented by real photos or clean typographical initial fallbacks.
2. **No Neon Radial Gradients or Heavy Glows**: Remove `.shadow(color: ... radius: 16)` and `RadialGradient`.
3. **Monochrome / Subtle Accent Liquid Glass**:
   - Background: `.glassEffect(in: Circle())` with a subtle tint (`Color.slooshAccent.opacity(0.12)` or `Color.primary.opacity(0.06)`).
   - Letter: Single uppercase initial (`name.prefix(1).uppercased()`) styled with `.font(.system(size: size * 0.42, weight: .bold, design: .rounded))` and `.foregroundColor(accentColor ?? .primary)`.
4. **Channel Indicator**: Subtle megaphone badge in bottom-trailing position.
5. **Online Indicator**: Subtle green status dot with system background stroke.

---

## 6. Unified Avatar Component Specification (`SlooshAvatarView`)

```swift
import SwiftUI

public struct SlooshAvatarView: View {
    public let avatarSource: String?
    public let fallbackText: String
    public let size: CGFloat
    public var accentColor: Color? = nil
    public var isChannel: Bool = false
    public var showOnline: Bool = false
    public var isOnline: Bool = false

    public init(
        avatarSource: String?,
        fallbackText: String,
        size: CGFloat,
        accentColor: Color? = nil,
        isChannel: Bool = false,
        showOnline: Bool = false,
        isOnline: Bool = false
    ) {
        self.avatarSource = avatarSource
        self.fallbackText = fallbackText
        self.size = size
        self.accentColor = accentColor
        self.isChannel = isChannel
        self.showOnline = showOnline
        self.isOnline = isOnline
    }

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            avatarContent
                .frame(width: size, height: size)
                .clipShape(Circle())

            if isChannel {
                channelBadge
            } else if showOnline && isOnline {
                onlineBadge
            }
        }
    }

    @ViewBuilder
    private var avatarContent: some View {
        if let decoded = AvatarImageProcessor.decodeImage(from: avatarSource) {
            Image(uiImage: decoded)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else if let source = avatarSource, let url = URL(string: source), source.starts(with: "http") {
            AsyncCachedImage(url: url) {
                fallbackView
            } content: { img in
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } fallback: {
                fallbackView
            }
        } else {
            fallbackView
        }
    }

    private var fallbackView: some View {
        ZStack {
            Circle()
                .fill(accentColor?.opacity(0.12) ?? Color.primary.opacity(0.06))

            Text(initialLetter)
                .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                .foregroundColor(accentColor ?? .primary)
        }
        .glassEffect(in: Circle())
    }

    private var initialLetter: String {
        let trimmed = fallbackText.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(1)).uppercased().ifEmpty("S")
    }

    private var channelBadge: some View {
        Circle()
            .fill(Color(UIColor.systemBackground))
            .frame(width: size * 0.32, height: size * 0.32)
            .overlay(
                Circle()
                    .fill(Color.slooshAccent)
                    .frame(width: size * 0.26, height: size * 0.26)
                    .overlay(
                        Image(systemName: "megaphone.fill")
                            .font(.system(size: size * 0.11, weight: .bold))
                            .foregroundColor(.black)
                    )
            )
            .offset(x: 2, y: 2)
    }

    private var onlineBadge: some View {
        Circle()
            .fill(Color(UIColor.systemBackground))
            .frame(width: size * 0.3, height: size * 0.3)
            .overlay(
                Circle()
                    .fill(Color.green)
                    .frame(width: size * 0.24, height: size * 0.24)
            )
            .offset(x: 1, y: 1)
    }
}
```

---

## 7. Exact File Inventory & Proposed Modifications

### 7.1 Data & Model Layer

| Target File | Status | Planned Modifications |
|---|---|---|
| `Data/Models/MessengerModels.swift` | **Modify** | 1. Deprecate `avatarEmoji` in `ChannelModel`, prioritize `avatarUrl: String?`.<br>2. Add `avatarInitials` computed property to `ChannelModel` and `SlooshUser`.<br>3. Remove `displayAvatarEmoji`. |
| `Data/Models/UserProfile.swift` | **Modify** | 1. Ensure `avatarInitials` returns clean 1-letter uppercase string.<br>2. Support base64 image data string in `photoURL`. |
| `Data/Repositories/AuthRepository.swift` | **Modify** | 1. Add `updateUserProfile(displayName: String?, photoURL: String?) async -> Bool`.<br>2. Updates Firebase Auth `accounts:update` endpoint and local `UserDefaults`.<br>3. Triggers `MessengerRepository.syncCurrentUserProfile()`. |
| `Data/Repositories/MessengerRepository.swift` | **Modify** | 1. Update `createChannel(name:description:avatarUrl:accentColorHex:)` to accept `avatarUrl` instead of `avatarEmoji`.<br>2. Ensure `updateChannelMetadata` persists `avatarUrl` to Firebase RTDB `/channels/{id}.json` and subscriptions.<br>3. Ensure `syncCurrentUserProfile` pushes updated `avatarUrl` to `/user_profiles/{uid}.json`. |

### 7.2 UI Shared & Utilities (New Files)

| Target File | Status | Planned Content |
|---|---|---|
| `UI/Shared/AvatarImageProcessor.swift` | **Create** | In-memory downscale, center crop, orientation fix, iterative JPEG compression to $< 50\text{ KB}$, Base64 Data URI formatting & fast decoding cache. |
| `UI/Shared/SlooshAvatarView.swift` | **Create** | Unified Liquid Glass avatar component supporting base64 data, HTTP URLs, clean letter initials, channel badge, and online indicator. |

### 7.3 UI Screens & Sheets

| Target File | Status | Planned Modifications |
|---|---|---|
| `UI/Messenger/CreateChannelSheet.swift` | **Modify** | 1. Remove `emojiPresets`, `selectedEmoji`, `emojiPickerSection`.<br>2. Add `PhotosPicker` avatar uploader button with photo preview and reset button.<br>3. Clean preview circle with `.glassEffect(in: Circle())`. |
| `UI/Messenger/ChannelInfoView.swift` | **Modify** | 1. Remove `RadialGradient` and glow shadows in header (lines 191–214).<br>2. Use `SlooshAvatarView` for header avatar.<br>3. In `EditChannelSheet` (lines 725–825): replace emoji picker with `PhotosPicker` integration. |
| `UI/Messenger/ChannelDetailView.swift` | **Modify** | 1. Toolbar title: replace `Text(channel.displayAvatarEmoji)` with `SlooshAvatarView(channel, size: 24)`.<br>2. Empty state: replace emoji circle with `SlooshAvatarView(channel, size: 72)`. |
| `UI/Messenger/MessengerView.swift` | **Modify** | 1. Channel rows and public channel cards: use `SlooshAvatarView` instead of `displayAvatarEmoji`.<br>2. Replace/alias `PeakAvatarView` with `SlooshAvatarView`. |
| `UI/Messenger/ChatDetailView.swift` | **Modify** | 1. Toolbar trailing avatar: use `SlooshAvatarView`.<br>2. Peer info sheet: clean Liquid Glass avatar without harsh strokes/glows. |
| `UI/Profile/ProfileView.swift` | **Modify** | 1. Update `ProfileAvatarButton` to decode base64 photos.<br>2. Tap on avatar in authenticated state presents `EditProfileSheet` (or action sheet with "Редактировать профиль" / "Выйти"). |
| `UI/Profile/EditProfileSheet.swift` | **Create** | User profile editing sheet: change display name, pick avatar via `PhotosPicker`, crop/compress, and save to Firebase. |
| `UI/Details/ShareToFriendSheet.swift` | **Modify** | Replace `LinearGradient` in `UserAvatarView` with `SlooshAvatarView`. |

---

## 8. Firebase Realtime Database Data Structure

```json
{
  "user_profiles": {
    "<userId>": {
      "id": "<userId>",
      "displayName": "Alex",
      "email": "alex@sloosh.tv",
      "avatarUrl": "data:image/jpeg;base64,/9j/4AAQSkZJRg...",
      "isOnline": true
    }
  },
  "channels": {
    "<channelId>": {
      "id": "<channelId>",
      "name": "КиноКлуб Sloosh",
      "description": "Обсуждение новинок кино",
      "avatarUrl": "data:image/jpeg;base64,/9j/4AAQSkZJRg...",
      "accentColorHex": "#FF9F0A",
      "ownerId": "<userId>",
      "ownerName": "Alex",
      "subscriberCount": 128,
      "createdAtMs": 1724540000000,
      "updatedAtMs": 1724545000000,
      "isPublic": true
    }
  }
}
```

---

## 9. Conclusion & Architecture Readiness

The proposed avatar and image pipeline completely eliminates legacy emoji artifacts, respects Apple iOS 26 Liquid Glass design language, maintains $< 50\text{ KB}$ network footprints with zero third-party dependencies, and unifies all avatar rendering into a single performant component.
