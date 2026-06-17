import { useFocusEffect } from 'expo-router';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import * as SecureStore from 'expo-secure-store';

import { useContentSource } from '@/hooks/use-content-source';
import { useWatchProgress } from '@/hooks/use-watch-progress';
import { getProviderEmbedHtml, getTvEpisodeDetails } from '@/lib/neomovies-api';
import { CollapsCatalog, CollapsSeason, listCollapsWatchProgressRecords, parseCollapsCatalog } from '@/native/collaps-parser';
import { MediaDetails } from '@/types/api';
import { buildAllohaSeriesCatalogFromApi } from '@/hooks/watch-player/alloha';

type EpisodeMeta = {
  overview?: string;
  name?: string;
  tmdbRating?: number | null;
  imdbRating?: number | null;
};

type EpisodeMetaCacheEntry = {
  overview?: string;
  name?: string;
  tmdbRating?: number | null;
  imdbRating?: number | null;
  fetchedAtMs: number;
  missing?: boolean;
};

type EpisodeMetaCachePayload = {
  entries: Record<string, EpisodeMetaCacheEntry>;
};

const EPISODE_META_CACHE_TTL_MS = 1000 * 60 * 60 * 12;
const EPISODE_META_MISSING_CACHE_TTL_MS = 1000 * 60 * 30;
const EPISODE_META_CACHE_PREFIX = 'series_episode_meta_v1';
const EPISODE_META_WRITE_DEBOUNCE_MS = 700;
const PRIORITY_EPISODE_META_PREFETCH = 6;
const EPISODE_META_FETCH_CONCURRENCY = 2;
const BACKGROUND_EPISODE_META_FETCH_CONCURRENCY = 1;
const BACKGROUND_EPISODE_META_DELAY_MS = 140;
const BACKGROUND_EPISODE_META_BATCH_SIZE = 8;
const EPISODE_META_RETRY_DELAYS_MS = [180, 500];
const EPISODE_META_INITIAL_DEFER_MS = 350;

type EpisodeMetaStorageAdapter = {
  getString: (key: string) => Promise<string | null>;
  setString: (key: string, value: string) => Promise<void>;
};

function createEpisodeMetaStorage(): EpisodeMetaStorageAdapter {
  try {
    // Lazy require to avoid crashing on web/unsupported runtimes.
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    const mmkvModule = require('react-native-mmkv') as { MMKV?: new (...args: unknown[]) => { getString: (key: string) => string | undefined; set: (key: string, value: string) => void } };
    if (typeof mmkvModule?.MMKV === 'function') {
      const instance = new mmkvModule.MMKV({ id: 'neomovies_episode_meta' });
      return {
        getString: async (key: string) => instance.getString(key) ?? null,
        setString: async (key: string, value: string) => {
          instance.set(key, value);
        },
      };
    }
  } catch {
    // fall through to SecureStore
  }

  return {
    getString: (key: string) => SecureStore.getItemAsync(key),
    setString: (key: string, value: string) => SecureStore.setItemAsync(key, value),
  };
}

const episodeMetaStorage = createEpisodeMetaStorage();
const episodeMetaMemoryCache = new Map<string, Record<string, EpisodeMetaCacheEntry>>();
const episodeMetaWriteTimers = new Map<string, ReturnType<typeof setTimeout>>();

function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function runAfterIdle(callback: () => void) {
  if (typeof requestIdleCallback === 'function') {
    const id = requestIdleCallback(() => callback(), { timeout: 400 });
    return () => cancelIdleCallback(id);
  }
  const timer = setTimeout(callback, 0);
  return () => clearTimeout(timer);
}

async function waitForIdle(): Promise<void> {
  await new Promise<void>((resolve) => {
    const cancel = runAfterIdle(resolve);
    void cancel;
  });
}

function episodeMetaCacheKey(mediaId: string, season: number): string {
  const normalized = String(mediaId).replace(/^kp_/, '').trim();
  return `${EPISODE_META_CACHE_PREFIX}_${normalized}_s${season}`;
}

async function readEpisodeMetaCache(mediaId: string, season: number): Promise<Record<string, EpisodeMetaCacheEntry>> {
  const key = episodeMetaCacheKey(mediaId, season);
  const memoryValue = episodeMetaMemoryCache.get(key);
  if (memoryValue) return memoryValue;
  try {
    const raw = await episodeMetaStorage.getString(key);
    if (!raw) return {};
    const parsed = JSON.parse(raw) as EpisodeMetaCachePayload;
    const next = parsed.entries ?? {};
    episodeMetaMemoryCache.set(key, next);
    return next;
  } catch {
    return {};
  }
}

