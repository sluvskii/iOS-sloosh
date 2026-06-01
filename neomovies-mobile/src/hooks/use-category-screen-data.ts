import { useEffect, useRef, useState } from 'react';
import * as SecureStore from 'expo-secure-store';

import { getPopularMovies, getTopFilms, getTopSeries } from '@/lib/neomovies-api';
import { getOfflineModeSnapshot, subscribeOfflineMode } from '@/lib/offline-mode';
import { PopularMovie } from '@/types/api';

type CategoryKind = 'popular' | 'top-films' | 'top-series';
type CategoryCachePayload = {
  items: PopularMovie[];
  page: number;
  totalPages: number;
  updatedAt: number;
};

const CATEGORY_CACHE_PREFIX = 'neomovies_category_v1';
const memoryCache: Partial<Record<CategoryKind, CategoryCachePayload>> = {};

function cacheKey(kind: CategoryKind) {
  return `${CATEGORY_CACHE_PREFIX}:${kind}`;
}

function isDifferent(a: CategoryCachePayload | null, b: CategoryCachePayload) {
  if (!a) return true;
  return (
    a.page !== b.page ||
    a.totalPages !== b.totalPages ||
    JSON.stringify(a.items) !== JSON.stringify(b.items)
  );
}

function toCachePayload(items: PopularMovie[], page: number, totalPages: number): CategoryCachePayload {
  return {
    items,
    page,
    totalPages,
    updatedAt: Date.now(),
  };
}

async function getCategoryPage(kind: CategoryKind, page: number) {
  if (kind === 'popular') return getPopularMovies(page);
  if (kind === 'top-films') return getTopFilms(page);
  return getTopSeries(page);
}

export function useCategoryScreenData(kind: CategoryKind) {
  const [offlineState, setOfflineState] = useState(getOfflineModeSnapshot());
  const initialCache = memoryCache[kind] ?? null;
  const [loading, setLoading] = useState(initialCache === null);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [items, setItems] = useState<PopularMovie[]>(initialCache?.items ?? []);
  const [page, setPage] = useState(initialCache?.page ?? 0);
  const [totalPages, setTotalPages] = useState(initialCache?.totalPages ?? 0);
  const requestIdRef = useRef(0);

  const loadPage = async (requestedPage: number, append: boolean, options?: { clearError?: boolean }) => {
    const requestId = append ? requestIdRef.current : requestIdRef.current + 1;
    if (!append) {
      requestIdRef.current = requestId;
      setLoading(true);
    } else {
      setLoadingMore(true);
    }
    if (options?.clearError ?? true) setError(null);
    try {
      const data = await getCategoryPage(kind, requestedPage);
      if (requestId !== requestIdRef.current) return;
      const incoming = data.results ?? [];
      let nextItems: PopularMovie[] = [];
      setItems((previous) => {
        if (!append) return incoming;
        const next = [...previous];
        for (const item of incoming) {
          if (!next.find((value) => value.id === item.id)) {
            next.push(item);
          }
        }
        nextItems = next;
        return next;
      });
      const nextPage = requestedPage;
      const nextTotalPages = data.pages ?? requestedPage;
      if (!append) {
        nextItems = incoming;
      }
      setPage(nextPage);
      setTotalPages(nextTotalPages);

      const payload = toCachePayload(nextItems, nextPage, nextTotalPages);
      memoryCache[kind] = payload;
      await SecureStore.setItemAsync(cacheKey(kind), JSON.stringify(payload));
    } catch (reason) {
      if (requestId !== requestIdRef.current) return;
      setError(reason instanceof Error ? reason.message : 'Request failed');
    } finally {
      if (requestId === requestIdRef.current) {
        setLoading(false);
        setLoadingMore(false);
      }
    }
  };

  useEffect(() => {
    return subscribeOfflineMode(setOfflineState);
  }, []);

  useEffect(() => {
    let mounted = true;
    requestIdRef.current += 1;

    setError(null);
    const inMemory = memoryCache[kind] ?? null;
    const hasInMemoryItems = Boolean(inMemory && (inMemory.items?.length ?? 0) > 0);
    if (inMemory) {
      setItems(inMemory.items);
      setPage(inMemory.page);
      setTotalPages(inMemory.totalPages);
      setLoading(!hasInMemoryItems);
    } else {
      setItems([]);
      setPage(0);
      setTotalPages(0);
      setLoading(true);
    }

    (async () => {
      if (!inMemory) {
        try {
          const raw = await SecureStore.getItemAsync(cacheKey(kind));
          if (raw && mounted) {
            const disk = JSON.parse(raw) as CategoryCachePayload;
            memoryCache[kind] = disk;
            setItems(disk.items ?? []);
            setPage(disk.page ?? 0);
            setTotalPages(disk.totalPages ?? 0);
            setLoading((disk.items?.length ?? 0) === 0);
          }
        } catch {}
      }

      // Always refresh first page in background to keep category fresh.
      // We keep existing cards on screen and only replace if server has changes.
      const previous = memoryCache[kind] ?? null;
      try {
        const response = await getCategoryPage(kind, 1);
        if (!mounted) return;
        const freshItems = response.results ?? [];
        const freshPayload = toCachePayload(freshItems, 1, response.pages ?? 1);
        if (isDifferent(previous, freshPayload)) {
          memoryCache[kind] = freshPayload;
          setItems(freshPayload.items);
          setPage(freshPayload.page);
          setTotalPages(freshPayload.totalPages);
          await SecureStore.setItemAsync(cacheKey(kind), JSON.stringify(freshPayload));
        }
        setLoading(false);
      } catch (reason) {
        if (!mounted) return;
        setLoading(false);
        if (!previous || (previous.items?.length ?? 0) === 0) {
          setError(reason instanceof Error ? reason.message : 'Request failed');
        }
      }
    })();

    return () => {
      mounted = false;
    };
  }, [kind, offlineState.enabled]);

  const hasNextPage = page > 0 && page < totalPages;

  const loadNextPage = async () => {
    if (loading || loadingMore || !hasNextPage) return;
    await loadPage(page + 1, true);
  };

  const refresh = async () => {
    await loadPage(1, false, { clearError: true });
  };

  return {
    loading,
    loadingMore,
    error,
    items,
    hasNextPage,
    loadNextPage,
    refresh,
  };
}
