# Agent Onboarding

## Workspace Overview

This workspace contains the flagship native iOS client for **sloosh**:

- `sloosh-iOS/`: Active native iOS app under the `sloosh` brand (SwiftUI, iOS 26+, current marketing version **2.1**).
- The dedicated backend API server (`sloosh-api`) is maintained in its own private repository: `sluvskii/sloosh-api` (`w:\sloosh-api`) and deployed on Vercel Edge with Cloudflare Edge Gateway proxy:
  - **Active Public Gateway**: `https://api.sloosh.workers.dev` (bypasses ISP/TSPU blocks on `*.vercel.app` in Russia).
  - **Origin Server**: `https://api-sloosh.vercel.app` (Vercel Edge Runtime).
  - **Dynamic Remote Config**: `endpoint.json` hosted live on GitHub raw and GitHub Pages (`https://sluvskii.github.io/iOS-sloosh/endpoint.json`).
- **Firebase Realtime Database** (`https://sloosh-77434-default-rtdb.firebaseio.com`) is used directly by the client for social and live features: messenger (channels, posts, chats), clips feed (likes, views, comments), movie/series comments (`media_comments` + `media_comment_reports`), user presence and live "watching now" sessions, media artwork overrides, and admin operations. Security is defined in `database.rules.json` at the repository root; all requests are authenticated with Firebase ID tokens.

> [!NOTE]
> The app is completely independent. We have fully transitioned away from the legacy `neomovies` API and codebase. We do NOT use `neomovies` or rely on it in any form. Our own backend (`sloosh-api`) provides a significantly faster, more reliable, and feature-rich API specifically tailored for `sloosh`.

---

## Product Identity & Rules

- **Public product name**: `sloosh`.
- **UI Copy Language**: Russian strictly.
- **Provider Confidentiality**: Never introduce any user-facing mention of internal sources, providers, or scrapers (`Alloha`, `Collaps`, `NeoMovies`, `TMDB`, `Kinopoisk`, etc.). In the UI, streaming sources are exposed only as «Основной» / «Резервный».
- **Streaming Sources** (dual-source architecture):
  - **Primary** (`MediaStreamSource.source1`, «Основной»): `Alloha` (`api.alloha.tv`) with dynamic multi-token pool and headless WebKit iframe resolution.
  - **Backup** (`MediaStreamSource.source2`, «Резервный»): `Collaps` — actively integrated as a manual secondary source and automatic fallback (inline seasons in `DetailsView`, playback in `PlayerView`, clips in `ClipStreamResolver`). Keep it UI-anonymous under the «Резервный» label.
  - The preferred source is user-selectable (`preferredStreamSource` in Settings → «Воспроизведение» → «Источник», default: primary).
- **Tone & Polish**: Minimalist, flagship, streaming-service look (like Apple TV+ meets Liquid Glass). Avoid clutter screens like Credits, Changes, or debug panels.

---

## Security & Secrets Architecture

1. **Client API Key Hardening**:
   - The master API key is **never** committed to Git in plaintext or obfuscated arrays.
   - In code, `AppSecrets.apiKey` defaults to `""`.
   - During official GitHub Actions CI builds, `${{ secrets.SLOOSH_API_KEY }}` is dynamically injected into `AppSecrets.swift` prior to compilation.
   - Forks built without secrets compile with an empty key and receive `401 Unauthorized` from the backend, protecting infrastructure from abuse.
2. **Dynamic Streaming Tokens & Fallbacks**:
   - Balancer streaming tokens are **never** bundled in the iOS application binary.
   - At startup and on demand, the client fetches the active pool of tokens from `GET /api/v1/config/streams` (authenticated via `X-API-Key`).
   - The client implements in-memory caching (10 min TTL), background prewarming (`slooshApp.swift`), and smart runtime failover with 5-minute cooldown on exhausted/banned tokens.
   - `endpoint.json` also supports emergency `streamTokens` fallback if the backend API token endpoint is temporarily unreachable.
3. **Dynamic Remote Endpoint Resolution, Self-Healing & Zero-Update Hot-Fixing**:
   - The app does **not** hardcode a single immutable API, balancer, or image host.
   - At startup, `MoviesApi.shared.loadRemoteConfig()` checks `https://raw.githubusercontent.com/sluvskii/iOS-sloosh/main/endpoint.json` (and GitHub Pages / jsDelivr backups).
   - `endpoint.json` dynamically provides `apiBaseUrl`, `imagesBaseUrl`, `fallbackUrls`, `balancerBaseUrl` (customizable balancer proxy host), emergency `apiKey` rotation, `streamTokens`, broadcast `notice` banners, and `mediaOverrides` (emergency artwork overrides).
   - Active hosts are cached in `UserDefaults` (`sloosh_cached_api_base_url`, `sloosh_cached_images_base_url`, `sloosh_cached_balancer_base_url`). Legacy hosts containing `vercel.app` are automatically sanitized.
   - **Self-Healing Architecture**: If API requests fail due to `401 Unauthorized`, `403 Forbidden`, or server downtime, `MoviesApi` triggers an automatic force-reload of remote config and immediately retries the request once if endpoints or keys were updated, fixing outages with zero app updates.
   - **System Notices**: `endpoint.json` can deliver broadcast announcements (`info`, `warning`, `error`, `critical`) shown once per notice ID via `ToastManager`.