function writeEpisodeMetaCacheDebounced(mediaId: string, season: number, entries: Record<string, EpisodeMetaCacheEntry>): void {
  const key = episodeMetaCacheKey(mediaId, season);
  episodeMetaMemoryCache.set(key, entries);
  const existingTimer = episodeMetaWriteTimers.get(key);
  if (existingTimer) clearTimeout(existingTimer);

  const timer = setTimeout(() => {
    episodeMetaWriteTimers.delete(key);
    try {
      void episodeMetaStorage
        .setString(key, JSON.stringify({ entries } satisfies EpisodeMetaCachePayload))
        .catch(() => {
          // ignore async cache write failures
        });
    } catch {
      // ignore cache write failures
    }
  }, EPISODE_META_WRITE_DEBOUNCE_MS);

  episodeMetaWriteTimers.set(key, timer);
}

function shouldRetryEpisodeMetaError(error: unknown): boolean {
  if (!(error instanceof Error)) return true;
  const message = error.message || '';
  if (message.includes('HTTP 404')) return false;
  return true;
}

async function fetchEpisodeMetaWithRetry(
  mediaId: string,
  season: number,
  episode: number
) {
  let attempt = 0;
  while (true) {
    try {
      return await getTvEpisodeDetails(mediaId, season, episode);
    } catch (error) {
      if (!shouldRetryEpisodeMetaError(error) || attempt >= EPISODE_META_RETRY_DELAYS_MS.length) {
        throw error;
      }
      await sleep(EPISODE_META_RETRY_DELAYS_MS[attempt]);
      attempt += 1;
    }
  }
}

