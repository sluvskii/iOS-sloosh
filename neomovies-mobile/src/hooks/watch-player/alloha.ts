import {
  CollapsCatalog,
  CollapsSubtitle,
  fetchAllohaSeriesCatalog,
  resolveAllohaPlayableFromIframe,
} from '@/native/collaps-parser';

import { PlayerHeaders, ResolvedAllohaPlayable } from './types';

const ALLOHA_PUBLIC_TOKEN = 'ffbd312217e27c4245f2678afe1881';
const ALLOHA_CATALOG_CACHE_TTL_MS = 1000 * 60 * 5;
const ALLOHA_IFRAME_CACHE_TTL_MS = 1000 * 45;

const catalogCache = new Map<string, { expiresAt: number; value: CollapsCatalog | null }>();
const catalogInflight = new Map<string, Promise<CollapsCatalog | null>>();
const iframeCache = new Map<string, { expiresAt: number; value: ResolvedAllohaPlayable }>();
const iframeInflight = new Map<string, Promise<ResolvedAllohaPlayable>>();

export async function buildAllohaSeriesCatalogFromApi(mediaId: string): Promise<CollapsCatalog | null> {
  const rawId = mediaId.replace(/^kp_/, '');
  if (!rawId) return null;

  const cached = catalogCache.get(rawId);
  if (cached && cached.expiresAt > Date.now()) {
    return cached.value;
  }

  const inflight = catalogInflight.get(rawId);
  if (inflight) return inflight;

  const request = fetchAllohaSeriesCatalog(rawId, ALLOHA_PUBLIC_TOKEN)
    .then((result) => {
      catalogCache.set(rawId, {
        expiresAt: Date.now() + ALLOHA_CATALOG_CACHE_TTL_MS,
        value: result,
      });
      return result;
    })
    .finally(() => {
      catalogInflight.delete(rawId);
    });

  catalogInflight.set(rawId, request);
  return request;
}

export async function resolveAllohaIframeToPlayable(
  iframeUrl: string,
  _headers: PlayerHeaders
): Promise<ResolvedAllohaPlayable> {
  const cached = iframeCache.get(iframeUrl);
  if (cached && cached.expiresAt > Date.now()) {
    return cached.value;
  }

  const inflight = iframeInflight.get(iframeUrl);
  if (inflight) return inflight;

  const request = (resolveAllohaPlayableFromIframe(iframeUrl) as Promise<ResolvedAllohaPlayable>)
    .then((result) => {
      iframeCache.set(iframeUrl, {
        expiresAt: Date.now() + ALLOHA_IFRAME_CACHE_TTL_MS,
        value: result,
      });
      return result;
    })
    .finally(() => {
      iframeInflight.delete(iframeUrl);
    });

  iframeInflight.set(iframeUrl, request);
  return request;
}

export function mergeResolvedSubtitles(
  resolved: ResolvedAllohaPlayable,
  fallback: CollapsSubtitle[]
): CollapsSubtitle[] {
  return resolved.subtitles?.length ? resolved.subtitles : fallback;
}