4. **Repository Confidentiality**:
   - `sluvskii/iOS-sloosh` is the public client repository.
   - `sluvskii/sloosh-api` is the private backend repository. Server endpoints, edge routing, and scraping algorithms remain completely confidential.

---

## UI / Design Guidelines (iOS 26+)

- **Liquid Glass Everywhere**: The app is a premium edge-to-edge application. All floating elements, navigation capsules, cards, and modal sheets must use `.glassEffect()`.
- **CRITICAL FORBIDDEN API**: The use of `.ultraThinMaterial` is **STRICTLY FORBIDDEN** throughout the entire codebase.
- **CRITICAL FORBIDDEN TYPOGRAPHY**: The use of rounded fonts (`design: .rounded`) is **STRICTLY FORBIDDEN** throughout the entire codebase. Always use standard default San Francisco typography (`design: .default` or omit the `design:` parameter) for a flagship native iOS / Apple TV look.
- **Native iOS Patterns**:
  - Top floating components (category tabs, sticky bars) use `.safeAreaBar(edge: .top)` or `.safeAreaInset(edge: .top)`.
  - Let the system handle Liquid Glass blur and morphing automatically during scroll. Do not add redundant opaque backgrounds or dark overlays.
  - Floating pills, action buttons, and sheet backgrounds use `.glassEffect(in:)` with `.capsule` or `.rect(cornerRadius:)`.
  - Root navigation (`ContentView`) is a 5-tab `TabView`: Главная, Поиск (search role), **Моменты** (clips feed), Продолжить, Профиль (avatar-backed tab icon). The floating tab bar uses `.tabBarMinimizeBehavior(tabBarMinimizeOnScroll ? .onScrollDown : .never)` for auto-hide on scroll (user toggle, default `true`) and shows unread badges from `MessengerRepository`.
  - Dark Cinematic Isolation: All player presentations (`PlayerHostingController`, `PlayerView`, `PlayerContainerView`, and parent `.fullScreenCover` callers) as well as `DetailsView` and `PersonDetailView` strictly enforce `.environment(\.colorScheme, .dark)` and `.preferredColorScheme(.dark)`, ensuring Liquid Glass controls, menus, and text never become washed out in light system theme.
  - In-Sheet Quality Selection: `SourceSelectionView` seamlessly animates between source/translation selection and video quality selection within the same sheet (`isSelectingQuality`, back button, "Remember choice") with spring animation; a standalone `QualitySelectionSheet` exists for the global quality preference flow. `WatchSelectorUI` provides the shared selection chips.
  - Native zoom transitions: use `.navigationTransition(.zoom(sourceID:in:))` and `.matchedTransitionSource(id:in:)` for seamless card-to-detail and avatar-to-person transitions.
  - Top and bottom insets: respect natural safe areas via `.safeAreaInset` without manually stacking artificial window padding.
  - Full-width swipe back: interactive pop gesture across the entire screen via `.fullWidthSwipeBack()` (disabled inside `DetailsView`).
  - Details hero actions: Apple Music-inspired centered **Download · Play · Favorite** circles (52 / 72 / 52pt, 22pt gaps). No visible «Смотреть» capsule. Play is a white disc with an actual transparent symbol cutout (`destinationOut` inside a local compositing group), not a black glyph; no glass behind the primary disc. The 34pt Play symbol stays centered. Hero side buttons use a flat white fill at 12% opacity, without blur, border, or Liquid Glass (intentional exception to the general glass rule); download uses `arrow.down.to.line`, not a bare arrow. Hero controls use `.plusLighter` against the actual Details backdrop, matching Home text tabs in dark mode: Play disc at 85% opacity, secondary symbols at 72%, side fills at 12% (latest tuning: slightly stronger side symbols, slightly more translucent Play). Keep Play’s local destination-out compositing group before the outer blend; never apply blending to the glass surface itself. Navigation favorite stays 44pt with glass. Share remains in the top bar, including after scrolling. Released titles expose Favorite only in the hero; unreleased titles retain their nonplayable premiere/countdown and keep Favorite up top. `DetailsHeroDownloadButton` observes download progress independently of the whole Details hierarchy. Preserve existing source/translation/quality and episode selection flows.
  - Loading skeletons: Metal-accelerated smooth light beam via `.shimmer()` (`Shimmer.metal` + `ShimmerModifier.swift`).
  - Performance: `AsyncCachedImage` decodes images off the main thread using `UIImage.byPreparingForDisplay()` before SwiftUI rendering, eliminating scroll hitches.
  - Unified empty states: `AppEmptyStateView` (large SF Symbol, bold title, description, optional action) is the standard for all empty screens.
