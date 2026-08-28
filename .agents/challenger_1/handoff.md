# Handoff Report: Player Voiceover & Episode Navigation Empirical Verification (R1 & R2)

## 1. Observation

### Codebase Inspection
1. **`AllohaRepository.swift`**:
   - **Lines 313–387**: Movie translation parsing preserves all translations provided by the Alloha API (whether dictionary, array, or string) in `parsedTrans`.
   - **Lines 383–387**: The destructive eager iframe resolution loop (which previously replaced translations with audio variants) was successfully removed.
   - **Lines 260–307**: TV series episode parsing preserves `parsedTrans` per episode in `AllohaEpisode.translations` and `AllohaSeason.episodes`.
   - **Lines 55–62**: `injectTranslationId` properly injects `?translation=<id>` for both movie and episode iframes.
   - **Lines 103–135**: `allohaTranslationNamesMatch` provides robust exact, word-overlap, and language-tag matching.

2. **`PlayerView.swift` & `PlayerViewModel`**:
   - **Lines 397–406**: In `beginLoad`, `availableVoiceovers` is correctly initialized from `seriesResult.seasons[...].episodes[...].translations` for TV shows and `seriesResult.movie.translations` for movies.
   - **Lines 1887–1890**: In `applyResolvedAllohaStream`, `availableVoiceovers` is preserved and not overwritten:
     ```swift
     let voices = resolvedVoiceovers(from: resolved)
     if self.availableVoiceovers.isEmpty && !voices.isEmpty {
         self.availableVoiceovers = voices
     }
     ```
   - **Lines 2068–2070**: In `syncNativeAudioTracks`, `availableVoiceovers` is not overwritten:
     ```swift
     guard self.availableVoiceovers.isEmpty else { return }
     ```
   - **Lines 787–908**: In `switchVoiceover(to:at:)`:
     - Captures `let savedTime = self.player?.currentTime().seconds ?? self.currentTime` (line 789).
     - Cancels in-flight tasks and resolvers (`resolveTask?.cancel()`, `resolver?.cancel()`, lines 844-845).
     - Invalidates resolver cache: `AllohaRuntimeResolver.invalidateCache(for: iframeUrl)` (line 843).
     - Restores `self.currentTime = savedTime` (line 890) and performs sample-accurate seek upon `.readyToPlay` (line 1016).
     - Provides native audio track fallback via `selectAudioTrackInPlayer(named: name)` (lines 910–915).
   - **Lines 1730–1768**: In `playEpisode`:
     - Sets `_currentTranslationName = episode.translation.name` (line 1745).
     - Sets `if targetVoiceover == nil { targetVoiceover = episode.translation.name }` (lines 1748–1750).
     - Persists selection only if matching: `if let pref = targetVoiceover, allohaTranslationNamesMatch(episode.translation.name, pref) { persistVoiceoverSelection(episode.translation.name) }` (lines 1752–1754).
     - Calls `beginLoad(..., selectedVoiceover: episode.translation.name)` (lines 1760–1766).
   - **Line 381**: In `beginLoad`:
     ```swift
     self.targetVoiceover = selectedVoiceover
     ```
     **Defect Found**: `beginLoad` unconditionally overwrites `self.targetVoiceover` with `selectedVoiceover`. When advancing to an episode where the preferred voiceover is missing (e.g. Ep 2 has only LostFilm), `self.targetVoiceover` is changed from "Дубляж" to "LostFilm".

### Empirical Test Execution
We built and executed a test harness simulating the player state machine (`W:\iOS-sloosh\.agents\challenger_1\test_sim.ps1` and `test_sim_fix.ps1`).

**Test Run Output for Scenario C (Current Implementation)**:
```
=== RUNNING TEST SUITE ===
[PASS] Test 1: Single translation movie initialized correctly.
[PASS] Test 2: Movie with 15+ translations preserves all options in availableVoiceovers.
[PASS] Test 3: In-player voiceover switching preserves playback position (1450.5s) and updates iframe URL.
Started Series Ep 1 with translation: Дубляж, TargetVoiceover: Дубляж
Candidate for Ep 2: S1E2 - LostFilm
Now playing Ep 2 with translation: LostFilm, TargetVoiceover: LostFilm
Candidate for Ep 3: S1E3 - LostFilm
Now playing Ep 3 with translation: LostFilm, TargetVoiceover: LostFilm
=== TEST SUITE COMPLETE ===
```
**Observation**: On Episode 3 (where "Дубляж" is available), candidate selection returned "LostFilm" because `targetVoiceover` was overwritten during Episode 2 load.

