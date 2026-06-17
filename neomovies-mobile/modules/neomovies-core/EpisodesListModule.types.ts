import { ViewProps } from 'react-native';

export type NativeEpisodeItem = {
  season: number;
  episode: number;
  title: string;
  description: string;
  progress: number;
  stillUrl?: string | null;
  fallbackPosterUrl?: string | null;
  tmdbRating?: number | null;
  imdbRating?: number | null;
};

export type EpisodesListViewProps = ViewProps & {
  episodes: NativeEpisodeItem[];
  textColor?: string;
  secondaryTextColor?: string;
  borderColor?: string;
  backgroundColor?: string;
  onEpisodePress?: (event: { nativeEvent: { season: number; episode: number } }) => void;
  onContentHeight?: (event: { nativeEvent: { height: number } }) => void;
  onDownloadPress?: (event: { nativeEvent: { season: number; episode: number } }) => void;
};
