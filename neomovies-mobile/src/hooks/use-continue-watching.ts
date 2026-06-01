import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';

import { listCollapsWatchProgressRecords } from '@/native/collaps-parser';

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

export function useContinueWatching(): ContinueWatchingItem[] {
  const [items, setItems] = useState<ContinueWatchingItem[]>([]);

  useFocusEffect(
    useCallback(() => {
      const records = listCollapsWatchProgressRecords();

      // Group by kpId, keep most recent record per kpId
      const byKpId = new Map<number, typeof records[number]>();
      for (const r of records) {
        const existing = byKpId.get(r.kpId);
        if (!existing || r.updatedAtMs > existing.updatedAtMs) {
          byKpId.set(r.kpId, r);
        }
      }

      const result: ContinueWatchingItem[] = [];

      for (const r of byKpId.values()) {
        if (r.progressPercent < MIN_PROGRESS_PERCENT) continue;

        if (r.kind === 'movie_or_generic') {
          if (r.watched) continue;
          result.push({
            kpId: r.kpId,
            mediaId: r.mediaId,
            kind: 'movie',
            season: null,
            episode: null,
            progressPercent: r.progressPercent,
            updatedAtMs: r.updatedAtMs,
          });
        } else {
          // episode — show current episode (continue watching)
          result.push({
            kpId: r.kpId,
            mediaId: r.mediaId,
            kind: 'episode',
            season: r.season,
            episode: r.episode,
            progressPercent: r.progressPercent,
            updatedAtMs: r.updatedAtMs,
          });

          // next up — next episode if current is mostly watched (>= 85%)
          if (r.progressPercent >= 85 && r.season != null && r.episode != null) {
            result.push({
              kpId: r.kpId,
              mediaId: r.mediaId,
              kind: 'next_up',
              season: r.season,
              episode: r.episode + 1,
              progressPercent: 0,
              updatedAtMs: r.updatedAtMs,
            });
          }
        }
      }

      result.sort((a, b) => b.updatedAtMs - a.updatedAtMs);

      const uniqueKpIds = new Set(result.map((i) => i.kpId));
      if (uniqueKpIds.size < MIN_ITEMS_TO_SHOW) {
        setItems([]);
        return;
      }

      setItems(result.slice(0, MAX_ITEMS));
    }, [])
  );

  return items;
}
