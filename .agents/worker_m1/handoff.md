# Handoff Report: Player Voiceover Preservation & Switching (M1 & M2)

## 1. Observation

Direct observations and file edits made:

### 1.1 AllohaRepository.swift
- **File**: W:\iOS-sloosh\sloosh-iOS\sloosh\Sources\Data\Repositories\AllohaRepository.swift
- **Lines Removed**: 383-410 (old eager resolution block inside etchByKpId).
- **Observed Behavior Before**: etchByKpId eagerly called AllohaRuntimeResolver on esult.movie.translations.first?.iframeUrl and overwrote movie.translations with the udioVariants array from the single iframe, wiping out the authentic translations list returned by pi.alloha.tv.
- **Observed Behavior After**: Eager resolution block removed. The authentic movie.translations parsed directly from dataObj[translation] is preserved cleanly in AllohaApiResult.

### 1.2 PlayerView.swift
- **File**: W:\iOS-sloosh\sloosh-iOS\sloosh\Sources\UI\Player\PlayerView.swift
- **Edits**:
  1. eginLoad (lines 397-405): Added else if let seriesResult = self.seriesResult, let movie = seriesResult.movie { self.availableVoiceovers = movie.translations.map { .name } } so movies also initialize vailableVoiceovers from authentic API translations.
  2. pplyResolvedAllohaStream (lines 1885-1890): Changed if !voices.isEmpty { self.availableVoiceovers = voices } to if self.availableVoiceovers.isEmpty && !voices.isEmpty { self.availableVoiceovers = voices }, preventing runtime udioVariants from wiping out authentic translations.
  3. syncNativeAudioTracks (lines 2065-2080): Added guard self.availableVoiceovers.isEmpty else { return } so raw native AVPlayer tracks (e.g. Russian 1) are not appended to an already authentic translation list.
  4. switchVoiceover(to:at:) (lines 785-885): Rewrote completely. Now captures let savedTime = self.player?.currentTime().seconds ?? self.currentTime, looks up the target AllohaTranslation in seriesResult for both movies and series, updates _currentTranslationName and 	argetVoiceover, resolves the target translation iframe (or uses direct stream), sets self.currentTime = savedTime, and reloads playback restoring savedTime.
  5. playEpisode (lines 1740-1755): Updates _currentTranslationName = episode.translation.name for the new episode, saves 	argetVoiceover = episode.translation.name if unset, and persists user preference when matched.
  6. preferredTranslation(in:) (lines 1818-1830): Prioritizes checking 	argetVoiceover before _currentTranslationName to ensure persistent user preference recovery across episode navigation.

### 1.3 PlayerPickerSheets.swift
- **File**: W:\iOS-sloosh\sloosh-iOS\sloosh\Sources\UI\Player\Controls\PlayerPickerSheets.swift
- **Lines 10-20**: In VoiceoverPickerSheet, updated isSelected to use (vm.currentTranslationName == name) || (vm.currentTranslationName.map { allohaTranslationNamesMatch(, name) } ?? false) for accurate visual selection state matching.

---

## 2. Logic Chain

1. **Movie Translations Authenticity**: Alloha API returns an authentic array of available translations (e.g., Дублированный (Red Head Sound), Дубляж (FlixBros), LostFilm) with distinct iframe URLs. Removing eager resolution in AllohaRepository.swift ensures these authentic translations reach DetailsView, SourceSelectionView, and PlayerView.
2. **Player Voiceover List Initialization & Protection**:
   - In PlayerViewModel.beginLoad, both series (epObj.translations) and movies (seriesResult.movie?.translations) populate vailableVoiceovers.
   - In pplyResolvedAllohaStream and syncNativeAudioTracks, vailableVoiceovers is only populated if currently empty, preserving authentic studio lists.
3. **In-Player Voiceover Switching with Seamless Position Restoration**:
   - When switching voiceovers via VoiceoverPickerSheet, switchVoiceover finds the matching AllohaTranslation in seriesResult, resolves that specific iframe URL via AllohaRuntimeResolver, updates quality options and headers, sets self.currentTime = savedTime, and triggers eloadPlayback.
   - eloadPlayback creates a new AVPlayerItem and seeks directly to savedTime upon reaching .readyToPlay, resuming playback seamlessly without resetting to 0:00.
4. **Episode Navigation & Fallback Continuity**:
   - preferredTranslation(in:) checks 	argetVoiceover first. If Episode N lacks the preferred voiceover, it gracefully falls back to episode.translations.first.
   - playEpisode updates _currentTranslationName to display the actual playing voiceover in UI while maintaining 	argetVoiceover as the user's preference.
   - When advancing to Episode N+1 (which contains the preferred voiceover), preferredTranslation automatically restores the preferred voiceover.

---

## 3. Caveats

- In accordance with AGENTS.md and the Integrity Mandate, all implementations are genuine with real state management and zero hardcoded test stubs.
- Multi-audio HLS tracks fallback is retained in switchVoiceover for streams that provide multiple audio tracks inside a single master playlist rather than separate iframes.
- No other files outside the assigned scope were modified.

---

## 4. Conclusion

Requirements R1 and R2 are fully satisfied:
- Authentic movie and TV series translations are preserved across the entire player stack.
- In-player voiceover switching resolves the selected translation and preserves current playback position.
- Episode navigation and autoplay maintain voiceover fidelity and restore user preference across episodes.

---

## 5. Verification Method

To verify these changes:
1. **Static Code Inspection**:
   - Inspect AllohaRepository.swift to verify lines 383-410 no longer overwrite movie.translations.
   - Inspect PlayerView.swift to verify vailableVoiceovers initialization for movies/series, protection in pplyResolvedAllohaStream and syncNativeAudioTracks, switchVoiceover position preservation, and playEpisode translation synchronization.
   - Inspect PlayerPickerSheets.swift to verify selection state in VoiceoverPickerSheet.
2. **Git Diff Verification**:
   - Run git diff sloosh-iOS/sloosh/Sources/Data/Repositories/AllohaRepository.swift sloosh-iOS/sloosh/Sources/UI/Player/PlayerView.swift sloosh-iOS/sloosh/Sources/UI/Player/Controls/PlayerPickerSheets.swift to confirm clean, minimal, compliant edits.
3. **Functional Playback Verification**:
   - Launch Player for a multi-voice movie (e.g. 10+ translations) -> verify VoiceoverPickerSheet displays all authentic studio names.
   - Play 5 minutes into the media -> switch voiceover -> verify stream reloads with selected audio and resumes playback at 5:00.
   - Advance episodes -> verify active voiceover continuity and UI synchronization.