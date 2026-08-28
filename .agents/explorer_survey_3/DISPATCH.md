## 2026-08-27T15:30:52Z
Task:
Investigate the DownloadManager and quality/stream selection in `W:\iOS-sloosh\sloosh-iOS\sloosh\Sources\`:
1. Inspect `Data/Repositories/DownloadManager.swift`, `UI/Downloads/DownloadsView.swift`, and related models/views.
2. In `DownloadManager.prepareAndEnqueue`: check how `translation.iframeUrl` is passed, resolved via `AllohaRuntimeResolver`, and how the stream URL is selected (ensure no erroneous overrides from unrelated `audioVariants`).
3. In `DownloadManager.chooseMediaPlaylistUrl`: analyze how master HLS playlists (`#EXT-X-STREAM-INF`) are parsed for resolution (`RESOLUTION=...`), variant URLs (`1080.m3u8`, `720.m3u8`), and bitrates, and how `resolved["qualityVariants"]` is evaluated. Identify why requested qualities (e.g. 1080p, 720p) might downgrade to 720p and how to ensure downloading at highest matching resolution up to user preference without downgrading.
4. Analyze how downloaded media metadata (`translationName`, `quality`, `key.bin`, `local.m3u8`) is saved and verified, and how offline playback in `PlayerView` consumes it to ensure exact audio voiceover and video quality.

Deliverables:
- Write your detailed analysis and findings to `W:\iOS-sloosh\.agents\explorer_survey_3\analysis.md`.
- Write a self-contained handoff report to `W:\iOS-sloosh\.agents\explorer_survey_3\handoff.md` with exact file paths, line numbers, code snippets, and clear fix recommendations.
- Send a completion message back to parent using send_message.
