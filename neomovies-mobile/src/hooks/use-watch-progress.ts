import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';

import { CollapsWatchProgressSnapshot, getCollapsWatchProgress } from '@/native/collaps-parser';

export function useWatchProgress(
  kpId: number | null,
  season: number | null = null,
  episode: number | null = null
): CollapsWatchProgressSnapshot | null {
  const enabled = kpId != null && Number.isFinite(kpId);

  const [progress, setProgress] = useState<CollapsWatchProgressSnapshot | null>(() =>
    enabled && kpId != null ? getCollapsWatchProgress(kpId, season, episode) : null
  );

  useFocusEffect(
    useCallback(() => {
      if (!enabled || kpId == null) {
        setProgress(null);
        return;
      }
      setProgress(getCollapsWatchProgress(kpId, season, episode));
    }, [enabled, kpId, season, episode])
  );

  return progress;
}
