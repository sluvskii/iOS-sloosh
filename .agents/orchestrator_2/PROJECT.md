# Project: Playback & Download Voiceover Fidelity & Video Quality

## Architecture
- **API & Domain Layer**:
  - `sloosh-iOS/sloosh/Sources/Data/Repositories/AllohaRepository.swift`: Fetches and parses authentic movie and TV series translations and episodes from `api.alloha.tv`. Preserves raw API translation arrays (`movie.translations`, `epObj.translations`).
- **Resolver & Stream Layer**:
  - `sloosh-iOS/sloosh/Sources/Data/Repositories/AllohaRuntimeResolver.swift`: Headless WKWebView pool for resolving Alloha iframe URLs to direct HLS master playlists and headers.
  - `sloosh-iOS/sloosh/Sources/Data/Repositories/AllohaRuntimeParser.swift`: Parses `/bnsi/` payloads for quality and audio variants.
  - `sloosh-iOS/sloosh/Sources/Data/Repositories/HlsProxyServer.swift` & `PlaybackHlsRewriter.swift`: Local HTTP proxy serving upstream rewritten HLS playlists (stripping AV1) and local offline media `/local/`.
- **UI & Playback Layer**:
  - `sloosh-iOS/sloosh/Sources/UI/Player/PlayerView.swift`: AVPlayer lifecycle, `PlayerViewModel` state management (`availableVoiceovers`, `currentTranslationName`, `switchVoiceover`, `playEpisode`, `applyResolvedAllohaStream`).
  - `sloosh-iOS/sloosh/Sources/UI/Player/Controls/PlayerPickerSheets.swift`: `VoiceoverPickerSheet` and quality selectors.
  - `sloosh-iOS/sloosh/Sources/UI/Details/SourceSelectionView.swift` & `DetailsView.swift`: Source and translation pickers forwarding selection to `PlayerView`.
- **Download Layer**:
  - `sloosh-iOS/sloosh/Sources/Data/Repositories/DownloadManager.swift`: Offline download queue, master playlist parsing (`#EXT-X-STREAM-INF`), quality variant picking, segment downloading, metadata persistence (`key.bin`, `local.m3u8`, `translationName`).

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | Preserve Authentic Movie Translations in API | Removed destructive eager resolution in `AllohaRepository.swift` to retain authentic movie translation lists. | M1 | Survey 2 |
| 2 | Player Voiceover List Preservation | Populated `availableVoiceovers` for both movies and series in `beginLoad`, and protected against runtime overwrite in `applyResolvedAllohaStream` / `syncNativeAudioTracks`. | M1 | ORIGINAL_REQUEST R1 |
| 3 | In-Player Voiceover Switcher Fidelity | Rewrote `switchVoiceover(to:at:)` to look up translation in `AllohaApiResult`, resolve stream, and restore playback at `savedTime`. | M1 | ORIGINAL_REQUEST R1 |
| 4 | Episode Advance & Autoplay Voiceover Continuity | In `playEpisode` & `beginLoad`, synchronized `_currentTranslationName` with playing translation and protected sticky `targetVoiceover` preference across episode navigation. | M2 | ORIGINAL_REQUEST R2 |
| 5 | DownloadManager Direct Translation Stream Usage | In `prepareAndEnqueue`, used `resolved["url"]` directly without erroneous `audioVariants` overrides. | M3 | ORIGINAL_REQUEST R3 |
| 6 | Robust Master Playlist & Quality Variant Parsing | Parsed `#EXT-X-STREAM-INF` resolutions, `BANDWIDTH`, URL filenames (`1080.m3u8`), filtered AV1, and selected highest resolution $\le \text{targetHeight}$ without downgrading. | M3 | ORIGINAL_REQUEST R3 |
| 7 | Offline Download Metadata & Playback Consistency | Verified `local.m3u8`, `key.bin`, `translationName`, and resolution metadata in `DownloadManager` for accurate offline playback. | M3 | ORIGINAL_REQUEST R3 |
| 8 | End-to-End Integration, Verification & Git Push | Comprehensive code review, challenge verification, audit integrity verification, and committed & pushed changes (`49208fb`). | M4 | AGENTS.md |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| 1 | Player Voiceover Preservation & Switching (R1) | `AllohaRepository.swift`, `PlayerView.swift`, `PlayerPickerSheets.swift` | none | DONE |
| 2 | Episode Navigation Voiceover Continuity (R2) | `PlayerView.swift` (playEpisode, beginLoad, preferredTranslation) | M1 | DONE |
| 3 | DownloadManager Quality & Stream Selection (R3) | `DownloadManager.swift` | none | DONE |
| 4 | E2E Integration & Git Push | Full verification (Reviewers, Challengers, Auditor) and git push (`49208fb`) | M1, M2, M3 | DONE |
