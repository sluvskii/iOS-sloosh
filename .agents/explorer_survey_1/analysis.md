# Detailed Analysis: Player & Source Selection UI Layer

## Overview & Scope
This investigation analyzes the Player & Source Selection UI layer in W:\iOS-sloosh\sloosh-iOS\sloosh\Sources\ to diagnose and solve:
1. Voiceover selection fidelity between SourceSelectionView, DetailsView, and PlayerView.
2. Overwrite of vailableVoiceovers in pplyResolvedAllohaStream by internal WKWebView udioVariants.
3. In-player voiceover switching in VoiceoverPickerSheet / PlayerViewModel.switchVoiceover with seamless position preservation.
4. Voiceover preservation and graceful fallback during episode navigation (Next Episode button, Autoplay, Episode changes).

---

## 1. Architecture & Data Flow

### 1.1 Source Hierarchy & Models
- AllohaApiResult (Data/Repositories/AllohaRepository.swift):
  - isSerial: Bool
  - movie: AllohaMovie? containing 	ranslations: [AllohaTranslation]
  - seasons: [AllohaSeason] where each season contains episodes: [AllohaEpisode], and each episode contains 	ranslations: [AllohaTranslation]
  - llTranslationNames: [String]: Unique sorted list of all translation names across all seasons/episodes or movie translations.
- AllohaTranslation:
  - id: String
  - 
