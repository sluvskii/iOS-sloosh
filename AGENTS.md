# Agent Onboarding

## Workspace Overview

This workspace contains the two core projects of the `sloosh` ecosystem:

- `sloosh-iOS/`: the active native iOS app under the `sloosh` brand (SwiftUI, iOS 26+).
- `sloosh-backend/`: the dedicated backend API server deployed to Vercel (`https://api-sloosh.vercel.app`), built with TypeScript, Hono, and Vercel Edge Runtime.

> [!NOTE]
> The app is completely independent. We have fully transitioned away from the legacy `neomovies` API and codebase. We do NOT use `neomovies` or rely on it in any form. Our own backend (`sloosh-backend`) provides a significantly faster, more reliable, and feature-rich API specifically tailored for `sloosh`.

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

## UI / Design Guidelines (iOS 26+)

- **Liquid Glass Everywhere**: The app is a premium edge-to-edge application. All floating elements, navigation capsules, cards, and modal sheets must use `.glassEffect()`.
- **CRITICAL FORBIDDEN API**: The use of `.ultraThinMaterial` is **STRICTLY FORBIDDEN** throughout the entire codebase.
- **Native iOS Patterns**:
  - Top floating components (category tabs, sticky bars) use `.safeAreaBar(edge: .top)` or `.safeAreaInset(edge: .top)`.
  - Let the system handle Liquid Glass blur and morphing automatically during scroll. Do not add redundant opaque backgrounds or dark overlays.
  - Floating pills, action buttons, and sheet backgrounds use `.glassEffect(in:)` with `.capsule` or `.rect(cornerRadius:)`.
  - Floating navigation tab bar uses `.tabBarMinimizeBehavior(.onScrollDown)` for auto-hide on scroll (set in `ContentView`).
  - Native zoom transitions: use `.navigationTransition(.zoom(sourceID:in:))` and `.matchedTransitionSource(id:in:)` for seamless card-to-detail and avatar-to-person transitions.
  - Top and bottom insets: respect natural safe areas via `.safeAreaInset` without manually stacking artificial window padding.

---

## Backend Architecture (`sloosh-backend`)

The backend is located in `sloosh-backend/` and deployed to Vercel:
- **Base URL**: `https://api-sloosh.vercel.app`
- **Tech Stack**: TypeScript, Hono web framework, Vercel Edge Runtime.
- **Primary Data Provider**: The Movie Database (TMDB) v3 API with rich extensions.
- **Streaming Source Provider**: Alloha API.

### Key Capabilities:
1. **Edge CDN Caching**:
   - Automated `Cache-Control` response headers with `stale-while-revalidate` caching on Vercel's global Edge network.
   - Details, collections, and person profiles cached for up to 24 hours (`s-maxage=86400`), cutting response latencies to 15–30 ms.
2. **Streaming Image Proxy for TMDB**:
   - `/api/v1/images/tmdb/:size/*` streams images from TMDB with proper mobile headers to bypass ISP blocks in Russia (`image.tmdb.org`).
3. **Russian Localization Engine**:
   - Automated country name translation via `src/utils/countries.ts` (`localizeCountry`, `CountryLocalizer`).
   - Russian genre mapping and bi-directional resolution for TMDB Discover.
   - Cleaned person biographies: emojis stripped, automatically parsed into awards, key projects, and interesting facts.
4. **Smart Fallback for Similar Media**:
   - `/movies/:id` and `/tv/:id` deduplicate recommendations and similar items. If count < 6, automatically falls back to Discover query for top titles in the same primary genre. 100% of titles have similar media.
5. **Crew & Creator Parsing (`extractCrew`)**:
   - Extracts directors (`Director`), writers (`Writing`, `Screenplay`, `Writer`, `Story`, `Author`, `Novel`), and series creators (`created_by`).
   - Deduplicates members with unified compound roles (e.g. `"Режиссёр, сценарист"`, `"Создатель, сценарист"`).
   - In `/person/:id`, filmography merges both `combined_credits.cast` AND `combined_credits.crew`, guaranteeing that directors and writers have complete filmographies.

---

## iOS App Architecture (`sloosh-iOS`)

Root: `sloosh-iOS/sloosh/Sources/`

