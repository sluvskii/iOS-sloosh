import { useCallback, useEffect, useMemo, useState } from 'react';
import * as SecureStore from 'expo-secure-store';

import { getPopularMovies, getTopFilms, getTopSeries } from '@/lib/neomovies-api';
import { getOfflineModeSnapshot, subscribeOfflineMode } from '@/lib/offline-mode';
import { PopularMovie } from '@/types/api';

type HomeDataState = {
  loading: boolean;
  error: string | null;
  popular: PopularMovie[];
  topFilms: PopularMovie[];
  topSeries: PopularMovie[];
};

const HOME_CACHE_KEY = 'neomovies_home_v1';

type HomeCachePayload = {
  popular: PopularMovie[];
  topFilms: PopularMovie[];
  topSeries: PopularMovie[];
  updatedAt: number;
};

// Lives while app process is alive: instant data on tab revisit.
let memoryCache: HomeCachePayload | null = null;

function toCachePayload(data: Pick<HomeDataState, 'popular' | 'topFilms' | 'topSeries'>): HomeCachePayload {
  return {
    popular: data.popular,
    topFilms: data.topFilms,
    topSeries: data.topSeries,
    updatedAt: Date.now(),
  };
}

function isDifferent(a: HomeCachePayload | null, b: HomeCachePayload) {
  if (!a) return true;
  return (
    JSON.stringify(a.popular) !== JSON.stringify(b.popular) ||
    JSON.stringify(a.topFilms) !== JSON.stringify(b.topFilms) ||
    JSON.stringify(a.topSeries) !== JSON.stringify(b.topSeries)
  );
}

export function useHomeScreenData() {
  const [offlineState, setOfflineState] = useState(getOfflineModeSnapshot());
  const [state, setState] = useState<HomeDataState>({
    loading: memoryCache === null,
    error: null,
    popular: memoryCache?.popular ?? [],
    topFilms: memoryCache?.topFilms ?? [],
    topSeries: memoryCache?.topSeries ?? [],
  });

  const fetchFresh = async (mountedRef?: { current: boolean }) => {
    try {
      const [popularRes, topFilmsRes, topSeriesRes] = await Promise.all([
        getPopularMovies(1),
        getTopFilms(1),
        getTopSeries(1),
      ]);

      if (mountedRef && !mountedRef.current) return;

      const fresh = toCachePayload({
        popular: popularRes.results ?? [],
        topFilms: topFilmsRes.results ?? [],
        topSeries: topSeriesRes.results ?? [],
      });

      if (isDifferent(memoryCache, fresh)) {
        memoryCache = fresh;
        setState({
          loading: false,
          error: null,
          popular: fresh.popular,
          topFilms: fresh.topFilms,
          topSeries: fresh.topSeries,
        });
        await SecureStore.setItemAsync(HOME_CACHE_KEY, JSON.stringify(fresh));
      } else {
        setState((prev) => ({ ...prev, loading: false, error: null }));
      }
    } catch (error) {
      if (mountedRef && !mountedRef.current) return;
      const hasCache = Boolean(memoryCache && (memoryCache.popular.length || memoryCache.topFilms.length || memoryCache.topSeries.length));
      setState((prev) => ({
        ...prev,
        loading: false,
        error: hasCache ? null : (error instanceof Error ? error.message : 'Request failed'),
      }));
      throw error;
    }
  };

  useEffect(() => {
    return subscribeOfflineMode(setOfflineState);
  }, []);

  useEffect(() => {
    const mountedRef = { current: true };

    (async () => {
      if (!memoryCache) {
        try {
          const raw = await SecureStore.getItemAsync(HOME_CACHE_KEY);
          if (raw && mountedRef.current) {
            const disk = JSON.parse(raw) as HomeCachePayload;
            memoryCache = disk;
            setState({
              loading: false,
              error: null,
              popular: disk.popular ?? [],
              topFilms: disk.topFilms ?? [],
              topSeries: disk.topSeries ?? [],
            });
          }
        } catch {}
      }
      await fetchFresh(mountedRef);
    })();

    return () => {
      mountedRef.current = false;
    };
  }, [offlineState.enabled]);

  const refresh = useCallback(async () => {
    await fetchFresh();
  }, []);

  return useMemo(() => ({ ...state, refresh }), [state, refresh]);
}
