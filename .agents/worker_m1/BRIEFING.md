# BRIEFING — 2026-08-27T15:38:00Z

## Mission
Implement Player Voiceover Preservation, In-Player Voiceover Switching with Playback Position Preservation, and Movie Translations Fidelity in AllohaRepository and PlayerView (R1 & R2).

## 🔒 My Identity
- Archetype: implementer
- Roles: implementer, qa, specialist
- Working directory: W:\iOS-sloosh\.agents\worker_m1
- Original parent: e8fa1221-3ddf-4c07-8ee2-5bc9cdec5746
- Milestone: M1 & M2 (Player Voiceover Fidelity & Episode Continuity)

## 🔒 Key Constraints
- Exclusively own and edit:
  - W:\iOS-sloosh\sloosh-iOS\sloosh\Sources\Data\Repositories\AllohaRepository.swift
  - W:\iOS-sloosh\sloosh-iOS\sloosh\Sources\UI\Player\PlayerView.swift
  - W:\iOS-sloosh\sloosh-iOS\sloosh\Sources\UI\Player\Controls\PlayerPickerSheets.swift (if needed)
- Do NOT edit any other files.
- Zero usage of .ultraThinMaterial. All floating UI uses .glassEffect().
- Zero mention of internal provider names (Alloha, Collaps, etc.) in user-facing UI.
- Never hardcode test outputs or create dummy implementations.

## Current Parent
- Conversation ID: e8fa1221-3ddf-4c07-8ee2-5bc9cdec5746
- Updated: 2026-08-27T15:38:00Z

## Task Summary
- **What to build**:
  1. In AllohaRepository.swift (etchByKpId), remove destructive eager resolver call on first movie iframe and retain authentic movie.translations parsed directly from dataObj[translation].
  2. In PlayerView.swift (eginLoad), populate vailableVoiceovers for movies from seriesResult.movie?.translations.map { .name } and for series from epObj.translations.map { .name }.
  3. In PlayerView.swift (pplyResolvedAllohaStream), only populate vailableVoiceovers from esolvedVoiceovers if vailableVoiceovers.isEmpty.
  4. In PlayerView.swift (syncNativeAudioTracks), do not append raw native tracks to vailableVoiceovers if already populated.
  5. In PlayerView.swift (switchVoiceover(to:at:)), lookup target AllohaTranslation in seriesResult (for both movies and series), resolve target iframeUrl (or pre-resolved streamUrl), preserve savedTime, and reload playback restoring savedTime.
  6. In PlayerView.swift (playEpisode), update _currentTranslationName = episode.translation.name, preserve 	argetVoiceover as user preference across episodes.
- **Success criteria**: All voiceovers preserved, in-player switching works seamlessly with position preservation, episode navigation keeps active voiceover, clean compilation.

## Key Decisions Made
- Authentic translations from Alloha API are primary. udioVariants from single iframe are only fallback if no translation list exists.
- In switchVoiceover, preserve currentTime across stream reloads so user playback is uninterrupted.

## Artifact Index
- W:\iOS-sloosh\.agents\worker_m1\handoff.md — Final Handoff Report
