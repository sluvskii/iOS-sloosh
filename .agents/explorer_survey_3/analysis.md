# Deep Analysis: DownloadManager & Quality/Stream Selection in Sloosh iOS

**Author**: `explorer_survey_3`  
**Date**: 2026-08-27  
**Workspace**: `W:\iOS-sloosh\sloosh-iOS\sloosh\Sources\`  
**Target Milestone**: Voiceover & Quality Discrepancies Investigation (Task 3: DownloadManager & Quality/Stream Selection)

---

## 1. Executive Summary

This investigation analyzes the end-to-end download architecture, stream/quality resolution, master playlist parsing, and offline playback mechanisms in `sloosh-iOS`.

### Core Findings
1. **Erroneous `audioVariants` Overrides in `prepareAndEnqueue`**:
   `DownloadManager.prepareAndEnqueue` receives a translation-specific `item.iframeUrl`. Resolving this URL via `AllohaRuntimeResolver` yields the authentic master stream URL in `resolved["url"]`. However, lines 326–332 perform title matching against `resolved["audioVariants"]`. Because `audioVariants` items often contain internal, generic, or partial titles, and their URLs frequently point to secondary adaptive playlists (such as `720.m3u8` selected by `preferredAdaptiveURL`), this override causes the downloader to discard the master playlist and lock onto a 720p stream or a mismatched audio track.
2. **Deficiencies in `chooseMediaPlaylistUrl`**:
   - Master HLS playlists (`#EXT-X-STREAM-INF`) are parsed solely for `RESOLUTION=WxH`. `BANDWIDTH` and `AVERAGE-BANDWIDTH` regex parsing is completely missing (initialized to 0 and left at 0).
   - If `RESOLUTION=` is missing on CDN variant lines, height defaults to 0 and the distance-based sorter picks the first available variant (often lowest quality: 360p or 480p).
   - `resolved["qualityVariants"]` returned by Alloha is completely ignored.
   - AV1 codec variants (`codecs="av01..."` / `av1`) are not filtered, risking unplayable downloads on iOS.
   - Sorter uses `abs(height - targetHeight)`, causing ambiguous selections (e.g. 720p vs 1440p when 1080p is targeted) rather than selecting the maximum available resolution $\le \text{targetHeight}$.
3. **Offline Metadata & Playback Flow**:
   - Media is packaged into `taskDir` with `poster.jpg`, `manifest.json`, `key.bin` (AES-128 key), `local.m3u8` (rewritten playlist), and `segment_<index>.ts`.
   - `HlsProxyServer` correctly serves `/local/<path>` endpoints.
   - `PlayerView` consumes `directStreamUrl` via `http://127.0.0.1:8181/local/.../local.m3u8`, which AVPlayer decrypts via `key.bin`.
   - `DetailsView` checks `downloadItem.translationName == translation.name` before playing offline; if a user selects a different translation, it streams online.

---

## 2. Component Inspection & Code Mapping

### 2.1 File & Module Directory
| File | Role | Key Locations |
|---|---|---|
| `Data/Repositories/DownloadManager.swift` | Manages download queue, resolution, playlist parsing, segment downloads, and storage | Lines 13–63 (`DownloadItem`), 147–209 (`startDownload`), 296–447 (`prepareAndEnqueue`), 659–701 (`chooseMediaPlaylistUrl`) |
| `Data/Repositories/DownloadManifest.swift` | Manifest DTO for segment URLs, headers, key URL, local directory | Lines 1–10 (`DownloadManifest`) |
| `UI/Downloads/DownloadsView.swift` | Downloads UI: filter tabs, progress rows, swipe delete, fullScreenCover player launch | Lines 58–166 (`DownloadsView`), 176–294 (`DownloadRowView`) |
| `Data/Repositories/AllohaRuntimeResolver.swift` | Evaluates iframe URL via pooled `WKWebView` to extract HLS master URL, headers, quality/audio variants | Lines 42–63 (`resolve`), 157–232 (`resolveBestAvailablePayload`) |
| `Data/Repositories/AllohaRuntimeParser.swift` | Parses JSON payload/DOM for `hlsSource`, subtitles, skips, quality variants | Lines 64–159 (`parseAllohaBNsiStream`), 268–279 (`preferredAdaptiveURL`) |
| `Data/Repositories/HlsProxyServer.swift` | Local HTTP proxy on port 8181 serving `/master.m3u8`, `/proxy/`, and `/local/` | Lines 261–285 (`/local/` handling), 383–395 (AV1 filtering) |
| `UI/Player/PlayerView.swift` | AVPlayer streaming & offline playback controller | Lines 327–433 (`beginLoad`), 414–427 (direct local playback), 1139–1240 (`playVideo`) |
| `UI/Details/SourceSelectionView.swift` | Sheet for selecting voiceover, season, episode, quality preference | Lines 207–233 (`finishAction`) |
| `UI/Details/DetailsView.swift` | Movie/show details view triggering playback & downloads | Lines 302–329 (`showSourceSheet` action), 473–533 (movie download), 1470–1516 (episode download) |

