# NeomoviesCore Native Module

Native iOS module for parsing Collaps catalog and rewriting HLS/DASH manifests with proper file naming.

## Features

- **Parse Collaps catalog** - Extract movies and series data from embed HTML
- **Rewrite HLS playlists** - Clean up duplicates, add subtitles, rename audio tracks
- **Rewrite DASH manifests** - Add subtitles, rename audio tracks
- **ExoPlayer Video Component** (Android) - Native video player with advanced codec support
- **Proper file naming**:
  - Movies: `{mediaId}_0.m3u8`, `{mediaId}_1.m3u8`, etc.
  - Series: `{mediaId}_{season}_{episode}_0.m3u8`, etc.

## Swift Implementation (iOS)

All Swift code is in `modules/neomovies-core/ios/`:
- `NeomoviesCoreModule.swift` - Expo module definition
- `CollapsParser.swift` - HTML/JSON parser
- `CollapsModels.swift` - Data models
- `CollapsHlsRewriter.swift` - HLS manifest rewriter
- `CollapsDashRewriter.swift` - DASH manifest rewriter
- `CollapsHTTPClient.swift` - HTTP client for fetching manifests

## Kotlin Implementation (Android)

All Kotlin code is in `modules/neomovies-core/android/src/main/java/com/neo/neomovies/core/`:
- `NeomoviesCoreModule.kt` - Expo module definition
- `CollapsParser.kt` - HTML/JSON parser
- `CollapsModels.kt` - Data models
- `CollapsHlsRewriter.kt` - HLS manifest rewriter
- `CollapsDashRewriter.kt` - DASH manifest rewriter
- `CollapsHTTPClient.kt` - HTTP client for fetching manifests

### Native Libraries (Android)

ExoPlayer native decoders in `android/libs/`:
- `lib-decoder-ffmpeg-release.aar` - FFmpeg decoder
- `lib-decoder-vp9-release.aar` - VP9 decoder
- `lib-decoder-opus-release.aar` - Opus decoder
- `lib-decoder-flac-release.aar` - FLAC decoder
- `lib-decoder-iamf-release.aar` - IAMF decoder
- `lib-decoder-mpegh-release.aar` - MPEG-H decoder

## Usage

### Collaps Parser

```typescript
import { parseCollapsCatalog, rewriteCollapsHlsFromUrl } from '@/native/collaps-parser';

// Parse catalog
const catalog = await parseCollapsCatalog(embedHtml);

// Rewrite HLS with proper naming
const rewritten = await rewriteCollapsHlsFromUrl(
  hlsUrl,
  voices,
  subtitles,
  '12345', // mediaId for movies
  { referer: 'https://example.com' }
);

// For series episodes: '12345_1_5' (mediaId_season_episode)
```

### ExoPlayer Component (Android)

```typescript
import { ExoPlayerView } from 'neomovies-core';

function VideoPlayer() {
  return (
    <ExoPlayerView
      style={{ width: '100%', height: 300 }}
      source="https://example.com/video.m3u8"
      paused={false}
      playbackSpeed={1.0}
      onReady={() => console.log('Player ready')}
      onError={(e) => console.error('Player error:', e.nativeEvent.error)}
      onProgress={(e) => console.log('Progress:', e.nativeEvent)}
      onPlaybackStateChanged={(e) => console.log('Playing:', e.nativeEvent.isPlaying)}
    />
  );
}
```

## File Naming Convention

- **Movies**: `{kpId}` → generates `{kpId}_0.m3u8`, `{kpId}_1.m3u8`, etc.
- **Series**: `{kpId}_{season}_{episode}` → generates `{kpId}_{season}_{episode}_0.m3u8`, etc.

This ensures AV players can properly handle the playlists and variants.
