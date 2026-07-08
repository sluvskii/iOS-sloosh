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

## User Preferences And Constraints

- Preferred communication language with the user: Russian.
- Preferred implementation style: native SwiftUI, minimal and verifiable edits.
- Target platform: iOS 26+ first.
- Preferred visual style: "Liquid Glass", premium look, floating components, native iOS 26 behaviors.
- Prefer native iOS patterns over literal Android UI copies.
- **IMPORTANT for iOS 26 UI**:
  - Do NOT create custom "floating" components by wrapping views in `.ultraThinMaterial` and `safeAreaInset`.
  - For top floating components (like category tabs), use `.safeAreaBar(edge: .top)` — already used in `HomeView`.
  - Let the system (iOS 26) handle the Liquid Glass blur and morphing automatically during scroll. Do not add redundant backgrounds or overlays.
  - Use `.glassEffect(in:)` for pill/card surfaces (already used in `HomeView` and `DetailsView`).
  - Use `.tabBarMinimizeBehavior(.onScrollDown)` for tab bar auto-hide on scroll (already set in `ContentView`).

## iOS App Structure

Root: `sloosh-iOS/sloosh/Sources/`

- `App/`: app entry point and crash monitoring.
- `Data/Models/`: DTOs, image URL normalization, enums.
- `Data/Network/`: API client.
- `Data/Repositories/`: business logic, caching, playback progress, favorites.
- `UI/`: SwiftUI screens organized by feature.

### Key Files

| File | Purpose |
|------|---------|
| `App/slooshApp.swift` | App entry, audio session setup, crash alert, URL cache (50MB mem / 200MB disk) |
| `App/AppDiagnostics.swift` | Crash monitoring via `NSSetUncaughtExceptionHandler`, session tracking, log export via `ShareSheet` |
| `UI/Home/ContentView.swift` | Root `TabView` with 5 tabs, logo overlay, `.tabBarMinimizeBehavior(.onScrollDown)`, `.tint(Color.slooshAccent)` |
| `UI/Home/HomeView.swift` | Horizontal paged catalog, category tabs via `.safeAreaBar`, shimmer placeholders, `HomeViewModel` with per-key pagination cache |
| `UI/Search/SearchView.swift` | Searchable grid with history (5 items max, `UserDefaults`), debounced 300ms search, pagination |
| `UI/Details/DetailsView.swift` | Full details page: stretchy backdrop, logo overlay, play button, genres (FlowLayout), description, inline episodes for TV |
| `UI/Details/SourceSelectionView.swift` | Alloha source picker: translation/season/episode chips (`WatchSelectorChip`), quality selection, restores last played position |
| `UI/Details/WatchSelectorUI.swift` | `WatchSelectorChip` component, `FlowLayout` for chip wrapping |
| `UI/Details/QualitySelectionSheet.swift` | Quality selection sheet shown when preference is `.ask` |
| `UI/Player/PlayerView.swift` | AVPlayer-based player with Alloha iframe resolution, HLS proxy, progress tracking, autoplay next episode |
| `UI/Continue/ContinueView.swift` | "Continue Watching" screen: reads `PlaybackProgressStore`, re-fetches Alloha sources, resumes playback |
| `UI/Profile/ProfileView.swift` | Favorites display with category tabs (Все/Фильмы/Сериалы/Мульты), settings gear opens `SettingsView` |
| `UI/Favorites/FavoritesView.swift` | Standalone `FavoritesView` (currently unused in main navigation — `ProfileView` handles favorites) |
| `UI/Downloads/DownloadsView.swift` | Placeholder tab — download functionality not yet implemented |
| `UI/Settings/SettingsView.swift` | Video quality picker, autoplay toggle, tab bar labels toggle (debounced 350ms), navigation to `AboutView` |
| `UI/Settings/AboutView.swift` | App icon + version display, minimal |
| `UI/Shared/ShareSheet.swift` | UIActivityViewController wrapper |
| `UI/ShimmerModifier.swift` | `.shimmer()` modifier for loading skeletons |
| `UI/Color+Theme.swift` | `Color.slooshAccent` definition |
| `Data/Network/MoviesApi.swift` | API client for `api.neomovies.ru`, timeout 15s/30s, cache policy `.returnCacheDataElseLoad` |
| `Data/Repositories/MoviesRepository.swift` | In-memory page cache, methods: `getPopularMovies`, `getTopMovies`, `getTopTv`, `getDetails`, `getEpisodeDetails`, `searchMovies`, `searchMoviesResponse` |
| `Data/Models/Models.swift` | All DTOs: `MediaDto`, `MediaDetailsDto`, `FavoriteDto`, `TvEpisodeDetailsDto`, `VideoQualityPreference`, `normalizeImageUrl()` |
| `Data/Models/PlaybackSubtitle.swift` | `PlaybackSubtitle` model |
| `Data/Repositories/AllohaRepository.swift` | Fetches Alloha source metadata and translations by KP ID |
| `Data/Repositories/AllohaParser.swift` | Parses Alloha API response into `AllohaApiResult` (movie/serial structure) |
| `Data/Repositories/AllohaRuntimeResolver.swift` | Resolves Alloha iframe URL → real HLS stream URL (async/await) |
| `Data/Repositories/AllohaRuntimeParser.swift` | Parses resolved Alloha runtime payload, extracts stream URLs |
| `Data/Repositories/AllohaSessionManager.swift` | Manages Alloha session state |
| `Data/Repositories/HlsProxyServer.swift` | Local HTTP proxy server on `127.0.0.1` for header-sensitive HLS playback, injects custom headers |
| `Data/Repositories/PlaybackHlsRewriter.swift` | Rewrites HLS playlist content for proxy compatibility |
| `Data/Repositories/PlaybackProgressStore.swift` | Progress/position/duration/watched state in `UserDefaults`, per-episode keys like `kp_{id}_s{s}_e{e}`, metadata cache, voiceover persistence |
| `Data/Repositories/FavoritesRepository.swift` | Local favorites in `UserDefaults` (key: `local_favorites`), auto-refreshes missing metadata on launch |

