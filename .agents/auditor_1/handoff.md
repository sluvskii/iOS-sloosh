# Forensic Integrity Audit & Handoff Report

## Forensic Audit Report

**Work Product**: Playback & Download Voiceover Fidelity and Video Quality Stack (`AllohaRepository.swift`, `PlayerView.swift`, `PlayerPickerSheets.swift`, `DownloadManager.swift`)  
**Profile**: General Project (Forensic Integrity)  
**Integrity Mode**: Development (from `ORIGINAL_REQUEST.md`)  
**Verdict**: CLEAN  

### Phase Results
- **Phase 1: Static Analysis & Dummy Code Detection**: PASS — Zero hardcoded test results, zero dummy stubs, zero mock constants, zero facade methods.
- **Phase 2: Architectural & Behavioral Verification**: PASS — Authentic API data consumption, real async stream resolution via `AllohaRuntimeResolver`, genuine HLS master playlist parsing with AV1 filtering, real AVPlayer item reloading, seamless timestamp preservation.
- **Phase 3: Design System & Guidelines Compliance**: PASS — Exactly 0 matches for `.ultraThinMaterial` across the entire codebase, 0 Collaps streaming source implementations, 0 leaked internal provider names in user-facing UI copy, native Liquid Glass styling.
- **Phase 4: Git Scope Verification**: PASS — Only the 4 authorized files in `sloosh-iOS/sloosh/Sources/` were modified.

---

## 1. Observation

Direct empirical inspection of modified codebase:

1. **AllohaRepository (`AllohaRepository.swift`)**:
   - Lines 378–387: Destructive eager resolution of the first movie iframe has been removed. Authentic `translations` parsed directly from `dataObj["movie"]?["translations"]` are preserved without being overwritten by partial WKWebView `audioVariants`.
   - Network fetches target authentic `api.alloha.tv` endpoints without hardcoded mocks.

2. **PlayerViewModel & Playback (`PlayerView.swift`)**:
   - Lines 787–870 (`switchVoiceover(to:at:)`): Finds target `AllohaTranslation` by index and/or name matching in `seriesResult.movie?.translations` or `seriesResult.seasons[...].episodes[...].translations`. Resolves authentic `iframeUrl` via `AllohaRuntimeResolver`, updates `availableQualities`, preserves `savedTime` (`self.currentTime = savedTime`), and reloads playback using `reloadPlayback(to: preferredPeakBitRate:)`.
   - Lines 1741–1755 (`playEpisode`): Synchronizes `_currentTranslationName` to `episode.translation.name`, preserves user's preferred `targetVoiceover`, and persists selection.
   - Lines 1818–1835 (`preferredTranslation`): Prioritizes `targetVoiceover` over fallback translations to maintain voiceover continuity across episode changes.
   - Lines 1885–1888 (`applyResolvedAllohaStream`): Protects `availableVoiceovers` from being overwritten by partial WKWebView `audioVariants` if authentic API translations already exist.
   - Lines 2065–2085 (`syncNativeAudioTracks`): Protects `availableVoiceovers` from being replaced by raw `AVMediaSelectionGroup` track names.

3. **Player Controls (`PlayerPickerSheets.swift`)**:
   - Lines 12–21 (`VoiceoverPickerSheet`): Iterates over `vm.availableVoiceovers` and checks `isSelected` matching `vm.currentTranslationName`. Calls `vm.switchVoiceover(to: name, at: idx)` on user selection.
   - Zero usage of `.ultraThinMaterial`. Uses clean popover container styling with `Capsule()`.

4. **Download Manager (`DownloadManager.swift`)**:
   - Lines 319–327 (`prepareAndEnqueue`): Uses `resolved["url"]` directly as `streamUrlString` for the target translation without erroneous title-matching overrides from `audioVariants`.
   - Lines 650–775 (`chooseMediaPlaylistUrl`): Real HLS master playlist parsing supporting `#EXT-X-STREAM-INF:` tags with `BANDWIDTH`, `AVERAGE-BANDWIDTH`, `RESOLUTION=WxH`, and URL resolution extraction (`extractHeightFromUrlString`). Actively parses `CODECS` and filters out AV1 codecs (`av01`, `codecs="av01"`). Selects the highest resolution variant $\le \text{targetHeight}$ without downgrading.

