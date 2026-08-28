## 2026-08-27T15:30:52Z

Investigate the Player & Source Selection UI layer in W:\iOS-sloosh\sloosh-iOS\sloosh\Sources\:
1. Inspect UI/Player/PlayerView.swift, UI/Player/PlayerViewModel.swift (if any), UI/Details/SourceSelectionView.swift, UI/Details/DetailsView.swift, and any related voiceover sheets / models.
2. Trace how AllohaApiResult (or AllohaTranslation, AllohaEpisode, AllohaMovie) is passed into PlayerView when launching from SourceSelectionView vs DetailsView.
3. Check how vailableVoiceovers and currentTranslationName / active voiceover state are initialized and updated.
4. Locate pplyResolvedAllohaStream and identify where/why it overwrites vailableVoiceovers with internal/partial WKWebView udioVariants.
5. Examine how voiceover switching works inside VoiceoverPickerSheet (or in-player sheet): how to lookup the selected translation in AllohaApiResult, resolve its iframeUrl / stream, and reload playback at the current playback position seamlessly.
6. Trace episode advance (next episode button, autoplay, episode sheet) and analyze how to preserve the user's active voiceover across episodes with graceful fallback.

Deliverables:
- Write your detailed analysis and findings to W:\iOS-sloosh\.agents\explorer_survey_1\analysis.md.
- Write a self-contained handoff report to W:\iOS-sloosh\.agents\explorer_survey_1\handoff.md with exact file paths, line numbers, code snippets, root causes, and clear fix recommendations.
- Send a completion message back to parent using send_message.