## iOS Screens Status

### Fully Implemented

| Screen | File | Notes |
|--------|------|-------|
| Home | `HomeView.swift` | Paged horizontal categories (Все/Фильмы/Сериалы/Мульты), filter (Смотрят сейчас / По рейтингу via long-press context menu), infinite scroll, shimmer skeletons |
| Search | `SearchView.swift` | Debounced search, history, paginated grid results |
| Details | `DetailsView.swift` | Stretchy backdrop, logo, metadata, play button → source sheet, inline episodes for TV, dominant color extraction, favorites toggle |
| Source Selection | `SourceSelectionView.swift` | Alloha only — translation/season/episode chips, quality selection, saves last played position |
| Player | `PlayerView.swift` | AVPlayer + `AVPlayerViewController`, Alloha iframe resolution, HLS proxy, quality switching, audio track selection, progress tracking every 5s, autoplay next episode |
| Continue Watching | `ContinueView.swift` | Reads `PlaybackProgressStore`, shows cards with backdrop/progress bar, re-fetches sources from Alloha, supports resume for movies and series |
| Profile / Favorites | `ProfileView.swift` | Shows local favorites with category tabs; opens `SettingsView` via gear icon |
| Settings | `SettingsView.swift` | Quality preference, autoplay toggle, tab labels toggle |
| About | `AboutView.swift` | App icon + version |

### Placeholder / Not Implemented

| Screen | Status |
|--------|--------|
| `DownloadsView.swift` | Placeholder UI only — no download logic |
| `FavoritesView.swift` | Exists but **not connected to main navigation** (profile uses `ProfileView` instead) |
| Profile / Auth | Not implemented |
| TorrServer / Torrents | Not implemented |

## Navigation Structure

