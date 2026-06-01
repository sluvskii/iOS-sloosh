import { API_BASE_URL, API_ORIGIN } from '@/lib/config';
import { httpGet, httpGetText } from '@/lib/http';
import { getStoredTokens, refreshAccessToken } from '@/lib/neoid-auth';
import {
  MAINTENANCE_ERROR_CODE,
  NETWORK_ERROR_CODE,
  disableOfflineMode,
  enableMaintenanceOfflineMode,
  enableNetworkOfflineMode,
  isMaintenancePayload,
} from '@/lib/offline-mode';
import {
  ApiEnvelope,
  FavoriteItem,
  MediaDetails,
  PopularMoviesResponse,
  SearchResponse,
  TvEpisodeDetails,
  TopRatedResponse,
} from '@/types/api';

function unwrapEnvelope<T>(response: ApiEnvelope<T> | T): T {
  if (
    response &&
    typeof response === 'object' &&
    'success' in response &&
    'data' in response
  ) {
    return (response as ApiEnvelope<T>).data;
  }
  return response as T;
}

async function authFetch(input: string, init?: RequestInit) {
  const tokens = await getStoredTokens();
  if (!tokens?.accessToken) {
    throw new Error('Not authenticated');
  }

  const run = async (accessToken: string) =>
    fetch(input, {
      ...init,
      headers: {
        Accept: 'application/json',
        ...(init?.headers ?? {}),
        Authorization: `Bearer ${accessToken}`,
      },
    });

  let response: Response;
  try {
    response = await run(tokens.accessToken);
  } catch {
    enableNetworkOfflineMode();
    throw new Error(NETWORK_ERROR_CODE);
  }
  if (response.status !== 401) return response;

  const nextToken = await refreshAccessToken();
  if (!nextToken) return response;
  try {
    response = await run(nextToken);
  } catch {
    enableNetworkOfflineMode();
    throw new Error(NETWORK_ERROR_CODE);
  }
  return response;
}

async function authGet<T>(url: string): Promise<T> {
  const response = await authFetch(url, { method: 'GET' });
  const text = await response.text();
  if (!response.ok) {
    if (isMaintenancePayload(response.status, text)) {
      enableMaintenanceOfflineMode();
      throw new Error(MAINTENANCE_ERROR_CODE);
    }
    disableOfflineMode();
    throw new Error(`HTTP ${response.status}: ${text || 'Request failed'}`);
  }
  disableOfflineMode();
  const payload = (text ? JSON.parse(text) : {}) as ApiEnvelope<T> | T;
  return unwrapEnvelope(payload);
}

async function authMutate<T>(url: string, method: 'POST' | 'DELETE'): Promise<T> {
  const response = await authFetch(url, { method });
  const text = await response.text();
  if (!response.ok) {
    if (isMaintenancePayload(response.status, text)) {
      enableMaintenanceOfflineMode();
      throw new Error(MAINTENANCE_ERROR_CODE);
    }
    disableOfflineMode();
    throw new Error(`HTTP ${response.status}: ${text || 'Request failed'}`);
  }
  disableOfflineMode();
  const payload = (text ? JSON.parse(text) : {}) as ApiEnvelope<T> | T;
  return unwrapEnvelope(payload);
}

export async function getPopularMovies(page = 1) {
  const url = `${API_BASE_URL}/movies/popular?page=${page}`;
  const response = await httpGet<ApiEnvelope<PopularMoviesResponse> | PopularMoviesResponse>(url);
  return unwrapEnvelope(response);
}

export async function searchMovies(query: string, page = 1) {
  const encoded = encodeURIComponent(query);
  const url = `${API_BASE_URL}/search?query=${encoded}&page=${page}`;
  const response = await httpGet<ApiEnvelope<SearchResponse> | SearchResponse>(url);
  return unwrapEnvelope(response);
}

export async function getTopFilms(page = 1) {
  const url = `${API_BASE_URL}/movies/top-rated?page=${page}`;
  const response = await httpGet<ApiEnvelope<TopRatedResponse> | TopRatedResponse>(url);
  return unwrapEnvelope(response);
}

export async function getTopSeries(page = 1) {
  const url = `${API_BASE_URL}/tv/top-rated?page=${page}`;
  const response = await httpGet<ApiEnvelope<TopRatedResponse> | TopRatedResponse>(url);
  return unwrapEnvelope(response);
}

