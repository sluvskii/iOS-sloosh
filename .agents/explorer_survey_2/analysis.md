# Detailed Investigation Report: Resolver, Parser, and Stream Handling Layer

## 1. Executive Summary

This investigation explores the playback resolution, HLS parsing, proxy streaming, and download subsystem in `sloosh-iOS` (`sloosh-iOS/sloosh/Sources/`). The system relies on Alloha as its primary streaming provider, utilizing a layered architecture:
- **API Layer**: `AllohaRepository.swift` queries `https://api.alloha.tv/?token=...&kp=...` for authentic catalog metadata (titles, seasons, episodes, and studio translation voiceovers with distinct `iframeUrl`s).
- **Runtime Resolver**: `AllohaRuntimeResolver.swift` embeds the target iframe in a pooled `WKWebView` (`SharedWebViewProvider`), injecting JavaScript hooks to intercept XHR/fetch `/bnsi/` responses and WebSocket `config_update` events (`edge_hash`).
- **Runtime Parser**: `AllohaRuntimeParser.swift` parses the `/bnsi/` `hlsSource` JSON into playable stream URLs, `audioVariants`, `qualityVariants`, skip ranges, and subtitles.
- **HLS Proxy Server**: `HlsProxyServer.swift` runs a local HTTP proxy on `127.0.0.1:8181` using `Network.framework` (`NWListener`), attaching captured authentication headers, filtering incompatible codecs (AV1, HDR on H.264), and rewriting master playlists via `PlaybackHlsRewriter.swift`.
- **Playback & Download Consumers**: `PlayerView.swift` / `PlayerViewModel` consume resolved streams for online playback; `DownloadManager.swift` consumes them to download HLS media playlists, segments, and encryption keys for offline playback.

The investigation pinpointed critical root causes for voiceover loss, stream mismatch, and quality selection discrepancies across `PlayerView`, `AllohaRepository`, and `DownloadManager`.

---

## 2. Component Inspection & Architecture

### 2.1 AllohaRuntimeResolver (`Data/Repositories/AllohaRuntimeResolver.swift`)
- **Mechanism**:
  - Employs `SharedWebViewProvider` to maintain a prewarmed, non-terminated `WKWebView`.
  - Wraps the given `iframeUrl` in a minimal HTML container (`wrapperHTML`) with full permissions (`autoplay; fullscreen; encrypted-media`).
  - Injects `bootstrapScript` via `WKUserScript` (at `.atDocumentEnd` in all frames).
  - The script hooks `XMLHttpRequest.prototype.open`, `XMLHttpRequest.prototype.setRequestHeader`, `fetch`, and `WebSocket.prototype.send`.
  - Captures:
    1. HTTP headers: `origin`, `referer`, `user-agent`, `authorizations`, `authorization`, and `accepts-controls` (from WS `config_update`).
    2. Stream payloads: `/bnsi/` responses, any JSON containing `hlsSource`, and direct `master.m3u8` URLs.
  - Passes data to Swift via `window.webkit.messageHandlers.allohaResolver.postMessage`.
  - Evaluates payloads using `AllohaRuntimeParser.parsePayload`.
  - Caches resolved results in `iframeCache` with a 20-second TTL.
  - Supports cache invalidation via `AllohaRuntimeResolver.invalidateCache(for:)`.

### 2.2 AllohaRuntimeParser (`Data/Repositories/AllohaRuntimeParser.swift`)
- **Payload Parsing**:
  - Scans for `hlsSource` JSON array (`parseAllohaBNsiStream`).
  - Formats:
    - `hlsSource: [{"quality": {"1080": "url1 or url2", "720": "..."}}]`
  - Parses quality labels ("1080", "720", etc.) and splits CDN failover mirrors (`" or "`).
  - Constructs:
    - `"videoURL"`: Highest priority master or adaptive stream URL.
    - `"audioVariants"`: Extracted per `source` entry with title heuristics (`translation`, `translator`, `studio`, `voice`, `dub`, etc., fallback `Озвучка N`).
    - `"qualityVariants"`: Array of `[label, url, bandwidth, resolution]`.
    - `"subtitles"`: Subtitles parsed from payload (`.vtt`, `.srt`).
    - `"introRange"` & `"outroRange"`: Skip timecodes extracted from `skipTime`, `skips`, `intro`/`outro`, or `timecodes`.