export function useSeriesDetails(details: MediaDetails | null) {
  const { source, ready: sourceReady } = useContentSource();
  const [catalog, setCatalog] = useState<CollapsCatalog | null>(null);
  const [selectedSeason, setSelectedSeason] = useState(1);
  const [isSeasonPickerExpanded, setSeasonPickerExpanded] = useState(false);
  const [episodeMetaMap, setEpisodeMetaMap] = useState<Record<string, EpisodeMeta>>({});
  const episodeMetaPatchRef = useRef<Record<string, EpisodeMeta>>({});
  const episodeMetaFlushTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const [seasonProgressMap, setSeasonProgressMap] = useState<Record<string, number>>({});
  const mediaIdNumber = Number((details?.id ?? '').replace(/^kp_/, ''));
  const canReadProgress = Number.isFinite(mediaIdNumber);
  const progressKpId = details?.type === 'tv' && canReadProgress ? mediaIdNumber : null;
  const seriesProgress = useWatchProgress(progressKpId);

  const flushEpisodeMetaPatch = useCallback(() => {
    const patch = episodeMetaPatchRef.current;
    episodeMetaPatchRef.current = {};
    episodeMetaFlushTimerRef.current = null;
    if (Object.keys(patch).length === 0) return;
    runAfterIdle(() => {
      setEpisodeMetaMap((prev) => {
        let changed = false;
        for (const [key, nextMeta] of Object.entries(patch)) {
          const prevMeta = prev[key];
          if (
            !prevMeta
            || prevMeta.name !== nextMeta.name
            || prevMeta.overview !== nextMeta.overview
            || prevMeta.tmdbRating !== nextMeta.tmdbRating
            || prevMeta.imdbRating !== nextMeta.imdbRating
          ) {
            changed = true;
            break;
          }
        }
        if (!changed) return prev;
        return { ...prev, ...patch };
      });
    });
  }, []);

  const enqueueEpisodeMetaPatch = useCallback((patch: Record<string, EpisodeMeta>) => {
    if (Object.keys(patch).length === 0) return;
    episodeMetaPatchRef.current = { ...episodeMetaPatchRef.current, ...patch };
    if (episodeMetaFlushTimerRef.current) return;
    episodeMetaFlushTimerRef.current = setTimeout(() => {
      flushEpisodeMetaPatch();
    }, 220);
  }, [flushEpisodeMetaPatch]);

  useEffect(() => {
    let active = true;
    if (!details || details.type !== 'tv') {
      setCatalog(null);
      return () => {
        active = false;
      };
    }
    void (async () => {
      try {
        if (!sourceReady) return;
        const parsed =
          source === 'alloha'
            ? (await (async () => {
                const apiCatalog = await buildAllohaSeriesCatalogFromApi(details.id).catch((error) => {
                  if (__DEV__) {
                    console.log('[AllohaSeries] api catalog error', {
                      message: error instanceof Error ? error.message : String(error),
                    });
                  }
                  return null;
                });
                return apiCatalog;
              })())
            : await (async () => {
                const payload = await getProviderEmbedHtml(details.id, source);
                return parseCollapsCatalog(payload.embedHtml);
              })();
        if (!active) return;
        if (__DEV__) {
          console.log('[SeriesDetails] parsed catalog', {
            source,
            kind: parsed?.kind ?? null,
            seasons: parsed && parsed.kind === 'series' ? parsed.seasons.length : 0,
            episodes:
              parsed && parsed.kind === 'series'
                ? parsed.seasons.reduce((sum, season) => sum + season.episodes.length, 0)
                : 0,
          });
        }
        setCatalog(parsed);
      } catch {
        if (!active) return;
        setCatalog(null);
      }
    })();
    return () => {
      active = false;
    };
  }, [details, source, sourceReady]);

  const seriesCatalog = catalog?.kind === 'series' ? catalog : null;
  const selectedSeasonData: CollapsSeason | null =
    seriesCatalog?.seasons.find((season) => season.season === selectedSeason) ??
    seriesCatalog?.seasons[0] ??
    null;

  useEffect(() => {
    if (!selectedSeasonData?.season) return;
    setSelectedSeason(selectedSeasonData.season);
  }, [selectedSeasonData?.season]);

  useEffect(() => {
    let active = true;
    if (!details || !selectedSeasonData) return () => {
      active = false;
    };

    const season = selectedSeasonData.season;
    const episodes = selectedSeasonData.episodes.slice();
    const now = Date.now();

    void (async () => {
      const cacheEntries = await readEpisodeMetaCache(details.id, season);
      if (!active) return;

      const cachedMetaPatch: Record<string, EpisodeMeta> = {};
      for (const item of episodes) {
        const key = `${item.season}-${item.episode}`;
        const cache = cacheEntries[key];
        if (!cache) continue;
        cachedMetaPatch[key] = {
          overview: cache.overview,
          name: cache.name,
          tmdbRating: cache.tmdbRating,
          imdbRating: cache.imdbRating,
        };
      }
      if (Object.keys(cachedMetaPatch).length > 0) {
        enqueueEpisodeMetaPatch(cachedMetaPatch);
      }

      const pendingEpisodes = episodes.filter((item) => {
        const key = `${item.season}-${item.episode}`;
        const cache = cacheEntries[key];
        if (!cache) return true;
        const ttl = cache.missing ? EPISODE_META_MISSING_CACHE_TTL_MS : EPISODE_META_CACHE_TTL_MS;
        return now - cache.fetchedAtMs > ttl;
      }).sort((a, b) => {
        const pivot = seriesProgress?.lastEpisode ?? selectedSeasonData.episodes[0]?.episode ?? 1;
        return Math.abs(a.episode - pivot) - Math.abs(b.episode - pivot);
      });

      if (pendingEpisodes.length === 0) return;

      await waitForIdle();
      if (!active) return;
      await sleep(EPISODE_META_INITIAL_DEFER_MS);
      if (!active) return;

      const priorityQueue = pendingEpisodes.slice(0, PRIORITY_EPISODE_META_PREFETCH);
      const backgroundQueue = pendingEpisodes.slice(PRIORITY_EPISODE_META_PREFETCH);

      const nextCacheEntries = { ...cacheEntries };

      const fetchEpisodeMeta = async (item: typeof pendingEpisodes[number]) => {
        const key = `${item.season}-${item.episode}`;
        const candidateMediaIds = Array.from(
          new Set(
            [details.id, details.sourceId]
              .map((value) => String(value ?? '').trim())
              .filter((value) => value.length > 0)
          )
        );
        try {
          let data:
            | {
                overview?: string;
                name?: string;
                ratings?: { tmdb?: number | null; imdb?: number | null };
              }
            | null = null;

          for (const candidateMediaId of candidateMediaIds) {
            try {
              const attempt = await fetchEpisodeMetaWithRetry(candidateMediaId, item.season, item.episode);
              data = attempt;
              const hasUsefulPayload = Boolean(
                (attempt.name && attempt.name.trim().length > 0) ||
                (attempt.overview && attempt.overview.trim().length > 0) ||
                attempt.ratings?.tmdb != null ||
                attempt.ratings?.imdb != null
              );
              if (hasUsefulPayload) break;
            } catch {
              continue;
            }
          }

          if (!active) return null;
          if (!data) {
            nextCacheEntries[key] = {
              fetchedAtMs: Date.now(),
              missing: true,
            };
            return { key, meta: {} };
          }
          const nextMeta = {
            overview: data.overview,
            name: data.name || item.title,
            tmdbRating: data.ratings?.tmdb,
            imdbRating: data.ratings?.imdb,
          };
          nextCacheEntries[key] = {
            ...nextMeta,
            fetchedAtMs: Date.now(),
            missing: false,
          };
          return { key, meta: nextMeta };
        } catch {
          if (!active) return null;
          nextCacheEntries[key] = {
            fetchedAtMs: Date.now(),
            missing: true,
          };
          return { key, meta: {} };
        }
      };

      const runQueue = async (
        queue: typeof pendingEpisodes,
        concurrency: number,
        delayMs = 0
      ) => {
        const patch: Record<string, EpisodeMeta> = {};
        const workers = Array.from({ length: Math.min(concurrency, queue.length) }, async () => {
          while (active && queue.length > 0) {
            const item = queue.shift();
            if (!item) return;
            if (delayMs > 0) {
              await sleep(delayMs);
              if (!active) return;
            }
            const result = await fetchEpisodeMeta(item);
            if (result) {
              patch[result.key] = result.meta;
            }
          }
        });
        await Promise.all(workers);
        return patch;
      };

      const priorityPatch = await runQueue(priorityQueue, EPISODE_META_FETCH_CONCURRENCY);
      if (!active) return;
      if (Object.keys(priorityPatch).length > 0) {
        enqueueEpisodeMetaPatch(priorityPatch);
      }
      writeEpisodeMetaCacheDebounced(details.id, season, nextCacheEntries);

      if (backgroundQueue.length > 0) {
        void (async () => {
          const queue = [...backgroundQueue];
          while (active && queue.length > 0) {
            const chunk = queue.splice(0, BACKGROUND_EPISODE_META_BATCH_SIZE);
            const patch = await runQueue(
              chunk,
              BACKGROUND_EPISODE_META_FETCH_CONCURRENCY,
              BACKGROUND_EPISODE_META_DELAY_MS
            );
            if (!active) return;
            if (Object.keys(patch).length > 0) {
              enqueueEpisodeMetaPatch(patch);
              writeEpisodeMetaCacheDebounced(details.id, season, nextCacheEntries);
            }
          }
        })();
      }
    })();

    return () => {
      active = false;
      if (episodeMetaFlushTimerRef.current) {
        clearTimeout(episodeMetaFlushTimerRef.current);
        episodeMetaFlushTimerRef.current = null;
      }
      flushEpisodeMetaPatch();
    };
  }, [details, enqueueEpisodeMetaPatch, flushEpisodeMetaPatch, selectedSeasonData, source, seriesProgress?.lastEpisode]);

  useFocusEffect(
    useCallback(() => {
      if (!details || details.type !== 'tv' || !Number.isFinite(mediaIdNumber)) {
        setSeasonProgressMap({});
        return;
      }

      const records = listCollapsWatchProgressRecords(mediaIdNumber);
      const nextMap: Record<string, number> = {};
      for (const record of records) {
        if (record.season == null || record.episode == null) continue;
        nextMap[`${record.season}-${record.episode}`] = Math.max(0, Math.min(record.progressPercent ?? 0, 100));
      }
      setSeasonProgressMap(nextMap);
    }, [details, mediaIdNumber])
  );

  const firstEpisode = selectedSeasonData?.episodes[0] ?? null;

  const sortedEpisodes = useMemo(
    () => selectedSeasonData?.episodes.slice().sort((a, b) => a.episode - b.episode) ?? [],
    [selectedSeasonData]
  );

  return {
    seriesCatalog,
    selectedSeasonData,
    selectedSeason,
    setSelectedSeason,
    isSeasonPickerExpanded,
    setSeasonPickerExpanded,
    episodeMetaMap,
    firstEpisode,
    mediaIdNumber,
    canReadProgress,
    seriesProgress,
    seasonProgressMap,
    sortedEpisodes,
  };
}
