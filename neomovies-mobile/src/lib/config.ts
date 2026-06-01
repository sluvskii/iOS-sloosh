const DEFAULT_API_BASE_URL = 'https://api.neomovies.ru/api/v1';
const DEFAULT_NEO_ID_BASE_URL = 'https://id.neomovies.ru';

function normalizeBaseUrl(input: string | undefined, fallback: string) {
  const value = (input || '').trim();
  if (!value) return fallback;
  return value.replace(/\/+$/, '');
}

export const API_BASE_URL = normalizeBaseUrl(
  process.env.EXPO_PUBLIC_API_BASE_URL,
  DEFAULT_API_BASE_URL
);

export const API_ORIGIN = API_BASE_URL.replace(/\/api\/v1$/, '');

export const NEO_ID_BASE_URL = normalizeBaseUrl(
  process.env.EXPO_PUBLIC_NEO_ID_BASE_URL,
  DEFAULT_NEO_ID_BASE_URL
);