- **Two foreground styles, not a global screen filter**: `.backdropForeground(opacity:)` styles neutral text/symbols above cinematic backgrounds and variable-blur headers (primary 90%, prose 85%, secondary 65%). `.glassForeground()` styles icon/text content **inside glass controls across the app**, including headers, custom platters, player controls and app-owned toolbar labels. Apply it BEFORE background/`.glassEffect`, never to a whole control surface. Dark uses `plusLighter`, light uses `plusDarker`; added foreground opacity is 72%, disabled/semantic tints opt out, Increase Contrast/Reduce Transparency use normal/no additional opacity. Inverted black/white send-button ink uses `isInverted: true`. The common `TelegramGlassIconButton` retains its UIKit hit/accessibility layer but renders its visible symbol as a non-hit-testing SwiftUI overlay before glass. Never globally alter `.glassPress` to style entire labels after glass. Preserve explicit red/green/accent/disabled states, avatars, logos, body form text, poster cards and the accepted Details hero cutout/85%/72%/12%. Settings/About body content stays unchanged; their shared glass header buttons now participate like all other glass buttons. `docs/BACKDROP_FOREGROUND.md` is the current scope/checklist. CI tests both appearance policies and renders foreground pixel samples.

- **Moments right-rail exception**: The user rejected the solid/tinted white foreground added to the heart/comment/share/scale custom glass shapes. Keep their original `Color.white.opacity(0.001)` fills and no `.glassForeground()` on these four shapes; liked heart retains red at 0.92. Preserve the rest of app-wide foreground blending, rail captions/counts, avatars, glass geometry and callbacks.
- **User Personalization Settings** (`@AppStorage`, Settings screen):
  - `appTheme` (system/light/dark), `posterQuality` (high/low), `showOriginalTitle`, `autoAdvanceBackdrops`.
  - Catalog appearance: `cardStyle` (classic poster / overlay info), `cardDensity` (regular/compact grid).
  - Interface: `tabBarShowsLabels`, `tabBarMinimizeOnScroll`.
  - Playback: `preferredStreamSource`, `preferredVideoQuality` (ask/auto/1080p/720p/480p/360p), `autoplayNextEpisode`, `playerVolumeBrightnessGestures`, subtitle font size (`SubtitleSettings`: 18/24/30pt).
- **Subtitles Typography & Motion (Apple TV / Native AVKit Style)**:
  - Subtitle styling in `SubtitleOverlayView.swift` strictly follows native Apple TV / AVKit captions: clean standard typography (`design: .default`, `weight: .medium`) with each line individually wrapped in a rounded dark translucent plate (`Color.black.opacity(0.72)`, `cornerRadius: 5`).
  - Dynamically adjustable font sizing via `SubtitleSettings.shared`: Small (18pt), Medium (24pt), Large (30pt), directly selectable from the player's subtitle menu in `BottomRowView.swift`.
  - Responsive positioning: automatically animates smoothly upwards (+68pt) above player controls and drops down above the Home indicator when controls fade out. Passive touch handling (`allowsHitTesting(false)`).
  - Native AVPlayer suppression: `AVPlayerItemLegibleOutput` has `suppressesPlayerRendering = true` to prevent double rendering while synchronizing cues.

---

## Backend Architecture (`sloosh-api` & Edge Proxy)

- **Active Gateway**: `https://api.sloosh.workers.dev` (Cloudflare Worker proxy with Edge caching).
- **Backend Origin**: `https://api-sloosh.vercel.app` (TypeScript, Hono web framework, Vercel Edge Runtime).
- **Primary Data Provider**: The Movie Database (TMDB) v3 API with rich extensions.
- **Streaming Source Providers**: Alloha API (primary, dynamic token pool) and Collaps (backup source, resolved on demand).

### Key Capabilities:
1. **Cloudflare Edge Gateway & Direct TMDB Image CDN**:
   - `api.sloosh.workers.dev` intercepts `/api/v1/images/tmdb/:size/*` and proxies directly from `image.tmdb.org` with 30-day Edge Caching (`cacheTtl: 2592000`, `max-age=31536000, immutable`, `X-Sloosh-Edge: tmdb-direct`). Bypasses Vercel entirely for images, cutting poster latency to 5–15 ms.
   - Global Edge Cache API (`caches.default`) for API GET responses (`X-Sloosh-Cache: HIT-EDGE`), returning catalog and details in 5–15 ms without origin round-trips.
   - Automatic origin retry (400ms delay) on transient Vercel 502/503/504 errors, providing zero-downtime resilience.
   - Sanitized `Vary: Accept-Encoding` header (removed `Authorization` and `X-API-Key`), unlocking unified global CDN caching across all authorized clients.
2. **Alloha Stream & ID Resolution Optimization**:
   - In-memory LRU resolution caches (`allohaResolutionCache`, `kpToTmdbCache`) with 24-hour positive and 2-hour negative TTL.
   - Reduced query timeout to 2500ms and wrapped `attachAllohaAndIds` in a fast 2500ms `Promise.race` timeout guard. Movie detail screens never hang if Alloha has connectivity issues.
3. **TMDB Subrequest Memoization (`tmdbFetchCached`)**:
   - Movie collections (Marvel, Harry Potter, etc.) cached for 24 hours.
   - Fallback discover queries for similar items cached for 6 hours.
4. **Russian Localization Engine**:
   - Automated country name translation via `src/utils/countries.ts` (`localizeCountry`, `CountryLocalizer`).
   - Russian genre mapping and bi-directional resolution for TMDB Discover.
   - Cleaned person biographies: emojis stripped, automatically parsed into awards, key projects, and interesting facts.
5. **Smart Fallback for Similar Media**:
   - `/movies/:id` and `/tv/:id` deduplicate recommendations and similar items. If count < 6, automatically falls back to Discover query for top titles in the same primary genre. 100% of titles have similar media.
