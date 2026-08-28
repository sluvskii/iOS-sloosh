# Self-Contained Handoff Report: Player & Source Selection UI Layer

## 1. Observation

### 1.1 Source Selection & Presentation Flow
- **UI/Details/SourceSelectionView.swift (lines 207-233)**:
  `swift
  func finishAction(quality: VideoQualityPreference) {
      if result.isSerial {
          guard let s = selectedSeason, let e = selectedEpisode, let tName = selectedTranslationName else { return }
          guard let seasonObj = result.seasons.first(where: { .season == s }),
                let epObj = seasonObj.episodes.first(where: { .episode == e }),
                let translation = epObj.translations.first(where: { allohaTranslationNamesMatch(.name, tName, exactOnly: true) }) else { return }
          
          if mode == .play, let kpId = kpId {
              PlaybackProgressStore.shared.saveLastPlayed(kpId: kpId, season: s, episode: e)
              PlaybackProgressStore.shared.saveLastVoiceover(kpId: kpId, source: alloha, voiceover: translation.name)
          }
          
          onAction(translation, s, e, quality)
          dismiss()
      } else if let movie = result.movie {
          guard let tName = selectedTranslationName,
                let translation = movie.translations.first(where: { .name == tName }) else { return }
          
          if mode == .play, let kpId = kpId {
              PlaybackProgressStore.shared.saveLastPlayed(kpId: kpId, season: nil, episode: nil)
              PlaybackProgressStore.shared.saveLastVoiceover(kpId: kpId, source: alloha, voiceover: translation.name)
          }
          
          onAction(translation, nil, nil, quality)
          dismiss()
      }
  }
  `
- **UI/Details/DetailsView.swift (lines 293-317 & 352-357)**:
  SourceSelectionView passes (translation, season, episode, quality) -> DetailsView populates playerKpId = wrapper.kpId, playerSeason = season, playerEpisode = episode, playerQuality = quality, playerSeriesResult = result, playerVoices = result.allTranslationNames, selectedIframeUrl = translation.iframeUrl, playerVoiceover = translation.name, playerStreamUrl = translation.streamUrl.
  PlayerView is then instantiated with these exact arguments.

### 1.2 Voiceover Overwrite in PlayerView
- **UI/Player/PlayerView.swift (lines 397-404 in eginLoad)**:
  `swift
  if let seriesResult = self.seriesResult, let s = season, let e = episode {
      if let seasonObj = seriesResult.seasons.first(where: { .season == s }),
         let epObj = seasonObj.episodes.first(where: { .episode == e }) {
          self.availableVoiceovers = epObj.translations.map { .name }
      }
  } else if !voices.isEmpty {
      self.availableVoiceovers = voices
  }
  `
- **UI/Player/PlayerView.swift (lines 1854-1860 in pplyResolvedAllohaStream)**:
  `swift
  self.resolvedAudioVariants = audioVariants
  let voices = resolvedVoiceovers(from: resolved)
  if !voices.isEmpty {
      self.availableVoiceovers = voices
  }
  `
- **UI/Player/PlayerView.swift (lines 1916-1929 in esolvedVoiceovers)**:
  esolvedVoiceovers extracts strings from WKWebView esolved[audioVariants]. These variants are extracted from internal hlsSource DOM items and contain only 1-2 generic entries (such as Озвучка 1, DUB), completely replacing the authentic 10+ translation names previously populated in vailableVoiceovers.
- **UI/Player/PlayerView.swift (lines 2047-2050 in syncNativeAudioTracks)**:
  Appends raw AVPlayer group.options.map { .displayName } (e.g. Russian 1) to vailableVoiceovers.

### 1.3 In-Player Voiceover Switching & Playback Position Loss
- **UI/Player/Controls/PlayerPickerSheets.swift (lines 6-23 in VoiceoverPickerSheet)**:
  `swift
  ForEach(Array(vm.availableVoiceovers.enumerated()), id: \.offset) { idx, name in
      popoverRow(
          label: displayTranslationName(name, at: idx, in: vm.availableVoiceovers),
          isSelected: vm.currentTranslationName == name
      ) {
          vm.switchVoiceover(to: name, at: idx)
          dismiss()
      }
  }
  `
