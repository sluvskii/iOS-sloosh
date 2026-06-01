import { Platform } from 'react-native';

import {
  avPlayerConfigurePlaylist,
  avPlayerPresentNativeUI,
  CollapsSubtitle,
} from '@/native/collaps-parser';
import NeomoviesCore from 'neomovies-core';

import { mergeResolvedSubtitles, resolveAllohaIframeToPlayable } from './alloha';
import { findEpisodeByNumber, findSeasonByNumber, shouldPreferHlsForAndroidExo } from './helpers';
import { SeriesCatalog, PlayerHeaders } from './types';

export async function launchSeriesPlayer(
  catalog: SeriesCatalog,
  playbackHeaders: PlayerHeaders,
  title: string | null,
  mediaId: string,
  initialSeason: number,
  initialEpisode: number
) {
  if (catalog.source === 'alloha') {
    return launchAllohaSeriesPlayer(catalog, playbackHeaders, title, mediaId, initialSeason, initialEpisode);
  }
  return launchCollapsSeriesPlayer(catalog, playbackHeaders, title, mediaId, initialSeason, initialEpisode);
}

async function launchAllohaSeriesPlayer(
  catalog: SeriesCatalog,
  playbackHeaders: PlayerHeaders,
  title: string | null,
  mediaId: string,
  initialSeason: number,
  initialEpisode: number
) {
  const activeSeason = findSeasonByNumber(catalog.seasons, initialSeason);
  const activeEpisode = activeSeason ? findEpisodeByNumber(activeSeason.episodes, initialEpisode) : null;
  if (!activeEpisode) return;

  const kpId = Number(mediaId.replace(/^kp_/, ''));

  if (Platform.OS === 'ios') {
    const headers: Record<string, string> = {
      Referer: playbackHeaders.Referer,
      Origin: playbackHeaders.Origin,
    };
    const sortedEpisodes = [...activeSeason.episodes].sort((a, b) => a.episode - b.episode);
    const playlistItems: {
      mediaId: string;
      title: string;
      url: string;
      headers: Record<string, string>;
      season: number;
      episode: number;
      voiceovers: string[];
      subtitles: CollapsSubtitle[];
      audioVariants: {
        title: string;
        url: string;
        qualityVariants?: { label: string; url: string; bitrate?: number | null; height?: number | null }[];
      }[];
      qualityVariants?: { label: string; url: string; bitrate?: number | null; height?: number | null }[];
    }[] = [];

    const resolved = await resolveAllohaIframeToPlayable(activeEpisode.playlist.primaryUrl, playbackHeaders);
    const activeEpisodeId = `${mediaId}_s${activeEpisode.season}_e${activeEpisode.episode}`;

    for (const episode of sortedEpisodes) {
      const episodeId = `${mediaId}_s${episode.season}_e${episode.episode}`;
      if (episodeId === activeEpisodeId && resolved?.url) {
        const variants = (resolved.audioVariants ?? []).filter((variant) => variant.url);
        playlistItems.push({
          mediaId: episodeId,
          title: title ?? 'Series',
          url: resolved.url,
          headers: {
            ...headers,
            ...(resolved.headers ?? {}),
            'X-Neo-Alloha-Iframe': episode.playlist.primaryUrl,
          },
          season: episode.season,
          episode: episode.episode,
          voiceovers: [],
          subtitles: mergeResolvedSubtitles(resolved, []),
          audioVariants: variants,
          qualityVariants: resolved.qualityVariants ?? [],
        });
      } else {
        playlistItems.push({
          mediaId: episodeId,
          title: title ?? 'Series',
          url: episode.playlist.primaryUrl,
          headers: {
            ...headers,
            'X-Neo-Alloha-Iframe': episode.playlist.primaryUrl,
          },
          season: episode.season,
          episode: episode.episode,
          voiceovers: [],
          subtitles: [],
          audioVariants: [],
          qualityVariants: [],
        });
      }
    }

    if (playlistItems.length === 0) {
      throw new Error('Alloha runtime parser did not return playable URL (no_stream_no_iframe)');
    }

    const startIndex = Math.max(0, playlistItems.findIndex((item) => item.mediaId === activeEpisodeId));
    await avPlayerConfigurePlaylist(playlistItems, startIndex, true, Number.isFinite(kpId) ? kpId : null);
    await avPlayerPresentNativeUI();
    return;
  }

  // Set episode playlist for in-player episode switching (Android)
  if (NeomoviesCore.exoPlayerSetAllohaEpisodes && activeSeason) {
    const sortedEpisodes = [...activeSeason.episodes].sort((a, b) => a.episode - b.episode);
    const episodeIframeUrls = sortedEpisodes.map((ep) => ep.playlist.primaryUrl);
    const episodeNames = sortedEpisodes.map((ep) => `S${String(ep.season).padStart(2, '0')}E${String(ep.episode).padStart(2, '0')}`);
    const startIndex = sortedEpisodes.findIndex((ep) => ep.season === activeEpisode.season && ep.episode === activeEpisode.episode);

    await NeomoviesCore.exoPlayerSetAllohaEpisodes(
      JSON.stringify(episodeIframeUrls),
      JSON.stringify(episodeNames),
      Math.max(0, startIndex),
      JSON.stringify(playbackHeaders),
      title
    );
  }

  const resolved = await resolveAllohaIframeToPlayable(activeEpisode.playlist.primaryUrl, playbackHeaders);
  const audioVariants = (resolved.audioVariants ?? []).filter((v) => v.url);
  const qualityVariants = resolved.qualityVariants ?? [];

  if (NeomoviesCore.exoPlayerSetAllohaVariants) {
    await NeomoviesCore.exoPlayerSetAllohaVariants(
      audioVariants.length > 0 ? JSON.stringify(audioVariants) : null,
      qualityVariants.length > 0 ? JSON.stringify(qualityVariants) : null
    );
  }

  const episodeName = `S${String(activeEpisode.season).padStart(2, '0')}E${String(activeEpisode.episode).padStart(2, '0')}`;
  const displayTitle = title ? `${title} • ${episodeName}` : episodeName;

  await NeomoviesCore.exoPlayerLaunch?.(
    resolved.url,
    { ...playbackHeaders, ...(resolved.headers ?? {}) },
    displayTitle,
    Number.isFinite(kpId) ? kpId : null
  );
}

