# Agent Onboarding

## Workspace Overview

This workspace contains related projects:

- `sloosh-iOS/`: the active iOS app under the `sloosh` brand.
- `neomovies-mobile/`: the main reference project for internal logic, parsers, watch/player flows, and iOS-native implementations.
- `neomovies-android-main/`: an older secondary reference that may still help with edge cases or legacy behavior comparison.

The iOS app is a new standalone product. Do not treat it as a branded clone of either reference project.

## Product Identity

- Public product name on iOS: `sloosh`.
- Do not introduce any user-facing mention of `NeoMovies`, `neomovies`, `Alloha`, `Collaps`, or other internal source/provider names.
- Backend, package, and module naming in the reference projects may still contain legacy names. Those are technical details only and must not leak into iOS UI copy.
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

Key new reference areas:

- `neomovies-mobile/src/lib/neomovies-api.ts`: current API contract and source/provider request flow.
- `neomovies-mobile/src/hooks/watch-player/`: high-level watch/player orchestration for movie and series flows.
- `neomovies-mobile/src/native/`: TS native bridge contracts used by the mobile app.
- `neomovies-mobile/modules/neomovies-core/ios/`: the most important reference area for native iOS playback, parsers, runtime resolve, progress, and storage logic.

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

- The iOS app already mirrors the core backend API shape for:
  - popular movies
  - top-rated movies
  - top-rated TV
  - details
  - search
- Some backend capabilities are not yet fully ported to iOS, especially:
  - favorites endpoints
  - support/auth/profile flows
  - deeper download/offline flows
- `Models.swift` and `MoviesApi.swift` still reference `api.neomovies.ru` as a technical backend host. This is acceptable as an internal dependency if needed, but never expose that branding in UI.
- When in doubt about request shapes, playback payloads, progress storage, or parser behavior, prefer `neomovies-mobile` over the old Android project.

## Playback Architecture

The iOS playback stack is source-dependent:

- `AllohaRepository.swift`: fetches Alloha source metadata and translations.
- `AllohaRuntimeResolver.swift` and `AllohaRuntimeParser.swift`: current native iOS runtime resolve pipeline for Alloha iframe playback.
- `CollapsRepository.swift`: resolve direct stream data for movies/episodes.
- `HlsProxyServer.swift`: local proxy for header-sensitive HLS playback.
- `PlayerView.swift`: AVPlayer presentation, orientation switching, cleanup.

Important rule:

- `TrustAllSessionDelegate` and SSL-bypass-related behavior must be preserved where already used in networking/parsing flows.

Reference-first rule:

- For playback internals, parser behavior, progress/watched state, and storage logic, use `neomovies-mobile/modules/neomovies-core/ios/` as the primary source of truth.
- Do not copy Expo/React Native bridge code blindly. Port the Swift core logic and adapt interfaces to the `sloosh-iOS` architecture.

## Main Reference Purpose

Use `neomovies-mobile/` as the main source of truth for:

- feature scope
- behavior
- data contract
- edge cases
- watch selector flows
- parser/runtime resolve logic
- player internals
- watched/progress/storage flows
- downloads/offline structure

Use `neomovies-android-main/` only as a secondary fallback reference for:

- legacy edge cases not obvious in `neomovies-mobile`
- older behavior comparisons
- gaps where the new mobile project does not expose enough detail

Do not copy from the references blindly:

- branding
- package names
- Expo or React Native bridge structure
- support/credits/changelog clutter
- user-facing source/provider names
- Android-specific UI structure when a more native iOS solution exists

## Key Mobile Reference Areas

- `src/lib/neomovies-api.ts`: backend/API contract, provider fetch flow, and request behavior.
- `src/hooks/watch-player/movie.ts`: movie watch flow orchestration.
- `src/hooks/watch-player/series.ts`: series watch flow orchestration.
- `src/hooks/watch-player/alloha.ts`: Alloha-specific flow on the JS side.
- `modules/neomovies-core/ios/AllohaRuntimeResolver.swift`: most important current iOS reference for Alloha iframe runtime resolve.
- `modules/neomovies-core/ios/AllohaRuntimeParser.swift`: payload parsing and stream extraction.
- `modules/neomovies-core/ios/CollapsParser.swift`: current iOS reference for Collaps parsing.
- `modules/neomovies-core/ios/NeomoviesHTTPClient.swift`: request/header handling reference.
- `modules/neomovies-core/ios/CollapsPlaybackProgressStore.swift`: progress persistence reference.
- `modules/neomovies-core/ios/CollapsAV*.swift`: player playlist, audio, quality, and playback internals.

## Secondary Android Reference Areas

- `app/src/main/java/com/neo/neomovies/ui/watch/`: still useful for old watch/source-selection edge cases.
- `app/src/main/java/com/neo/neomovies/ui/details/`: still useful for old favorites/downloads behavior comparison.
- `app/src/main/java/com/neo/neomovies/data/` and `data/network/`: still useful when validating legacy contracts.

## Current Mapping: Reference -> iOS

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
- Part of the Alloha runtime logic is now being aligned with `neomovies-mobile` native Swift implementations instead of the old Android-only reference.

## Highest-Value Next Steps

When continuing work, the highest-value missing areas are:

1. Continue replacing old internal playback/parser code with adapted Swift logic from `neomovies-mobile/modules/neomovies-core/ios/`.
2. Bring `Collaps` parsing and playback internals closer to the new mobile reference.
3. Port real progress/watched/storage support using the new mobile reference contracts.
4. Real favorites support using the existing backend contract.
5. Real downloads/offline UI and storage flow.
6. Deeper playback settings without exposing internal source names.
7. Optional profile/auth/update features only if they fit the iOS product direction.

## Editing Guidance For Future Agents

- Keep edits small and verifiable.
- Read nearby code before changing it; this project may be actively edited.
- Do not revert unrelated user changes.
- Prefer preserving existing SwiftUI style and naming.
- Prefer `neomovies-mobile` as the main reference for internal logic.
- Port Swift core logic from `neomovies-mobile/modules/neomovies-core/ios/` where practical, but adapt it to the `sloosh-iOS` architecture instead of copying module boundaries verbatim.
- If using Android code as a secondary reference, port behavior rather than copying terminology.
- Keep all new user-facing text aligned with the `sloosh` brand.

## Quick Summary

This is a premium-looking iOS SwiftUI app called `sloosh`. The main technical reference for internal logic is now `neomovies-mobile`, especially its native iOS Swift core in `modules/neomovies-core/ios/`. Preserve the standalone identity, keep internal provider names out of the UI, prefer native iOS solutions, port Swift core logic where useful, and use the old Android project only as a secondary fallback reference for edge cases.
