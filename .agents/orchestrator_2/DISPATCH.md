# DISPATCH LOG

## 2026-08-27T15:30:01Z

You are the Project Orchestrator for the task defined in `W:\iOS-sloosh\.agents\ORIGINAL_REQUEST.md`.

Your working directory is: `W:\iOS-sloosh\.agents\orchestrator_2`

Please read `W:\iOS-sloosh\.agents\ORIGINAL_REQUEST.md` (specifically the latest section timestamped 2026-08-27T15:29:02Z) and `W:\iOS-sloosh\AGENTS.md` for workspace rules and context.

Task Summary:
Fix voiceover selection and video quality discrepancies across the playback stack (`PlayerView`, `SourceSelectionView`, `DetailsView`, `AllohaRuntimeResolver`, and `DownloadManager`) so that user choices (e.g., Dubbed voiceover, 1080p quality) are strictly honored during both online streaming and offline downloads.

Key Requirements:
R1. Complete Synchronization & Fidelity of Voiceovers in Player
- Preserve authentic translation voiceovers from AllohaApiResult (`epObj.translations` for TV shows, `movie.translations` for movies) in `availableVoiceovers`.
- Prevent `applyResolvedAllohaStream` from overwriting `availableVoiceovers` with internal/partial WKWebView `audioVariants`.
- Ensure selecting a voiceover in `SourceSelectionView` opens `PlayerView` with that exact translation's stream and displays the correct active voiceover in `VoiceoverPickerSheet`.
- Switching voiceovers in `VoiceoverPickerSheet` reloads the exact translation stream via AllohaApiResult and preserves current playback time.

R2. Voiceover Consistency Across Episode Navigation & Autoplay
- When advancing to the next episode, look up and select the matching voiceover in the new episode.
- If unavailable, fall back gracefully to preferred order and update UI/state.

R3. Strict Quality Selection & Download Fidelity in DownloadManager
- In `DownloadManager.prepareAndEnqueue`, use the resolved stream URL directly for the chosen `translation.iframeUrl` without erroneous overrides.
- In `DownloadManager.chooseMediaPlaylistUrl`, accurately parse HLS master playlists (`#EXT-X-STREAM-INF` resolutions, variant URLs, bitrates) and evaluate `resolved["qualityVariants"]` so requested qualities (e.g., 1080p, 720p) download at highest matching resolution up to user preference without downgrading.
- Save and verify downloaded media metadata (`translationName`, `quality`, `key.bin`, `local.m3u8`) ensuring offline playback in `PlayerView` plays the exact downloaded audio and video stream.

Project Rules:
- Working directory for code: `W:\iOS-sloosh\sloosh-iOS`
- Strict adherence to AGENTS.md: iOS 26+ first, `.glassEffect()`, forbidden `.ultraThinMaterial`, no Collaps, Alloha only.
- Commit all changes and push to GitHub (`git add .`, `git commit -m "..."`, `git push`).
- Maintain `progress.md` and `plan.md` in `W:\iOS-sloosh\.agents\orchestrator_2`.
- When all tasks are completed, tested, and pushed to GitHub, report back your completion with full details so the Sentinel can trigger the Victory Audit.
