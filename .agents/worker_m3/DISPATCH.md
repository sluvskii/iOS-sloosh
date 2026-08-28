## 2026-08-27T15:37:14Z
You are a Worker subagent (worker_m3).
Your working directory is: W:\iOS-sloosh\.agents\worker_m3
Read ORIGINAL_REQUEST.md at: W:\iOS-sloosh\.agents\ORIGINAL_REQUEST.md (latest section 2026-08-27T15:29:02Z)
Read AGENTS.md at: W:\iOS-sloosh\AGENTS.md
Read PROJECT.md at: W:\iOS-sloosh\.agents\orchestrator_2\PROJECT.md
Read Explorer 3 findings at: W:\iOS-sloosh\.agents\explorer_survey_3\handoff.md

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Scope & Write Ownership:
You exclusively own and may edit:
- `W:\iOS-sloosh\sloosh-iOS\sloosh\Sources\Data\Repositories\DownloadManager.swift`
Do NOT edit any other files.

Requirements (R3):
1. `DownloadManager.swift` (`prepareAndEnqueue`): Remove lines 326-332 that overrode `streamUrlString` with fuzzy matched `audioVariants`. Use `resolved["url"]` directly as the stream URL for the chosen `translation.iframeUrl` without erroneous overrides.
2. `DownloadManager.swift` (`chooseMediaPlaylistUrl`):
   - Parse `BANDWIDTH=` from `#EXT-X-STREAM-INF`.
   - Parse resolution from `#EXT-X-STREAM-INF` `RESOLUTION=WxH` and fallback from variant URLs (e.g. `1080.m3u8`, `720.m3u8`, `480.m3u8`, `360.m3u8`).
   - Filter out AV1 streams (`codecs="av01..."` or `av01` in codecs).
   - Implement accurate sorting: select the variant with highest resolution <= targetHeight (e.g. 1080p for `.q1080`), tie-breaking on highest bandwidth. If no variant <= targetHeight exists, select the closest available resolution.
3. Ensure downloaded media metadata (`translationName`, `quality`, `key.bin`, `local.m3u8`) is properly formatted and saved for seamless offline playback in `PlayerView`.