- **UI/Player/PlayerView.swift (lines 788-858 in switchVoiceover)**:
  `swift
  // 1. Быстрое переключение через resolvedAudioVariants (прямые HLS ссылки от Alloha)
  var targetStreamUrl: String?
  if !resolvedAudioVariants.isEmpty {
      if let idx = index, idx < resolvedAudioVariants.count {
          targetStreamUrl = resolvedAudioVariants[idx][url] as? String
      } else if let variant = resolvedAudioVariants.first(where: {
          let vTitle = ([title] as? String) ?? "
 return allohaTranslationNamesMatch(vTitle, name)
 }) {
 targetStreamUrl = variant[url] as? String
 }
 }
 ...
 // 2. Ищем iframeUrl для нужной озвучки из Alloha DTO
 ...
 beginLoad(
 iframeUrl: iframeUrl,
 kpId: currentKpId,
 season: currentSeason,
 episode: currentEpisode,
 selectedVoiceover: name
 )
 `
 - Index mismatch: idx from vailableVoiceovers (AllohaTranslation list) is used as an index into esolvedAudioVariants (unrelated internal WKWebView array).
 - Position reset: eginLoad executes self.currentTime = 0; self.currentDuration = 0 (lines 388-389), destroying current playback position.

### 1.4 Episode Navigation & Fallback
- **UI/Player/PlayerView.swift (lines 1714-1724 in playEpisode)**:
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
 When the next episode lacks the active voiceover and falls back to episode.translations.first, _currentTranslationName is NOT updated, creating a mismatch between what is playing and what is reported in UI/NowPlaying.

---

## 2. Logic Chain

1. **Initial State Fidelity**: SourceSelectionView allows users to select exact translations from AllohaApiResult. It forwards ranslation.name, ranslation.iframeUrl, seriesResult, and llTranslationNames to PlayerView.
2. **First Defect (Movie voices initialization)**: In PlayerViewModel.beginLoad, vailableVoiceovers is set for series via seriesResult.seasons, but for movies (seriesResult.movie != nil), it only falls back to oices. If oices is not provided, vailableVoiceovers is empty.
3. **Second Defect (Destructive Overwrite)**: In pplyResolvedAllohaStream, self.availableVoiceovers = voices replaces the full translation list with whatever 1-2 audio variants WKWebView parsed from the single translation page. This collapses the voiceover options down to 1 item (hiding the waveform icon in BottomRowView) or replaces recognizable studio names with generic labels like Озвучка 1.
4. **Third Defect (Broken Voiceover Switcher)**:
 - switchVoiceover attempts to index into esolvedAudioVariants using the vailableVoiceovers index idx. Because the arrays have different lengths and different contents, this loads the wrong variant.
 - When switchVoiceover falls back to eginLoad(iframeUrl:), eginLoad sets currentTime = 0, resetting the user to the start of the media.
5. **Fourth Defect (Episode Fallback Inconsistency)**:
 - When navigating to the next episode where the preferred voiceover does not exist, preferredTranslation falls back to episode.translations.first.
 - However, playEpisode failed to update _currentTranslationName to the fallback translation name because of the conditional guard if let preferredName, allohaTranslationNamesMatch(...).
 - Consequently, the player UI reports the previous episode's translation while playing the fallback audio.

---