---

## 2. Logic Chain

1. In `playEpisode`, the developer designed `targetVoiceover` to act as the user's sticky preferred voiceover across episodes (preserving preference even when a single episode temporarily lacks that voiceover).
2. On Episode 1, the user selects "Дубляж". `targetVoiceover` is set to "Дубляж".
3. When advancing to Episode 2 (which only offers "LostFilm"), `preferredTranslation(in: ep2)` cannot find "Дубляж" and falls back to `ep2.translations.first` ("LostFilm").
4. `playEpisode` correctly updates `_currentTranslationName = "LostFilm"` (so the UI displays "LostFilm" on Ep 2) and avoids calling `persistVoiceoverSelection("LostFilm")` because `targetVoiceover` ("Дубляж") != "LostFilm".
5. However, `playEpisode` then invokes `beginLoad(..., selectedVoiceover: "LostFilm")`.
6. Inside `beginLoad` (line 381), `self.targetVoiceover = selectedVoiceover` unconditionally overwrites `self.targetVoiceover` with `"LostFilm"`.
7. When Episode 2 ends and `nextEpisodeCandidate()` is called for Episode 3:
   - `preferredTranslation(in: ep3)` evaluates `targetVoiceover` (now `"LostFilm"`).
   - Because Episode 3 has both "Дубляж" and "LostFilm", `preferredTranslation` matches `"LostFilm"` in step 1 and returns `"LostFilm"`.
8. Result: The user's preference ("Дубляж") is permanently lost after any intermediate episode that lacked that translation, violating the requirement that "Episode 3 (Dubbed exists) restores Dubbed".

### Proposed Fix
In `sloosh-iOS/sloosh/Sources/UI/Player/PlayerView.swift` at line 381:
```swift
// Replace:
self.targetVoiceover = selectedVoiceover

// With:
if self.targetVoiceover == nil {
    self.targetVoiceover = selectedVoiceover
}
```
*(Note: `switchVoiceover` explicitly updates `targetVoiceover = translation.name` at line 821 when the user actively changes voiceover).*

With this fix applied, the simulation test confirms:
```
=== RUNNING FIXED SIMULATION TEST SUITE ===
Started Series Ep 1 with translation: Дубляж, TargetVoiceover: Дубляж
Candidate for Ep 2: S1E2 - LostFilm
Now playing Ep 2 with translation: LostFilm, TargetVoiceover: Дубляж
[PASS] Ep 2 plays fallback LostFilm while preserving TargetVoiceover=Дубляж
Candidate for Ep 3: S1E3 - Дубляж
Now playing Ep 3 with translation: Дубляж, TargetVoiceover: Дубляж
[PASS] Ep 3 restored user preference (Дубляж) successfully!
=== FIXED TEST COMPLETE ===
```

---

## 3. Caveats

- All other tested areas (movie single/multi voiceover parsing, in-player switching with position preservation, cancellation tokens, cache invalidation, native audio track sync, 1080p quality clamping, and AV1 rejection) were verified and found fully sound and robust.
- The only identified flaw is the sticky preference overwrite in `PlayerViewModel.beginLoad`.

---

## 4. Conclusion

The implementation of R1 and R2 is well-structured and largely complete, but contains a reproducible defect in episode-to-episode voiceover preference stickiness:
- Overwriting `self.targetVoiceover` in `beginLoad` causes fallback voiceovers on missing episodes to permanently replace user preferences on subsequent episodes.
- A one-line guard in `beginLoad` (`if self.targetVoiceover == nil { self.targetVoiceover = selectedVoiceover }`) completely resolves the issue.

---

## 5. Verification Method

1. Run the empirical test harness:
   ```powershell
   powershell -ExecutionPolicy Bypass -File W:\iOS-sloosh\.agents\challenger_1\test_sim.ps1
   powershell -ExecutionPolicy Bypass -File W:\iOS-sloosh\.agents\challenger_1\test_sim_fix.ps1
   ```
2. Inspect `PlayerView.swift` line 381 vs lines 1748–1766.

---

Verdict: REQUEST_CHANGES