### 2.3 HlsProxyServer & PlaybackHlsRewriter (`Data/Repositories/HlsProxyServer.swift`, `PlaybackHlsRewriter.swift`)
- **Proxy Server (`HlsProxyServer.swift`)**:
  - Listens on `127.0.0.1:8181`.
  - Endpoints:
    - `/master.m3u8`: Fetches current master playlist and passes it through `PlaybackHlsRewriter`.
    - `/proxy/stream.<ext>?url=<base64>`: Proxies playlist variants and `.ts` media segments with captured headers (`authorizations`, `accepts-controls`, `Referer`, `Origin`, `User-Agent`).
    - `/local/<relative_path>`: Serves offline downloaded `.m3u8`, `.ts`, and `key.bin` files.
- **Rewriter (`PlaybackHlsRewriter.swift`)**:
  - Filters out AV1 codec streams (`av01.*`, `av1`) and excessive resolutions (> 1080p).
  - Strips unsupported HDR transfer functions (`VIDEO-RANGE=PQ`, `VIDEO-RANGE=HLG`) from non-HEVC streams to prevent AVPlayer crash `-11848`.
  - Injects subtitle tracks into `#EXT-X-MEDIA:TYPE=SUBTITLES`.
  - Rewrites audio tracks in `#EXT-X-MEDIA:TYPE=AUDIO` matching `voices` input.

### 2.4 Data Models (`Data/Repositories/AllohaRepository.swift`, `Data/Models/`)
| Model | Fields | Purpose |
|---|---|---|
| `AllohaTranslation` | `id: String`, `name: String`, `iframeUrl: String`, `streamUrl: String?` | Represents a single voiceover/translation option with authentic API metadata and iframe URL |
| `AllohaEpisode` | `season: Int`, `episode: Int`, `translations: [AllohaTranslation]` | Represents a TV show episode with all available studio translations |
| `AllohaSeason` | `season: Int`, `episodes: [AllohaEpisode]` | Represents a TV show season containing episodes |
| `AllohaMovie` | `title: String`, `iframeUrl: String`, `translations: [AllohaTranslation]` | Represents a movie with all available translations |
| `AllohaApiResult` | `title: String`, `isSerial: Bool`, `movie: AllohaMovie?`, `seasons: [AllohaSeason]` | Root catalog result from `api.alloha.tv` |
| `PlaybackSubtitle` | `id: UUID`, `url: String`, `label: String`, `lang: String` | Subtitle track model |
| `DownloadItem` | `id`, `kpId`, `title`, `season`, `episode`, `translationName`, `iframeUrl`, `status`, `progress`, etc. | Download task record persisted in `downloads.json` |
| `DownloadManifest` | `itemId`, `segmentUrls: [URL]`, `headers`, `keyUrl`, `localDirectory` | HLS download manifest for offline playback reconstruction |

---

## 3. Root Cause Analysis: Voiceover & Quality Discrepancies

### Issue 1: `applyResolvedAllohaStream` Overwriting `availableVoiceovers`
- **Location**: `sloosh-iOS/sloosh/Sources/UI/Player/PlayerView.swift:1856-1859`
- **Observation**:
  ```swift
  self.resolvedAudioVariants = audioVariants
  let voices = resolvedVoiceovers(from: resolved)
  if !voices.isEmpty {
      self.availableVoiceovers = voices
  }
  ```