```
TabView (ContentView)
├── .home       → HomeView → DetailsView → PlayerView (fullScreenCover)
│                                       → SourceSelectionView (sheet)
├── .search     → SearchView → DetailsView (same flow as Home)
├── .downloads  → DownloadsView (placeholder)
├── .continueWatching → ContinueView → PlayerView (fullScreenCover)
└── .profile    → ProfileView → DetailsView
                             → SettingsView (navigationDestination) → AboutView
```

## Data Layer Notes

### API Endpoints (base: `https://api.neome.uk`)

| Method | Endpoint | Returns |
|--------|----------|---------|
| GET | `api/v1/movies/popular?page=N` | `ApiEnvelope<MediaResponse>` |
| GET | `api/v1/movies/top-rated?page=N` | `ApiEnvelope<MediaResponse>` |
| GET | `api/v1/tv/top-rated?page=N` | `ApiEnvelope<MediaResponse>` |
| GET | `api/v1/movie/{id}` | `ApiEnvelope<MediaDetailsDto>` |
| GET | `api/v1/tv/{id}/season/{s}/episode/{e}` | `ApiEnvelope<TvEpisodeDetailsDto>` |
| GET | `api/v1/search?query=...&page=N` | `ApiEnvelope<MediaResponse>` |

### Image URL Normalization

`normalizeImageUrl(path:id:)` in `Models.swift`:
- Absolute URLs → returned as-is (percent encoded)
- Paths starting with `/` → prefixed with `https://api.neome.uk`
- Paths starting with `api/` → prefixed with `https://api.neome.uk/`
- Fallback by numeric KP id → `api/v1/images/kp_small/{id}?fallback=true`

### Playback Progress Key Schema (`UserDefaults`)

- Episodes: `neomovies.collaps.progress.kp_{id}_s{season}_e{episode}`
- Movies: `neomovies.collaps.progress.kp_{id}`
- Duration, watched, updatedAt: same suffixes (`dur.`, `watched.`, `updatedAt.`)
- Metadata: `neomovies.collaps.meta.kp_{id}` (JSON-encoded `PlaybackMediaMetadata`)
- Last voiceover: `neomovies.alloha.lastVoiceover.kp_{id}`
- Last season/episode: `neomovies.collaps.lastSeason.kp_{id}`, `neomovies.collaps.lastEpisode.kp_{id}`

### Favorites Storage

- Key: `local_favorites` in `UserDefaults`
- Type: JSON-encoded `[FavoriteDto]`
- Auto-refreshes entries missing `rating` on app launch
- **Not synced with server** — local only

## Playback Architecture

```
DetailsView → SourceSelectionView (Alloha)
    ↓ iframeUrl + kpId + season + episode + voiceover
PlayerView
    ↓
PlayerViewModel.load()
    ↓
AllohaRuntimeResolver.resolve(iframeUrl:)  [async]
    ↓
AllohaRuntimeParser  [parses payload → stream URL + headers]
    ↓
HlsProxyServer (127.0.0.1:PORT)  [injects headers, rewrites HLS]
    ↓
AVPlayerViewController (fullscreen, landscape lock)
```

Key behaviors:
- Progress is saved every 5 seconds and on cleanup
- On cleanup: orientation restored to `.all`, proxy stopped, player deallocated
- Audio track selection: matches saved voiceover name via `allohaTranslationNamesMatch()`
- Autoplay next episode: reads `autoplayNextEpisode` from `UserDefaults`, fetches next translation from `seriesResult`
- `TrustAllSessionDelegate` and SSL-bypass-related behavior must be preserved where already used

## Continue Watching Logic

1. `PlaybackProgressStore.listProgressRecords()` scans all `UserDefaults` keys matching the progress prefix
2. Filters: `!watched`, `positionSec >= 30`, `durationSec >= 60`, `progressFraction >= 0.03`
3. Groups by `kpId`, picks latest episode per title
4. Backfills missing metadata via `MoviesRepository.getDetails()`
5. On resume: calls `AllohaRepository.fetchByKpId()`, selects saved voiceover and episode

