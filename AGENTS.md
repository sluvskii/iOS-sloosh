# Agent Onboarding

## Workspace Overview

This workspace contains two projects:

- `sloosh-iOS/`: the active iOS app under the `sloosh` brand.
- `neomovies-mobile/`: the main reference project for internal logic, parsers, watch/player flows, and iOS-native implementations.

The iOS app is a standalone product. Do not treat it as a branded clone of the reference project.

## Product Identity

- Public product name on iOS: `sloosh`.
- Do not introduce any user-facing mention of `NeoMovies`, `neomovies`, `Alloha`, `Collaps`, or other internal source/provider names.
- Backend, package, and module naming in the reference project may still contain legacy names. Those are technical details only and must not leak into iOS UI copy.
- Avoid adding screens like Credits, Changes, or support clutter. The preferred UI is focused and flagship-like.
- **CRITICAL SOURCE RULE**: Do NOT implement or attempt to integrate the `Collaps` streaming source. It is a dead topic and completely unnecessary for the application. Focus exclusively on `Alloha`.

## User Preferences And Constraints

- Preferred communication language with the user: Russian.
- Preferred implementation style: native SwiftUI, minimal and verifiable edits.
- Target platform: iOS 26+ first.
- Preferred visual style: "Liquid Glass", premium look, floating components, native iOS 26/27 behaviors.
- Prefer native iOS patterns over literal Android UI copies.
- **IMPORTANT for iOS 26/27 UI**:
  - **CRITICAL**: The app is a premium edge-to-edge application. All floating elements must use liquid glass (`.glassEffect()`).
  - **CRITICAL**: The use of `.ultraThinMaterial` is STRICTLY FORBIDDEN in the project.
  - For top floating components (like category tabs), use `.safeAreaBar(edge: .top)` — already used in `HomeView`.
  - Let the system (iOS 26/27) handle the Liquid Glass blur and morphing automatically during scroll. Do not add redundant backgrounds or overlays.
  - Use `.glassEffect(in:)` for pill/card surfaces and sheets.
  - Use `.tabBarMinimizeBehavior(.onScrollDown)` for tab bar auto-hide on scroll (already set in `ContentView`).

## iOS App Structure

Root: `sloosh-iOS/sloosh/Sources/`

- `App/`: app entry point and crash monitoring.
- `Data/Models/`: DTOs, image URL normalization, enums.
- `Data/Network/`: API client.
- `Data/Repositories/`: business logic, caching, playback progress, favorites, downloads.
- `UI/`: SwiftUI screens organized by feature.

### Key Files

| File | Purpose |
|------|---------|
| `App/slooshApp.swift` | App entry, audio session setup, crash alert, URL cache |
| `App/AppDiagnostics.swift` | Crash monitoring via `NSSetUncaughtExceptionHandler` |
| `UI/Home/ContentView.swift` | Root `TabView` with 5 tabs, logo overlay, `.tabBarMinimizeBehavior(.onScrollDown)`, `.tint(Color.slooshAccent)` |
| `UI/Home/HomeView.swift` | Horizontal paged catalog, category tabs via `.safeAreaBar`, shimmer placeholders |
| `UI/Search/SearchView.swift` | Searchable grid with history, debounced search, pagination |
| `UI/Details/DetailsView.swift` | Full details page: stretchy backdrop, logo overlay, play button, inline episodes for TV |
| `UI/Details/SourceSelectionView.swift` | Alloha source picker: translation/season/episode chips |
| `UI/Player/PlayerView.swift` | AVPlayer-based player with Alloha iframe resolution, HLS proxy, progress tracking |
| `UI/Continue/ContinueView.swift` | "Continue Watching" screen: reads `PlaybackProgressStore`, resumes playback |
| `UI/Profile/ProfileView.swift` | Favorites display with category tabs (Все/Фильмы/Сериалы/Мульты); Settings gear |
| `UI/Downloads/DownloadsView.swift` | Downloads tab with `DownloadManager` integration, progress radial bars, swipe to delete |
| `UI/Settings/SettingsView.swift` | Video quality picker, autoplay toggle, tab bar labels toggle |
| `Data/Network/MoviesApi.swift` | API client for `api.neomovies.ru` |
| `Data/Repositories/MoviesRepository.swift` | Page cache (memory + disk), search logic, details caching |
| `Data/Repositories/AllohaRuntimeResolver.swift` | Resolves Alloha iframe URL → real HLS stream URL via a pooled `WKWebView` |
| `Data/Repositories/PlaybackProgressStore.swift` | Progress/position/duration/watched state in `SwiftData` (`ProgressRecordModel`) |
| `Data/Repositories/FavoritesRepository.swift` | Manages user favorites via `SwiftData` (`FavoriteModel`) |
| `Data/Models/Schema.swift` | `SwiftData` models for persistence |
| `UI/ShimmerModifier.swift` | Metal-based shader for skeleton loading placeholders |
| `Data/GroupActivities/WatchTogetherActivity.swift` | SharePlay integration for synchronized playback |

