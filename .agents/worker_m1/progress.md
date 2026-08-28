# Progress — worker_m1

Last visited: 2026-08-27T15:41:30Z

## Current Status: Completed
- [x] Initialized workspace and briefing
- [x] Inspected AllohaRepository.swift around lines 383-410
- [x] Inspected PlayerView.swift (beginLoad, applyResolvedAllohaStream, syncNativeAudioTracks, switchVoiceover, playEpisode, preferredTranslation)
- [x] Inspected PlayerPickerSheets.swift
- [x] Applied changes to AllohaRepository.swift: removed destructive eager resolver call on first movie iframe, preserved authentic movie.translations list parsed directly from API
- [x] Applied changes to PlayerView.swift:
  - Initialized availableVoiceovers for movies from seriesResult.movie?.translations.map { .name }
  - Protected availableVoiceovers from being overwritten by resolvedAudioVariants in applyResolvedAllohaStream
  - Guarded syncNativeAudioTracks to not append raw AVPlayer track names when authentic translations exist
  - Rewrote switchVoiceover(to:at:) to resolve target translation iframeUrl / stream, preserve savedTime, and reload playback restoring savedTime
  - Updated playEpisode to set _currentTranslationName = episode.translation.name and preserve targetVoiceover preference across episodes
  - Updated preferredTranslation(in:) to check targetVoiceover first
- [x] Applied changes to PlayerPickerSheets.swift: used allohaTranslationNamesMatch for isSelected matching in VoiceoverPickerSheet
- [x] Verified git diff and static integrity across all modified files
- [x] Prepared handoff report