- **Analysis**:
  When `PlayerView` loads, `availableVoiceovers` is initially populated with authentic translations from `seriesResult` (e.g., `["Дублированный (Red Head Sound)", "LostFilm", "HDRezka"]`). However, when `AllohaRuntimeResolver` finishes resolving the stream, `applyResolvedAllohaStream` replaces `self.availableVoiceovers` with `voices` extracted from `resolved["audioVariants"]`.
  Because `audioVariants` only contains internal tracks for that single resolved iframe (often generic strings like `["Russian 1"]`), this wipes out the real list of available voiceovers in the UI (`VoiceoverPickerSheet`).

### Issue 2: `AllohaRepository.fetchByKpId` Mutating Movie Translations
- **Location**: `sloosh-iOS/sloosh/Sources/Data/Repositories/AllohaRepository.swift:383-410`
- **Observation**:
  ```swift
  if let m = result.movie, let firstIframe = m.translations.first?.iframeUrl {
      let resolver = await AllohaRuntimeResolver()
      if let resolved = try? await resolver.resolve(iframeUrl: firstIframe),
         let audioVariants = resolved["audioVariants"] as? [[String: Any]], !audioVariants.isEmpty {
          let newTranslations = audioVariants.enumerated().compactMap { index, variant -> AllohaTranslation? in
              ...
              return AllohaTranslation(id: vTitle, name: cleanTitle, iframeUrl: m.iframeUrl, streamUrl: nil)
          }
          if !newTranslations.isEmpty {
              let newMovie = AllohaMovie(title: m.title, iframeUrl: m.iframeUrl, translations: newTranslations)
              result = AllohaApiResult(title: result.title, isSerial: false, movie: newMovie, seasons: [])
          }
      }
  }
  ```
- **Analysis**:
  When fetching movie catalog data, `AllohaRepository` was proactively resolving the first translation's iframe and overwriting the authentic `movie.translations` list (parsed from the Alloha API) with `audioVariants` from the resolver. This corrupted the catalog at the data layer before it even reached the UI.

### Issue 3: Missing Movie Translation Population in `PlayerViewModel.beginLoad`
- **Location**: `sloosh-iOS/sloosh/Sources/UI/Player/PlayerView.swift:397-405`
- **Observation**:
  ```swift
  if let seriesResult = self.seriesResult, let s = season, let e = episode {
      if let seasonObj = seriesResult.seasons.first(where: { $0.season == s }),
         let epObj = seasonObj.episodes.first(where: { $0.episode == e }) {
          self.availableVoiceovers = epObj.translations.map { $0.name }
      }
  } else if !voices.isEmpty {
      self.availableVoiceovers = voices
  }
  ```
- **Analysis**:
  For movies (`season == nil`, `episode == nil`), `beginLoad` only populated `availableVoiceovers` if `voices` was non-empty. It failed to check `self.seriesResult?.movie?.translations`, leaving `availableVoiceovers` empty or prone to being overwritten.

### Issue 4: `DownloadManager` Stream URL Override from `audioVariants`
- **Location**: `sloosh-iOS/sloosh/Sources/Data/Repositories/DownloadManager.swift:326-332`
- **Observation**:
  ```swift
  if let targetVoice = item.translationName, !targetVoice.isEmpty {
      let exactMatch = audioVariants.first(where: { allohaTranslationNamesMatch($0["title"] as? String, targetVoice, exactOnly: true) })
      let match = exactMatch ?? audioVariants.first(where: { allohaTranslationNamesMatch($0["title"] as? String, targetVoice, exactOnly: false) })
      if let validMatch = match, let matchedUrl = validMatch["url"] as? String, !matchedUrl.isEmpty {
          streamUrlString = matchedUrl.trimmingCharacters(in: .whitespacesAndNewlines)
      }
  }
  ```
- **Analysis**:
  `item.iframeUrl` already has the selected `translation` ID injected (e.g. `?translation=418`). The resolver's primary `resolved["url"]` is already the exact master playlist for that translation. Overriding `streamUrlString` by fuzzy-matching against internal `audioVariants` caused wrong audio tracks or streams to be downloaded.