---

## 3. Deep Dive Findings & Logic Chain

### Finding 1: Erroneous `audioVariants` Overrides in `prepareAndEnqueue`
**Location**: `sloosh-iOS/sloosh/Sources/Data/Repositories/DownloadManager.swift`, lines 313–337:
```swift
let resolver = AllohaRuntimeResolver()
let resolved: [String: Any]
do {
    resolved = try await resolver.resolve(iframeUrl: item.iframeUrl)
} catch {
    await finishWithError(id: itemId, message: "Не удалось получить источник")
    return
}

let audioVariants = (resolved["audioVariants"] as? [[String: Any]]) ?? []
var streamUrlString = (resolved["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
let headers = (resolved["headers"] as? [String: String]) ?? [:]

if let targetVoice = item.translationName, !targetVoice.isEmpty {
    let exactMatch = audioVariants.first(where: { allohaTranslationNamesMatch($0["title"] as? String, targetVoice, exactOnly: true) })
    let match = exactMatch ?? audioVariants.first(where: { allohaTranslationNamesMatch($0["title"] as? String, targetVoice, exactOnly: false) })
    if let validMatch = match, let matchedUrl = validMatch["url"] as? String, !matchedUrl.isEmpty {
        streamUrlString = matchedUrl.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

#### Detailed Logic & Cause:
1. When user initiates a download (from `SourceSelectionView` or `DetailsView`), `item.iframeUrl` is set to `translation.iframeUrl`.
2. Alloha encodes the exact translation ID inside this `iframeUrl` (e.g. `https://alloha.tv/box/...?translation=54`).
3. `AllohaRuntimeResolver` loads this specific translation iframe in `WKWebView`. The CDN provides the exact master stream for that voiceover, returned as `resolved["url"]`.
4. `audioVariants` contains secondary stream entries parsed from `hlsSource`. In `AllohaRuntimeParser.swift` (line 123–125), `audioVariants[i]["url"]` is constructed as:
   ```swift
   let chosenAudioURL = itemMasterURL
       ?? itemAdaptiveURL
       ?? sortedItemVariants.last.flatMap { URL(string: ($0["url"] as? String) ?? "") }
   ```
   And `preferredAdaptiveURL` (line 273) selects `urls[1]`, which is often `720.m3u8`.
5. When `prepareAndEnqueue` performs `allohaTranslationNamesMatch` against `audioVariants`, if any match occurs (exact or loose), `streamUrlString` is overwritten with `validMatch["url"]` (e.g. `https://.../720.m3u8`).
6. Because `720.m3u8` is already a media playlist with `.ts` segments (not a master playlist), `playlistContent.contains("#EXT-X-STREAM-INF")` evaluates to `false`.
7. As a direct consequence, `DownloadManager` never executes `chooseMediaPlaylistUrl` and downloads 720p, completely ignoring user's 1080p selection!
8. Furthermore, if fuzzy matching matches an unrelated studio voiceover, the download downloads the wrong audio track.

---

