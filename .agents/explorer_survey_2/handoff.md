# Handoff Report: Resolver, Parser, and Stream Handling Layer

## 1. Observation

### 1.1 Codebase Structure and File Locations
The playback resolution and stream handling subsystem consists of the following components:
- **API Models & Client**:
  - `sloosh-iOS/sloosh/Sources/Data/Repositories/AllohaRepository.swift`
    - Defines `AllohaTranslation` (lines 3-10), `AllohaEpisode` (lines 12-16), `AllohaSeason` (lines 18-21), `AllohaMovie` (lines 23-27), `AllohaApiResult` (lines 29-34).
    - `fetchByKpId(kpId:)` (lines 217-418): Fetches and parses JSON from `https://api.alloha.tv/?token=...&kp=...`.
- **Runtime Resolution & Parsing**:
  - `sloosh-iOS/sloosh/Sources/Data/Repositories/AllohaRuntimeResolver.swift`
    - `SharedWebViewProvider` (lines 489-577): Maintains a pooled `WKWebView`.
    - `resolve(iframeUrl:)` (lines 42-63): Injects `bootstrapScript` (lines 332-486) into `WKWebView`, hooks XHR/fetch/WS, captures headers and `/bnsi/` payloads, and returns a resolved dictionary (`url`, `audioVariants`, `qualityVariants`, `headers`, `subtitles`, `introRange`, `outroRange`).
    - In-memory cache with TTL (lines 7-13).
  - `sloosh-iOS/sloosh/Sources/Data/Repositories/AllohaRuntimeParser.swift`
    - `parsePayload(_:baseURL:headers:)` (lines 4-41): Parses the JSON payload from `/bnsi/` (`parseAllohaBNsiStream`, lines 64-159).
    - Extracts `qualityVariants` from `item["quality"]` (lines 80-118).
    - Extracts `audioVariants` with `audioVariantTitle(from:item:index:)` (lines 127-133).
    - Extracts skip ranges (`extractSkips`, lines 161-219) and subtitles (lines 305-324).
- **HLS Proxy & Master Playlist Rewriter**:
  - `sloosh-iOS/sloosh/Sources/Data/Repositories/HlsProxyServer.swift`
    - TCP server running on `127.0.0.1:8181` using `NWListener` (lines 7-113).
    - Rewrites upstream master playlists via `PlaybackHlsRewriter.rewrite` (lines 328-338) and `rewriteM3u8` (lines 372-421).
    - Strips AV1 codecs (`hlsLineHasAV1Codecs`, lines 442-463) and normalizes `VIDEO-RANGE` for non-HEVC streams (`normalizeStreamInfVideoRange`, lines 426-439).
    - Serves `/local/...` endpoints for offline downloads (lines 261-288).
  - `sloosh-iOS/sloosh/Sources/Data/Repositories/PlaybackHlsRewriter.swift`
    - Rewrites `#EXT-X-STREAM-INF` and `#EXT-X-MEDIA` lines (lines 3-77).
- **Player & UI Integration**:
  - `sloosh-iOS/sloosh/Sources/UI/Player/PlayerView.swift`
    - `PlayerViewModel.beginLoad(...)` (lines 359-433)
    - `PlayerViewModel.applyResolvedAllohaStream(...)` (lines 1813-1886)
    - `PlayerViewModel.switchVoiceover(to:at:)` (lines 785-884)
    - `PlayerViewModel.playEpisode(...)` & `nextEpisodeCandidate()` (lines 1699-1762)
    - `PlayerViewModel.changeQuality(to:)` (lines 908-934)
  - `sloosh-iOS/sloosh/Sources/UI/Player/Controls/PlayerPickerSheets.swift`
    - `VoiceoverPickerSheet` (lines 6-23): Displays `vm.availableVoiceovers` and triggers `vm.switchVoiceover`.
- **Download Management**:
  - `sloosh-iOS/sloosh/Sources/Data/Repositories/DownloadManager.swift`
    - `prepareAndEnqueue(itemId:item:preferredQuality:)` (lines 296-447)
    - `chooseMediaPlaylistUrl(from:baseUrl:preferredQuality:)` (lines 659-701)

---

### 1.2 Observed Defects & Code Snippets

#### Observation 1: `PlayerView.swift:1856-1859` Overwrites API Voiceovers with Resolver `audioVariants`
```swift
// sloosh-iOS/sloosh/Sources/UI/Player/PlayerView.swift:1854-1860
// Заполняем список доступных озвучек и варианты стримов из audioVariants
self.resolvedAudioVariants = audioVariants
let voices = resolvedVoiceovers(from: resolved)
if !voices.isEmpty {
    self.availableVoiceovers = voices
}
```
When `applyResolvedAllohaStream` executes, `self.availableVoiceovers` (which was populated with the full translation list from `seriesResult` / `epObj.translations`) is overwritten by `voices`, which are extracted from `resolved["audioVariants"]` of that single iframe. This replaces authentic studio names with generic labels like `["Russian 1"]`.

