# Orchestration Plan: Voiceover Selection & Quality Fidelity

## Objective
Fix voiceover selection and video quality discrepancies across the playback stack (`PlayerView`, `SourceSelectionView`, `DetailsView`, `AllohaRuntimeResolver`, and `DownloadManager`) so that user choices (e.g., Dubbed voiceover, 1080p quality) are strictly honored during both online streaming and offline downloads.

## Workflow Phases

### Phase 0: Survey & Investigation
- Spawn 3 parallel Explorers:
  1. `teamwork_preview_explorer_survey_1`: Player & UI layer (`PlayerView`, `PlayerViewModel`, `SourceSelectionView`, `DetailsView`, `VoiceoverPickerSheet`).
  2. `teamwork_preview_explorer_survey_2`: Resolver & Network layer (`AllohaRuntimeResolver`, `AllohaRuntimeParser`, `HlsProxyServer`, `MoviesRepository`).
  3. `teamwork_preview_explorer_survey_3`: Download pipeline (`DownloadManager`, `MediaPlaylistParser`, quality variant resolution, offline playback metadata).
- Merge explorer findings into `PROJECT.md`.

### Phase 1: Implementation - M1 & M2 (Voiceovers in Player & Episode Navigation)
- Worker implements R1 & R2:
  - Preserve `epObj.translations` / `movie.translations` in `availableVoiceovers`.
  - Prevent `applyResolvedAllohaStream` from overwriting authentic translations with internal `audioVariants`.
  - Ensure selecting a voiceover in `SourceSelectionView` launches player with that exact translation and displays active voiceover.
  - Implement dynamic in-player voiceover switching via `VoiceoverPickerSheet` retaining current playback timestamp.
  - Implement episode transition voiceover lookup and matching with fallback logic.
- Verification: 2 Reviewers, 2 Challengers, 1 Auditor.

### Phase 2: Implementation - M3 (DownloadManager Quality & Stream Selection)
- Worker implements R3:
  - In `prepareAndEnqueue`, use resolved stream URL for chosen `translation.iframeUrl`.
  - In `chooseMediaPlaylistUrl`, accurately parse HLS master playlists (`#EXT-X-STREAM-INF` resolutions, variant URLs, bitrates) and evaluate `resolved["qualityVariants"]` so requested qualities (e.g., 1080p, 720p) download at highest matching resolution up to user preference without downgrading.
  - Verify and save metadata (`translationName`, `quality`, `key.bin`, `local.m3u8`).
- Verification: 2 Reviewers, 2 Challengers, 1 Auditor.

### Phase 3: Integration, Regression Verification & Git Push
- Final verification of entire stack.
- Commit all changes and push to GitHub repository (`git add .`, `git commit -m "..."`, `git push`).
- Report completion to Sentinel.
