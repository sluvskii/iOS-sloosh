import { useCallback, useEffect, useMemo, useState } from 'react';

import { getStoredTokens } from '@/lib/neoid-auth';
import { getFavorites } from '@/lib/neomovies-api';
import { FavoriteItem, PopularMovie } from '@/types/api';

type FavoritesState = {
  loading: boolean;
  error: string | null;
  items: FavoriteItem[];
  isAuthenticated: boolean;
};

function mapFavoriteToMovie(item: FavoriteItem): PopularMovie {
  return {
    id: item.mediaId,
    title: item.title,
    rating: item.rating ?? null,
    year: item.year ?? null,
    posterUrl: item.posterUrl,
  };
}

export function useFavoritesScreen() {
  const [state, setState] = useState<FavoritesState>({
    loading: true,
    error: null,
    items: [],
    isAuthenticated: false,
  });

  const load = useCallback(async () => {
    setState((prev) => ({ ...prev, loading: true, error: null }));
    try {
      const tokens = await getStoredTokens();
      if (!tokens?.accessToken) {
        setState({ loading: false, error: null, items: [], isAuthenticated: false });
        return;
      }

      const items = await getFavorites();
      setState({ loading: false, error: null, items, isAuthenticated: true });
    } catch (reason) {
      const message = reason instanceof Error ? reason.message : 'Request failed';
      if (message.includes('HTTP 401') || message.includes('Not authenticated')) {
        setState({ loading: false, error: null, items: [], isAuthenticated: false });
        return;
      }
      setState((prev) => ({
        ...prev,
        loading: false,
        error: message,
      }));
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const movies = useMemo(() => state.items.map(mapFavoriteToMovie), [state.items]);

  return {
    ...state,
    movies,
    refresh: load,
  };
}
