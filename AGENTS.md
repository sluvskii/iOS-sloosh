# Agent Onboarding

## Workspace Overview

This workspace contains the flagship native iOS client for **sloosh**:

- `sloosh-iOS/`: Active native iOS app under the `sloosh` brand (SwiftUI, iOS 26+).
- The dedicated backend API server (`sloosh-api`) is maintained in its own private repository: `sluvskii/sloosh-api` (`w:\sloosh-api`) and deployed on Vercel Edge with Cloudflare Edge Gateway proxy:
  - **Active Public Gateway**: `https://api.sloosh.workers.dev` (bypasses ISP/TSPU blocks on `*.vercel.app` in Russia).
  - **Origin Server**: `https://api-sloosh.vercel.app` (Vercel Edge Runtime).
  - **Dynamic Remote Config**: `endpoint.json` hosted live on GitHub raw and GitHub Pages (`https://sluvskii.github.io/iOS-sloosh/endpoint.json`).

> [!NOTE]
> The app is completely independent. We have fully transitioned away from the legacy `neomovies` API and codebase. We do NOT use `neomovies` or rely on it in any form. Our own backend (`sloosh-api`) provides a significantly faster, more reliable, and feature-rich API specifically tailored for `sloosh`.

---

## Product Identity & Rules

- **Public product name**: `sloosh`.
- **UI Copy Language**: Russian strictly.
- **Provider Confidentiality**: Never introduce any user-facing mention of internal sources, providers, or scrapers (`Alloha`, `Collaps`, `NeoMovies`, `TMDB`, `Kinopoisk`, etc.).
- **Streaming Sources**: 
  - Exclusively `Alloha` (`api.alloha.tv`).
  - **CRITICAL**: Do NOT implement or integrate `Collaps`. It is completely deprecated, unnecessary, and prohibited.
- **Tone & Polish**: Minimalist, flagship, streaming-service look (like Apple TV+ meets Liquid Glass). Avoid clutter screens like Credits, Changes, or debug panels.

---

## Security & Secrets Architecture

1. **Client API Key Hardening**:
   - The master API key is **never** committed to Git in plaintext or obfuscated arrays.
   - In code, `AppSecrets.apiKey` defaults to `""`.
   - During official GitHub Actions CI builds, `${{ secrets.SLOOSH_API_KEY }}` is dynamically injected into `AppSecrets.swift` prior to compilation.
   - Forks built without secrets compile with an empty key and receive `401 Unauthorized` from the backend, protecting infrastructure from abuse.
2. **Dynamic Streaming Tokens**:
   - Balancer streaming tokens are **never** bundled in the iOS application binary.
   - At startup and on demand, the client fetches the active pool of tokens from `GET /api/v1/config/streams` (authenticated via `X-API-Key`).
   - The client implements in-memory caching (10 min TTL), background prewarming (`slooshApp.swift`), and smart runtime failover with 5-minute cooldown on exhausted/banned tokens.
3. **Dynamic Remote Endpoint Resolution & Failover**:
   - The app does **not** hardcode a single immutable API or image host.
   - At startup, `MoviesApi.shared.loadRemoteConfig()` checks `https://raw.githubusercontent.com/sluvskii/iOS-sloosh/main/endpoint.json` (and GitHub Pages backup).
   - `endpoint.json` dynamically provides `apiBaseUrl`, `imagesBaseUrl`, and `fallbackUrls`.
   - Active hosts are cached in `UserDefaults` (`sloosh_cached_api_base_url`, `sloosh_cached_images_base_url`). Any legacy host containing `vercel.app` is automatically sanitized/discarded.
   - If a host becomes unreachable or blocked by an ISP, the client automatically fails over to `fallbackUrls`.
   - If an endpoint changes, updating `endpoint.json` in the GitHub repo instantly switches all client devices **without rebuilding or reinstalling `.ipa`**.
4. **Repository Confidentiality**:
   - `sluvskii/iOS-sloosh` is the public client repository.
   - `sluvskii/sloosh-api` is the private backend repository. Server endpoints, edge routing, and scraping algorithms remain completely confidential.

---

## UI / Design Guidelines (iOS 26+)

