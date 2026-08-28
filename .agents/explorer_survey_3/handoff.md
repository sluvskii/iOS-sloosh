# Handoff Report: DownloadManager & Quality/Stream Selection Investigation

**Author**: `explorer_survey_3`  
**Date**: 2026-08-27  
**Task**: Survey 3 — DownloadManager and Quality/Stream Selection  
**Working Directory**: `W:\iOS-sloosh\.agents\explorer_survey_3`

---

## 1. Observation

### Obs 1: Erroneous `audioVariants` Overrides in `DownloadManager.prepareAndEnqueue`
- **File**: `W:\iOS-sloosh\sloosh-iOS\sloosh\Sources\Data\Repositories\DownloadManager.swift`, lines 313–337
```swift
313:         let resolver = AllohaRuntimeResolver()
314:         let resolved: [String: Any]
315:         do {
316:             resolved = try await resolver.resolve(iframeUrl: item.iframeUrl)
317:         } catch {
318:             await finishWithError(id: itemId, message: "Не удалось получить источник")
319:             return
320:         }
321:         
322:         let audioVariants = (resolved["audioVariants"] as? [[String: Any]]) ?? []
323:         var streamUrlString = (resolved["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
324:         let headers = (resolved["headers"] as? [String: String]) ?? [:]
325:         
326:         if let targetVoice = item.translationName, !targetVoice.isEmpty {
327:             let exactMatch = audioVariants.first(where: { allohaTranslationNamesMatch($0["title"] as? String, targetVoice, exactOnly: true) })
328:             let match = exactMatch ?? audioVariants.first(where: { allohaTranslationNamesMatch($0["title"] as? String, targetVoice, exactOnly: false) })
329:             if let validMatch = match, let matchedUrl = validMatch["url"] as? String, !matchedUrl.isEmpty {
330:                 streamUrlString = matchedUrl.trimmingCharacters(in: .whitespacesAndNewlines)
331:             }
332:         }
```
- **Context in `PlayerView.swift`**: `PlayerView.swift` lines 1823–1826:
```swift
1823:             // The iframeUrl already has translation=ID injected for both movies and series, 
1824:             // so CDN delivers the correct voiceover stream as the default. 
1825:             // No audioVariant name matching needed.
1826:             logDebug("applyResolvedAllohaStream: using default resolved url (translation embedded in iframe)")
```
- **Context in `AllohaRuntimeParser.swift`**: Lines 123–133 and 268–279:
`audioVariants[i]["url"]` is constructed via `itemAdaptiveURL = preferredAdaptiveURL(in: urls)`. `preferredAdaptiveURL` chooses `urls[1]`, which is frequently `720.m3u8` rather than `master.m3u8`. Overwriting `streamUrlString` replaces the master playlist with `720.m3u8`.

---

### Obs 2: Master Playlist Parsing Deficiencies in `chooseMediaPlaylistUrl`
- **File**: `W:\iOS-sloosh\sloosh-iOS\sloosh\Sources\Data\Repositories\DownloadManager.swift`, lines 659–701
```swift
659:     private func chooseMediaPlaylistUrl(from content: String, baseUrl: URL, preferredQuality: VideoQualityPreference) -> URL? {
660:         let lines = content.components(separatedBy: .newlines)
661:         var variants: [(url: URL, height: Int, bandwidth: Double)] = []
662:         var currentBandwidth: Double = 0
663:         var currentHeight: Int = 0
664:         
665:         for line in lines {
666:             let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
667:             if trimmed.isEmpty { continue }
668:             if trimmed.hasPrefix("#EXT-X-STREAM-INF:") {
669:                 currentBandwidth = 0
670:                 currentHeight = 0
671:                 if let range = trimmed.range(of: "RESOLUTION=([^,\\s]+)", options: .regularExpression) {
672:                     let match = String(trimmed[range]).replacingOccurrences(of: "RESOLUTION=", with: "")
673:                     let components = match.components(separatedBy: "x")
674:                     if components.count == 2, let h = Int(components[1]) { currentHeight = h }
675:                 }
676:             } else if !trimmed.hasPrefix("#") {
677:                 let variantUrl = trimmed.hasPrefix("http") ? URL(string: trimmed) : URL(string: trimmed, relativeTo: baseUrl)
678:                 if let variantUrl = variantUrl {
679:                     variants.append((url: variantUrl, height: currentHeight, bandwidth: currentBandwidth))
680:                 }
681:             }
682:         }
683:         if variants.isEmpty { return nil }
684:         
685:         let targetHeight: Int
686:         switch preferredQuality {
687:         case .q1080: targetHeight = 1080
688:         case .q720: targetHeight = 720
689:         case .q480: targetHeight = 480
690:         case .q360: targetHeight = 360
691:         default: targetHeight = 1080
692:         }
693:         
694:         let sorted = variants.sorted { a, b in
695:             let diffA = abs(a.height - targetHeight)
696:             let diffB = abs(b.height - targetHeight)
697:             if diffA != diffB { return diffA < diffB }
698:             return a.bandwidth > b.bandwidth
699:         }
700:         return sorted.first?.url
701:     }
```
- **Deficiencies identified**:
  1. `currentBandwidth` is never updated (always 0) because regex for `BANDWIDTH=` is absent.
  2. No fallback for variant URLs with resolutions in their filename (e.g. `1080.m3u8`, `720.m3u8`).
  3. `resolved["qualityVariants"]` is never inspected in `prepareAndEnqueue`.
  4. AV1 codec streams (`codecs="av01..."`) are not filtered out.
  5. Distance sort `abs(a.height - targetHeight)` causes ambiguous priority and unwanted downgrades.

