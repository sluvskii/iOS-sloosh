import { Platform } from 'react-native';

import { avPlayerConfigurePlaylist, avPlayerPresentNativeUI } from '@/native/collaps-parser';
import NeomoviesCore from 'neomovies-core';

import { resolveAllohaIframeToPlayable } from './alloha';
import { normalizeMediaFileId, shouldPreferHlsForAndroidExo } from './helpers';
import { rewriteDashToLocalOrFallback, rewriteHlsToLocalOrFallback } from './manifest';
import { MovieCatalog, PlayerHeaders } from './types';

export async function launchMoviePlayer(
  catalog: MovieCatalog,
  playbackHeaders: PlayerHeaders,
  title: string | null,
  mediaId: string
) {
  if (catalog.source === 'alloha') {
    return launchAllohaMoviePlayer(catalog, playbackHeaders, title, mediaId);
  }
  if (Platform.OS === 'ios') {
    return launchIOSMoviePlayer(catalog, playbackHeaders, title, mediaId);
  }
  return launchAndroidMoviePlayer(catalog, playbackHeaders, title, mediaId);
}

async function launchAllohaMoviePlayer(
  catalog: MovieCatalog,
  playbackHeaders: PlayerHeaders,
  title: string | null,
  mediaId: string
) {
  const allohaVariants = catalog.allohaVariants ?? [];
  if (allohaVariants.length === 0) return;

  // Resolve the first variant's iframe to get a real stream URL + all audio variants
  const firstIframeUrl = allohaVariants[0].url;
  const resolved = await resolveAllohaIframeToPlayable(firstIframeUrl, playbackHeaders);
  if (!resolved?.url) return;

  const kpId = Number(mediaId.replace(/^kp_/, ''));
  const headers = {
    Referer: playbackHeaders.Referer,
    Origin: playbackHeaders.Origin,
    ...(resolved.headers ?? {}),
  };

  // Build per-dub playlist items: resolved audioVariants (multiple dubs from one iframe)
  // or fall back to one item per allohaVariant iframe (each dub as separate iframe)
  const resolvedAudioVariants = (resolved.audioVariants ?? []).filter((v) => v.url);

  if (Platform.OS === 'ios') {
    const playlistItems = resolvedAudioVariants.length > 1
      ? resolvedAudioVariants.map((v) => ({
          mediaId,
          title: title || '',
          voiceoverLabel: v.title,
          url: v.url,
          headers,
          voiceovers: [],
          subtitles: resolved.subtitles ?? [],
          audioVariants: [],
          qualityVariants: v.qualityVariants ?? [],
        }))
      : [{
          mediaId,
          title: title ?? '',
          url: resolved.url,
          headers,
          voiceovers: [],
          subtitles: resolved.subtitles ?? [],
          audioVariants: resolvedAudioVariants,
          qualityVariants: resolved.qualityVariants ?? [],
        }];

    await avPlayerConfigurePlaylist(playlistItems, 0, true, Number.isFinite(kpId) ? kpId : null);
    await avPlayerPresentNativeUI();
    return;
  }

  if (resolvedAudioVariants.length > 1 && NeomoviesCore.exoPlayerLaunchPlaylist) {
    await NeomoviesCore.exoPlayerLaunchPlaylist(
      resolvedAudioVariants.map((v) => v.url),
      0,
      headers,
      resolvedAudioVariants.map((v) => v.title || title || ''),
      title,
      [],
      Number.isFinite(kpId) ? kpId : null
    );
    return;
  }

  if (NeomoviesCore.exoPlayerSetAllohaVariants && (resolvedAudioVariants.length > 0 || (resolved.qualityVariants?.length ?? 0) > 0)) {
    await NeomoviesCore.exoPlayerSetAllohaVariants(
      resolvedAudioVariants.length > 0 ? JSON.stringify(resolvedAudioVariants) : null,
      (resolved.qualityVariants?.length ?? 0) > 0 ? JSON.stringify(resolved.qualityVariants) : null
    );
  }

  await NeomoviesCore.exoPlayerLaunch?.(resolved.url, headers, title, Number.isFinite(kpId) ? kpId : null);
}

async function launchIOSMoviePlayer(
  catalog: MovieCatalog,
  playbackHeaders: PlayerHeaders,
  title: string | null,
  mediaId: string
) {
  const kpId = Number(mediaId.replace(/^kp_/, ''));
  const allohaVariants = catalog.allohaVariants;
  const headers = { Referer: playbackHeaders.Referer, Origin: playbackHeaders.Origin };

  const playlistItems = allohaVariants && allohaVariants.length > 1
    ? allohaVariants.map((variant) => ({
        mediaId,
        title: variant.title || title || '',
        url: variant.url,
        headers,
        voiceovers: [],
        subtitles: catalog.playlist.subtitles,
      }))
    : (() => {
        const url = catalog.playlist.hlsUrl ?? catalog.playlist.dashUrl ?? catalog.playlist.primaryUrl;
        if (!url) return null;
        return [{
          mediaId: mediaId || url,
          title: title ?? '',
          url,
          headers,
          voiceovers: catalog.playlist.voiceovers,
          subtitles: catalog.playlist.subtitles,
        }];
      })();

  if (!playlistItems) return;
  await avPlayerConfigurePlaylist(playlistItems, 0, true, Number.isFinite(kpId) ? kpId : null);
  await avPlayerPresentNativeUI();
}

async function launchAndroidMoviePlayer(
  catalog: MovieCatalog,
  playbackHeaders: PlayerHeaders,
  title: string | null,
  mediaId: string
) {
  const kpId = Number(mediaId.replace(/^kp_/, ''));
  const allohaVariants = catalog.allohaVariants;

  if (allohaVariants && allohaVariants.length > 1 && NeomoviesCore.exoPlayerLaunchPlaylist) {
    await NeomoviesCore.exoPlayerLaunchPlaylist(
      allohaVariants.map((variant) => variant.url),
      0,
      playbackHeaders,
      allohaVariants.map((variant) => variant.title || title || ''),
      title,
      [],
      Number.isFinite(kpId) ? kpId : null
    );
    return;
  }

  const hlsUrl = catalog.playlist.hlsUrl;
  const dashUrl = catalog.playlist.dashUrl;
  const primaryUrl = catalog.playlist.primaryUrl;
  const preferHls = await shouldPreferHlsForAndroidExo(hlsUrl, dashUrl, playbackHeaders);
  const mediaFileId = normalizeMediaFileId(mediaId, 'movie');

  let finalUrl: string;
  if (preferHls && hlsUrl) {
    finalUrl = await rewriteHlsToLocalOrFallback(
      hlsUrl,
      catalog.playlist.voiceovers,
      catalog.playlist.subtitles,
      mediaFileId,
      playbackHeaders
    );
  } else if (dashUrl) {
    const dashLocalOrNull = await rewriteDashToLocalOrFallback(
      dashUrl,
      catalog.playlist.voiceovers,
      catalog.playlist.subtitles,
      mediaFileId,
      playbackHeaders
    );
    if (dashLocalOrNull) {
      finalUrl = dashLocalOrNull;
    } else if (hlsUrl) {
      finalUrl = await rewriteHlsToLocalOrFallback(
        hlsUrl,
        catalog.playlist.voiceovers,
        catalog.playlist.subtitles,
        mediaFileId,
        playbackHeaders
      );
    } else {
      finalUrl = dashUrl;
    }
  } else {
    finalUrl = primaryUrl;
  }

  if (!finalUrl) return;
  await NeomoviesCore.exoPlayerLaunch?.(finalUrl, playbackHeaders, title, Number.isFinite(kpId) ? kpId : null);
}
