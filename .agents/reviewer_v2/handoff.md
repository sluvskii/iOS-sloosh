# Handoff Report: Reviewer v2 Code Review & Verdict (M1 V2 Fix)

## 1. Observation

1. **`PlayerView.swift` (`PlayerViewModel.beginLoad`, lines 381–383, 410–416)**:
   - `self.targetVoiceover` assignment is guarded:
     ```swift
     if self.targetVoiceover == nil {
         self.targetVoiceover = selectedVoiceover
     }
     ```
   - Persistence is guarded:
     ```swift
     if kpId != nil, let selectedVoiceover, !selectedVoiceover.isEmpty {
         if let pref = targetVoiceover, allohaTranslationNamesMatch(selectedVoiceover, pref) {
             persistVoiceoverSelection(selectedVoiceover)
         } else if targetVoiceover == nil {
             persistVoiceoverSelection(selectedVoiceover)
         }
     }
     ```
2. **`PlayerView.swift` (`PlayerViewModel.playEpisode`, lines 1753–1760)**:
   - Active playback name `_currentTranslationName` is updated to the episode's actual voiceover (`episode.translation.name`), while `targetVoiceover` is preserved if already set:
     ```swift
     _currentTranslationName = episode.translation.name
     if targetVoiceover == nil {
         targetVoiceover = episode.translation.name
     }
     if let pref = targetVoiceover, allohaTranslationNamesMatch(episode.translation.name, pref) {
         persistVoiceoverSelection(episode.translation.name)
     }
     ```
3. **`PlayerView.swift` (`PlayerViewModel.switchVoiceover`, lines 824–829, 917–920)**:
   - On explicit user selection (either via Alloha translation iframe/stream lookup or native audio track fallback), `targetVoiceover` is explicitly updated to the chosen voiceover and persisted to `PlaybackProgressStore` / `UserDefaults`:
     ```swift
     _currentTranslationName = translation.name
     targetVoiceover = translation.name
     persistVoiceoverSelection(translation.name)
     ```
4. **`PlayerView.swift` (`PlayerViewModel.preferredTranslation`, lines 1824–1847)**:
   - Evaluates `targetVoiceover` with highest priority before considering fallback choices (`_currentTranslationName`, saved progress, or first translation).

## 2. Logic Chain

1. **Sticky User Preference**: When a user selects a voiceover on initial load or via `switchVoiceover`, `targetVoiceover` is set to that preferred voiceover name.
2. **Fallback Navigation Protection**: When advancing or autoplaying to an episode where the preferred voiceover is not available:
   - `preferredTranslation` falls back to available translations (e.g. "LostFilm").
   - `playEpisode` sets `_currentTranslationName = "LostFilm"` so the UI displays the active audio, but leaves `targetVoiceover` untouched (e.g. "Дубляж").
   - `beginLoad` checks `self.targetVoiceover == nil` (false) and does not overwrite `targetVoiceover`.
   - `persistVoiceoverSelection` is skipped because `allohaTranslationNamesMatch("LostFilm", "Дубляж")` is false.
3. **Seamless Preference Recovery**: When advancing to a subsequent episode that contains "Дубляж" again, `preferredTranslation` matches `targetVoiceover` ("Дубляж"), successfully selecting "Дубляж" and restoring the user's preferred audio.
4. **No Side-Effects or Regressions**: No unwanted state mutation occurs; UI reactivity is preserved.

## 3. Caveats

- No caveats. The implementation cleanly isolates active playback display (`_currentTranslationName`) from persistent user preference (`targetVoiceover`).

## 4. Conclusion

**Verdict: APPROVE**

All acceptance criteria and adversarial checks pass:
- `beginLoad` protects `targetVoiceover` from fallback overwrites during episode transitions.
- `beginLoad` and `playEpisode` properly guard persistence against temporary fallback selections.
- `switchVoiceover` updates `targetVoiceover` and persists on explicit user changes.
- Automatic recovery to the user's preferred voiceover on subsequent episodes works as expected.

## 5. Verification Method

Run the simulation test suite:
```powershell
powershell -ExecutionPolicy Bypass -File W:\iOS-sloosh\.agents\challenger_1\test_sim_fix.ps1
```
Expected output:
- `[PASS] Ep 2 plays fallback LostFilm while preserving TargetVoiceover=Дубляж`
- `[PASS] Ep 3 restored user preference (Дубляж) successfully!`
- `=== FIXED TEST COMPLETE ===`
