// Common types for both iOS and Android
export type CollapsSubtitle = {
  url: string;
  label: string;
  language: string;
};

export type CollapsPlaylist = {
  primaryUrl: string;
  hlsUrl: string | null;
  dashUrl: string | null;
  voiceovers: string[];
  subtitles: CollapsSubtitle[];
};

export type CollapsEpisode = {
  season: number;
  episode: number;
  title: string;
  playlist: CollapsPlaylist;
};

export type CollapsSeason = {
  season: number;
  title: string;
  episodes: CollapsEpisode[];
};

export type CollapsCatalogMovie = {
  kind: 'movie';
  source: string;
  playlist: CollapsPlaylist;
};

export type CollapsCatalogSeries = {
  kind: 'series';
  source: string;
  seasons: CollapsSeason[];
};

export type CollapsCatalog = CollapsCatalogMovie | CollapsCatalogSeries;

export type CollapsWatchProgressRecord = {
  schemaVersion: number;
  source: 'collaps';
  mediaId: string;
  kpId: number;
  season: number | null;
  episode: number | null;
  kind: 'episode' | 'movie_or_generic';
  positionMs: number;
  durationMs: number;
  progressPercent: number;
  watched: boolean;
  updatedAtMs: number;
};

export type CollapsWatchProgressSnapshot = CollapsWatchProgressRecord & {
  lastSeason: number | null;
  lastEpisode: number | null;
  lastPositionMs: number;
  lastDurationMs: number;
  lastUpdatedAtMs: number;
};

// Common parser functions (available on both platforms)
export type CollapsParserModule = {
  parseCollapsCatalog(embedHtml: string): CollapsCatalog;
  parseAllohaRuntimePayload?(payload: string, baseUrl: string, headers: Record<string, string>): {
    videoURL?: string;
    audioTracks?: string[];
    audioVariants?: unknown[];
    subtitles?: CollapsSubtitle[];
    qualityVariants?: unknown[];
    httpHeaders?: Record<string, string>;
  };
  rewriteCollapsHlsMaster(master: string, voices: string[], subtitles: CollapsSubtitle[], mediaId: string): string;
  rewriteCollapsDashManifest(manifest: string, voices: string[], subtitles: CollapsSubtitle[], mediaId: string): string;
  rewriteCollapsHlsFromUrl(
    hlsUrl: string,
    voices: string[],
    subtitles: CollapsSubtitle[],
    mediaId: string,
    referer?: string | null,
    origin?: string | null
  ): Promise<string>;
  rewriteCollapsDashFromUrl(
    dashUrl: string,
    voices: string[],
    subtitles: CollapsSubtitle[],
    mediaId: string,
    referer?: string | null,
    origin?: string | null
  ): Promise<string>;
  collapsDeviceSupportsAv1?(): boolean;
  exoPlayerLaunch?(url: string, headers?: Record<string, string>, title?: string | null, kpId?: number | null): Promise<void>;
  exoPlayerLaunchPlaylist?(
    urls: string[],
    startIndex: number,
    headers?: Record<string, string>,
    names?: string[] | null,
    title?: string | null,
    voiceNames?: string[] | null,
    kpId?: number | null
  ): Promise<void>;
  exoPlayerSetAllohaVariants?(
    audioVariantsJson: string | null,
    qualityVariantsJson: string | null
  ): Promise<void>;
  exoPlayerSetAllohaEpisodes?(
    episodeIframeUrlsJson: string | null,
    episodeNamesJson: string | null,
    startIndex: number,
    headersJson: string | null,
    title: string | null
  ): Promise<void>;
  exoPlayerLaunchAlloha?(iframeUrl: string, title?: string | null, kpId?: number | null): Promise<void>;
  exoPlayerGetAllohaEpisodeState?(): {
    currentIndex: number;
    totalEpisodes: number;
    hasPrevious: boolean;
    hasNext: boolean;
    currentName: string;
  };
  getCollapsWatchProgress?(
    kpId: number,
    season?: number | null,
    episode?: number | null
  ): CollapsWatchProgressSnapshot;
  listCollapsWatchProgressRecords?(kpId?: number | null): CollapsWatchProgressRecord[];
};