- **Liquid Glass Everywhere**: The app is a premium edge-to-edge application. All floating elements, navigation capsules, cards, and modal sheets must use `.glassEffect()`.
- **CRITICAL FORBIDDEN API**: The use of `.ultraThinMaterial` is **STRICTLY FORBIDDEN** throughout the entire codebase.
- **Native iOS Patterns**:
  - Top floating components (category tabs, sticky bars) use `.safeAreaBar(edge: .top)` or `.safeAreaInset(edge: .top)`.
  - Let the system handle Liquid Glass blur and morphing automatically during scroll. Do not add redundant opaque backgrounds or dark overlays.
  - Floating pills, action buttons, and sheet backgrounds use `.glassEffect(in:)` with `.capsule` or `.rect(cornerRadius:)`.
  - Floating navigation tab bar uses `.tabBarMinimizeBehavior(.onScrollDown)` for auto-hide on scroll (configured in `ContentView`).
  - Native zoom transitions: use `.navigationTransition(.zoom(sourceID:in:))` and `.matchedTransitionSource(id:in:)` for seamless card-to-detail and avatar-to-person transitions.
  - Top and bottom insets: respect natural safe areas via `.safeAreaInset` without manually stacking artificial window padding.
  - Full-width swipe back: interactive pop gesture across the entire screen via `.fullWidthSwipeBack()`.
  - Loading skeletons: Metal-accelerated smooth light beam via `.shimmer()` (`Shimmer.metal`).
- **Subtitles Typography & Motion**:
  - Subtitle styling in `SubtitleOverlayView.swift` strictly uses clean standard typography (`design: .default`, `weight: .semibold`, size ~21pt) — **NO rounded font**.
  - Crisp outline drop-shadows with subtle dark translucent backing (`black.opacity(0.55)`).
  - Responsive positioning: automatically animates smoothly upwards (+108pt) when player controls appear and drops down (+36pt) when controls fade out.

---

## Backend Architecture (`sloosh-api` & Edge Proxy)

- **Active Gateway**: `https://api.sloosh.workers.dev` (Cloudflare Worker proxy with Edge caching).
- **Backend Origin**: `https://api-sloosh.vercel.app` (TypeScript, Hono web framework, Vercel Edge Runtime).
- **Primary Data Provider**: The Movie Database (TMDB) v3 API with rich extensions.
- **Streaming Source Provider**: Alloha API (with primary and backup token failover).

### Key Capabilities:
1. **Edge CDN & Image Caching**:
   - Automated `Cache-Control` response headers with `stale-while-revalidate` caching on Edge.
   - Details, collections, and person profiles cached for up to 24 hours (`s-maxage=86400`), cutting response latencies to 15–30 ms.
   - Images proxied through `/api/v1/images/tmdb/:size/*` and cached on Cloudflare Edge for 7 days (`cacheEverything: true`), bypassing ISP blocks on `image.tmdb.org`.
2. **Russian Localization Engine**:
   - Automated country name translation via `src/utils/countries.ts` (`localizeCountry`, `CountryLocalizer`).
   - Russian genre mapping and bi-directional resolution for TMDB Discover.
   - Cleaned person biographies: emojis stripped, automatically parsed into awards, key projects, and interesting facts.
3. **Smart Fallback for Similar Media**:
   - `/movies/:id` and `/tv/:id` deduplicate recommendations and similar items. If count < 6, automatically falls back to Discover query for top titles in the same primary genre. 100% of titles have similar media.
4. **Crew & Creator Parsing (`extractCrew`)**:
   - Extracts directors (`Director`), writers (`Writing`, `Screenplay`, `Writer`, `Story`, `Author`, `Novel`), and series creators (`created_by`).
   - Deduplicates members with unified compound roles (e.g. `"Режиссёр, сценарист"`, `"Создатель, сценарист"`).
   - In `/person/:id`, filmography merges both `combined_credits.cast` AND `combined_credits.crew`, guaranteeing that directors and writers have complete filmographies.

---

## iOS App Architecture (`sloosh-iOS`)

Root: `sloosh-iOS/sloosh/Sources/`

### 1. Application Layer (`App/`)
- `slooshApp.swift`: App entry point, startup prewarming (`MoviesApi.loadRemoteConfig`, `AllohaRepository.warmup`, `SharedWebViewProvider.prewarm`), audio session configuration, and crash logging.
- `AppDiagnostics.swift`: Crash logging, system event diagnostics, and performance metrics.
- `SlooshIntents.swift`: Siri Shortcuts and AppIntents (`PlayMovieIntent`, `ContinueWatchingIntent`).

