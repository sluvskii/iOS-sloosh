import * as SecureStore from 'expo-secure-store';
import * as Linking from 'expo-linking';
import * as WebBrowser from 'expo-web-browser';

import { API_BASE_URL } from '@/lib/config';
import { NeoIdTokens, NeoIdUserProfile } from '@/types/neo-id';

const ACCESS_TOKEN_KEY = 'neomovies_auth_access_token_v1';
const REFRESH_TOKEN_KEY = 'neomovies_auth_refresh_token_v1';

type LoginUrlResponse = {
  login_url: string;
};

type CallbackExchangeResponse = {
  accessToken?: string;
  refreshToken?: string;
  token?: string;
  refresh_token?: string;
};

type AuthSessionResultWithUrl = WebBrowser.WebBrowserAuthSessionResult & { url: string };

function hasAuthResultUrl(result: WebBrowser.WebBrowserAuthSessionResult): result is AuthSessionResultWithUrl {
  return 'url' in result && typeof result.url === 'string';
}

function mask(value: string | null | undefined, prefix = 6, suffix = 4): string {
  if (!value) return 'null';
  if (value.length <= prefix + suffix) return `${value.slice(0, 2)}***`;
  return `${value.slice(0, prefix)}...${value.slice(-suffix)}`;
}

function parseJson<T>(value: unknown): T {
  if (value && typeof value === 'object' && 'data' in value) {
    return (value as { data: T }).data;
  }
  return value as T;
}

