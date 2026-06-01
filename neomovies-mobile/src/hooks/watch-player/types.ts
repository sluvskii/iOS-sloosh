import { CollapsCatalog, CollapsSubtitle } from '@/native/collaps-parser';

export type PlayerHeaders = {
  Referer: string;
  Origin: string;
};

export type WatchPlayerLaunchParams = {
  mediaId: string;
  title: string | null;
  initialSeason: number;
  initialEpisode: number;
};

export type ResolvedAllohaPlayable = {
  url: string;
  subtitles: CollapsSubtitle[];
  audioVariants?: {
    title: string;
    url: string;
    qualityVariants?: { label: string; url: string; bitrate?: number | null; height?: number | null }[];
  }[];
  qualityVariants?: { label: string; url: string; bitrate?: number | null; height?: number | null }[];
  headers?: Record<string, string>;
};

export type MovieCatalog = CollapsCatalog & { kind: 'movie' };
export type SeriesCatalog = CollapsCatalog & { kind: 'series' };