async function launchCollapsSeriesPlayer(
  catalog: SeriesCatalog,
  playbackHeaders: PlayerHeaders,
  title: string | null,
  mediaId: string,
  initialSeason: number,
  initialEpisode: number
) {
  const activeSeason = findSeasonByNumber(catalog.seasons, initialSeason);
  if (!activeSeason) return;

  const activeEpisode = findEpisodeByNumber(activeSeason.episodes, initialEpisode);
  if (!activeEpisode) return;

  if (Platform.OS === 'ios') {
    const kpId = Number(mediaId.replace(/^kp_/, ''));
    const headers = { Referer: playbackHeaders.Referer, Origin: playbackHeaders.Origin };
    const allohaVariants = catalog.allohaVariants;

    const playlistItems = allohaVariants && allohaVariants.length > 1
      ? allohaVariants.map((variant) => ({
          mediaId: `${mediaId}_s${initialSeason}_e${initialEpisode}`,
          title: title || '',
          voiceoverLabel: variant.title,
          url: variant.url,
          headers,
          season: initialSeason,
          episode: initialEpisode,
          voiceovers: [],
          subtitles: activeEpisode.playlist.subtitles,
        }))
      : catalog.seasons.flatMap((season) =>
          season.episodes.flatMap((episode) => {
            const url = episode.playlist.primaryUrl || episode.playlist.hlsUrl || episode.playlist.dashUrl;
            if (!url) return [];
            return [{
              mediaId: `${mediaId}_s${season.season}_e${episode.episode}`,
              title: title ?? 'Series',
              url,
              headers,
              season: season.season,
              episode: episode.episode,
              voiceovers: episode.playlist.voiceovers,
              subtitles: episode.playlist.subtitles,
            }];
          })
        );

    const startIndex = allohaVariants && allohaVariants.length > 1
      ? 0
      : Math.max(0, playlistItems.findIndex((item) => item.season === initialSeason && item.episode === initialEpisode));

    await avPlayerConfigurePlaylist(playlistItems, startIndex, true, Number.isFinite(kpId) ? kpId : null);
    await avPlayerPresentNativeUI();
    return;
  }

  const kpId = Number(mediaId.replace(/^kp_/, ''));
  const allohaVariantsAndroid = catalog.allohaVariants;
  if (allohaVariantsAndroid && allohaVariantsAndroid.length > 1 && NeomoviesCore.exoPlayerLaunchPlaylist) {
    await NeomoviesCore.exoPlayerLaunchPlaylist(
      allohaVariantsAndroid.map((variant) => variant.url),
      0,
      playbackHeaders,
      allohaVariantsAndroid.map((variant) => variant.title || title || ''),
      title,
      [],
      Number.isFinite(kpId) ? kpId : null
    );
    return;
  }

  const hlsUrl = activeEpisode.playlist.hlsUrl;
  const dashUrl = activeEpisode.playlist.dashUrl;
  const preferHls = await shouldPreferHlsForAndroidExo(hlsUrl, dashUrl, playbackHeaders);

  const seasonPlaylist = [...catalog.seasons]
    .sort((a, b) => a.season - b.season)
    .flatMap((season) =>
      [...season.episodes]
        .sort((a, b) => a.episode - b.episode)
        .map((episode) => ({
          season: season.season,
          episode: episode.episode,
          url: preferHls
            ? (episode.playlist.hlsUrl ?? episode.playlist.dashUrl ?? episode.playlist.primaryUrl)
            : (episode.playlist.dashUrl ?? episode.playlist.hlsUrl ?? episode.playlist.primaryUrl),
          name: `${title ?? 'Series'}_S${String(season.season).padStart(2, '0')}E${String(episode.episode).padStart(2, '0')}`,
        }))
        .filter((item) => Boolean(item.url))
    );

  const startIndex = Math.max(
    0,
    seasonPlaylist.findIndex((item) => item.season === activeEpisode.season && item.episode === activeEpisode.episode)
  );

  if (NeomoviesCore.exoPlayerLaunchPlaylist && seasonPlaylist.length > 0) {
    await NeomoviesCore.exoPlayerLaunchPlaylist(
      seasonPlaylist.map((item) => item.url),
      startIndex,
      playbackHeaders,
      seasonPlaylist.map((item) => item.name),
      title,
      activeEpisode.playlist.voiceovers,
      Number.isFinite(kpId) ? kpId : null
    );
    return;
  }

  const singleUrl = seasonPlaylist[startIndex]?.url;
  if (singleUrl) {
    await NeomoviesCore.exoPlayerLaunch?.(
      singleUrl,
      playbackHeaders,
      `${title ?? 'Series'} S${activeEpisode.season}E${activeEpisode.episode}`,
      Number.isFinite(kpId) ? kpId : null
    );
  }
}