async function httpPost<T>(url: string, body: Record<string, unknown>, token?: string): Promise<T> {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), 30000); // 30s timeout
  
  try {
    const response = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Accept: 'application/json',
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
    clearTimeout(timeoutId);
    
    const text = await response.text();
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}: ${text || 'Request failed'}`);
    }
    return parseJson<T>(text ? JSON.parse(text) : {});
  } catch (error) {
    clearTimeout(timeoutId);
    if (error instanceof Error && error.name === 'AbortError') {
      throw new Error('Request timeout after 30 seconds');
    }
    throw error;
  }
}

async function httpGet<T>(url: string, token: string): Promise<T> {
  const response = await fetch(url, {
    method: 'GET',
    headers: {
      Accept: 'application/json',
      Authorization: `Bearer ${token}`,
    },
  });
  const text = await response.text();
  if (!response.ok) {
    throw new Error(`HTTP ${response.status}: ${text || 'Request failed'}`);
  }
  return parseJson<T>(text ? JSON.parse(text) : {});
}

export async function getStoredTokens(): Promise<NeoIdTokens | null> {
  const [accessToken, refreshToken] = await Promise.all([
    SecureStore.getItemAsync(ACCESS_TOKEN_KEY),
    SecureStore.getItemAsync(REFRESH_TOKEN_KEY),
  ]);
  if (!accessToken) return null;
  return { accessToken, refreshToken: refreshToken ?? undefined };
}

export async function setStoredTokens(tokens: NeoIdTokens) {
  await Promise.all([
    SecureStore.setItemAsync(ACCESS_TOKEN_KEY, tokens.accessToken),
    tokens.refreshToken
      ? SecureStore.setItemAsync(REFRESH_TOKEN_KEY, tokens.refreshToken)
      : SecureStore.deleteItemAsync(REFRESH_TOKEN_KEY),
  ]);
}

export async function clearStoredTokens() {
  await Promise.all([
    SecureStore.deleteItemAsync(ACCESS_TOKEN_KEY),
    SecureStore.deleteItemAsync(REFRESH_TOKEN_KEY),
  ]);
}

export async function refreshAccessToken() {
  const tokens = await getStoredTokens();
  if (!tokens?.refreshToken) return null;
  const response = await httpPost<CallbackExchangeResponse>(
    `${API_BASE_URL}/auth/refresh`,
    { refreshToken: tokens.refreshToken }
  );
  const nextAccess = response.accessToken;
  const nextRefresh = response.refreshToken;
  if (!nextAccess || !nextRefresh) return null;
  await setStoredTokens({ accessToken: nextAccess, refreshToken: nextRefresh });
  return nextAccess;
}

export async function getProfile(): Promise<NeoIdUserProfile> {
  const tokens = await getStoredTokens();
  if (!tokens?.accessToken) {
    throw new Error('Not authenticated');
  }
  try {
    return await httpGet<NeoIdUserProfile>(`${API_BASE_URL}/auth/profile`, tokens.accessToken);
  } catch (error) {
    const message = error instanceof Error ? error.message : '';
    if (!message.includes('HTTP 401')) throw error;
    const nextToken = await refreshAccessToken();
    if (!nextToken) throw error;
    return httpGet<NeoIdUserProfile>(`${API_BASE_URL}/auth/profile`, nextToken);
  }
}

export async function logout() {
  await clearStoredTokens();
}

export async function loginViaNeoId() {
  const mobileRedirectUrl = Linking.createURL('auth/neo-id/callback');
  const redirectUrl = `${API_BASE_URL}/auth/neo-id/mobile-callback?mobile_redirect_url=${encodeURIComponent(mobileRedirectUrl)}`;
  const state = Math.random().toString(36).slice(2);
  
  console.log('[NeoID] Starting login flow (token mode)');
  console.log('[NeoID] state:', state);
  console.log('[NeoID] mobileRedirectUrl:', mobileRedirectUrl);
  console.log('[NeoID] redirectUrl:', redirectUrl);
  
  const loginPayload = {
    redirect_url: redirectUrl,
    state,
    mode: 'redirect',
  };
  const loginUrlResponse = await httpPost<LoginUrlResponse>(`${API_BASE_URL}/auth/neo-id/login`, loginPayload);
  const loginUrl = loginUrlResponse.login_url;
  if (!loginUrl) {
    throw new Error('No login URL returned');
  }
  
  const parsedLoginUrl = Linking.parse(loginUrl);
  console.log('[NeoID] loginUrl host/path:', parsedLoginUrl.hostname, parsedLoginUrl.path);
  console.log('[NeoID] loginUrl query:', parsedLoginUrl.queryParams);
  console.log('[NeoID] Opening auth session:', loginUrl);

  const sub = Linking.addEventListener('url', (event) => {
    console.log('[NeoID] Linking event URL:', event.url);
  });
  const authResult = await WebBrowser.openAuthSessionAsync(loginUrl, mobileRedirectUrl);
  sub.remove();
  console.log('[NeoID] Auth result type:', authResult.type);
  console.log('[NeoID] Auth result URL:', hasAuthResultUrl(authResult) ? authResult.url : null);
  
  if (authResult.type !== 'success' || !hasAuthResultUrl(authResult)) {
    throw new Error('Neo ID auth cancelled before deep link callback');
  }

  const callbackUrl = authResult.url;

  const parsed = Linking.parse(callbackUrl);
  console.log('[NeoID] Parsed query params:', parsed.queryParams);
  console.log('[NeoID] callback path:', parsed.path);
  
  const accessToken = typeof parsed.queryParams?.access_token === 'string'
    ? parsed.queryParams.access_token
    : typeof parsed.queryParams?.token === 'string'
      ? parsed.queryParams.token
      : null;
  const refreshToken = typeof parsed.queryParams?.refresh_token === 'string'
    ? parsed.queryParams.refresh_token
    : null;
  const callbackError = typeof parsed.queryParams?.error === 'string'
    ? parsed.queryParams.error
    : null;
  const callbackErrorDescription = typeof parsed.queryParams?.error_description === 'string'
    ? parsed.queryParams.error_description
    : null;
  const returnedState = typeof parsed.queryParams?.state === 'string'
    ? parsed.queryParams.state
    : null;

  console.log('[NeoID] Access token:', mask(accessToken));
  console.log('[NeoID] Refresh token:', mask(refreshToken));
  console.log('[NeoID] Returned state:', returnedState, 'matches:', returnedState === state);
  if (callbackError) {
    console.log('[NeoID] Callback error:', callbackError, callbackErrorDescription);
    throw new Error(
      `Neo ID callback error: ${callbackError}${callbackErrorDescription ? ` (${callbackErrorDescription})` : ''}`
    );
  }

  if (!accessToken) {
    throw new Error(`Neo ID did not return access token. Callback URL: ${callbackUrl}`);
  }

  console.log('[NeoID] Exchanging Neo ID token for app tokens...');
  
  const exchange = await httpPost<CallbackExchangeResponse>(`${API_BASE_URL}/auth/neo-id/callback`, {
    access_token: accessToken,
    refresh_token: refreshToken || '',
  });
  console.log('[NeoID] Exchange response:', exchange);

  const appAccessToken = exchange.accessToken || exchange.token;
  const appRefreshToken = exchange.refreshToken || exchange.refresh_token;

  console.log('[NeoID] App access token:', appAccessToken ? 'present' : 'null');
  console.log('[NeoID] App refresh token:', appRefreshToken ? 'present' : 'null');

  if (!appAccessToken || !appRefreshToken) {
    throw new Error('Invalid callback token response');
  }
  await setStoredTokens({ accessToken: appAccessToken, refreshToken: appRefreshToken });
  console.log('[NeoID] Login successful!');
}
