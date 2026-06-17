import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';

import { useContentSource } from '@/hooks/use-content-source';
import { buildAllohaSeriesCatalogFromApi } from '@/hooks/watch-player/alloha';
import { getProviderEmbedHtml } from '@/lib/neomovies-api';
import {
  CollapsCatalog,
  CollapsEpisode,
  CollapsWatchProgressRecord,
  listCollapsWatchProgressRecords,
  parseCollapsCatalog,
} from '@/native/collaps-parser';

export type ContinueWatchingItem = {
  kpId: number;
  mediaId: string;
  kind: 'movie' | 'episode' | 'next_up';
  season: number | null;
  episode: number | null;
  progressPercent: number;
  updatedAtMs: number;
};

const MIN_PROGRESS_PERCENT = 3;
const MIN_ITEMS_TO_SHOW = 1;
const MAX_ITEMS = 20;
const CATALOG_CACHE_TTL_MS = 1000 * 60 * 5;

const catalogCache = new Map<string, { expiresAt: number; value: CollapsCatalog | null }>();

function progressKey(season: number | null, episode: number | null) {
  return `${season ?? 0}-${episode ?? 0}`;
}

async function resolveSeriesCatalog(mediaId: string, source: 'collaps' | 'alloha') {
  const cacheKey = `${source}:${mediaId}`;
  const cached = catalogCache.get(cacheKey);
  if (cached && cached.expiresAt > Date.now()) return cached.value;

  const catalog =
    source === 'alloha'
      ? await buildAllohaSeriesCatalogFromApi(mediaId)
      : await getProviderEmbedHtml(mediaId, source).then((payload) => parseCollapsCatalog(payload.embedHtml));

  catalogCache.set(cacheKey, {
    expiresAt: Date.now() + CATALOG_CACHE_TTL_MS,
    value: catalog,
  });
  return catalog;
}

function findNextEpisode(catalog: CollapsCatalog | null, season: number, episode: number): CollapsEpisode | null {
  if (catalog?.kind !== 'series') return null;
  const episodes = catalog.seasons
    .flatMap((item) => item.episodes)
    .sort((a, b) => a.season - b.season || a.episode - b.episode);
  const currentIndex = episodes.findIndex((item) => item.season === season && item.episode === episode);
  if (currentIndex < 0) return null;
  return episodes[currentIndex + 1] ?? null;
}

function toEpisodeItem(record: CollapsWatchProgressRecord): ContinueWatchingItem {
  return {
    kpId: record.kpId,
    mediaId: record.mediaId,
    kind: 'episode',
    season: record.season,
    episode: record.episode,
    progressPercent: record.progressPercent,
    updatedAtMs: record.updatedAtMs,
  };
}

export function useContinueWatching(): ContinueWatchingItem[] {
  const [items, setItems] = useState<ContinueWatchingItem[]>([]);
  const { source, ready: sourceReady } = useContentSource();

  useFocusEffect(
    useCallback(() => {
      let cancelled = false;
      const records = listCollapsWatchProgressRecords();
      const byKpId = new Map<number, typeof records>();

      for (const record of records) {
        const group = byKpId.get(record.kpId);
        if (group) {
          group.push(record);
        } else {
          byKpId.set(record.kpId, [record]);
        }
      }

      void (async () => {
        if (!sourceReady) return;

        const result: ContinueWatchingItem[] = [];

        for (const group of byKpId.values()) {
          const sorted = group
            .filter((record) => record.progressPercent >= MIN_PROGRESS_PERCENT)
            .sort((a, b) => b.updatedAtMs - a.updatedAtMs);
          if (sorted.length === 0) continue;

          const latestMovie = sorted[0].kind === 'movie_or_generic' ? sorted[0] : null;
          if (latestMovie) {
            if (latestMovie.watched) continue;
            result.push({
              kpId: latestMovie.kpId,
              mediaId: latestMovie.mediaId,
              kind: 'movie',
              season: null,
              episode: null,
              progressPercent: latestMovie.progressPercent,
              updatedAtMs: latestMovie.updatedAtMs,
            });
            continue;
          }

          const latestEpisode = sorted[0];
          if (latestEpisode.kind !== 'episode' || latestEpisode.season == null || latestEpisode.episode == null) {
            continue;
          }

          const episodeRecords = sorted.filter(
            (record) => record.kind === 'episode' && record.season != null && record.episode != null
          );
          const progressByEpisode = new Map(
            episodeRecords.map((record) => [progressKey(record.season, record.episode), record])
          );

          if (!latestEpisode.watched) {
            result.push(toEpisodeItem(latestEpisode));
            continue;
          }

          try {
            const catalog = await resolveSeriesCatalog(latestEpisode.mediaId, source);
            const nextEpisode = findNextEpisode(catalog, latestEpisode.season, latestEpisode.episode);
            if (!nextEpisode) continue;

            const nextProgress = progressByEpisode.get(progressKey(nextEpisode.season, nextEpisode.episode));
            if (nextProgress?.watched) continue;

            result.push({
              kpId: latestEpisode.kpId,
              mediaId: latestEpisode.mediaId,
              kind: 'next_up',
              season: nextEpisode.season,
              episode: nextEpisode.episode,
              progressPercent: nextProgress?.progressPercent ?? 0,
              updatedAtMs: latestEpisode.updatedAtMs,
            });
          } catch {
          }
        }

        if (cancelled) return;

        result.sort((a, b) => b.updatedAtMs - a.updatedAtMs);

        const uniqueKpIds = new Set(result.map((item) => item.kpId));
        if (uniqueKpIds.size < MIN_ITEMS_TO_SHOW) {
          setItems([]);
          return;
        }

        setItems(result.slice(0, MAX_ITEMS));
      })();

      return () => {
        cancelled = true;
      };
    }, [source, sourceReady])
  );

  return items;
}