### Finding 2: Deficiencies & Downgrade Vectors in `chooseMediaPlaylistUrl`
**Location**: `sloosh-iOS/sloosh/Sources/Data/Repositories/DownloadManager.swift`, lines 659–701:
```swift
private func chooseMediaPlaylistUrl(from content: String, baseUrl: URL, preferredQuality: VideoQualityPreference) -> URL? {
    let lines = content.components(separatedBy: .newlines)
    var variants: [(url: URL, height: Int, bandwidth: Double)] = []
    var currentBandwidth: Double = 0
    var currentHeight: Int = 0
    
    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { continue }
        if trimmed.hasPrefix("#EXT-X-STREAM-INF:") {
            currentBandwidth = 0
            currentHeight = 0
            if let range = trimmed.range(of: "RESOLUTION=([^,\\s]+)", options: .regularExpression) {
                let match = String(trimmed[range]).replacingOccurrences(of: "RESOLUTION=", with: "")
                let components = match.components(separatedBy: "x")
                if components.count == 2, let h = Int(components[1]) { currentHeight = h }
            }
        } else if !trimmed.hasPrefix("#") {
            let variantUrl = trimmed.hasPrefix("http") ? URL(string: trimmed) : URL(string: trimmed, relativeTo: baseUrl)
            if let variantUrl = variantUrl {
                variants.append((url: variantUrl, height: currentHeight, bandwidth: currentBandwidth))
            }
        }
    }
    if variants.isEmpty { return nil }
    
    let targetHeight: Int
    switch preferredQuality {
    case .q1080: targetHeight = 1080
    case .q720: targetHeight = 720
    case .q480: targetHeight = 480
    case .q360: targetHeight = 360
    default: targetHeight = 1080
    }
    
    let sorted = variants.sorted { a, b in
        let diffA = abs(a.height - targetHeight)
        let diffB = abs(b.height - targetHeight)
        if diffA != diffB { return diffA < diffB }
        return a.bandwidth > b.bandwidth
    }
    return sorted.first?.url
}
```

#### Detailed Breakdown of Flaws:
1. **Bandwidth Missing**:
   Lines 662 and 669 initialize `currentBandwidth = 0`. No regex extracts `BANDWIDTH=(\d+)` or `AVERAGE-BANDWIDTH=(\d+)`. `a.bandwidth > b.bandwidth` is a no-op ($0 > 0 \to \text{false}$).
2. **Missing `RESOLUTION=` Fallback**:
   Many master playlists omit `RESOLUTION=` and indicate quality in the URI (`1080.m3u8`, `720p.m3u8`, `1080p/index.m3u8`, `video_1080.m3u8`). Without fallback filename parsing, `currentHeight` remains 0.
3. **No Quality Evaluation from `resolved["qualityVariants"]`**:
   `AllohaRuntimeParser` extracts structured `qualityVariants` (e.g. `[{"label": "1080p", "url": "..."}, {"label": "720p", "url": "..."}]`). `prepareAndEnqueue` never checks this array.
4. **No AV1 Filtering**:
   If a master playlist offers AV1 (`codecs="av01.0.08M.08"`) and H.264 (`codecs="avc1.640028"`), both at 1080p, `chooseMediaPlaylistUrl` will blindly pick the first one (often AV1), producing unplayable downloads on Apple devices.
5. **Flawed Distance Sorter**:
   Using `abs(height - targetHeight)` means:
   - When target is 1080p: a 720p stream ($\text{diff}=360$) and a 1440p stream ($\text{diff}=360$) have equal priority.
   - When target is 720p: if 720p is missing, 480p ($\text{diff}=240$) is picked over 1080p ($\text{diff}=360$).
   **Desired Strategy**:
   Find the maximum resolution that does not exceed `targetHeight`. If none exists $\le \text{targetHeight}$, fall back to the lowest resolution above `targetHeight`.

---

### Finding 3: Download Packaging, Verification, and Offline Consumption
**Location**: `DownloadManager.swift` lines 373–445, `HlsProxyServer.swift` lines 261–285, `PlayerView.swift` lines 414–427.

#### Packaging Pipeline:
1. **Directory**: `downloads/movies/<kpId>` or `downloads/shows/<kpId>/s<season>_e<episode>`.
2. **Poster**: Direct download to `poster.jpg`.
3. **Encryption Key**: If `#EXT-X-KEY` contains `URI="..."`, downloads raw key bytes to `key.bin` (`isExcludedFromBackup = true`).
4. **Playlist Rewriting**: Rewrites all `#EXT-X-KEY:METHOD=AES-128,URI="..."` to `URI="key.bin"`. Rewrites all segment lines to `segment_0.ts`, `segment_1.ts`, etc. Saves to `local.m3u8`.
5. **Manifest**: Serializes `DownloadManifest` with all remote segment URLs to `manifest.json`.
6. **Segments**: Downloads segments via background `URLSessionDownloadTask` with concurrency limit of 4 and up to 3 retries.
7. **Serving via `HlsProxyServer`**:
   - `DownloadItem.localPlayableUrl` = `http://127.0.0.1:8181/local/\(localDirectory)/local.m3u8`.
   - `HlsProxyServer` serves `local.m3u8` (`application/vnd.apple.mpegurl`), `key.bin` (`application/octet-stream`), and `segment_*.ts` (`video/MP2T`).