export async function getMediaDetails(mediaId: string) {
  const rawId = mediaId.replace(/^kp_/, '');
  const url = `${API_BASE_URL}/movie/${rawId}`;
  const response = await httpGet<ApiEnvelope<MediaDetails> | MediaDetails>(url);
  return unwrapEnvelope(response);
}

export async function getTvEpisodeDetails(mediaId: string, season: number, episode: number) {
  const rawId = mediaId.replace(/^kp_/, '');
  const url = `${API_BASE_URL}/tv/${rawId}/season/${season}/episode/${episode}`;
  const response = await httpGet<ApiEnvelope<TvEpisodeDetails> | TvEpisodeDetails>(url, { trackOffline: false });
  return unwrapEnvelope(response);
}

export type CollapsEmbedPayload = {
  embedHtml: string;
  embedOrigin: string;
  embedReferer: string;
  wrapperHtml?: string;
  iframeSource?: string | null;
};

const PROVIDER_EMBED_CACHE_TTL_MS = 1000 * 30;
const providerEmbedCache = new Map<string, { expiresAt: number; value: CollapsEmbedPayload }>();
const providerEmbedInflight = new Map<string, Promise<CollapsEmbedPayload>>();

function extractIframeSource(html: string): string | null {
  const match = html.match(/<iframe[^>]+src=["']([^"']+)["']/i);
  if (!match?.[1]) return null;
  return match[1];
}

export async function getProviderEmbedHtml(
  mediaId: string,
  provider: 'collaps' | 'alloha',
  season?: number,
  episode?: number
): Promise<CollapsEmbedPayload> {
  const rawId = mediaId.replace(/^kp_/, '');
  const cacheKey = [provider, rawId, season ?? 0, episode ?? 0].join(':');
  const cached = providerEmbedCache.get(cacheKey);
  if (cached && cached.expiresAt > Date.now()) {
    return cached.value;
  }

  const inflight = providerEmbedInflight.get(cacheKey);
  if (inflight) return inflight;

  const request = loadProviderEmbedHtml(rawId, provider, season, episode)
    .then((result) => {
      providerEmbedCache.set(cacheKey, {
        expiresAt: Date.now() + PROVIDER_EMBED_CACHE_TTL_MS,
        value: result,
      });
      return result;
    })
    .finally(() => {
      providerEmbedInflight.delete(cacheKey);
    });

  providerEmbedInflight.set(cacheKey, request);
  return request;
}

async function loadProviderEmbedHtml(
  rawId: string,
  provider: 'collaps' | 'alloha',
  season?: number,
  episode?: number
): Promise<CollapsEmbedPayload> {
  const qs = new URLSearchParams();
  if (season) qs.set('season', String(season));
  if (episode) qs.set('episode', String(episode));
  const suffix = qs.toString() ? `?${qs.toString()}` : '';
  const playerUrl = `${API_BASE_URL}/players/${provider}/kp/${rawId}${suffix}`;
  const wrapperHtml = await httpGetText(playerUrl, { headers: { Accept: 'text/html' }, trackOffline: false });

  const iframeSource = extractIframeSource(wrapperHtml);
  if (!iframeSource) {
    return {
      embedHtml: wrapperHtml,
      embedOrigin: API_ORIGIN,
      embedReferer: API_ORIGIN.endsWith('/') ? API_ORIGIN : `${API_ORIGIN}/`,
      wrapperHtml,
      iframeSource: null,
    };
  }

  let iframeResponse: Response;
  try {
    iframeResponse = await fetch(iframeSource, {
      method: 'GET',
      headers: {
        Accept: 'text/html,application/xhtml+xml',
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
        Referer: API_ORIGIN.endsWith('/') ? API_ORIGIN : `${API_ORIGIN}/`,
        Origin: API_ORIGIN,
      },
    });
  } catch {
    throw new Error(NETWORK_ERROR_CODE);
  }
  const embedHtml = await iframeResponse.text();
  if (!iframeResponse.ok) {
    if (isMaintenancePayload(iframeResponse.status, embedHtml)) {
      throw new Error(MAINTENANCE_ERROR_CODE);
    }
    throw new Error(`HTTP ${iframeResponse.status}: ${embedHtml || 'Failed to load provider embed HTML'}`);
  }

  const iframeUrl = new URL(iframeSource);

  if (provider === 'collaps') {
    return {
      embedHtml,
      embedOrigin: 'https://kinokrad.my',
      embedReferer: 'https://kinokrad.my/',
      wrapperHtml,
      iframeSource,
    };
  }

  return {
    embedHtml,
    embedOrigin: iframeUrl.origin,
    embedReferer: iframeUrl.origin.endsWith('/') ? `${iframeUrl.origin}/` : `${iframeUrl.origin}/`,
    wrapperHtml,
    iframeSource,
  };
}

