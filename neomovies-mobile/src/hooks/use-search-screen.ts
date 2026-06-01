import { useEffect, useRef, useState } from 'react';
import * as SecureStore from 'expo-secure-store';

import { MAINTENANCE_ERROR_CODE, getOfflineModeSnapshot, subscribeOfflineMode } from '@/lib/offline-mode';
import { searchMovies } from '@/lib/neomovies-api';
import { SearchResultItem } from '@/types/api';

const SEARCH_HISTORY_KEY = 'neomovies_search_history_v1';
const HISTORY_LIMIT = 5;
const AUTO_SEARCH_MIN_CHARS = 3;
const AUTO_SEARCH_DEBOUNCE_MS = 700;
const LETTER_RE = /[A-Za-zА-Яа-яЁёЇїІіЄєЎў]/;

type SearchScreenSessionCache = {
  query: string;
  results: SearchResultItem[];
  page: number;
  totalPages: number;
  error: string | null;
};

let searchScreenSessionCache: SearchScreenSessionCache = {
  query: '',
  results: [],
  page: 0,
  totalPages: 0,
  error: null,
};

function normalizeQuery(value: string) {
  return value.trim();
}

function normalizeHistoryKey(value: string) {
  return normalizeQuery(value).replace(/\s+/g, ' ').toLocaleLowerCase();
}

function shouldTrackHistoryQuery(value: string) {
  const normalized = normalizeQuery(value);
  return normalized.length >= AUTO_SEARCH_MIN_CHARS && LETTER_RE.test(normalized);
}

