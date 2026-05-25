# Agent Onboarding

## Workspace Overview

This workspace contains two related projects:

- `sloosh-iOS/`: the active iOS app under the `sloosh` brand.
- `neomovies-android-main/`: the Android reference project used as a feature and behavior source for the iOS port.

The iOS app is a new standalone product. Do not treat it as a branded clone of the Android app.

## Product Identity

- Public product name on iOS: `sloosh`.
- Do not introduce any user-facing mention of `NeoMovies`, `neomovies`, `Alloha`, `Collaps`, or other internal source/provider names.
- Backend and package naming in the Android reference may still contain legacy names. Those are technical details only and must not leak into iOS UI copy.
- Avoid adding screens like Credits, Changes, or support clutter. The preferred UI is focused and flagship-like.

## User Preferences And Constraints

- Preferred communication language with the user: Russian.
- Preferred implementation style: native SwiftUI, minimal and verifiable edits.
- Target platform: iOS 26+ first.
- Preferred visual style: "Liquid Glass", premium look, floating components.
- Prefer native iOS patterns over literal Android UI copies.
- **IMPORTANT for iOS 26 UI**: 
  - Do NOT create custom "floating" components by wrapping views in `.ultraThinMaterial` and `safeAreaInset`.
  - ALWAYS use native system placement. For top floating components (like segmented controls), place them directly inside `.toolbar` (e.g., `ToolbarItem(placement: .principal)`).
  - Let the system (iOS 26) handle the Liquid Glass blur and morphing automatically during scroll. Do not add redundant backgrounds or overlays.

## iOS App Structure

Root:

- `sloosh-iOS/sloosh/Sources/App/`: app entry point.
- `sloosh-iOS/sloosh/Sources/Data/`: models, API, repositories, source manager.
- `sloosh-iOS/sloosh/Sources/UI/`: SwiftUI screens and shared UI helpers.

Important files:

- `sloosh-iOS/sloosh/Sources/App/slooshApp.swift`: app entry, audio session, orientation handling support.
- `sloosh-iOS/sloosh/Sources/UI/Home/ContentView.swift`: main `TabView`, uses iOS 18 `.sidebarAdaptable`.
- `sloosh-iOS/sloosh/Sources/Data/Network/MoviesApi.swift`: main API client.
- `sloosh-iOS/sloosh/Sources/Data/Repositories/MoviesRepository.swift`: main repository used by screens.
- `sloosh-iOS/sloosh/Sources/Data/Models/Models.swift`: DTOs and image URL normalization.
- `sloosh-iOS/sloosh/Sources/Data/SourceManager.swift`: current playback source selection.

## iOS Screens Status

Implemented or active:

- `HomeView.swift`: catalog grid, category switching, sorting, pagination.
- `SearchView.swift`: search, history, grid results, pagination.
- `DetailsView.swift`: details page, metadata, source fetch, handoff to player/source selection.
- `SourceSelectionView.swift`: Alloha selection UI.
- `CollapsSelectionView.swift`: Collaps selection UI.
- `PlayerView.swift`: AVPlayer-based playback, HLS proxy support, Alloha iframe parsing.
- `SettingsView.swift`: basic settings shell.
- `AboutView.swift`: simplified app info page.

Currently mostly placeholder or much simpler than Android:

- `FavoritesView.swift`
- `DownloadsView.swift`
- player settings in `SettingsView.swift`

## Data Layer Notes

- The iOS app already mirrors the core Android API shape for:
  - popular movies
  - top-rated movies
  - top-rated TV
  - details
  - search
- Some Android API capabilities are not yet ported to iOS, especially:
  - favorites endpoints
  - support/auth/profile flows
  - deeper download/offline flows
- `Models.swift` and `MoviesApi.swift` still reference `api.neomovies.ru` as a technical backend host. This is acceptable as an internal dependency if needed, but never expose that branding in UI.

## Playback Architecture

The iOS playback stack is source-dependent:

- `AllohaRepository.swift` and `AllohaParser.swift`: resolve iframe-based playback.
- `CollapsRepository.swift`: resolve direct stream data for movies/episodes.
- `HlsProxyServer.swift`: local proxy for header-sensitive HLS playback.
- `PlayerView.swift`: AVPlayer presentation, orientation switching, cleanup.

Important rule:

- `TrustAllSessionDelegate` and SSL-bypass-related behavior must be preserved where already used in networking/parsing flows.

## Android Reference Purpose

Use `neomovies-android-main/` as the source of truth for:

- feature scope
- behavior
- data contract
- edge cases
- watch selector flows
- downloads/offline structure

Do not copy from Android blindly:

- branding
- package names
- support/credits/changelog clutter
- user-facing source/provider names
- Android-specific UI structure when a more native iOS solution exists

## Key Android Reference Areas

- `app/src/main/java/com/neo/neomovies/MainActivity.kt`: app shell and top-level nav behavior.
- `app/src/main/java/com/neo/neomovies/ui/home/`: home feed behavior.
- `app/src/main/java/com/neo/neomovies/ui/search/`: search behavior and pagination.
- `app/src/main/java/com/neo/neomovies/ui/details/`: details behavior, favorites, downloads, watched state.
- `app/src/main/java/com/neo/neomovies/ui/watch/`: the most important reference for source selection and playback flows.
- `app/src/main/java/com/neo/neomovies/ui/downloads/`: offline/download UX and grouping.
- `app/src/main/java/com/neo/neomovies/ui/settings/`: source, player, language, TorrServer, update channel.
- `app/src/main/java/com/neo/neomovies/data/` and `data/network/`: API and repository behavior.

## Current Mapping: Android -> iOS

- `HomeScreen` -> `HomeView`
- `SearchScreen` -> `SearchView`
- `DetailsScreen` -> `DetailsView`
- `WatchSelectorScreen` -> split across `DetailsView`, `SourceSelectionView`, `CollapsSelectionView`, `PlayerView`
- `SettingsScreen` -> `SettingsView`
- `SourceSettingsScreen` -> `SourceSettingsView`
- `FavoritesScreen` -> not fully ported yet
- `DownloadsScreen` -> not fully ported yet
- `Profile/Auth` -> not ported
- `TorrServer/Torrents` -> not ported

## What Has Already Been Reworked For iOS

- The iOS app is not a direct visual copy of Android.
- Main navigation uses native iOS tabs and iOS 18 tab behavior.
- Home uses a custom floating category strip instead of a standard segmented control.
- Credits and changes screens were intentionally removed from iOS.
- User-facing references to internal parser/source names were already reduced in several places and should stay hidden.

## Highest-Value Next Steps

When continuing work, the highest-value missing areas are:

1. A stronger native iOS watch selector flow, based on Android behavior but redesigned for iOS.
2. Real favorites support using the existing backend contract.
3. Real downloads/offline UI and storage flow.
4. Deeper playback settings without exposing internal source names.
5. Optional profile/auth/update features only if they fit the iOS product direction.

## Editing Guidance For Future Agents

- Keep edits small and verifiable.
- Read nearby code before changing it; this project may be actively edited.
- Do not revert unrelated user changes.
- Prefer preserving existing SwiftUI style and naming.
- If using Android code as reference, port behavior rather than copying terminology.
- Keep all new user-facing text aligned with the `sloosh` brand.

## Quick Summary

This is a premium-looking iOS SwiftUI app called `sloosh`, using an Android project as a technical reference only. Preserve the standalone identity, keep internal provider names out of the UI, prefer native iOS solutions, and use the Android app mainly to port behavior, data flows, and missing media features.
