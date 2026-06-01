import { requireNativeModule, requireNativeViewManager } from 'expo-modules-core';
import { Platform } from 'react-native';

// Export all types
export * from './NeomoviesCoreModule.types';
export * from './AVPlayerModule.types';
export * from './ExoPlayerModule.types';
export * from './EpisodesListModule.types';

import type { CollapsParserModule } from './NeomoviesCoreModule.types';
import type { AVPlayerModule } from './AVPlayerModule.types';
import type { ExoPlayerViewProps } from './ExoPlayerModule.types';
import type { EpisodesListViewProps } from './EpisodesListModule.types';

// Common parser module (both iOS and Android)
const CollapsParser = requireNativeModule<CollapsParserModule>('NeomoviesCore');

// iOS-only AVPlayer
const AVPlayer = Platform.OS === 'ios' 
  ? requireNativeModule<AVPlayerModule>('NeomoviesCore')
  : null;

// Android-only ExoPlayer View
const ExoPlayerView = Platform.OS === 'android'
  ? requireNativeViewManager<ExoPlayerViewProps>('NeomoviesCore', 'ExoPlayerView')
  : null;

const EpisodesListView = requireNativeViewManager<EpisodesListViewProps>('NeomoviesCore', 'EpisodesListView');

export { CollapsParser, AVPlayer, ExoPlayerView, EpisodesListView };
export default CollapsParser;