#### Observation 2: `AllohaRepository.swift:383-410` Mutates Movie Translations on Fetch
```swift
// sloosh-iOS/sloosh/Sources/Data/Repositories/AllohaRepository.swift:383-410
if let m = result.movie, let firstIframe = m.translations.first?.iframeUrl {
    let resolver = await AllohaRuntimeResolver()
    if let resolved = try? await resolver.resolve(iframeUrl: firstIframe),
       let audioVariants = resolved["audioVariants"] as? [[String: Any]], !audioVariants.isEmpty {
        let newTranslations = audioVariants.enumerated().compactMap { index, variant -> AllohaTranslation? in
            ...
            return AllohaTranslation(
                id: vTitle,
                name: cleanTitle.isEmpty ? vTitle : cleanTitle,
                iframeUrl: m.iframeUrl,
                streamUrl: nil
            )
        }
        if !newTranslations.isEmpty {
            let newMovie = AllohaMovie(title: m.title, iframeUrl: m.iframeUrl, translations: newTranslations)
            result = AllohaApiResult(title: result.title, isSerial: false, movie: newMovie, seasons: [])
        }
    }
}
```
In `AllohaRepository.fetchByKpId`, movie metadata was eagerly resolved and overwritten by `audioVariants` from the first iframe, wiping out the authentic translations list directly at the repository level.

#### Observation 3: `PlayerView.swift:397-405` Movie Translation Population Gap
```swift
// sloosh-iOS/sloosh/Sources/UI/Player/PlayerView.swift:397-405
if let seriesResult = self.seriesResult, let s = season, let e = episode {
    if let seasonObj = seriesResult.seasons.first(where: { $0.season == s }),
       let epObj = seasonObj.episodes.first(where: { $0.episode == e }) {
        self.availableVoiceovers = epObj.translations.map { $0.name }
    }
} else if !voices.isEmpty {
    self.availableVoiceovers = voices
}
```
`beginLoad` handles `seriesResult.seasons` for series, but lacks explicit handling for `seriesResult.movie?.translations.map { $0.name }` for movies.

#### Observation 4: `DownloadManager.swift:326-332` Unnecessary `audioVariants` URL Override
```swift
// sloosh-iOS/sloosh/Sources/Data/Repositories/DownloadManager.swift:326-332
if let targetVoice = item.translationName, !targetVoice.isEmpty {
    let exactMatch = audioVariants.first(where: { allohaTranslationNamesMatch($0["title"] as? String, targetVoice, exactOnly: true) })
    let match = exactMatch ?? audioVariants.first(where: { allohaTranslationNamesMatch($0["title"] as? String, targetVoice, exactOnly: false) })
    if let validMatch = match, let matchedUrl = validMatch["url"] as? String, !matchedUrl.isEmpty {
        streamUrlString = matchedUrl.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```
`item.iframeUrl` is already the specific translation's iframe URL. Overriding `streamUrlString` by fuzzy-matching against internal `audioVariants` causes the wrong stream/audio to be downloaded.

#### Observation 5: `DownloadManager.swift:659-701` Incomplete Master Playlist Parsing
```swift
// sloosh-iOS/sloosh/Sources/Data/Repositories/DownloadManager.swift:671-675
if let range = trimmed.range(of: "RESOLUTION=([^,\\s]+)", options: .regularExpression) {
    let match = String(trimmed[range]).replacingOccurrences(of: "RESOLUTION=", with: "")
    let components = match.components(separatedBy: "x")
    if components.count == 2, let h = Int(components[1]) { currentHeight = h }
}
```
- `currentBandwidth` is not parsed from `#EXT-X-STREAM-INF` lines.
- Variant URLs without explicit `RESOLUTION=` attributes (e.g. `1080.m3u8`, `720.m3u8`) are not detected by filename cues.
- Sorting should choose the highest resolution variant `<= targetHeight` (or highest available) rather than pure absolute difference.

---

## 2. Logic Chain