---

### Obs 3: Offline Media Packaging & Playback Pipeline
- **File**: `W:\iOS-sloosh\sloosh-iOS\sloosh\Sources\Data\Repositories\DownloadManager.swift`, lines 33–42, 373–447
  - `localPlayableUrl`: `http://127.0.0.1:8181/local/\(localDirectory)/\(localPlayableFileName)`
  - Rewriting: Key URI rewritten to `URI="key.bin"`, media segments rewritten to `segment_\(segIdx).ts`.
- **File**: `W:\iOS-sloosh\sloosh-iOS\sloosh\Sources\Data\Repositories\HlsProxyServer.swift`, lines 261–285
  - Serves `/local/` directory files (`.m3u8`, `.ts`, `.bin`) from `documentDirectory`.
- **File**: `W:\iOS-sloosh\sloosh-iOS\sloosh\Sources\UI\Player\PlayerView.swift`, lines 414–427, 1153–1158, 1202–1206
  - Accepts `directStreamUrl` via local proxy, sets `isLocalPlayback = true`, enables `setupImageGenerator`, sets `currentQualityKey = "Локальный"`.
- **File**: `W:\iOS-sloosh\sloosh-iOS\sloosh\Sources\UI\Details\DetailsView.swift`, lines 302–313
  - Compares `downloadItem.translationName == translation.name`. Plays offline if translation matches; falls back to online streaming if user requests a different translation.

---

## 2. Logic Chain

1. **Voiceover Fidelity**:
   - `item.iframeUrl` is obtained from `translation.iframeUrl`, which contains the exact translation query parameter.
   - `AllohaRuntimeResolver` resolves that iframe URL into a stream specifically corresponding to that translation in `resolved["url"]`.
   - Overriding `streamUrlString` with an entry from `resolved["audioVariants"]` is unnecessary and harmful because `audioVariants` may have mismatched names or point to non-master URLs (e.g. `720.m3u8`).
   - Removing the `audioVariants` override guarantees that the downloaded stream matches the exact translation selected by the user.

2. **Quality Selection Fidelity**:
   - `DownloadManager` needs to evaluate both explicit `resolved["qualityVariants"]` and the master playlist `#EXT-X-STREAM-INF` variants.
   - If `prepareAndEnqueue` checks `resolved["qualityVariants"]` matching the preferred quality, it can select the exact stream URL directly.
   - When parsing master playlists, extracting `BANDWIDTH`, `RESOLUTION`, and URL filename hints ensures accurate metadata.
   - Filtering AV1 streams prevents downloading streams that fail to render on Apple Silicon/iOS VideoToolbox.
   - Sorting candidates by highest available resolution $\le \text{targetHeight}$ (with bandwidth tie-breaking) guarantees that 1080p downloads in 1080p whenever available, and gracefully selects 720p only if 1080p does not exist.

3. **Offline Playback Consistency**:
   - `local.m3u8` references `key.bin` and `segment_*.ts`.
   - `HlsProxyServer` serves these with standard MIME types.
   - AVPlayer decrypts and plays the local stream identically to online playback, preserving the exact audio track and video resolution.

---

## 3. Caveats

1. **Network Authentication / Expiring Tokens**:
   - HLS segments are downloaded immediately upon enqueuing. If an item remains pending for a long duration before segments are queued, segment token expiration depends on CDN TTL. Manifest retry mechanism handles up to 3 retries.
2. **Device Display Constraints**:
   - Downloads are capped at 1080p (Full HD) to prevent excessive disk usage and decoding overhead on mobile devices, matching the app's `VideoQualityPreference` specification (`.q1080`, `.q720`, `.q480`, `.q360`).

---

## 4. Conclusion

- In `DownloadManager.prepareAndEnqueue`, removing the `audioVariants` matching and using `resolved["url"]` directly eliminates voiceover mismatch and prevents accidental downgrading to 720p.
- In `DownloadManager.chooseMediaPlaylistUrl`, adding BANDWIDTH parsing, filename resolution fallbacks, AV1 codec filtering, and a top-down $\le \text{targetHeight}$ resolution sorter guarantees downloading at the highest matching resolution up to user preference without downgrading.
- The packaging and offline playback pipeline in `DownloadManager`, `HlsProxyServer`, and `PlayerView` is robust and correctly preserves voiceover and quality fidelity.

---

## 5. Verification Method

1. **Unit / Logic Verification**:
   - Inspect `sloosh-iOS/sloosh/Sources/Data/Repositories/DownloadManager.swift`:
     - Verify `prepareAndEnqueue` uses `resolved["url"]` without `audioVariants` override.
     - Verify `chooseMediaPlaylistUrl` parses `BANDWIDTH`, extracts resolution from `#EXT-X-STREAM-INF` and URLs, filters AV1, and selects highest $\le \text{targetHeight}$.
2. **Scenario Testing**:
   - Download a movie/series with "Дублированный" at 1080p.
   - Verify `local.m3u8` is populated from the 1080p variant.
   - Enable Airplane Mode / offline state.
   - Open `DownloadsView` and play the item. Verify audio track matches "Дублированный" and video resolution is 1080p.
   - Open `DetailsView` for the same title while online. Selecting "Дублированный" plays offline local stream; selecting "LostFilm" streams LostFilm online.
