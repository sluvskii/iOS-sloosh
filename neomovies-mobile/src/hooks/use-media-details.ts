import { useEffect, useState } from 'react';
import * as SecureStore from 'expo-secure-store';

import { getMediaDetails } from '@/lib/neomovies-api';
import { getOfflineModeSnapshot, subscribeOfflineMode } from '@/lib/offline-mode';
import { MediaDetails } from '@/types/api';

const MEDIA_CACHE_PREFIX = 'neomovies_media_details_v1';

function cacheKey(mediaId: string) {
  return `${MEDIA_CACHE_PREFIX}:${mediaId}`;
}

export function useMediaDetails(mediaId?: string) {
  const [offlineState, setOfflineState] = useState(getOfflineModeSnapshot());
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [details, setDetails] = useState<MediaDetails | null>(null);

  useEffect(() => {
    return subscribeOfflineMode(setOfflineState);
  }, []);

  useEffect(() => {
    if (!mediaId) {
      setError('Missing media id');
      setDetails(null);
      setLoading(false);
      return;
    }

    let active = true;
    setLoading(true);
    setError(null);

    void (async () => {
      let cached: MediaDetails | null = null;
      try {
        const raw = await SecureStore.getItemAsync(cacheKey(mediaId));
        if (raw) cached = JSON.parse(raw) as MediaDetails;
      } catch {
        // ignore cache read failure
      }

      if (!active) return;
      if (cached) {
        setDetails(cached);
        if (offlineState.enabled) {
          setLoading(false);
          return;
        }
      }

      if (offlineState.enabled) {
        setError('Offline mode is enabled, but no cached data is available yet.');
        setLoading(false);
        return;
      }

      try {
        const response = await getMediaDetails(mediaId);
        if (!active) return;
        setDetails(response);
        try {
          await SecureStore.setItemAsync(cacheKey(mediaId), JSON.stringify(response));
        } catch {
          // ignore cache write failure
        }
      } catch (reason) {
        if (!active) return;
        setError(reason instanceof Error ? reason.message : 'Request failed');
      } finally {
        if (!active) return;
        setLoading(false);
      }
    })();

    return () => {
      active = false;
    };
  }, [mediaId, offlineState.enabled]);

  return { loading, error, details };
}