8. **Offline Consumption in `PlayerView`**:
   - `PlayerView` receives `directStreamUrl: item.localPlayableUrl?.absoluteString` and `selectedVoiceover: item.translationName`.
   - `PlayerViewModel.beginLoad` sets `isLocalPlayback = true`, configures `AVAssetImageGenerator` for thumbnails, sets `currentQualityKey = "Локальный"`, and sets `_currentTranslationName = selectedVoiceover`.
   - `HlsProxyServer.shared.start(headers: [:], voices: [], subtitles: [], mediaId: "local")` ensures the proxy listener is alive.
   - AVPlayer loads `http://127.0.0.1:8181/local/.../local.m3u8`, requests `key.bin`, decrypts AES-128 segments, and plays offline seamlessly.
9. **UI Fidelity in DetailsView**:
   `DetailsView` checks:
   ```swift
   if let kpId = wrapper.kpId,
      DownloadManager.shared.isDownloaded(kpId: kpId, season: season, episode: episode),
      let downloadItem = DownloadManager.shared.getDownloadItem(kpId: kpId, season: season, episode: episode),
      downloadItem.translationName == translation.name {
       // Play offline
   } else {
       // Stream online for the chosen translation
   }
   ```
   If user selects a different translation than the downloaded one, `DetailsView` streams the selected translation online without forcing the downloaded voiceover.

---

## 4. Synthesis of Discrepancies & Fix Matrix

| Area | Current Behavior | Problem / Risk | Proposed Solution |
|---|---|---|---|
| **Stream URL Selection** | Matches `item.translationName` against `audioVariants` and overrides `streamUrlString` | Overrides master playlist with secondary/lower quality variant (e.g. 720p) or wrong voiceover | Use `resolved["url"]` directly; `item.iframeUrl` is already translation-specific |
| **`qualityVariants` from Resolver** | Ignored in `DownloadManager.prepareAndEnqueue` | Misses explicit quality URLs extracted from Alloha JSON | Evaluate `resolved["qualityVariants"]` to select preferred quality URL before or alongside master playlist |
| **Master Playlist Parsing** | Only checks `RESOLUTION=WxH`; bandwidth is unparsed ($0$); filename hints ignored | Fails on playlists without `RESOLUTION=`; defaults to lowest variant | Parse `BANDWIDTH`, `AVERAGE-BANDWIDTH`, `CODECS`, and filename resolution hints (`1080`, `720`, etc.) |
| **AV1 Streams** | Not filtered during download playlist parsing | Can download unplayable AV1 video stream | Filter out variants with `codecs="av01..."` or `av1` |
| **Quality Selection Sorter** | `abs(height - targetHeight)` | Indeterminate for equal distances; downgrades unnecessarily | Select highest available resolution $\le \text{targetHeight}$, with tie-breaker by bandwidth |
| **AES-128 Key Rewriting** | Only rewrites single `keyLineIndex` | If playlist has multiple key tags, only the last is rewritten | Rewrite all `#EXT-X-KEY` lines containing matching URI to `URI="key.bin"` |
| **Player View Voiceover List for Offline** | `availableVoiceovers` is empty when launched from `DownloadsView` | In-player sheet shows no active voiceovers | Initialize `availableVoiceovers = [selectedVoiceover]` if otherwise empty |

---

## 5. Proposed Code Fixes (Reference Snippets)

### Fix 1: `DownloadManager.prepareAndEnqueue`
In `sloosh-iOS/sloosh/Sources/Data/Repositories/DownloadManager.swift`:
```swift
// Use the resolved URL directly from the translation-specific iframe
var streamUrlString = (resolved["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
let headers = (resolved["headers"] as? [String: String]) ?? [:]
let qualityVariants = (resolved["qualityVariants"] as? [[String: Any]]) ?? []

// 1. If explicit qualityVariants exist and match preferred quality, evaluate first
if let chosenFromVariants = chooseFromQualityVariants(qualityVariants, preferredQuality: preferredQuality) {
    streamUrlString = chosenFromVariants.absoluteString
}

guard let masterPlaylistUrl = URL(string: streamUrlString) else {
    await finishWithError(id: itemId, message: "Не удалось получить ссылку на поток")
    return
}
```