## Reference Project: neomovies-mobile

Use `neomovies-mobile/` as the source of truth for:
- feature scope and behavior
- data contracts and edge cases
- watch selector flows
- parser/runtime resolve logic
- player internals
- watched/progress/storage flows

### Most Important iOS Reference Files

| File | iOS equivalent |
|------|---------------|
| `modules/neomovies-core/ios/AllohaRuntimeResolver.swift` | `AllohaRuntimeResolver.swift` |
| `modules/neomovies-core/ios/AllohaRuntimeParser.swift` | `AllohaRuntimeParser.swift` |
| `modules/neomovies-core/ios/CollapsParser.swift` | not yet ported |
| `modules/neomovies-core/ios/CollapsPlaybackProgressStore.swift` | `PlaybackProgressStore.swift` |
| `modules/neomovies-core/ios/CollapsAV*.swift` | partial — `PlayerView` covers some logic |
| `modules/neomovies-core/ios/AllohaHLSProxyServer.swift` | `HlsProxyServer.swift` |
| `modules/neomovies-core/ios/NeomoviesHlsRewriter.swift` | `PlaybackHlsRewriter.swift` |
| `src/lib/neomovies-api.ts` | `MoviesApi.swift` + API contract |
| `src/hooks/watch-player/movie.ts` | movie watch flow in `DetailsView`/`PlayerView` |
| `src/hooks/watch-player/series.ts` | series watch flow in `DetailsView`/`ContinueView` |

Do not copy from the reference:
- branding or package names
- Expo or React Native bridge structure
- support/credits/changelog clutter
- user-facing source/provider names
- Android-specific UI when a native iOS solution exists

## Highest-Value Next Steps

When continuing work, the highest-value missing areas are:

1. **Downloads**: Implement real download/offline storage flow (currently a placeholder).
2. **Collaps source support**: Port `CollapsParser.swift` and playback flow from `neomovies-mobile/modules/neomovies-core/ios/` for a second playback source.
3. **Deeper player settings**: Quality/audio track UI inside the player itself without exposing provider names.
4. **Profile/Auth**: Optional — only if it fits the iOS product direction.
5. **FavoritesView cleanup**: `FavoritesView.swift` exists but is unused (Profile handles favorites). Either remove it or integrate it.
6. **Cartoon detection improvement**: Currently relies on title string matching; a genre-based approach would be more accurate.

## Editing Guidance For Future Agents

- Keep edits small and verifiable.
- Read nearby code before changing it; this project is actively edited.
- Do not revert unrelated user changes.
- Preserve existing SwiftUI style, naming, and MVVM structure (`ViewModel` as `ObservableObject`).
- Prefer `neomovies-mobile` as the main reference for internal logic.
- Port Swift core logic from `neomovies-mobile/modules/neomovies-core/ios/` where practical, but adapt it to the `sloosh-iOS` architecture instead of copying module boundaries verbatim.
- Keep all new user-facing text aligned with the `sloosh` brand.
- `TrustAllSessionDelegate` and SSL-bypass behavior must be preserved where already in use.
- When adding new UserDefaults keys, follow the `neomovies.*` prefix convention used by `PlaybackProgressStore`.

## Quick Summary

`sloosh` is a premium iOS 26+ SwiftUI streaming app. It uses Alloha as the primary playback source, resolved natively via `AllohaRuntimeResolver` → `AllohaRuntimeParser` → `HlsProxyServer` → `AVPlayerViewController`. Progress is stored locally in `UserDefaults`. Favorites are stored locally (no server sync). The "Continue Watching" tab is fully functional. The "Downloads" tab is a placeholder. The main technical reference for internal logic is `neomovies-mobile`, especially its native iOS Swift core in `modules/neomovies-core/ios/`. There is no Android reference project in this workspace.