1. **Step 1 (Catalog Authenticity)**: `AllohaRepository` receives authentic translation names (e.g., "Дублированный (Red Head Sound)", "Дубляж (FlixBros)", "LostFilm") and distinct iframe URLs from `api.alloha.tv`. Overwriting this metadata with `audioVariants` (from `AllohaRuntimeResolver` on a single iframe) corrupts the translation list.
2. **Step 2 (Player Voiceover List Preservation)**: When `PlayerView` opens, `availableVoiceovers` must reflect the authentic list from `seriesResult` (`epObj.translations` for series, `movie.translations` for movies, or `voices`). `applyResolvedAllohaStream` must NOT overwrite `availableVoiceovers` with internal `audioVariants`.
3. **Step 3 (In-Player Voiceover Switching)**: When switching voiceovers via `VoiceoverPickerSheet`, `switchVoiceover` must find the target translation in `seriesResult`, invalidate the resolver cache for that translation's `iframeUrl`, and reload playback with the new translation stream while preserving `currentTime`.
4. **Step 4 (Episode Navigation Fidelity)**: When navigating to the next episode, `nextEpisodeCandidate()` uses `preferredTranslation` to select the translation matching the active voiceover (`_currentTranslationName`), or falls back gracefully to saved preferences if unavailable.
5. **Step 5 (Download Fidelity)**: In `DownloadManager.prepareAndEnqueue`, using `resolved["url"]` directly for `item.iframeUrl` guarantees downloading the exact chosen translation. Parsing master playlist resolutions accurately ensures the requested quality (e.g. 1080p) is downloaded without downgrade.

---

## 3. Caveats

- **Network Mode**: Investigation conducted in read-only mode across local codebase.
- **Provider Names**: Internal provider names (e.g. `Alloha`) are used strictly in internal code and technical documentation and must not leak into user-facing copy per `AGENTS.md`.
- **Collaps Integration**: As mandated in `AGENTS.md`, Collaps is excluded. The focus is strictly on Alloha.

---

## 4. Conclusion & Actionable Recommendations

### Recommendation 1: Fix `PlayerView.swift`
- In `PlayerViewModel.beginLoad`, populate `availableVoiceovers` for movies:
  ```swift
  if let seriesResult = self.seriesResult, let s = season, let e = episode {
      if let seasonObj = seriesResult.seasons.first(where: { $0.season == s }),
         let epObj = seasonObj.episodes.first(where: { $0.episode == e }) {
          self.availableVoiceovers = epObj.translations.map { $0.name }
      }
  } else if let seriesResult = self.seriesResult, let movie = seriesResult.movie {
      self.availableVoiceovers = movie.translations.map { $0.name }
  } else if !voices.isEmpty {
      self.availableVoiceovers = voices
  }
  ```
- In `PlayerViewModel.applyResolvedAllohaStream`, preserve `availableVoiceovers` if already populated:
  ```swift
  self.resolvedAudioVariants = audioVariants
  let voices = resolvedVoiceovers(from: resolved)
  if self.availableVoiceovers.isEmpty && !voices.isEmpty {
      self.availableVoiceovers = voices
  }
  ```
- In `PlayerViewModel.switchVoiceover`, ensure seamless reload to the target translation's `iframeUrl` while preserving `currentTime`.

### Recommendation 2: Fix `AllohaRepository.swift`
- Remove lines 383-410 in `AllohaRepository.swift` where `movie.translations` was being overwritten with `audioVariants`. Preserve the authentic `movie.translations` parsed directly from `dataObj["translation"]`.

### Recommendation 3: Fix `DownloadManager.swift`
- In `prepareAndEnqueue`, remove lines 326-332 that overrode `streamUrlString` with `audioVariants`.
- In `chooseMediaPlaylistUrl`, enhance master playlist parsing:
  - Parse `BANDWIDTH=` attribute.
  - Parse resolution from variant filenames (`1080.m3u8`, `720.m3u8`, `480.m3u8`, `360.m3u8`).
  - Select highest resolution matching or below the target preference.

---

## 5. Verification Method

To verify these findings and fixes:
1. **Source Inspection**:
   - Inspect `AllohaRepository.swift` to ensure `movie.translations` retains the raw API translation list.
   - Inspect `PlayerView.swift` to verify `availableVoiceovers` is populated from `seriesResult` and not overwritten by `applyResolvedAllohaStream`.
   - Inspect `DownloadManager.swift` to verify direct stream URL usage and master playlist parsing.
2. **Behavioral Test Scenarios**:
   - **Multi-voice Series (e.g. "Локи")**: Open in `SourceSelectionView`, select "Дублированный" -> verify `PlayerView` plays the dubbed audio, `VoiceoverPickerSheet` lists all translations, and switching voiceover updates playback at current position.
   - **Episode Navigation**: Complete an episode -> verify next episode plays with the same active voiceover.
   - **Offline Downloads**: Download an episode with a specific voiceover in 1080p -> verify `DownloadManager` downloads the 1080p variant of that voiceover and plays offline accurately in `PlayerView`.