### Issue 5: Sub-optimal Quality Selection & Master Playlist Parsing in `DownloadManager`
- **Location**: `sloosh-iOS/sloosh/Sources/Data/Repositories/DownloadManager.swift:659-701`
- **Observation**:
  - `currentBandwidth` is never extracted (the regex for `BANDWIDTH=` is not evaluated, leaving bandwidth = 0).
  - Master playlist variants lacking `RESOLUTION=` (e.g., variant playlists identified by filename like `1080.m3u8` or `index_1080.m3u8`) defaulted to `height = 0`.
  - The sorting algorithm `diffA = abs(a.height - targetHeight)` did not guarantee choosing the highest matching resolution up to `targetHeight` without downgrading.

---

## 4. Interaction Flow Tracing

### 4.1 Online Playback Flow
1. **User Selection**: User selects title, season, episode, and voiceover (e.g. "Дублированный (Red Head Sound)") in `SourceSelectionView`.
2. **Sheet Action**: `SourceSelectionView.finishAction` passes `AllohaTranslation`, `season`, `episode`, and `quality` to `DetailsView`.
3. **Player Presentation**: `DetailsView` presents `PlayerView` with `iframeUrl: translation.iframeUrl`, `kpId`, `season`, `episode`, `selectedVoiceover: translation.name`, `voices: result.allTranslationNames`, `seriesResult: result`.
4. **Player Initialization**: `PlayerViewModel.beginLoad` initializes state and preserves authentic translation names in `availableVoiceovers`.
5. **Runtime Resolution**: `AllohaRuntimeResolver.resolve` loads `translation.iframeUrl` in `WKWebView`. Injected scripts intercept `/bnsi/` payload and WS `accepts-controls` hash.
6. **Stream Application**: `applyResolvedAllohaStream` extracts `resolved["url"]`, `headers`, skip timecodes, and subtitles. It starts `HlsProxyServer` with captured headers and plays `http://127.0.0.1:8181/proxy/...` via `AVPlayer`.
7. **Voiceover Switching**: When user selects a different voiceover in `VoiceoverPickerSheet`:
   - `switchVoiceover` looks up the translation in `seriesResult.seasons[...].episodes[...].translations` or `seriesResult.movie.translations`.
   - Invalidates cache via `AllohaRuntimeResolver.invalidateCache(for: translation.iframeUrl)`.
   - Calls `beginLoad(iframeUrl: translation.iframeUrl, selectedVoiceover: translation.name)` while preserving current playback position (`currentTime`).
8. **Episode Advancement**: On episode completion or next episode button:
   - `nextEpisodeCandidate()` calls `preferredTranslation(in: nextEpisode)` to match the user's active voiceover.
   - Transitions to the new episode while maintaining voiceover preference and updating `_currentTranslationName`.

### 4.2 Offline Download Flow
1. **Download Trigger**: User taps download on a movie/episode with chosen voiceover and quality in `SourceSelectionView`.
2. **Download Enqueue**: `DownloadManager.startDownload` creates a `DownloadItem` with `translation.name` and `translation.iframeUrl`.
3. **Resolution**: `DownloadManager.prepareAndEnqueue` calls `AllohaRuntimeResolver().resolve(iframeUrl: item.iframeUrl)`.
4. **Stream Selection**: Uses `resolved["url"]` directly without overriding from `audioVariants`.
5. **Master Playlist Parsing**: `chooseMediaPlaylistUrl` downloads the master playlist and selects the optimal media playlist variant matching the requested quality (1080p, 720p, etc.).
6. **Segment Download**: Downloads segments (`segment_N.ts`) and encryption key (`key.bin`), creating `local.m3u8` and `manifest.json`.
7. **Offline Playback**: In `PlayerView`, local playback loads `http://127.0.0.1:8181/local/...` with exact downloaded audio and video streams.