## iOS Screens Status

### Fully Implemented

| Screen | File | Notes |
|--------|------|-------|
| Home | `HomeView.swift` | Paged horizontal categories, filters, infinite scroll, shimmer skeletons |
| Search | `SearchView.swift` | Debounced search, history, paginated grid results |
| Details | `DetailsView.swift` | Stretchy backdrop, metadata, play button → source sheet, dominant color extraction |
| Player | `PlayerView.swift` | AVPlayer + `AVPlayerViewController`, Alloha iframe resolution, HLS proxy |
| Continue | `ContinueView.swift` | Reads `PlaybackProgressStore`, supports resume for movies and series |
| Profile | `ProfileView.swift` | Shows local favorites with category tabs; opens Settings |
| Downloads | `DownloadsView.swift` | Fully functional downloads manager, radial progress, swipe actions |
| Settings | `SettingsView.swift` | Quality preference, autoplay toggle, tab labels toggle |

### Removed / Unused

| Screen | Status |
|--------|--------|
| `FavoritesView.swift` | **Deleted**. Profile handles favorites. |

## Data Layer Notes

### Caching Strategy
- `MediaDetailsDto` is cached on disk via `MediaDetailsDiskCache` (TTL 24 hours).
- Lists (`getPopularMovies`, `getTopMovies`, `getTopTv`) are cached via `ListDiskCache` to ensure instant cold starts.

## Reference Project: neomovies-mobile

Use `neomovies-mobile/` as the source of truth for internal logic, but **do not copy Expo/React Native structure**. Adapt core logic to iOS Swift strictly following MVVM.

## Quick Summary

`sloosh` is a premium iOS 26+ SwiftUI streaming app. It mandates strict usage of `.glassEffect()` and forbids `.ultraThinMaterial`. It uses Alloha as the primary playback source, resolved natively via `AllohaRuntimeResolver` (using a pooled `WKWebView` to optimize speed) → `AllohaRuntimeParser` → `HlsProxyServer` → `AVPlayerViewController`. Progress and favorites are stored locally via `SwiftData` (`AppDatabase`). SharePlay is fully integrated using `GroupActivities`. Shimmer skeletons are implemented using `Metal` shaders. Downloads are fully functional and use `DownloadManager`. The main technical reference for internal logic is `neomovies-mobile`.

## Development & Deployment Workflow

- **CRITICAL**: The project is NOT built locally via Xcode or Simulator. 
- Builds and distribution are executed exclusively via GitHub Actions.
- Upon completing any feature or task, you MUST commit your changes and push them to GitHub (`git add .`, `git commit -m "..."`, `git push`).
- After pushing, you must monitor the GitHub CI pipeline (or expect the user to report CI failures). If the build fails, you must investigate the compilation errors and push a fix.