## 3. Caveats
- No changes were made directly to Swift source files during this investigation (read-only mode).
- Offline download playback (DownloadsView.swift) bypasses AllohaRuntimeResolver and passes directStreamUrl directly to PlayerView; direct playback behaves correctly as long as vailableVoiceovers is not overwritten.
- Multi-audio HLS streams (containing multiple #EXT-X-MEDIA:TYPE=AUDIO tracks inside a single master playlist) still work with AVPlayer media selection, but Alloha primarily delivers distinct voiceovers via distinct translation iframe URLs (?translation=<id>).

---

## 4. Conclusion & Recommended Fixes

### 4.1 Fix 1: Protect vailableVoiceovers from being overwritten in PlayerView.swift
In pplyResolvedAllohaStream (around line 1856):
`swift
// Only populate availableVoiceovers from resolvedAudioVariants if availableVoiceovers is empty
if self.availableVoiceovers.isEmpty {
 let voices = resolvedVoiceovers(from: resolved)
 if !voices.isEmpty {
 self.availableVoiceovers = voices
 }
}
`
In syncNativeAudioTracks (around line 2035):
Do not append native track strings to vailableVoiceovers if vailableVoiceovers was already populated from seriesResult or oices.

### 4.2 Fix 2: Initialize vailableVoiceovers for movies and series in eginLoad
In eginLoad (lines 397-404):
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

### 4.3 Fix 3: Rewrite switchVoiceover with Position Preservation
In switchVoiceover(to:at:):
`swift
func switchVoiceover(to name: String, at index: Int? = nil) {
 logDebug(switchVoiceover: switching to '\(name)')
 let savedTime = self.player?.currentTime().seconds ?? self.currentTime
 let wasPlaying = player?.timeControlStatus == .playing || player?.timeControlStatus == .waitingToPlayAtSpecifiedRate

 // 1. Find target AllohaTranslation from seriesResult
 var targetTranslation: AllohaTranslation?
 if isMovie {
 targetTranslation = seriesResult?.movie?.translations.first(where: { allohaTranslationNamesMatch(.name, name) })
 } else if let seriesResult, let s = currentSeason, let e = currentEpisode,
 let seasonObj = seriesResult.seasons.first(where: { .season == s }),
 let epObj = seasonObj.episodes.first(where: { .episode == e }) {
 targetTranslation = epObj.translations.first(where: { allohaTranslationNamesMatch(.name, name) })
 }

 guard let translation = targetTranslation else {
 // Fallback to AVPlayer native track selection if no separate Alloha translation exists
 selectAudioTrackInPlayer(named: name)
 return
 }

 _currentTranslationName = translation.name
 targetVoiceover = translation.name
 persistVoiceoverSelection(translation.name)

 // Direct pre-resolved stream
 if let streamUrlString = translation.streamUrl, let streamUrl = URL(string: streamUrlString) {
 reloadPlayback(to: streamUrl, preferredPeakBitRate: player?.currentItem?.preferredPeakBitRate)
 return
 }

 // Resolve target translation iframe and reload preserving position
 let iframeUrl = translation.iframeUrl
 guard !iframeUrl.isEmpty else { return }

 AllohaRuntimeResolver.invalidateCache(for: iframeUrl)
 resolveTask?.cancel()
 resolver?.cancel()

 isLoading = true
 let resolver = AllohaRuntimeResolver()
 self.resolver = resolver

 resolveTask = Task { [weak self] in
 do {
 let resolved = try await resolver.resolve(iframeUrl: iframeUrl)
 guard let self, !Task.isCancelled else { return }
 
 var resolvedUrlString = (resolved[url] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? 
 guard let resolvedUrl = URL(string: resolvedUrlString) else {
 self.error = Не удалось извлечь ссылку на видео
 self.isLoading = false
 return
 }

 let headers = (resolved[headers] as? [String: String]) ?? [:]
 self.currentHeaders = headers
 
 // Reload playback and restore savedTime
 self.currentTime = savedTime
 self.reloadPlayback(to: resolvedUrl, preferredPeakBitRate: self.player?.currentItem?.preferredPeakBitRate)
 } catch {
 guard let self, !Task.isCancelled else { return }
 self.error = Не удалось переключить озвучку
 self.isLoading = false
 }
 }
}
`

### 4.4 Fix 4: Synchronize Active Voiceover and Maintain User Preference on Episode Advance
In playEpisode:
`swift
_currentTranslationName = episode.translation.name
if let pref = targetVoiceover, allohaTranslationNamesMatch(episode.translation.name, pref) {
 persistVoiceoverSelection(episode.translation.name)
}
`
And keep argetVoiceover as the user's explicit preference so that if episode N lacked the translation but episode N+1 has it, preferredTranslation will automatically restore it.

---

## 5. Verification Method

### 5.1 Static Verification & Inspection
1. Inspect UI/Player/PlayerView.swift to verify vailableVoiceovers is initialized from seriesResult for both TV episodes and movies, and is not overwritten by pplyResolvedAllohaStream.
2. Inspect switchVoiceover to verify that selecting a studio from VoiceoverPickerSheet resolves the target translation's iframe URL, preserves savedTime, and restores playback at savedTime.
3. Inspect playEpisode to verify _currentTranslationName is updated to episode.translation.name.

### 5.2 Build & Functional Testing
- **Compilation Check**:
 Build the project via GitHub Actions CI or Swift toolchain.
- **Scenario 1 (Multi-voice title, e.g. Локи)**:
 - Open Details -> tap Смотреть -> select Дублированный in SourceSelectionView.
 - Verify Player starts playback with Дублированный.
 - Open in-player voiceover popover (waveform icon): verify all studios (Дублированный, LostFilm, HDRezka Studio, etc.) are listed with Дублированный checked.
- **Scenario 2 (In-player voiceover switch)**:
 - Play 5 minutes into the movie/episode.
 - Open voiceover popover and select LostFilm.
 - Verify stream reloads with LostFilm audio and playback resumes at 5:00.
- **Scenario 3 (Episode advance & fallback)**:
 - Play Episode 1 with a chosen voiceover.
 - Advance to Episode 2: verify the chosen voiceover is preserved. If missing in Episode 2, verify fallback to first available translation and _currentTranslationName displays the fallback. Advance to Episode 3 (which has the voiceover) and verify automatic recovery to the preferred voiceover.
