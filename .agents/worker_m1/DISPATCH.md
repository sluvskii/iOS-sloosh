## 2026-08-27T15:37:14Z
Dispatch requirements for worker_m1:
Scope & Write Ownership:
You exclusively own and may edit:
- W:\iOS-sloosh\sloosh-iOS\sloosh\Sources\Data\Repositories\AllohaRepository.swift
- W:\iOS-sloosh\sloosh-iOS\sloosh\Sources\UI\Player\PlayerView.swift
- W:\iOS-sloosh\sloosh-iOS\sloosh\Sources\UI\Player\Controls\PlayerPickerSheets.swift (if needed)
Do NOT edit any other files.

Requirements (R1 & R2):
1. AllohaRepository.swift: In etchByKpId (around lines 383-410), remove the destructive code that called AllohaRuntimeResolver on the first movie iframe and overwrote movie.translations with udioVariants. Preserve the authentic movie.translations list parsed directly from dataObj[translation].
2. PlayerView.swift (PlayerViewModel.beginLoad): Initialize vailableVoiceovers for movies from seriesResult.movie?.translations.map { .name } in addition to series from epObj.translations.map { .name } and oices.
3. PlayerView.swift (PlayerViewModel.applyResolvedAllohaStream): Do NOT overwrite vailableVoiceovers with esolvedVoiceovers from esolved[audioVariants]. Only populate vailableVoiceovers if it is currently empty.
4. PlayerView.swift (PlayerViewModel.syncNativeAudioTracks): Do NOT append raw native audio track names to vailableVoiceovers if vailableVoiceovers is already populated with authentic translations.
5. PlayerView.swift (PlayerViewModel.switchVoiceover(to:at:)): Rewrite to find the target AllohaTranslation in seriesResult (for both movies and series), resolve its iframeUrl / stream, preserve savedTime, and reload playback restoring savedTime.
6. PlayerView.swift (PlayerViewModel.playEpisode): When advancing episodes, update _currentTranslationName = episode.translation.name. Preserve 	argetVoiceover as user preference across episodes.
