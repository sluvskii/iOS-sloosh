// iOS-only AVPlayer types
import { CollapsSubtitle } from './NeomoviesCoreModule.types';

export type AVPlayerTrack = {
  index: number;
  id: string;
  label: string;
  language: string;
};

export type AVPlayerQualityOption = {
  index: number;
  bitrate: number;
  height: number | null;
  label: string;
  isAuto: boolean;
  url?: string | null;
};

export type AVPlayerState = {
  isLoaded: boolean;
  isPlaying: boolean;
  rate: number;
  currentTimeSec: number;
  durationSec: number;
  currentIndex: number;
  totalItems: number;
  season: number | null;
  episode: number | null;
  mediaId: string | null;
};

export type AVPlayerModule = {
  avPlayerLoad(
    url: string,
    headers: Record<string, string>,
    autoplay: boolean,
    startPositionSec?: number | null
  ): Promise<AVPlayerState>;
  avPlayerConfigurePlaylist(
    items: Array<{
      mediaId?: string;
      title?: string;
      url: string;
      headers?: Record<string, string>;
      season?: number;
      episode?: number;
      voiceovers?: string[];
      subtitles?: CollapsSubtitle[];
      audioVariants?: Array<{
        title: string;
        url: string;
        qualityVariants?: Array<{
          label: string;
          url: string;
          bitrate?: number | null;
          height?: number | null;
        }>;
      }>;
      qualityVariants?: Array<{
        label: string;
        url: string;
        bitrate?: number | null;
        height?: number | null;
      }>;
    }>,
    startIndex: number,
    autoplay: boolean,
    kpId?: number | null
  ): Promise<AVPlayerState>;
  avPlayerPresentNativeUI(): Promise<void>;
  avPlayerDismissNativeUI(): Promise<void>;
  avPlayerSelectEpisode(index: number, autoplay: boolean): Promise<AVPlayerState>;
  avPlayerNextEpisode(autoplay: boolean): Promise<AVPlayerState>;
  avPlayerPreviousEpisode(autoplay: boolean): Promise<AVPlayerState>;
  avPlayerPlay(): AVPlayerState;
  avPlayerPause(): AVPlayerState;
  avPlayerStop(): void;
  avPlayerSeek(positionSec: number): AVPlayerState;
  avPlayerSetRate(rate: number): AVPlayerState;
  avPlayerSetPreferredPeakBitRate(bitrate: number): void;
  avPlayerRefreshQualityOptions(): Promise<AVPlayerQualityOption[]>;
  avPlayerListQualityOptions(): AVPlayerQualityOption[];
  avPlayerSelectQuality(index?: number | null): void;
  avPlayerSnapshot(): AVPlayerState;
  avPlayerListAudioTracks(): AVPlayerTrack[];
  avPlayerSelectAudioTrack(index?: number | null): void;
  avPlayerListSubtitleTracks(): AVPlayerTrack[];
  avPlayerSelectSubtitleTrack(index?: number | null): void;
};