6. **Crew & Creator Parsing (`extractCrew`)**:
   - Extracts directors (`Director`), writers (`Writing`, `Screenplay`, `Writer`, `Story`, `Author`, `Novel`), and series creators (`created_by`).
   - Deduplicates members with unified compound roles (e.g. `"Режиссёр, сценарист"`, `"Создатель, сценарист"`).
   - In `/person/:id`, filmography merges both `combined_credits.cast` AND `combined_credits.crew`, guaranteeing that directors and writers have complete filmographies.
7. **Media Artwork Overrides**:
   - `GET/POST/DELETE /api/v1/media-overrides` plus Firebase `media_stats/media_artwork_overrides` allow curators/admins to replace posters, logos, and backdrops for specific titles (e.g. missing regional artwork) with zero app updates.

---

## iOS App Architecture (`sloosh-iOS`)

Root: `sloosh-iOS/sloosh/Sources/`. Project is generated by **XcodeGen** (`project.yml`, target `com.sloosh.ios`, deployment target iOS 26.0, iPhone-only, URL schemes `sloosh://` + Google Sign-In reverse-client-id).

### 1. Application Layer (`App/`)
- `slooshApp.swift`: App entry point, startup prewarming (`MoviesApi.loadRemoteConfig`, `SharedWebViewProvider.prewarm`, `AllohaRepository.warmup`, `PlaybackAnalyticsService.sendSessionHeartbeat`, `MediaOverridesRepository.fetchOverrides`), orientation lock control (portrait / forced landscape for player), audio session configuration, `URLCache` tuning (50 MB memory / 200 MB disk), TipKit configuration, crash-log alert, deep link handling (`DeepLinkManager`), and scene-phase lifecycle (presence heartbeat, cloud sync push, config refresh).
- `AppDiagnostics.swift`: Crash logging (with "share logs" alert and Settings diagnostics section), system event diagnostics, and performance metrics.
- `SlooshIntents.swift`: Siri Shortcuts and AppIntents (`PlayMovieIntent`, `ContinueWatchingIntent`).