export function useSearchScreen() {
  const [offlineState, setOfflineState] = useState(getOfflineModeSnapshot());
  const [query, setQuery] = useState(searchScreenSessionCache.query);
  const [loading, setLoading] = useState(false);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState<string | null>(searchScreenSessionCache.error);
  const [results, setResults] = useState<SearchResultItem[]>(searchScreenSessionCache.results);
  const [recentQueries, setRecentQueries] = useState<string[]>([]);
  const [page, setPage] = useState(searchScreenSessionCache.page);
  const [totalPages, setTotalPages] = useState(searchScreenSessionCache.totalPages);
  const requestIdRef = useRef(0);
  const lastSavedHistoryQueryRef = useRef('');
  const skipFirstAutoSearchRef = useRef(
    searchScreenSessionCache.query.length >= AUTO_SEARCH_MIN_CHARS &&
      searchScreenSessionCache.results.length > 0
  );

  useEffect(() => {
    return subscribeOfflineMode(setOfflineState);
  }, []);

  useEffect(() => {
    (async () => {
      try {
        const raw = await SecureStore.getItemAsync(SEARCH_HISTORY_KEY);
        if (!raw) return;
        const parsed = JSON.parse(raw) as string[];
        setRecentQueries(Array.isArray(parsed) ? parsed.slice(0, HISTORY_LIMIT) : []);
      } catch {
        setRecentQueries([]);
      }
    })();
  }, []);

  const persistHistory = async (next: string[]) => {
    setRecentQueries(next);
    try {
      await SecureStore.setItemAsync(SEARCH_HISTORY_KEY, JSON.stringify(next));
    } catch {
      return;
    }
  };

  const pushHistory = async (value: string) => {
    const normalized = normalizeQuery(value);
    if (!shouldTrackHistoryQuery(normalized)) return;
    const normalizedKey = normalizeHistoryKey(normalized);
    if (lastSavedHistoryQueryRef.current === normalizedKey) return;
    const deduped = [
      normalized,
      ...recentQueries.filter((item) => normalizeHistoryKey(item) !== normalizedKey),
    ];
    const next = deduped.slice(0, HISTORY_LIMIT);
    lastSavedHistoryQueryRef.current = normalizedKey;
    await persistHistory(next);
  };

  const removeRecentQuery = async (value: string) => {
    const next = recentQueries.filter((item) => item !== value);
    await persistHistory(next);
  };

  const executeSearch = async (
    sourceQuery: string,
    options?: { trackHistory?: boolean; nextPage?: number; append?: boolean }
  ) => {
    const normalized = normalizeQuery(sourceQuery);
    if (normalized.length < AUTO_SEARCH_MIN_CHARS) {
      setError(null);
      setResults([]);
      setLoading(false);
      setLoadingMore(false);
      setPage(0);
      setTotalPages(0);
      return;
    }

    const requestedPage = options?.nextPage ?? 1;
    const shouldAppend = options?.append === true && requestedPage > 1;

    const requestId = shouldAppend ? requestIdRef.current : requestIdRef.current + 1;
    if (!shouldAppend) {
      requestIdRef.current = requestId;
    }
    if (shouldAppend) {
      setLoadingMore(true);
    } else {
      setLoading(true);
    }
    setError(null);

    try {
      const data = await searchMovies(normalized, requestedPage);
      if (requestId !== requestIdRef.current) return;
      const incoming = data.results ?? [];
      setResults((previous) => {
        if (!shouldAppend) {
          return incoming;
        }
        const next = [...previous];
        for (const item of incoming) {
          if (!next.find((existing) => existing.id === item.id)) {
            next.push(item);
          }
        }
        return next;
      });
      setPage(requestedPage);
      setTotalPages(data.pages ?? requestedPage);
      if (
        options?.trackHistory &&
        requestedPage === 1 &&
        incoming.length > 0 &&
        shouldTrackHistoryQuery(normalized)
      ) {
        await pushHistory(normalized);
      }
    } catch (e) {
      if (requestId !== requestIdRef.current) return;
      const message = e instanceof Error ? e.message : 'Request failed';
      if (message === MAINTENANCE_ERROR_CODE) {
        setError('Offline mode is enabled. Search is temporarily unavailable.');
      } else {
        setError(message);
      }
    } finally {
      if (requestId === requestIdRef.current) {
        if (shouldAppend) {
          setLoadingMore(false);
        } else {
          setLoading(false);
        }
      }
    }
  };

  const runSearch = async (customQuery?: string) => {
    const source = customQuery ?? query;
    const normalized = normalizeQuery(source);
    skipFirstAutoSearchRef.current = false;
    if (customQuery) {
      setQuery(normalized);
    }
    await executeSearch(normalized, { trackHistory: true });
  };

  const trackCurrentQuery = async () => {
    const normalized = normalizeQuery(query);
    if (!shouldTrackHistoryQuery(normalized)) return;
    await pushHistory(normalized);
  };

  useEffect(() => {
    searchScreenSessionCache = {
      query,
      results,
      page,
      totalPages,
      error,
    };
  }, [error, page, query, results, totalPages]);

  useEffect(() => {
    const normalized = normalizeQuery(query);
    if (skipFirstAutoSearchRef.current) {
      skipFirstAutoSearchRef.current = false;
      return;
    }
    if (normalized.length < AUTO_SEARCH_MIN_CHARS) {
      setError(null);
      setResults([]);
      setLoading(false);
      setLoadingMore(false);
      setPage(0);
      setTotalPages(0);
      return;
    }
    const timer = setTimeout(() => {
      void executeSearch(normalized, { trackHistory: false });
    }, AUTO_SEARCH_DEBOUNCE_MS);
    return () => clearTimeout(timer);
    // executeSearch intentionally excluded: recreating it each render would retrigger debounce loop.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [query, offlineState.enabled]);

  const hasNextPage = page > 0 && page < totalPages;

  const loadNextPage = async () => {
    if (loading || loadingMore || !hasNextPage) return;
    const normalized = normalizeQuery(query);
    if (normalized.length < AUTO_SEARCH_MIN_CHARS) return;
    await executeSearch(normalized, { nextPage: page + 1, append: true });
  };

  const refresh = async () => {
    const normalized = normalizeQuery(query);
    if (normalized.length < AUTO_SEARCH_MIN_CHARS) {
      return;
    }
    await executeSearch(normalized, { trackHistory: false });
  };

  return {
    query,
    setQuery,
    loading,
    loadingMore,
    error,
    results,
    recentQueries,
    hasNextPage,
    removeRecentQuery,
    runSearch,
    loadNextPage,
    refresh,
    trackCurrentQuery,
    autoSearchMinChars: AUTO_SEARCH_MIN_CHARS,
  };
}
