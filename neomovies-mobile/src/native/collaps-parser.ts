import { Platform } from 'react-native';
import NeomoviesCore from 'neomovies-core';

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

export type AllohaAudioVariant = {
  id: string;
  title: string;
  url: string;
};

export type CollapsCatalogMovie = {
  kind: 'movie';
  source: string;
  playlist: CollapsPlaylist;
  allohaVariants?: AllohaAudioVariant[];
};

export type CollapsCatalogSeries = {
  kind: 'series';
  source: string;
  seasons: CollapsSeason[];
  allohaVariants?: AllohaAudioVariant[];
};

export type CollapsCatalog = CollapsCatalogMovie | CollapsCatalogSeries;

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
};

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

type NeomoviesCoreModule = {
  parseCollapsCatalog(embedHtml: string): CollapsCatalog;
  parseAllohaRuntimePayload?(
    payload: string,
    baseUrl: string,
    headers: Record<string, string>
  ): {
    videoURL?: string;
    audioTracks?: string[];
    audioVariants?: AllohaAudioVariant[];
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
  collapsDashContainsAv1(
    dashUrl: string,
    referer?: string | null,
    origin?: string | null
  ): Promise<boolean>;
  fetchUrlTextInsecure?(
    url: string,
    referer?: string | null,
    origin?: string | null
  ): Promise<string>;
  fetchAllohaSeriesCatalog?(
    kpId: string,
    token: string
  ): Promise<CollapsCatalog | Record<string, never>>;
  resolveAllohaPlayableFromIframe?(
    iframeUrl: string
  ): Promise<{
    url: string;
    subtitles?: CollapsSubtitle[];
    headers?: Record<string, string>;
    qualityVariants?: {
      label?: string;
      url?: string;
      bandwidth?: number | null;
      height?: number | null;
    }[];
    audioVariants?: {
      title?: string;
      url?: string;
      qualityVariants?: {
        label?: string;
        url?: string;
        bandwidth?: number | null;
        height?: number | null;
      }[];
    }[];
  }>;
  collapsDeviceSupportsAv1?(): boolean;
  avPlayerLoad(
    url: string,
    headers: Record<string, string>,
    autoplay: boolean,
    startPositionSec?: number | null
  ): Promise<AVPlayerState>;
  avPlayerConfigurePlaylist(
    items: {
      mediaId?: string;
      title?: string;
      url: string;
      headers?: Record<string, string>;
      season?: number;
      episode?: number;
      voiceovers?: string[];
      subtitles?: CollapsSubtitle[];
      audioVariants?: {
        title: string;
        url: string;
        qualityVariants?: {
          label: string;
          url: string;
          bitrate?: number | null;
          height?: number | null;
        }[];
      }[];
      qualityVariants?: {
        label: string;
        url: string;
        bitrate?: number | null;
        height?: number | null;
      }[];
    }[],
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
  getCollapsWatchProgress?(kpId: number, season?: number | null, episode?: number | null): {
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
    lastSeason: number | null;
    lastEpisode: number | null;
    lastPositionMs: number;
    lastDurationMs: number;
    lastUpdatedAtMs: number;
  };
  listCollapsWatchProgressRecords?(kpId?: number | null): CollapsWatchProgressRecord[];
};

let nativeModule: NeomoviesCoreModule | null = null;
const LOG_PREFIX = '[NeomoviesNative]';
let nativeModuleInitLogged = false;

function debugLog(message: string, payload?: unknown) {
  if (__DEV__) {
    if (payload === undefined) {
      console.log(`${LOG_PREFIX} ${message}`);
    } else {
      console.log(`${LOG_PREFIX} ${message}`, payload);
    }
  }
}

function getNativeModule(): NeomoviesCoreModule {
  if (!nativeModule) {
    if (!nativeModuleInitLogged) {
      debugLog('getNativeModule:init', { platform: Platform.OS });
      nativeModuleInitLogged = true;
    }
    debugLog('NeomoviesCore linked successfully');
    nativeModule = NeomoviesCore as NeomoviesCoreModule;
  }
  return nativeModule;
}

type Subscription = { remove: () => void };

function addNativeListener(event: string, listener: (state: AVPlayerState) => void): Subscription {
  const module = getNativeModule() as unknown as {
    addListener?: (eventName: string, listener: (payload: AVPlayerState) => void) => Subscription;
  };
  if (!module.addListener) {
    throw new Error('NeomoviesCore event emitter is not available');
  }
  return module.addListener(event, listener);
}

export async function parseCollapsCatalog(embedHtml: string): Promise<CollapsCatalog> {
  debugLog('parseCollapsCatalog:called', { payloadLength: embedHtml.length });
  if (!embedHtml.trim()) {
    throw new Error('Empty Collaps payload');
  }
  const module = getNativeModule();
  const result = module.parseCollapsCatalog(embedHtml);
  debugLog('parseCollapsCatalog:done', { kind: result.kind });
  return result;
}

export function parseAllohaRuntimePayload(
  payload: string,
  baseUrl: string,
  headers: Record<string, string> = {}
): {
  videoURL?: string;
  audioTracks?: string[];
  audioVariants?: AllohaAudioVariant[];
  subtitles?: CollapsSubtitle[];
  qualityVariants?: unknown[];
  httpHeaders?: Record<string, string>;
} {
  return getNativeModule().parseAllohaRuntimePayload?.(payload, baseUrl, headers) ?? {};
}

function findBalancedObject(input: string, markerIndex: number): string | null {
  let start = markerIndex;
  while (start >= 0 && input[start] !== '{') start -= 1;
  if (start < 0) return null;

  let depth = 0;
  let inString = false;
  let escaped = false;
  let quote = '';

  for (let i = start; i < input.length; i += 1) {
    const ch = input[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (ch === '\\') {
        escaped = true;
      } else if (ch === quote) {
        inString = false;
      }
      continue;
    }

    if (ch === '"' || ch === "'") {
      inString = true;
      quote = ch;
      continue;
    }

    if (ch === '{') depth += 1;
    if (ch === '}') {
      depth -= 1;
      if (depth === 0) return input.slice(start, i + 1);
    }
  }

  return null;
}

type AllohaEpisodeHint = { season: number; episode: number; blob: string };

function extractAllohaEpisodeHints(payload: string): AllohaEpisodeHint[] {
  const hints: AllohaEpisodeHint[] = [];
  const seen = new Set<string>();
  const regex = /["']season["']\s*:\s*(\d+)[\s\S]{0,300}?["']episode["']\s*:\s*(\d+)[\s\S]{0,2000}?["']hlsSource["']\s*:/gi;

  for (const match of payload.matchAll(regex)) {
    const season = Number(match[1]);
    const episode = Number(match[2]);
    const idx = match.index ?? -1;
    if (!Number.isFinite(season) || !Number.isFinite(episode) || idx < 0) continue;
    const blob = findBalancedObject(payload, idx);
    if (!blob) continue;
    const key = `${season}-${episode}`;
    if (seen.has(key)) continue;
    seen.add(key);
    hints.push({ season, episode, blob });
  }

  return hints;
}

export function parseAllohaCatalogFromPayload(
  payload: string,
  baseUrl: string,
  headers: Record<string, string> = {},
  fallbackSeason = 1,
  fallbackEpisode = 1
): CollapsCatalog | null {
  debugLog('parseAllohaCatalogFromPayload:start', {
    payloadLength: payload.length,
    baseUrl,
    fallbackSeason,
    fallbackEpisode,
  });
  const root = parseAllohaRuntimePayload(payload, baseUrl, headers);
  const rootSubtitles = root.subtitles ?? [];
  const rootVariants = root.audioVariants ?? [];
  const hints = extractAllohaEpisodeHints(payload);
  debugLog('parseAllohaCatalogFromPayload:hints', { count: hints.length });

  if (hints.length > 0) {
    const episodes: CollapsEpisode[] = [];
    for (const hint of hints) {
      const parsed = parseAllohaRuntimePayload(hint.blob, baseUrl, headers);
      const url = parsed.videoURL ?? '';
      if (!url) continue;
      episodes.push({
        season: hint.season,
        episode: hint.episode,
        title: `Episode ${hint.episode}`,
        playlist: {
          primaryUrl: url,
          hlsUrl: url.includes('.m3u8') ? url : null,
          dashUrl: url.includes('.mpd') ? url : null,
          voiceovers: [],
          subtitles: parsed.subtitles ?? rootSubtitles,
        },
      });
    }

    if (episodes.length > 0) {
      const seasonsMap = new Map<number, CollapsEpisode[]>();
      for (const ep of episodes) {
        const arr = seasonsMap.get(ep.season) ?? [];
        arr.push(ep);
        seasonsMap.set(ep.season, arr);
      }

      const seasons = Array.from(seasonsMap.entries())
        .sort((a, b) => a[0] - b[0])
        .map(([season, seasonEpisodes]) => ({
          season,
          title: `Season ${season}`,
          episodes: seasonEpisodes.sort((a, b) => a.episode - b.episode),
        }));

      const result: CollapsCatalog = {
        kind: 'series',
        source: 'alloha',
        seasons,
        allohaVariants: rootVariants,
      };
      debugLog('parseAllohaCatalogFromPayload:series', {
        seasons: result.seasons.length,
        episodes: result.seasons.reduce((acc, s) => acc + s.episodes.length, 0),
      });
      return result;
    }
  }

  const url = root.videoURL ?? '';
  if (!url) return null;

  const fallback: CollapsCatalog = {
    kind: 'series',
    source: 'alloha',
    seasons: [
      {
        season: fallbackSeason,
        title: `Season ${fallbackSeason}`,
        episodes: [
          {
            season: fallbackSeason,
            episode: fallbackEpisode,
            title: `Episode ${fallbackEpisode}`,
            playlist: {
              primaryUrl: url,
              hlsUrl: url.includes('.m3u8') ? url : null,
              dashUrl: url.includes('.mpd') ? url : null,
              voiceovers: [],
              subtitles: rootSubtitles,
            },
          },
        ],
      },
    ],
    allohaVariants: rootVariants,
  };
  debugLog('parseAllohaCatalogFromPayload:fallback', {
    seasons: fallback.seasons.length,
    episodes: fallback.seasons[0]?.episodes.length ?? 0,
    hasVideo: Boolean(url),
  });
  return fallback;
}

export async function rewriteCollapsHlsMaster(
  master: string,
  voices: string[],
  subtitles: CollapsSubtitle[] = [],
  mediaId: string
): Promise<string> {
  debugLog('rewriteCollapsHlsMaster:called', {
    payloadLength: master.length,
    voices: voices.length,
    subtitles: subtitles.length,
    mediaId,
  });
  const module = getNativeModule();
  const rewritten = module.rewriteCollapsHlsMaster(master, voices, subtitles, mediaId);
  debugLog('rewriteCollapsHlsMaster:done', { payloadLength: rewritten.length });
  return rewritten;
}

export async function rewriteCollapsDashManifest(
  manifest: string,
  voices: string[],
  subtitles: CollapsSubtitle[] = [],
  mediaId: string
): Promise<string> {
  debugLog('rewriteCollapsDashManifest:called', {
    payloadLength: manifest.length,
    voices: voices.length,
    subtitles: subtitles.length,
    mediaId,
  });
  const module = getNativeModule();
  const rewritten = module.rewriteCollapsDashManifest(manifest, voices, subtitles, mediaId);
  debugLog('rewriteCollapsDashManifest:done', { payloadLength: rewritten.length });
  return rewritten;
}

export async function rewriteCollapsHlsFromUrl(
  hlsUrl: string,
  voices: string[],
  subtitles: CollapsSubtitle[] = [],
  mediaId: string,
  headers?: { referer?: string | null; origin?: string | null }
): Promise<string> {
  debugLog('rewriteCollapsHlsFromUrl:called', {
    hlsUrl,
    voices: voices.length,
    subtitles: subtitles.length,
    mediaId,
    referer: headers?.referer ?? null,
    origin: headers?.origin ?? null,
  });
  const module = getNativeModule();
  const rewritten = await module.rewriteCollapsHlsFromUrl(
    hlsUrl,
    voices,
    subtitles,
    mediaId,
    headers?.referer ?? null,
    headers?.origin ?? null
  );
  debugLog('rewriteCollapsHlsFromUrl:done', { payloadLength: rewritten.length });
  return rewritten;
}

export async function rewriteCollapsDashFromUrl(
  dashUrl: string,
  voices: string[],
  subtitles: CollapsSubtitle[] = [],
  mediaId: string,
  headers?: { referer?: string | null; origin?: string | null }
): Promise<string> {
  debugLog('rewriteCollapsDashFromUrl:called', {
    dashUrl,
    voices: voices.length,
    subtitles: subtitles.length,
    mediaId,
    referer: headers?.referer ?? null,
    origin: headers?.origin ?? null,
  });
  const module = getNativeModule();
  const rewritten = await module.rewriteCollapsDashFromUrl(
    dashUrl,
    voices,
    subtitles,
    mediaId,
    headers?.referer ?? null,
    headers?.origin ?? null
  );
  debugLog('rewriteCollapsDashFromUrl:done', { payloadLength: rewritten.length });
  return rewritten;
}

export async function collapsDashContainsAv1(
  dashUrl: string,
  headers?: { referer?: string | null; origin?: string | null }
): Promise<boolean> {
  debugLog('collapsDashContainsAv1:called', {
    dashUrl,
    referer: headers?.referer ?? null,
    origin: headers?.origin ?? null,
  });
  const module = getNativeModule();
  const result = await module.collapsDashContainsAv1(
    dashUrl,
    headers?.referer ?? null,
    headers?.origin ?? null
  );
  debugLog('collapsDashContainsAv1:done', { result });
  return result;
}

export async function fetchUrlTextInsecure(
  url: string,
  headers?: { referer?: string | null; origin?: string | null }
): Promise<string> {
  const module = getNativeModule();
  if (!module.fetchUrlTextInsecure) {
    throw new Error('fetchUrlTextInsecure is not available');
  }
  return module.fetchUrlTextInsecure(url, headers?.referer ?? null, headers?.origin ?? null);
}

export async function fetchAllohaSeriesCatalog(
  kpId: string,
  token: string
): Promise<CollapsCatalog | null> {
  const module = getNativeModule();
  if (!module.fetchAllohaSeriesCatalog) return null;
  const result = await module.fetchAllohaSeriesCatalog(kpId, token);
  if (!result || !('kind' in result)) return null;
  return result as CollapsCatalog;
}

export async function resolveAllohaPlayableFromIframe(
  iframeUrl: string
): Promise<{
  url: string;
  subtitles: CollapsSubtitle[];
  audioVariants?: { title: string; url: string; qualityVariants?: { label: string; url: string; bitrate?: number | null; height?: number | null }[] }[];
  qualityVariants?: { label: string; url: string; bitrate?: number | null; height?: number | null }[];
  headers?: Record<string, string>;
}> {
  const module = getNativeModule();
  if (!module.resolveAllohaPlayableFromIframe) {
    throw new Error('resolveAllohaPlayableFromIframe is not available');
  }
  const result = await module.resolveAllohaPlayableFromIframe(iframeUrl);
  return {
    url: result.url,
    subtitles: result.subtitles ?? [],
    headers: (result.headers && typeof result.headers === 'object') ? result.headers as Record<string, string> : {},
    qualityVariants: Array.isArray(result.qualityVariants)
      ? result.qualityVariants
          .map((item: any) => ({
            label: typeof item?.label === 'string' ? item.label : '',
            url: typeof item?.url === 'string' ? item.url : '',
            bitrate: typeof item?.bandwidth === 'number' ? item.bandwidth : null,
            height: typeof item?.label === 'string' && /\d+p/i.test(item.label) ? Number.parseInt(item.label, 10) : null,
          }))
          .filter((item: { url: string }) => item.url.length > 0)
      : [],
    audioVariants: Array.isArray(result.audioVariants)
      ? result.audioVariants
          .map((item: any) => ({
            title: typeof item?.title === 'string' ? item.title : '',
            url: typeof item?.url === 'string' ? item.url : '',
            qualityVariants: Array.isArray(item?.qualityVariants)
              ? item.qualityVariants
                  .map((q: any) => ({
                    label: typeof q?.label === 'string' ? q.label : '',
                    url: typeof q?.url === 'string' ? q.url : '',
                    bitrate: typeof q?.bandwidth === 'number' ? q.bandwidth : null,
                    height: typeof q?.label === 'string' && /\d+p/i.test(q.label) ? Number.parseInt(q.label, 10) : null,
                  }))
                  .filter((q: { url: string }) => q.url.length > 0)
              : [],
          }))
          .filter((item: { title: string; url: string }) => item.url.length > 0)
      : [],
  };
}

export function collapsDeviceSupportsAv1(): boolean {
  const module = getNativeModule();
  return module.collapsDeviceSupportsAv1?.() ?? false;
}

export async function avPlayerLoad(
  url: string,
  options?: {
    headers?: Record<string, string>;
    autoplay?: boolean;
    startPositionSec?: number | null;
  }
): Promise<AVPlayerState> {
  const module = getNativeModule();
  return module.avPlayerLoad(
    url,
    options?.headers ?? {},
    options?.autoplay ?? true,
    options?.startPositionSec ?? null
  );
}

export async function avPlayerConfigurePlaylist(
  items: {
    mediaId?: string;
    title?: string;
    url: string;
    headers?: Record<string, string>;
    season?: number;
    episode?: number;
    voiceovers?: string[];
    subtitles?: CollapsSubtitle[];
    audioVariants?: { title: string; url: string }[];
  }[],
  startIndex = 0,
  autoplay = true,
  kpId?: number | null
): Promise<AVPlayerState> {
  return getNativeModule().avPlayerConfigurePlaylist(items, startIndex, autoplay, kpId ?? null);
}

export async function avPlayerPresentNativeUI(): Promise<void> {
  await getNativeModule().avPlayerPresentNativeUI();
}

export async function avPlayerDismissNativeUI(): Promise<void> {
  await getNativeModule().avPlayerDismissNativeUI();
  // Orientation will be locked back via onAVPlayerDismissed event
}

export async function avPlayerSelectEpisode(index: number, autoplay = true): Promise<AVPlayerState> {
  return getNativeModule().avPlayerSelectEpisode(index, autoplay);
}

export async function avPlayerNextEpisode(autoplay = true): Promise<AVPlayerState> {
  return getNativeModule().avPlayerNextEpisode(autoplay);
}

export async function avPlayerPreviousEpisode(autoplay = true): Promise<AVPlayerState> {
  return getNativeModule().avPlayerPreviousEpisode(autoplay);
}

export function avPlayerPlay(): AVPlayerState {
  return getNativeModule().avPlayerPlay();
}

export function avPlayerPause(): AVPlayerState {
  return getNativeModule().avPlayerPause();
}

export function avPlayerStop(): void {
  getNativeModule().avPlayerStop();
}

export function avPlayerSeek(positionSec: number): AVPlayerState {
  return getNativeModule().avPlayerSeek(positionSec);
}

export function avPlayerSetRate(rate: number): AVPlayerState {
  return getNativeModule().avPlayerSetRate(rate);
}

export function avPlayerSetPreferredPeakBitRate(bitrate: number): void {
  getNativeModule().avPlayerSetPreferredPeakBitRate(bitrate);
}

export async function avPlayerRefreshQualityOptions(): Promise<AVPlayerQualityOption[]> {
  return getNativeModule().avPlayerRefreshQualityOptions();
}

export function avPlayerListQualityOptions(): AVPlayerQualityOption[] {
  return getNativeModule().avPlayerListQualityOptions();
}

export function avPlayerSelectQuality(index?: number | null): void {
  getNativeModule().avPlayerSelectQuality(index ?? null);
}

export function avPlayerSnapshot(): AVPlayerState {
  return getNativeModule().avPlayerSnapshot();
}

export function avPlayerListAudioTracks(): AVPlayerTrack[] {
  return getNativeModule().avPlayerListAudioTracks();
}

export function avPlayerSelectAudioTrack(index?: number | null): void {
  getNativeModule().avPlayerSelectAudioTrack(index ?? null);
}

export function avPlayerListSubtitleTracks(): AVPlayerTrack[] {
  return getNativeModule().avPlayerListSubtitleTracks();
}

export function avPlayerSelectSubtitleTrack(index?: number | null): void {
  getNativeModule().avPlayerSelectSubtitleTrack(index ?? null);
}

export function addAVPlayerStateListener(listener: (state: AVPlayerState) => void) {
  return addNativeListener('onAVPlayerStateChanged', listener);
}

export function addAVPlayerProgressListener(listener: (state: AVPlayerState) => void) {
  return addNativeListener('onAVPlayerProgress', listener);
}

export function addAVPlayerEpisodeChangedListener(listener: (state: AVPlayerState) => void) {
  return addNativeListener('onAVPlayerEpisodeChanged', listener);
}

export function getCollapsWatchProgress(kpId: number, season?: number | null, episode?: number | null): CollapsWatchProgressSnapshot {
  return getNativeModule().getCollapsWatchProgress?.(kpId, season ?? null, episode ?? null) ?? {
    schemaVersion: 1,
    source: 'collaps',
    mediaId: `kp_${kpId}`,
    kpId,
    season: season ?? null,
    episode: episode ?? null,
    kind: season != null && episode != null ? 'episode' : 'movie_or_generic',
    positionMs: 0,
    durationMs: 0,
    progressPercent: 0,
    watched: false,
    updatedAtMs: 0,
    lastSeason: null,
    lastEpisode: null,
    lastPositionMs: 0,
    lastDurationMs: 0,
    lastUpdatedAtMs: 0,
  };
}

export function listCollapsWatchProgressRecords(kpId?: number | null): CollapsWatchProgressRecord[] {
  return getNativeModule().listCollapsWatchProgressRecords?.(kpId ?? null) ?? [];
}