### 2. Data & Network Layer (`Data/`)
- `Models/`:
  - `Models.swift`: TMDB/Alloha DTOs, category models, collections, cast/crew models. Dynamic image URLs resolve via `MoviesApi.activeImagesBaseURL`.
  - `Schema.swift` & `AppDatabase.swift`: SwiftData schema for persistent watch progress and favorites.
  - `UserProfile.swift`: User profile DTO for cloud account synchronization.
  - `MessengerModels.swift`: Channels, posts, reactions, comments, and direct chat models.
  - `PlaybackSubtitle.swift`: Subtitle models and parsing.
- `Network/`:
  - `AppSecrets.swift`: Injected API credentials (`apiKey`).
  - `MoviesApi.swift`: Dynamic async/await client with remote `endpoint.json` config resolution, failover, `X-API-Key` headers, retry logic, and stream config polling.
  - `NetworkMonitor.swift`: Real-time network reachability (Wi-Fi, Cellular, Offline).
- `Repositories/`:
  - `MoviesRepository.swift`: In-memory and disk caches (`MediaDetailsDiskCache` v7, `PersonDetailsDiskCache` v1, `ListDiskCache`).
  - `AllohaRepository.swift`: Dynamic multi-token manager, request deduplication, priority failover, and cooldown.
  - `AllohaRuntimeResolver.swift` & `AllohaRuntimeParser.swift`: Headless WebKit resolver for encrypted Alloha iframes and stream extraction.
  - `WebVTTParser.swift`: High-performance parser for external WebVTT subtitle files and real-time cue lookup.
  - `HlsProxyServer.swift`: Local HTTP proxy for HLS playback with custom headers.
  - `PlaybackProgressStore.swift`: Watch history, duration, and progress store with SwiftData and cloud sync.
  - `FavoritesRepository.swift`: Favorites store with SwiftData and cloud sync.
  - `CloudSyncService.swift`: Two-way cloud sync with Firebase Realtime Database for favorites, progress, and metadata.
  - `AuthRepository.swift`: Email/password authentication, Google Sign-In, and user profile management via Firebase REST API.
  - `GoogleOAuthService.swift`: ASWebAuthenticationSession PKCE exchange for Google Sign-In.
  - `MessengerRepository.swift`: Telegram-style broadcast channels, posts, movie attachments, comments, and direct chats.
  - `DownloadManager.swift`: Multi-threaded background HLS/MP4 downloader with pause/resume support.
  - `DownloadManifest.swift` & `JSONDataStore.swift`: Offline download metadata persistence.
  - `AppIconManager.swift`: Runtime app icon switching (`Default`, `Cyrillic`, `Glyph`, `Cinema`).
  - `UserPresenceService.swift`: Real-time online/offline presence tracking.
  - `DeepLinkManager.swift`: URL scheme routing (`sloosh://details/:id`, `sloosh://home`).
  - `CacheManager.swift`: System cache size calculator and purge tool.

### 3. User Interface Layer (`UI/`)
- `Home/`:
  - `ContentView.swift`: Root tab navigation bar with Liquid Glass capsule, scroll auto-hide, and unread badges.
  - `HomeView.swift`: Category carousels (Popular, Top Rated, Cartoons, Anime, Sci-Fi), hero backdrop pager, sticky category safeAreaBar.
  - `HomeDirectPlayWrapper.swift`: Instant context-menu direct playback wrapper.
- `Details/`:
  - `DetailsView.swift`: Stretchy backdrop carousel, dynamic logo, crew/cast horizontal carousels, similar media, trailers, seasons/episodes selector.
  - `PersonDetailView.swift`: Person hero, structured bio (awards, key projects, facts), categorized filmography.
  - `SourceSelectionView.swift`: Voiceover, translation, and video quality picker.
  - `TrailerPlayerSheetView.swift`: Floating YouTube trailer player sheet.
  - `GenreCatalogView.swift` & `StudioCatalogView.swift`: Interactive genre and studio catalog navigation.
  - `ShareToFriendSheet.swift`: In-app messenger sharing sheet.
