import { useMemo } from 'react';

export type WatchPlayerRouteParams = {
  id?: string;
  title?: string;
  embed_html?: string;
  season?: string;
  episode?: string;
};

export function useWatchPlayerParams(params: WatchPlayerRouteParams) {
  return useMemo(() => {
    const mediaId = params.id ?? '';
    const title = params.title ?? null;
    const initialSeason = Number(params.season ?? '1') || 1;
    const initialEpisode = Number(params.episode ?? '1') || 1;

    return {
      mediaId,
      title,
      initialSeason,
      initialEpisode,
    };
  }, [params.episode, params.id, params.season, params.title]);
}
