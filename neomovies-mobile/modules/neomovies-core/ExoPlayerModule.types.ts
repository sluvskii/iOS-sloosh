// Android-only ExoPlayer types
import { ViewProps } from 'react-native';

export type ExoPlayerViewProps = ViewProps & {
  source?: string;
  paused?: boolean;
  playbackSpeed?: number;
  onReady?: () => void;
  onError?: (event: { nativeEvent: { error: string } }) => void;
  onProgress?: (event: { nativeEvent: { currentTime: number; duration: number } }) => void;
  onPlaybackStateChanged?: (event: { nativeEvent: { isPlaying: boolean } }) => void;
};