ame: String (e.g., Дублированный, LostFilm, HDRezka Studio, Кубик в кубе)
  - iframeUrl: String (e.g., https://alloha.tv/.../?translation=123)
  - streamUrl: String? (Optional pre-resolved direct HLS stream URL)

### 1.2 Flow: SourceSelectionView -> DetailsView -> PlayerView
1. **SourceSelectionView (UI/Details/SourceSelectionView.swift)**:
   - esult: AllohaApiResult, kpId: Int?, details: MediaDetailsDto?
   - User chooses Season (if TV show), Episode (if TV show), and Translation 	Name from chips/buttons.
   - inishAction(quality:) (lines 207-233):
     - For series: Finds 	ranslation in epObj.translations.first(where: { allohaTranslationNamesMatch(.name, tName, exactOnly: true) }).
     - For movie: Finds 	ranslation in movie.translations.first(where: { .name == tName }).
     - Saves PlaybackProgressStore.shared.saveLastPlayed(kpId: season: episode:) and saveLastVoiceover(kpId: source: alloha, voiceover: translation.name).
     - Invokes onAction(translation, season, episode, quality).
2. **DetailsView (UI/Details/DetailsView.swift)**:
   - In sheet(isPresented: ) (lines 293-318):
     `swift
     playerKpId = wrapper.kpId
     playerSeason = season
     playerEpisode = episode
     playerQuality = quality
     playerSeriesResult = result
     playerVoices = result.allTranslationNames
     selectedIframeUrl = translation.iframeUrl
     playerVoiceover = translation.name
     playerStreamUrl = translation.streamUrl
     pendingPlayerLaunch = true
     `
   - In ullScreenCover(isPresented: ) (lines 352-357):
     `swift
     PlayerView(
         iframeUrl: iframeUrl,
         fallbackTitle: details.title ?? details.originalTitle ?? ",
 kpId: playerKpId,
 season: playerSeason,
 episode: playerEpisode,
 selectedVoiceover: playerVoiceover,
 directStreamUrl: playerStreamUrl,
 voices: playerVoices,
 subtitles: playerSubtitles,
 initialQuality: playerQuality,
 seriesResult: playerSeriesResult
 )
 `
3. **Other Call Sites**:
 - HomeDirectPlayWrapper.swift (lines 34-49): Passes seriesResult: result, oices: result.allTranslationNames, oiceover: translation.name, iframeUrl: translation.iframeUrl, streamUrl: translation.streamUrl.
 - ContinueView.swift (lines 72-85, 441-477): Resolves AllohaApiResult, sets seriesResult: result, oiceover: translation.name, iframeUrl: translation.iframeUrl, oices: result.allTranslationNames.
 - DownloadsView.swift (lines 147-155): Plays offline local HLS with directStreamUrl and selectedVoiceover: item.translationName.

---

## 2. Voiceover State Lifecycle & Initialization

In PlayerView.swift (PlayerViewModel):
- Properties:
 - @Published var availableVoiceovers: [String] = []
 - ar currentTranslationName: String? { _currentTranslationName }
 - private var _currentTranslationName: String?
 - private var targetVoiceover: String?
 - ar seriesResult: AllohaApiResult?

### 2.1 Initialization in eginLoad (lines 359-408):
`swift
self.targetVoiceover = selectedVoiceover
self._currentTranslationName = selectedVoiceover

if let seriesResult = self.seriesResult, let s = season, let e = episode {
 if let seasonObj = seriesResult.seasons.first(where: { .season == s }),
 let epObj = seasonObj.episodes.first(where: { .episode == e }) {
 self.availableVoiceovers = epObj.translations.map { .name }
 }
} else if !voices.isEmpty {
 self.availableVoiceovers = voices
}
`
**Identified Gap**:
If seriesResult is a movie (isMovie == true, movie != nil, season == nil, episode == nil), the if let seriesResult = self.seriesResult, let s = season, let e = episode condition is false. If oices is empty, vailableVoiceovers is not populated from seriesResult.movie?.translations.
**Fix**: Check seriesResult.movie explicitly when s == nil && e == nil.

---

## 3. Root Cause Analysis: Overwrite in pplyResolvedAllohaStream

### 3.1 Mechanism of Failure
In PlayerView.swift (lines 1854-1860):
`swift
self.resolvedAudioVariants = audioVariants
let voices = resolvedVoiceovers(from: resolved)
if !voices.isEmpty {
 self.availableVoiceovers = voices
}
`
And esolvedVoiceovers(from: resolved) (lines 1916-1929):
`swift
private func resolvedVoiceovers(from resolved: [String: Any]) -> [String] {
 let variants = (resolved[audioVariants] as? [[String: Any]]) ?? []
 var seen = Set<String>()
 return variants.compactMap { variant in
 let title = (variant[title] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? 
 guard !title.isEmpty else { return nil }
 let cleanTitle = normalizedAllohaTranslationName(title).isEmpty ? title : normalizedAllohaTranslationName(title)
 let lower = cleanTitle.lowercased()
 if lower.contains(субтитр) || lower.contains(subtitle) {
 return nil
 }
 return seen.insert(cleanTitle).inserted ? cleanTitle : nil
 }
}
`
And in syncNativeAudioTracks() (lines 2047-2050):
`swift
if updatedVoiceovers != self.availableVoiceovers {
 self.availableVoiceovers = updatedVoiceovers
 logDebug(syncNativeAudioTracks: updated availableVoiceovers=\(self.availableVoiceovers))
}
`

### 3.2 Root Cause Explanation
1. AllohaApiResult provides the complete, authoritative list of studio translations (e.g. 10 translations for Локи: [Дублированный, HDRezka Studio, LostFilm, NewStudio, Кубик в Кубе, ...]).
2. When AllohaRuntimeResolver loads the iframe URL (e.g., https://alloha.tv/.../?translation=123), the underlying WKWebView evaluates Alloha's player page, which only contains the hlsSource for that single requested translation, or internal tracks labeled Озвучка 1, DUB, Russian 1.
3. pplyResolvedAllohaStream then overwrites self.availableVoiceovers = voices with those 1-2 partial/internal labels.
4. Consequence:
 - If vailableVoiceovers.count drops to 1, BottomRowView.swift (line 28: if vm.availableVoiceovers.count > 1) hides the voiceover waveform button entirely.
 - If vailableVoiceovers has 2 items, it shows Озвучка 1, Озвучка 2 instead of Дублированный, LostFilm, etc.
 - syncNativeAudioTracks() further pollutes the list with raw manifest strings like Russian 1.

---

## 4. In-Player Voiceover Switching (VoiceoverPickerSheet & switchVoiceover)

### 4.1 How VoiceoverPickerSheet Works
In PlayerPickerSheets.swift (lines 6-23):
`swift
struct VoiceoverPickerSheet: View {
 @ObservedObject var vm: PlayerViewModel
 @Environment(\.dismiss) private var dismiss

 var body: some View {
 PopoverContainer(title: Озвучка) {
 ForEach(Array(vm.availableVoiceovers.enumerated()), id: \.offset) { idx, name in
 popoverRow(
 label: displayTranslationName(name, at: idx, in: vm.availableVoiceovers),
 isSelected: vm.currentTranslationName == name
 ) {
 vm.switchVoiceover(to: name, at: idx)
 dismiss()
 }
 }
 }
 }
}
`

### 4.2 Deficiencies in switchVoiceover(to:at:) (lines 785-884)
1. **Mismatched Index in Step 1**:
 if let idx = index, idx < resolvedAudioVariants.count { targetStreamUrl = resolvedAudioVariants[idx][url] as? String }
 idx is the index into vailableVoiceovers (AllohaTranslation list), NOT esolvedAudioVariants. This mapped to unrelated or invalid stream URLs.
2. **Loss of Playback Position in Step 2**:
 When switching voiceover by resolving a new iframeUrl, switchVoiceover called eginLoad(...).
 eginLoad wiped self.currentTime = 0; self.currentDuration = 0.
 This caused playback to restart from 0:00 instead of resuming at the exact playback position.
3. **Missing Direct Stream URL Optimization**:
 If the target AllohaTranslation has a pre-resolved streamUrl, it can be reloaded immediately via eloadPlayback(to:streamUrl) at the current playback position without waiting for WKWebView re-resolution.
4. **Resolution via Runtime Resolver**:
 If resolving iframeUrl is needed, the current position currentPos = player?.currentTime().seconds ?? currentTime must be preserved and restored once the new stream becomes .readyToPlay.

---

## 5. Episode Navigation & Voiceover Preservation

### 5.1 Episode Advance Mechanisms
- **Autoplay**: handlePlaybackEnded() -> playNextEpisode().
- **Next / Prev Buttons**: CenterControlsView.swift -> m.playNextEpisode() / m.playPreviousEpisode().
- **Episode Selection in DetailsView**: handleEpisodeSelection(...) -> sets lastPlayed and opens SourceSelectionView on that episode.

### 5.2 Preservation Logic in preferredTranslation(in episode:)
In PlayerView.swift (lines 1787-1810):
`swift
private func preferredTranslation(in episode: AllohaEpisode) -> AllohaTranslation? {
 if let name = _currentTranslationName,
 let match = episode.translations.first(where: { allohaTranslationNamesMatch(.name, name) }) {
 return match
 }

 if let targetVoiceover,
 let match = episode.translations.first(where: { allohaTranslationNamesMatch(.name, targetVoiceover) }) {
 return match
 }

 if let kpId = currentKpId,
 let saved = PlaybackProgressStore.shared.loadLastVoiceover(kpId: kpId, source: alloha),
 let match = episode.translations.first(where: { allohaTranslationNamesMatch(.name, saved) }) {
 return match
 }

 if let globalSaved = UserDefaults.standard.string(forKey: alloha_last_translation_name),
 let match = episode.translations.first(where: { allohaTranslationNamesMatch(.name, globalSaved) }) {
 return match
 }

 return episode.translations.first
}
`

### 5.3 Fallback Handling in playEpisode
In playEpisode (lines 1715-1724):
`swift
let preferredName = targetVoiceover ?? _currentTranslationName ?? (currentKpId.flatMap { PlaybackProgressStore.shared.loadLastVoiceover(kpId: , source: alloha) })
if let preferredName, allohaTranslationNamesMatch(episode.translation.name, preferredName) {
 _currentTranslationName = episode.translation.name
 targetVoiceover = episode.translation.name
 persistVoiceoverSelection(episode.translation.name)
} else if _currentTranslationName == nil {
 _currentTranslationName = episode.translation.name
 targetVoiceover = episode.translation.name
}
`
**Issue**: When the user's preferred voiceover is not available in the new episode and it falls back to episode.translations.first, _currentTranslationName was not updated to reflect the fallback translation that is actually playing.
**Fix**: Update _currentTranslationName = episode.translation.name so UI and NowPlaying accurately reflect what is playing, while preserving userPreferredVoiceover (or argetVoiceover) so subsequent episodes can automatically restore the user's preferred studio when available.

---

## 6. Recommendations & Proposed Code Changes

### Recommendation 1: Never overwrite vailableVoiceovers if populated from AllohaApiResult / oices
In PlayerView.swift pplyResolvedAllohaStream:
`swift
// Only populate availableVoiceovers from resolvedAudioVariants if availableVoiceovers is currently empty
if self.availableVoiceovers.isEmpty {
 let voices = resolvedVoiceovers(from: resolved)
 if !voices.isEmpty {
 self.availableVoiceovers = voices
 }
}
`
And in syncNativeAudioTracks():
Do not mutate vailableVoiceovers if it was already populated from AllohaApiResult.

### Recommendation 2: Robust vailableVoiceovers initialization for movies and series
In PlayerView.swift eginLoad:
`swift
if let seriesResult = self.seriesResult {
 if let s = season, let e = episode,
 let seasonObj = seriesResult.seasons.first(where: { .season == s }),
 let epObj = seasonObj.episodes.first(where: { .episode == e }) {
 self.availableVoiceovers = epObj.translations.map { .name }
 } else if let movie = seriesResult.movie {
 self.availableVoiceovers = movie.translations.map { .name }
 }
} else if !voices.isEmpty {
 self.availableVoiceovers = voices
}
`

### Recommendation 3: Seamless Voiceover Switching with Playback Position Preservation
In PlayerView.swift switchVoiceover:
1. Find target AllohaTranslation in seriesResult for current episode or movie.
2. Capture current playback time: let savedTime = self.player?.currentTime().seconds ?? self.currentTime.
3. If ranslation.streamUrl is present, directly reload with eloadPlayback(to: streamUrl) (which preserves savedTime).
4. If ranslation.iframeUrl is present, resolve iframeUrl asynchronously while maintaining savedTime, and seek to savedTime once .readyToPlay.

### Recommendation 4: Graceful Fallback & Active Voiceover Sync
In PlayerView.swift playEpisode:
- Always set _currentTranslationName = episode.translation.name.
- If the new episode matches userPreferredVoiceover, persist it.
- Keep userPreferredVoiceover stored so future episodes restore it when available.