5. **Prohibition Compliance**:
   - Ripgrep for `.ultraThinMaterial` in `W:\iOS-sloosh\sloosh-iOS`: **0 matches**.
   - Ripgrep for `Collaps` streaming source: **0 matches** (only UI state `isFilterCollapsed` found in `HomeView.swift`).
   - Ripgrep for leaked provider names (`NeoMovies`, `Alloha`) in user-facing UI: **0 matches** (only internal `AdminDashboardView` diagnostic text and backend model references exist).

6. **Git Modification Scope**:
   - Only 4 files modified under `sloosh-iOS/sloosh/Sources/`:
     - `Data/Repositories/AllohaRepository.swift`
     - `Data/Repositories/DownloadManager.swift`
     - `UI/Player/Controls/PlayerPickerSheets.swift`
     - `UI/Player/PlayerView.swift`

---

## 2. Logic Chain

1. **Voiceover Fidelity**: By eliminating eager first-iframe resolution in `AllohaRepository.swift` and preventing overwrites in `applyResolvedAllohaStream` / `syncNativeAudioTracks`, `availableVoiceovers` accurately reflects the authentic translations list from the API for both movies and series.
2. **In-Player Switching**: When the user changes voiceovers in `VoiceoverPickerSheet`, `switchVoiceover(to:at:)` resolves the exact iframe URL corresponding to the selected translation, captures `savedTime`, updates quality variants, and triggers `reloadPlayback`. Playback resumes at the exact timestamp with the correct audio track.
3. **Episode Continuity**: `playEpisode` and `preferredTranslation` maintain `targetVoiceover` across episode transitions, ensuring that if a user chose Dubbed, subsequent episodes automatically play Dubbed if available.
4. **Download Accuracy**: By using the resolved stream URL directly for the chosen translation and parsing master playlist variant tags (`RESOLUTION`, `BANDWIDTH`) while filtering AV1, `DownloadManager` reliably downloads the intended audio translation and highest resolution up to the user's preference.
5. **Guideline & Scope Compliance**: All rules from `AGENTS.md` and `ORIGINAL_REQUEST.md` (no `.ultraThinMaterial`, no Collaps, clean Liquid Glass, authorized git scope) are strictly satisfied.

---

## 3. Caveats

- In accordance with `AGENTS.md` ("The project is NOT built locally via Xcode or Simulator. Builds and distribution are executed exclusively via GitHub Actions"), local building was not executed. Verification was performed via rigorous static analysis, regex pattern checks, and architectural inspection.

---

## 4. Conclusion

The implementation across all 4 files is authentic, genuine, robust, and completely free of integrity violations, dummy stubs, or unauthorized shortcuts. All requirements R1–R3 from `ORIGINAL_REQUEST.md` and architectural specifications from `PROJECT.md` are satisfied.

**Final Verdict**: **CLEAN**

---

## 5. Verification Method

- **Prohibition Check**:
  ```powershell
  rg -i "ultraThinMaterial" W:\iOS-sloosh\sloosh-iOS
  ```
  Expected: 0 matches.
- **Git Scope Check**:
  ```powershell
  git diff --stat sloosh-iOS/
  ```
  Expected: Exactly 4 modified source files (`AllohaRepository.swift`, `DownloadManager.swift`, `PlayerPickerSheets.swift`, `PlayerView.swift`).
- **Logic Inspection**:
  Verify `switchVoiceover` in `PlayerView.swift`, `chooseMediaPlaylistUrl` in `DownloadManager.swift`, and translation parsing in `AllohaRepository.swift`.