- `App/`: App entry (`slooshApp.swift`), audio session setup, crash diagnostics (`AppDiagnostics.swift`).
- `Data/Models/`: Models, DTOs (`Models.swift`), SwiftData schema (`Schema.swift`), image URL normalization.
- `Data/Network/`: Network client (`MoviesApi.swift`) targeting `https://api-sloosh.vercel.app`.
- `Data/Repositories/`:
  - `MoviesRepository.swift`: Page cache, search, details caching (`MediaDetailsDiskCache` v7, `PersonDetailsDiskCache` v1, `ListDiskCache`).
  - `AllohaRepository.swift` & `AllohaRuntimeResolver.swift`: Headless WKWebView-based Alloha iframe resolver + stream extractor.
  - `HlsProxyServer.swift`: Local HTTP proxy for HLS streams requiring custom headers/tokens.
  - `PlaybackProgressStore.swift`: Watch history, duration, and progress via SwiftData.
  - `FavoritesRepository.swift`: User favorites management in SwiftData.
  - `DownloadManager.swift`: Background HLS & MP4 downloader with resume support.
  - `MessengerRepository.swift`: Telegram-style channels, posts, and real-time chat sync.
- `UI/`:
  - `Home/`: `ContentView.swift` (root tab view), `HomeView.swift` (horizontal category carousels, cartoons, safeAreaBar).
  - `Search/`: `SearchView.swift` (debounced search, history, paginated media and person results).
  - `Details/`:
    - `DetailsView.swift`: Stretchy backdrop, dynamic logo, primary metadata, inline seasons/episodes for TV, franchise collections, similar media, trailers.
    - `CrewSection`: Horizontal carousel of creators (directors, writers, creators) with roles and zoom transition placed below `ActorsSection`.
    - `ActorsSection`: Horizontal carousel of cast members with zoom transition.
    - `SourceSelectionView.swift`: Translation, voiceover, and quality picker.
    - `TrailerPlayerSheetView.swift`: Embedded YouTube trailer player with PiP and external deep-link.
    - `PersonDetailView.swift`: Hero header, structured bio (awards, projects, facts), filmography with tabs ("Все", "Фильмы", "Сериалы").
    - `PersonPhotoGalleryView`: Native 120Hz ProMotion UIKit photo gallery with pinch-to-zoom, double-tap zoom, swipe-to-dismiss, and camera roll export (`PHPhotoLibrary`).
    - `GenreCatalogView.swift` & `StudioCatalogView.swift`: Interactive category catalogs.
  - `Player/`: `PlayerView.swift` (custom AVPlayerViewController integration, subtitle selection, audio tracks).
  - `Continue/`: `ContinueView.swift` ("Продолжить просмотр" shelf with resume playback).
  - `Profile/`: `ProfileView.swift` (favorites tab, history, settings button).
  - `Downloads/`: `DownloadsView.swift` (downloaded media list, offline playback, radial progress).
  - `Messenger/`: Telegram-style broadcast channels, post feed, movie attachments, emoji reactions.
  - `Settings/`: `SettingsView.swift` (video quality preferences, autoplay, tab labels).

---

## Caching Strategy

1. **Edge CDN (Vercel)**:
   - Movie/TV/Person details: 24-hour cache on Edge with instant response time.
2. **Local iOS Disk Caches**:
   - `MediaDetailsDiskCache`: Located in `Library/Caches/sloosh.mediadetails.v7` (TTL 24 hours). Automatically purges older cache versions (`v3`–`v6`).
   - `PersonDetailsDiskCache`: Located in `Library/Caches/sloosh.persondetails.v1` (TTL 24 hours).
   - `ListDiskCache`: Instant cold starts for popular movies, top movies, top TV series, and cartoons.
3. **Image Caching**:
   - `AsyncCachedImage` + `ImageCache` (memory + disk) with automatic re-routing of TMDB image URLs through the Edge proxy.

---

## Development & Deployment Workflow

- **CRITICAL**: The project is **NOT** built locally via Xcode or Simulator.
- Builds, code signing, and distribution are executed **exclusively via GitHub Actions CI**.
- **Delivery Protocol**:
  1. Make minimal, focused, verified edits.
  2. Verify TypeScript with `bun x tsc --noEmit` if backend files were changed.
  3. Commit changes and push directly to `main`:
     ```powershell
     $env:HTTPS_PROXY = $null; git add . ; git commit -m "..."; git push origin main
     ```
  4. Monitor the GitHub CI workflow run (`iOS Build`) until completion.
  5. Provide the user with the release tag and direct download link for the generated `.ipa`.
