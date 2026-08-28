## 2026-08-25T00:54:30+05:00
Investigate Data Layer, Firebase Realtime Database Integration, User Identity, and Caching in Sloosh iOS (`sloosh-iOS/sloosh/Sources/Data/`).
Specific areas:
1. Current MessengerRepository.swift and related network/data classes.
2. User identity / device UUID / profile setup.
3. Existing message/chat data models and DTOs.
4. Proposed Firebase schema and REST endpoints for Channels.
5. Local disk caching strategy.
6. Offline resilience and error handling.

## 2026-08-27T15:30:52Z
Investigate the Resolver, Parser, and Stream Handling layer in `W:\iOS-sloosh\sloosh-iOS\sloosh\Sources\`:
1. Inspect `Data/Repositories/AllohaRuntimeResolver.swift`, `Data/Repositories/AllohaRuntimeParser.swift`, `Data/Repositories/HlsProxyServer.swift`, and `Data/Models/` (Alloha data models).
2. Trace how Alloha iframe URLs are resolved into HLS master playlists and parsed dictionary fields (`resolved["file"]`, `resolved["audioVariants"]`, `resolved["qualityVariants"]`, etc.).
3. Identify all models representing translations, episodes, movies, and streams (e.g. `AllohaTranslation`, `AllohaEpisode`, `AllohaMovie`, `AllohaApiResult`).
4. Detail how `audioVariants` differs from authentic API `translations`, and why `audioVariants` from WKWebView must NOT overwrite the API translations in the player UI.
5. Check how `AllohaRuntimeResolver` is called by `PlayerView` / `PlayerViewModel` when switching translations or episodes, and by `DownloadManager`.
