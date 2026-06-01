import { router } from 'expo-router';
import * as ScreenOrientation from 'expo-screen-orientation';
import { useEffect, useRef, useState } from 'react';
import { NativeEventEmitter, NativeModules, Platform } from 'react-native';

import { useContentSource } from '@/hooks/use-content-source';
import { getProviderEmbedHtml } from '@/lib/neomovies-api';
import { launchMoviePlayer, launchSeriesPlayer, resolveCatalog } from '@/hooks/watch-player/launchers';
import { PlayerHeaders, WatchPlayerLaunchParams } from '@/hooks/watch-player/types';

const { NeomoviesCore } = NativeModules;
const eventEmitter = NeomoviesCore ? new NativeEventEmitter(NeomoviesCore) : null;

export function useWatchPlayerLaunch({
  mediaId,
  title,
  initialSeason,
  initialEpisode,
}: WatchPlayerLaunchParams) {
  const { source, ready: sourceReady } = useContentSource();
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const launchedKeyRef = useRef<string | null>(null);

  useEffect(() => {
    let cancelled = false;

    void (async () => {
      try {
        if (!sourceReady) return;
        if (!mediaId) {
          throw new Error('Missing media id');
        }
        const launchKey = [source, mediaId, initialSeason, initialEpisode].join(':');
        if (launchedKeyRef.current === launchKey) {
          return;
        }
        launchedKeyRef.current = launchKey;

        setLoading(true);
        setError(null);

        const payload = await getProviderEmbedHtml(mediaId, source, initialSeason, initialEpisode);
        const playbackHeaders: PlayerHeaders = {
          Referer: payload.embedReferer,
          Origin: payload.embedOrigin,
        };
        const catalog = await resolveCatalog(source, mediaId, payload.embedHtml);

        if (!catalog) {
          throw new Error('Failed to parse provider catalog');
        }
        if (cancelled) return;

        console.log('[WatchScreen] Launching player', {
          kind: catalog.kind,
          id: mediaId,
          title,
          season: initialSeason,
          episode: initialEpisode,
        });

        if (catalog.kind === 'movie') {
          await launchMoviePlayer(catalog, playbackHeaders, title, mediaId);
        } else if (catalog.kind === 'series') {
          await launchSeriesPlayer(catalog, playbackHeaders, title, mediaId, initialSeason, initialEpisode);
        }

        if (!cancelled && router.canGoBack()) {
          router.back();
        }
      } catch (reason) {
        if (cancelled) return;
        launchedKeyRef.current = null;
        setError(reason instanceof Error ? reason.message : 'Request failed');
      } finally {
        if (!cancelled) {
          setLoading(false);
        }
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [initialEpisode, initialSeason, mediaId, source, sourceReady, title]);

  // Listen for player dismiss event to refresh episode list
  useEffect(() => {
    if (!eventEmitter) return;

    const iosSubscription = eventEmitter.addListener('onAVPlayerDismissed', () => {
      console.log('[WatchScreen] iOS Player dismissed, refreshing episode list');
      // Lock orientation back to portrait after player dismissal
      void ScreenOrientation.lockAsync(ScreenOrientation.OrientationLock.PORTRAIT_UP);
      // Trigger a refresh by invalidating the launch key
      launchedKeyRef.current = null;
    });

    const androidSubscription = eventEmitter.addListener('onExoPlayerClosed', () => {
      console.log('[WatchScreen] Android Player closed, refreshing episode list');
      // Lock orientation back to portrait after player dismissal
      void ScreenOrientation.lockAsync(ScreenOrientation.OrientationLock.PORTRAIT_UP);
      // Trigger a refresh by invalidating the launch key
      launchedKeyRef.current = null;
    });

    return () => {
      iosSubscription.remove();
      androidSubscription.remove();
    };
  }, []);

  return {
    loading,
    error,
  };
}