### Fix 2: Enhanced `chooseMediaPlaylistUrl` & Quality Evaluation
In `sloosh-iOS/sloosh/Sources/Data/Repositories/DownloadManager.swift`:
```swift
private func chooseMediaPlaylistUrl(from content: String, baseUrl: URL, preferredQuality: VideoQualityPreference) -> URL? {
    let lines = content.components(separatedBy: .newlines)
    var variants: [(url: URL, height: Int, bandwidth: Double, isAV1: Bool)] = []
    var currentBandwidth: Double = 0
    var currentHeight: Int = 0
    var isAV1: Bool = false
    
    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { continue }
        if trimmed.hasPrefix("#EXT-X-STREAM-INF:") {
            currentBandwidth = 0
            currentHeight = 0
            isAV1 = false
            
            // 1. Check for AV1 codec
            let lower = trimmed.lowercased()
            if lower.contains("av01") || lower.contains("codecs=\"av1") {
                isAV1 = true
            }
            
            // 2. Parse RESOLUTION
            if let range = trimmed.range(of: "RESOLUTION=([^,\\s]+)", options: .regularExpression) {
                let match = String(trimmed[range]).replacingOccurrences(of: "RESOLUTION=", with: "")
                let components = match.components(separatedBy: "x")
                if components.count == 2, let h = Int(components[1]) { currentHeight = h }
            }
            
            // 3. Parse BANDWIDTH / AVERAGE-BANDWIDTH
            if let range = trimmed.range(of: "(?:AVERAGE-)?BANDWIDTH=(\\d+)", options: .regularExpression) {
                let match = String(trimmed[range])
                if let bwStr = match.components(separatedBy: "=").last, let bw = Double(bwStr) {
                    currentBandwidth = bw
                }
            }
        } else if !trimmed.hasPrefix("#") {
            let variantUrl = trimmed.hasPrefix("http") ? URL(string: trimmed) : URL(string: trimmed, relativeTo: baseUrl)
            if let variantUrl = variantUrl {
                // 4. Fallback height from URL if RESOLUTION attribute was missing
                var effectiveHeight = currentHeight
                if effectiveHeight == 0 {
                    effectiveHeight = extractHeightFromUrl(variantUrl)
                }
                variants.append((url: variantUrl, height: effectiveHeight, bandwidth: currentBandwidth, isAV1: isAV1))
            }
        }
    }
    
    // Filter out AV1 streams
    let playableVariants = variants.filter { !$0.isAV1 }
    let candidates = playableVariants.isEmpty ? variants : playableVariants
    if candidates.isEmpty { return nil }
    
    let targetHeight: Int
    switch preferredQuality {
    case .q1080: targetHeight = 1080
    case .q720: targetHeight = 720
    case .q480: targetHeight = 480
    case .q360: targetHeight = 360
    default: targetHeight = 1080
    }
    
    // Pick highest matching resolution <= targetHeight (capped at 1080)
    let cappedCandidates = candidates.filter { $0.height <= 1080 || $0.height == 0 }
    let atOrBelowTarget = cappedCandidates.filter { $0.height > 0 && $0.height <= targetHeight }
    
    if let best = atOrBelowTarget.sorted(by: { a, b in
        if a.height != b.height { return a.height > b.height }
        return a.bandwidth > b.bandwidth
    }).first {
        return best.url
    }
    
    // Fallback: lowest above target, or highest available
    if let fallback = cappedCandidates.sorted(by: { a, b in
        if a.height != b.height { return a.height > b.height }
        return a.bandwidth > b.bandwidth
    }).first {
        return fallback.url
    }
    
    return candidates.first?.url
}

private func extractHeightFromUrl(_ url: URL) -> Int {
    let filename = url.lastPathComponent.lowercased()
    if filename.contains("2160") || filename.contains("4k") { return 2160 }
    if filename.contains("1440") || filename.contains("2k") { return 1440 }
    if filename.contains("1080") { return 1080 }
    if filename.contains("720") { return 720 }
    if filename.contains("480") { return 480 }
    if filename.contains("360") { return 360 }
    return 0
}
```