### 2. Data & Network Layer (`Data/`)
- `Models/`:
  - `Models.swift`: TMDB/Alloha DTOs, category models, collections, cast/crew models, preference enums (`VideoQualityPreference`, `MediaStreamSource`, `CardStyle`, `CardDensity`, `PosterQuality`, `AppTheme`). Dynamic image URLs resolve via `MoviesApi.activeImagesBaseURL`.
  - `Schema.swift` & `AppDatabase.swift`: SwiftData schema for persistent watch progress and favorites.
  - `UserProfile.swift`: User profile DTO for cloud account synchronization.
  - `MessengerModels.swift`: Channels, posts, reactions, comments, and direct chat models.
  - `MovieClip.swift`: Clip («момент») model — media binding (`mediaId`, `kpId`, `tmdbId`, season/episode, translation), timecode range (`startTime`/`endTime`), author, counters (likes/comments/views), and formatting helpers.
  - `MediaArtworkOverride.swift`: Curated poster/logo/backdrop override models and image DTOs.
  - `MediaComment.swift`: Movie/series comment model (`media_comments/{mediaKey}/{id}`) — author snapshot, spoiler flag, `likedBy` map (likes are stored on the comment node, so counters can't drift), sort enum and limits, plus `MediaDetailsDto.commentsMediaKey` (`kp_…` → `tmdb_…` → internal id).
  - `CollapsModels.swift`: DTOs for the backup streaming source.
  - `PlaybackSubtitle.swift`: Subtitle models and parsing.
- `Network/`:
  - `AppSecrets.swift`: Injected API credentials (`apiKey`).
  - `MoviesApi.swift`: Dynamic async/await client with remote `endpoint.json` config resolution, failover, `X-API-Key` headers, retry logic, stream config polling, and media-override endpoints (`getMediaOverrides`, `saveMediaOverride`, `deleteMediaOverride`).
  - `NetworkMonitor.swift`: Real-time network reachability (Wi-Fi, Cellular, Offline).
- `Repositories/`:
  - `MoviesRepository.swift`: In-memory and disk caches (`MediaDetailsDiskCache` v7, `PersonDetailsDiskCache` v1, `ListDiskCache`).
  - `AllohaRepository.swift`: Dynamic multi-token manager, request deduplication, priority failover, and cooldown.
  - `AllohaRuntimeResolver.swift` & `AllohaRuntimeParser.swift`: Headless WebKit resolver for encrypted Alloha iframes, stream and subtitle extraction (`<track>`, `Playerjs` ctor hook, VTT/SRT scraping, `SharedWebViewProvider` prewarmed at startup).
  - `CollapsRepository.swift` & `CollapsParser.swift`: Backup streaming source — playlist parsing, 5-minute result cache, kinokrad referer/origin stream headers.
  - `WebVTTParser.swift`: High-performance parser for external WebVTT subtitle files and real-time cue lookup.
  - `HlsProxyServer.swift`: Local HTTP proxy for HLS playback with custom headers.
  - `PlaybackHlsRewriter.swift`: Master-playlist rewriter — exposes dubs/voiceovers as native audio tracks, injects external WebVTT subtitles (optionally stripping embedded ones), normalizes resolution labels (1080p/720p/480p/360p), injects missing `RESOLUTION=` tags, and strictly filters to the target quality.
  - `PlaybackProgressStore.swift`: Watch history, duration, and progress store with SwiftData and cloud sync.
  - `FavoritesRepository.swift`: Favorites store with SwiftData and cloud sync.
  - `CloudSyncService.swift`: Two-way cloud sync with Firebase Realtime Database for favorites, progress, and metadata.
  - `AuthRepository.swift`: Email/password authentication, Google Sign-In, and user profile management via Firebase REST API. Includes server-verified admin detection (`isAdmin` via `/admins/{uid}`) and user ban flags.
  - `GoogleOAuthService.swift`: ASWebAuthenticationSession PKCE exchange for Google Sign-In.
  - `MessengerRepository.swift`: Telegram-style broadcast channels, posts, movie attachments, comments, and direct chats with realtime updates (largest module, ~2.6k lines).
  - `ClipsRepository.swift`: «Моменты» feed over Firebase RTDB — resilient per-item feed decoding (a broken or resurrected-shard node can never poison the whole feed; counter-only shards are auto-purged from the database), counter writes guarded by clip existence so deleted clips cannot be resurrected by late likes/views, clip deletion also purges likes/views/comments subtrees, feed fetch + disk cache, recommendation ranking (blends favorites, watch progress, freshness, and counter penalties), publishing, likes, views, comments, and per-author clip listings. Moment playback offers only qualities ≤1080p (higher tiers from the balancer come in a codec iPhones cannot decode).
  - `ClipStreamResolver.swift`: Clip playback resolution — primary source via Alloha dynamic catalog (`kpId`/`tmdbId`/`title`, season/episode/translation matching, saved iframe fallback, runtime iframe resolution) and backup source via Collaps; TTL result cache.
  - `PlaybackAnalyticsService.swift`: Live watching sessions and session heartbeats to Firebase (`media_stats`, `global_stats`) — powers «Смотрят сейчас» on Home and the admin dashboard.
  - `UserPresenceService.swift`: Real-time online/offline presence tracking with heartbeats.
  - `MediaOverridesRepository.swift`: Realtime streaming of curated artwork overrides (Firebase + `endpoint.json` emergency path), UserDefaults cache, 30s heartbeat, and `mediaArtworkOverridesDidChange` notifications consumed by `AsyncCachedImage`.
  - `MediaCommentsRepository.swift`: Comments for movies/series over Firebase RTDB (`media_comments`, `media_comment_reports`, `admins`) — newest-200 page with `orderBy=createdAtMs`, request dedup, memory + disk cache, brief freshness window, optimistic likes stored as `likedBy/{uid}`, author-only delete for users, admin moderation (delete/spoiler/dismiss reports) enforced server-side via `root.child('admins').child(auth.uid).val() == true`, report flow, and a 15s per-title send cooldown.
  - `AdminRepository.swift`: Admin overview stats (users, online/guests, watching-now sessions, channels, posts, views, reactions, top translations, media analytics), user listing/banning, channel deletion.
  - `DownloadManager.swift`: Multi-threaded background HLS/MP4 downloader with pause/resume support.
  - `DownloadManifest.swift` & `JSONDataStore.swift`: Offline download metadata persistence.
  - `AppIconManager.swift`: Runtime app icon switching (`Default`, `Cyrillic`, `Glyph`, `Cinema`).
  - `DeepLinkManager.swift`: URL scheme routing (`sloosh://details/:id`, `sloosh://home`) plus universal links (GitHub Pages / `sloosh.vercel.app` hosts, `movie`/`tv` paths).
  - `CacheManager.swift`: System cache size calculator and purge tool.

### 3. User Interface Layer (`UI/`)
- `Home/`:
  - `ContentView.swift`: Root tab navigation bar with Liquid Glass capsule, scroll auto-hide, unread badges, and avatar-backed profile tab.
  - `HomeView.swift`: Catalog-first home — content-type tabs (Все / Фильмы / Сериалы / Мультфильмы / Аниме) with sorting, «Скоро» upcoming section, live «Смотрят сейчас» section, hero backdrop pager, and sticky category `safeAreaBar` (long-press opens `SearchFilterSheet`).
  - `HomeDirectPlayWrapper.swift`: Instant context-menu direct playback wrapper.
- `Clips/` (tab «Моменты»):
  - `ClipsFeedView.swift`: Full-screen vertical TikTok-style feed with isolated per-clip progress observers, playback coordinator, like/view/comment interactions, and open-in-details deep integration (~2.5k lines).
  - **Strict moment playback lifecycle**: `ClipsFeedView` in the root tab must receive `isSelected: selectedTab == .clips`; modal feeds (`isModal: true`) own a separate visible screen. `ClipPlaybackEligibility` permits playback only while the feed content is visible, selected, the scene is active, no blocking destination/presentation is covering it, and no main movie player holds focus. The partial interactive comments sheet is intentionally non-blocking (`ClipPlaybackCoverage`): keep the same video/player session running above it; opening/closing comments alone must not tear down or restart playback, or override a manual pause. Comments never bypass the selected-tab/visibility/scene/focus gates or another destination. Do not reintroduce global resume notifications. `PlaybackFocus` synchronously revokes the previous moment owner and holds a main-player lock from presentation/loading through audio/proxy teardown. Every asynchronous resolve/KVO/seek completion must validate its `ClipPlaybackSession` generation and current player/item before starting playback; leaving the screen cancels work and detaches the item. User pause intent survives temporary coverage/backgrounding.
  - `ClipCommentsSheetView.swift`: Glass comments sheet for clips.
  - `ClipDownloader.swift`: Offline clip saving — HLS segment download with AES-128 decryption and time-range trimming/remux via AVFoundation export.
- `Details/`:
  - `DetailsView.swift`: Stretchy backdrop carousel, dynamic logo, crew/cast horizontal carousels, similar media, trailers, seasons/episodes selector, dual-source episode resolution (primary + backup fallback).
  - `PremiereCampaignSlot` (`UI/Campaigns/`): data-only remote editorial block replacing the existing unreleased premiere capsule in Details, **never on Home**. Currently scoped only to Avengers: Doomsday (`movie_1003596`). `RemoteCampaignStore` receives independently validated `campaigns` from `endpoint.json`, with 72h offline cache, explicit expiry/kill switch and no changes to playback availability. One initial client update is necessary; later text/date/artwork/target changes require config only. See `docs/REMOTE_CAMPAIGNS.md`; `Tests/run-campaign-tests.sh` runs in macOS CI. Countdown appearance is inline typography only: five columns of bold monospaced digits (calendar months, residual days, hours, minutes, seconds) with aligned colon separators and correctly inflected lowercase Russian units; calculate in Gregorian/UTC (not the event/device zone, which introduces DST hour mismatches, and not fixed 30-day months); the event timeZone is date-display metadata only. No image/background/glass/border/headline/disclaimer. Legacy remote styling fields remain decodable for older clients; this visual redesign requires a new client build, but the existing main config already activates it.
  - `PersonDetailView.swift`: Person hero, structured bio (awards, key projects, facts), categorized filmography.
  - `SourceSelectionView.swift`: Source («Основной»/«Резервный»), voiceover/translation, and in-sheet video quality picker.
  - `MediaCommentsSection.swift` & `MediaCommentsSheetView.swift`: Movie/series comments — teaser section on Details (count, last two, spoiler-aware previews) and a full clips-style glass sheet: custom VariableBlur header with sort menu, 0.65→large detents, spoiler reveal, optimistic likes, copy/profile/report/delete menus, guest sign-in CTA inline in the composer and a 15s cooldown reveal. Neutral white glass styling (no accent color).
  - `QualitySelectionSheet.swift`: Standalone video quality sheet for the global `preferredVideoQuality` preference.
  - `WatchSelectorUI.swift`: Shared glass selection chips with haptics.
  - `TrailerPlayerSheetView.swift`: Floating YouTube trailer player sheet.
  - `GenreCatalogView.swift` & `StudioCatalogView.swift`: Interactive genre and studio catalog navigation.
  - `ShareToFriendSheet.swift`: In-app messenger sharing sheet.
  - `UIImage+AverageColor.swift`: Poster-derived placeholder colors.
- `Player/`:
  - `PlayerHostingController.swift`: Custom landscape `UIHostingController` with locked `overrideUserInterfaceStyle = .dark` and orientation control.
  - `PlayerView.swift`: Fullscreen custom player wrapper. Strict `.environment(\.colorScheme, .dark)` and `.preferredColorScheme(.dark)`, audio track switching with timecode preservation, dual-source stream switching.
  - `PlayerContainerView.swift`: Double-tap seeking, gestures overlay, controls coordinator, clip creation entry point, and dark theme enforcement.
  - `PlayerGesturesOverlay.swift`: Volume/brightness gesture overlay.
  - `SubtitleOverlayView.swift`: Apple TV-style native cinema subtitle rendering with individual rounded translucent dark plates.
  - `SubtitleSettings.swift`: Subtitle appearance and font size state management (`small`, `medium`, `large`).
  - `VideoLayerView.swift`: Hardware-accelerated `AVPlayerLayer` wrapper with `AVPictureInPictureControllerDelegate` and background stashing.
  - `Controls/`: `TopBarView`, `BottomRowView` (audio, quality, subtitle size & track menus), `SeekBarView`, `CenterControlsView`, `PlayerControlsView`, `PlayerGlassModifiers`, and `PlayerClipTrimmerView` — clip creation studio for «Моменты» built on the native Photos/iMovie interaction model: `ClipTrimSession` (single source of truth) opens a ~2-minute scene window around the selection (iMovie-style; pinch zooms continuously out to the full movie) over a filmstrip of real frames scanned from the live player decoder (sequential exact seeks + `AVPlayerItemVideoOutput` — the same pipeline that renders the video, so frames are guaranteed on any playable stream; `AVAssetImageGenerator` is intentionally not used because it silently yields nothing on the proxy-served HLS streams; the playhead is restored after each scan pass); anchored pinch-to-zoom, handle drags with paused-video scrub preview (coarse in motion, exact on release), body-drag selection moving without video jumps, background-drag track panning, pixel-based rubber-band limits (3 s hard minimum, 10 min max + movie edges) with haptic ticks and spring settle, single commit to the view model on gesture end; center tap deterministically plays the selection from its start (seek-then-play, looped while playing).
- `Continue/`:
  - `ContinueView.swift`: «Продолжить просмотр» grid with resume timecodes and batch deletion.
- `Search/`:
  - `SearchView.swift`: Instant debounced search for movies, series, and actors with search history and filter sheets.
  - `SearchFilterSheet.swift`: Multi-select filter sheet for genres, countries, years, and ratings.
- `Profile/`:
  - `ProfileView.swift`: Account management, cloud sync status, favorites shelf, admin dashboard entry (for admins), app settings access.
  - `AuthSheetView.swift` & `AuthView.swift`: Glass modal sheets for email/password and Google Sign-In.
  - `EditProfileSheet.swift`: Avatar picker, display name, and bio editor.
- `Messenger/`:
  - `MessengerView.swift`: Direct chats, pushed from Moments. Keep the native bottom tab bar available on the conversation list (including the guest state); hide it only inside an individual ChatDetailView. Standard SlooshTopBar back chevron returns to Moments; only the working compose action belongs in its trailing slot. No Edit mode, proxy/camera toast placeholders or archived channel controls. NewChatSheet uses the canonical glass sheet header, local cancellable search results, and pushes the selected peer only after dismissal. Deletion remains in the conversation context menu with explicit confirmation (existing delete-for-everyone semantics).
  - `ChannelDetailView.swift`, `ChannelPostRowView.swift` & `ChannelInfoView.swift`: Post feed, movie attachments, reactions, comments, pinned posts (`PinnedPostBar`), and channel info.
  - `ChatDetailView.swift` & `MediaMessageCardView.swift`: Direct chats with rich media message cards.
  - `CreateChannelSheet.swift` & `MovieSelectorSheet.swift`: Channel creation and movie card attachment selector.
- `Downloads/`:
  - `DownloadsView.swift`: Offline downloaded media list, radial download indicator, and local playback.
- `Admin/`:
  - `AdminDashboardView.swift`: Administrative controls — overview stats, live sessions, user management (ban/unban), channel broadcasts and deletion, and a «Жалобы» moderation tab (reported comments with reasons, admin delete, spoiler toggle, dismiss reports).
  - `MediaArtworkPickerSheet.swift`: Curator tool for overriding poster/logo/backdrop artwork of titles.
- `Settings/`:
  - `SettingsView.swift`: Catalog appearance (card style/density), app icon picker, theme, poster quality, playback preferences (stream source, video quality, autoplay, gestures), subtitle size, storage/cache cleaner, log sharing, and about page.
  - `AboutView.swift`: App information, version, and developer details.
- `Shared/`:
  - `AsyncCachedImage.swift`: Dual-tier image caching with automatic TMDB proxy routing through `MoviesApi.activeImagesBaseURL`, artwork-override interception, and legacy-host fallback.
  - `VariableBlurView.swift`: Progressive UIKit-backed gradient blur with a dual-pass iOS 27 look: the base linear-mask variableBlur pass plus a diffusion halo pass (higher radius, feathered ease-out mask, partial alpha, extending beyond the bar bounds) that makes blurred content bloom softly past the edge for an expensive glow; halo intensity/spread/radius-boost are configurable per call site (defaults: intensity 0.65, spread 0.2, radius boost 3; the unchanged mask fades to zero at 68% of the halo frame, so its visible reach is 81.6% of the base blur length, versus 108.8% previously; 0 intensity restores the flat single-pass look); private-filter self-healing (layout/didMoveToWindow hooks, delayed re-application bursts, app-activation observer, a 1 s health timer, and forced heal bursts after color-appearance changes with a full filter reset before re-install) survives UIKit recreating the backdrop layer after nav pops, theme switches, or full-screen player dismissal, fixing flat hard-edged bars.
  - Bottom edges: screens pair the custom top bars with the native iOS 26 scroll edge effect at the bottom edge — `.scrollEdgeEffectStyle(.soft, for: .bottom)` on their scroll roots (Home, Details portrait/landscape, PersonDetail, Downloads, Profile, UserProfileDetail, About, all Admin pages, ClipComments/Quality/Source sheets, ChannelInfo); Settings and SearchFilterSheet use `.for: .all`. The «Моменты» feed (ClipsFeedView) also carries it so full-bleed video dissolves under the tab bar at the bottom edge; the fullscreen Player is the only surface intentionally left without it.
  - `SlooshAvatarView.swift` & `AvatarImageProcessor.swift`: Liquid Glass user avatar with initials fallback, online status indicator, and background avatar processing.
  - `UserProfileDetailView.swift`: Flagship full-screen user profile — bio, presence, direct-chat entry, and the user's published clips grid.
  - `TelegramGlassIconButton.swift`: Consistent circular glass button for navigation and actions.
  - `SlooshTopBar.swift`: Unified custom screen header (centered title, glass back/close, trailing slot, optional bottom row) whose background is VariableBlurView revealed progressively on scroll. Canonical sheet header: `leadingIcon: "xmark"`, clear tint, `topPadding: 8 / bottomPadding: 4 / blurOverflow: -30`, real scroll-offset binding (never `.constant(100)`), trailing icon actions use TelegramGlassIconButton with `.primary` color, and the sheet carries `.presentationDragIndicator(.visible)` + `.presentationBackground { Color.clear.glassEffect(in: .rect) }` + content-appropriate detents. Canonical sheet content insets: horizontal 16 for everything inside a sheet (header, media cards with corner radius 16, text blocks, full-width buttons), top gap 8 under the header, section spacing 16.
  - `LaunchSplashView.swift`: Launch animation with logo reveal.
  - `FullWidthSwipeBack.swift`: Edge-to-edge interactive pop gesture.
  - `ToastManager.swift`: Non-intrusive floating toast notifications.
  - `TooltipView.swift`: Capsule tooltips with tail for onboarding hints.
  - `AppEmptyStateView.swift`: Unified empty-state component.
  - `CardPressButtonStyle.swift`, `MediaHelpers.swift`, `NavigationBarVisibilityHelper.swift`, `RadialDownloadIndicator.swift`, `ShareSheet.swift`, `Color+Theme.swift`, `ShimmerModifier.swift`: Shared styling, helpers, and effects.

---

## Caching Strategy

1. **Cloudflare Edge Gateway & Direct CDN**:
   - Direct TMDB Image proxy cached on Cloudflare Edge for 30 days (`X-Sloosh-Edge: tmdb-direct`, `max-age=31536000, immutable`), completely bypassing Vercel.
   - API GET responses cached via Cloudflare Cache API (`caches.default`) with `X-Sloosh-Cache: HIT-EDGE` (5–15 ms latency).
   - Dynamic endpoints and Edge CDN routing with sub-30ms global response time.
   - `Vary: Accept-Encoding` ensures shared cache hits across all client devices without auth fragmentation.
2. **Vercel Edge & Backend In-Memory Caches**:
   - `allohaResolutionCache` (24h positive / 2h negative TTL) + `kpToTmdbCache`.
   - `tmdbSubrequestCache` for collections (24h) and discover fallbacks (6h).
   - Details, collections, and person profiles cached for up to 24 hours (`s-maxage=86400`).
3. **Local iOS Disk Caches**:
   - `MediaDetailsDiskCache`: Located in `Library/Caches/sloosh.mediadetails.v7` (TTL 24 hours).
   - `PersonDetailsDiskCache`: Located in `Library/Caches/sloosh.persondetails.v1` (TTL 24 hours).
   - `ListDiskCache`: Instant cold starts for popular movies, top movies, top TV series, and cartoons.
   - Clips feed cache: `sloosh_cached_clips_v1` in `UserDefaults` (instant cold-start feed) plus liked/viewed sets (`sloosh_liked_clips_v1`, `sloosh_viewed_clips_v1`).
   - Media artwork overrides cache: `sloosh_media_artwork_overrides` in `UserDefaults`.
4. **Image Caching**:
   - `AsyncCachedImage` + `ImageCache` (memory + disk) with dynamic routing through `MoviesApi.activeImagesBaseURL`, plus a shared `URLCache` (50 MB memory / 200 MB disk) configured at launch.

---

## Distribution & CI/CD Workflow

- **CRITICAL**: The iOS project is **NOT** built locally via Xcode or Simulator.
- Builds, code signing, and distribution are executed **exclusively via GitHub Actions CI** (`.github/workflows/ios.yml`, runner `macos-15`, Xcode 26.0.1, XcodeGen 2.42.0, SwiftLint advisory-only for PRs).
- **Playback regression tests**: CI runs `bash sloosh-iOS/Tests/run-clip-playback-tests.sh` before XcodeGen/build. These standalone macOS Swift tests cover all 32 eligibility combinations, 4096 presentation/lifecycle combinations (including comments), comments session continuity, stale session rejection, and exclusive moment/main-player focus; device scenarios are listed in `sloosh-iOS/Tests/README.md`.
- **Versioning**: CI replaces the placeholder build number `890` with `github.run_number`, so the shipped version reads `<marketing>.<run_number>` (e.g. `2.1.1042`) for both `CFBundleShortVersionString` and `CFBundleVersion`.
- **AltStore / SideStore Distribution**:
  - CI automatically generates `apps.json` with the latest build number, download URL, and metadata.
  - The repository deploys `apps.json` and `endpoint.json` directly via official GitHub Actions Pages (`https://sluvskii.github.io/iOS-sloosh/apps.json`).
  - Builds are unsigned IPAs attached to prerelease tags `build-N` (installable via TrollStore, AltStore, or SideStore).
- **Delivery Protocol**:
  1. Make minimal, focused, verified edits.
  2. Commit and push to the assigned Arena session branch, never switch branches or push directly to `main`.
  3. Monitor the GitHub CI workflow run (`iOS Build`) until tests, build, packaging, and release succeed. A feature branch can fail only the protected GitHub Pages deployment; do not weaken that protection or mistake it for a build failure.
  4. Per the user's standing authorization, open a PR from the session branch and merge into `main` automatically after successful checks, without asking again. If tests/build fail or a material ambiguity remains, report it first and do not merge.
  5. Provide the user with the PR and direct download link for the generated `.ipa`.
  - Note: CI ignores docs-only changes (`AGENTS.md`, `README.md`, `.gitignore`, `database.rules.json`) and will not trigger a build for them.