- `Player/`:
  - `PlayerView.swift`: Fullscreen custom AVPlayerViewController wrapper. Handles audio track selection, subtitle parsing, Picture-in-Picture, and playback state.
  - `SubtitleOverlayView.swift`: Premium cinema subtitle rendering with smooth responsive controls animation. Prevents dual rendering by deselecting native AVPlayer legible tracks during custom VTT playback. Filters empty "CC" Closed Captions tracks.
  - `PlayerContainerView.swift`: Double-tap seeking, brightness/volume gestures overlay, top/bottom control bars.
  - `Controls/`: `TopBarView`, `BottomRowView`, `SeekBarView`, `CenterControlsView`, `PlayerControlsView`, `PlayerPickerSheets`.
- `Continue/`:
  - `ContinueView.swift`: "Продолжить просмотр" grid with resume timecodes and batch deletion.
- `Search/`:
  - `SearchView.swift`: Instant debounced search for movies, series, and actors with search history and filter sheets.
  - `SearchFilterSheet.swift`: Multi-select filter sheet for genres, countries, years, and ratings.
- `Profile/`:
  - `ProfileView.swift`: Account management, cloud sync status, favorites shelf, app settings access.
  - `AuthSheetView.swift` & `AuthView.swift`: Glass modal sheets for email/password and Google Sign-In.
  - `EditProfileSheet.swift`: Avatar picker, display name, and bio editor.
- `Messenger/`:
  - `MessengerView.swift`: Channels and direct chats list with real-time updates.
  - `ChannelDetailView.swift` & `ChatDetailView.swift`: Post feed, movie attachments, reactions, comments, and media sharing.
  - `CreateChannelSheet.swift` & `MovieSelectorSheet.swift`: Channel creation and movie card attachment selector.
- `Downloads/`:
  - `DownloadsView.swift`: Offline downloaded media list, radial download indicator, and local playback.
- `Admin/`:
  - `AdminDashboardView.swift`: Administrative controls for channel broadcasts and announcements.
- `Settings/`:
  - `SettingsView.swift`: Video quality preferences, stream CDN preferences, cache cleaner, app icon picker, and about page.
  - `AboutView.swift`: App information, version, and developer details.
- `Shared/`:
  - `AsyncCachedImage.swift`: Dual-tier image caching with automatic TMDB proxy routing through `MoviesApi.activeImagesBaseURL`. Automatic fallback interceptor for legacy hosts.
  - `VariableBlurView.swift`: Progressive UIKit-backed gradient blur for overlays and headers.
  - `SlooshAvatarView.swift`: Liquid Glass user avatar with initials fallback and online status indicator.
  - `TelegramGlassIconButton.swift`: Consistent circular glass button for navigation and actions.
  - `LaunchSplashView.swift`: Launch animation with logo reveal.
  - `FullWidthSwipeBack.swift`: Edge-to-edge interactive pop gesture.
  - `ToastManager.swift`: Non-intrusive floating toast notifications.

---

## Caching Strategy

1. **Edge Gateway CDN (Cloudflare + Vercel)**:
   - Dynamic endpoints and Edge CDN routing with sub-30ms global response time.
   - TMDB Image proxy cached on Cloudflare Edge for 7 days (`cacheEverything: true`).
2. **Local iOS Disk Caches**:
   - `MediaDetailsDiskCache`: Located in `Library/Caches/sloosh.mediadetails.v7` (TTL 24 hours).
   - `PersonDetailsDiskCache`: Located in `Library/Caches/sloosh.persondetails.v1` (TTL 24 hours).
   - `ListDiskCache`: Instant cold starts for popular movies, top movies, top TV series, and cartoons.
3. **Image Caching**:
   - `AsyncCachedImage` + `ImageCache` (memory + disk) with dynamic routing through `MoviesApi.activeImagesBaseURL`.

---

## Distribution & CI/CD Workflow

- **CRITICAL**: The iOS project is **NOT** built locally via Xcode or Simulator.
- Builds, code signing, and distribution are executed **exclusively via GitHub Actions CI**.
- **AltStore / SideStore Distribution**:
  - CI automatically generates `apps.json` with the latest build number, download URL, and metadata.
  - The repository deploys `apps.json` and `endpoint.json` directly via official GitHub Actions Pages (`https://sluvskii.github.io/iOS-sloosh/apps.json`).
- **Delivery Protocol**:
  1. Make minimal, focused, verified edits.
  2. Commit changes and push directly to `main`:
     ```powershell
     $env:HTTPS_PROXY = $null; git add . ; git commit -m "..."; git push origin main
     ```
  3. Monitor the GitHub CI workflow run (`iOS Build`) until completion.
  4. Provide the user with the release tag and direct download link for the generated `.ipa`.