export async function getCollapsEmbedHtml(mediaId: string, season?: number, episode?: number): Promise<CollapsEmbedPayload> {
  const rawId = mediaId.replace(/^kp_/, '');
  const iframeSource = `https://api.luxembd.ws/embed/kp/${rawId}`;

  let embedResponse: Response;
  try {
    embedResponse = await fetch(iframeSource, {
      method: 'GET',
      headers: {
        Accept: 'text/html,application/xhtml+xml',
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
        Referer: 'https://kinokrad.my/',
        Origin: 'https://kinokrad.my',
      },
    });
  } catch {
    throw new Error(NETWORK_ERROR_CODE);
  }
  const embedHtml = await embedResponse.text();
  if (!embedResponse.ok) {
    if (isMaintenancePayload(embedResponse.status, embedHtml)) {
      throw new Error(MAINTENANCE_ERROR_CODE);
    }
    throw new Error(`HTTP ${embedResponse.status}: ${embedHtml || 'Failed to load Collaps embed HTML'}`);
  }

  return {
    embedHtml,
    embedOrigin: 'https://kinokrad.my',
    embedReferer: 'https://kinokrad.my/',
  };
}

export async function getFavorites() {
  const url = `${API_BASE_URL}/favorites`;
  return authGet<FavoriteItem[]>(url);
}

export async function checkFavorite(kpId: string, mediaType: 'movie' | 'tv') {
  const rawId = kpId.replace(/^kp_/, '');
  const type = encodeURIComponent(mediaType);
  const url = `${API_BASE_URL}/favorites/${rawId}/check?type=${type}`;
  return authGet<{ isFavorite: boolean }>(url);
}

export async function addFavorite(kpId: string, mediaType: 'movie' | 'tv') {
  const rawId = kpId.replace(/^kp_/, '');
  const type = encodeURIComponent(mediaType);
  const url = `${API_BASE_URL}/favorites/${rawId}?type=${type}`;
  return authMutate<{ mediaId: string }>(url, 'POST');
}

export async function removeFavorite(kpId: string, mediaType: 'movie' | 'tv') {
  const rawId = kpId.replace(/^kp_/, '');
  const type = encodeURIComponent(mediaType);
  const url = `${API_BASE_URL}/favorites/${rawId}?type=${type}`;
  return authMutate<{ mediaId: string }>(url, 'DELETE');
}

export function resolvePosterUrl(input?: string | null) {
  if (!input) return null;
  if (input.startsWith('http://') || input.startsWith('https://')) return input;
  if (input.startsWith('/api/')) return `${API_ORIGIN}${input}`;
  return `${API_ORIGIN}/${input.replace(/^\/+/, '')}`;
}

export function resolveBackdropUrl(movieId?: string | null, size: 'small' | 'large' = 'small') {
  if (!movieId) return null;
  const rawId = movieId.replace(/^kp_/, '');
  return `${API_BASE_URL}/images/backdrops/${rawId}/${size}`;
}

export function resolveBackdropPageUrl(movieId?: string | null, size: 'small' | 'large' = 'small') {
  if (!movieId) return null;
  const rawId = movieId.replace(/^kp_/, '');
  return `${API_BASE_URL}/images/backdrops/page/${rawId}/${size}`;
}

export function resolveLogoUrl(movieId?: string | null, size: 'w500' | 'original' = 'w500') {
  if (!movieId) return null;
  const rawId = movieId.replace(/^kp_/, '');
  return `${API_BASE_URL}/images/logos/${rawId}/${size}`;
}

export function resolveEpisodeStillUrl(
  movieId?: string | null,
  season?: number,
  episode?: number,
  size: 'small' | 'large' = 'large'
) {
  if (!movieId || !season || !episode) return null;
  const rawId = movieId.replace(/^kp_/, '');
  return `${API_BASE_URL}/images/screens/${rawId}/${season}/${episode}/${size}`;
}
