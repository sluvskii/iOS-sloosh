import { useCallback, useEffect, useMemo, useState } from 'react';
import * as SecureStore from 'expo-secure-store';

import {
  clearStoredTokens,
  getProfile,
  getStoredTokens,
  loginViaNeoId,
} from '@/lib/neoid-auth';
import { NeoIdUserProfile } from '@/types/neo-id';

let cachedProfile: NeoIdUserProfile | null = null;
let cachedAuth = false;
const PROFILE_CACHE_KEY = 'neomovies_profile_cache_v1';
const profileListeners = new Set<(profile: NeoIdUserProfile | null, isAuthenticated: boolean) => void>();

function emitProfileState() {
  for (const listener of profileListeners) {
    listener(cachedProfile, cachedAuth);
  }
}

export function getCachedProfileState() {
  return {
    profile: cachedProfile,
    isAuthenticated: cachedAuth,
  };
}

export async function hydrateProfileCache() {
  if (cachedProfile) return getCachedProfileState();
  try {
    const raw = await SecureStore.getItemAsync(PROFILE_CACHE_KEY);
    if (raw) {
      cachedProfile = JSON.parse(raw) as NeoIdUserProfile;
    }
  } catch {
    cachedProfile = null;
  }
  try {
    const tokens = await getStoredTokens();
    cachedAuth = Boolean(tokens?.accessToken);
    if (!cachedAuth) {
      cachedProfile = null;
    }
  } catch {
    cachedAuth = false;
    cachedProfile = null;
  }
  emitProfileState();
  return getCachedProfileState();
}

export function subscribeProfileState(
  listener: (profile: NeoIdUserProfile | null, isAuthenticated: boolean) => void
) {
  profileListeners.add(listener);
  return () => {
    profileListeners.delete(listener);
  };
}

export function useProfileScreen() {
  const [loading, setLoading] = useState(cachedProfile === null);
  const [authenticating, setAuthenticating] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [profile, setProfile] = useState<NeoIdUserProfile | null>(cachedProfile);
  const [isAuthenticated, setIsAuthenticated] = useState(cachedAuth);

  const loadProfile = useCallback(async () => {
    if (!cachedProfile) setLoading(true);
    setError(null);
    try {
      const tokens = await getStoredTokens();
      if (!tokens?.accessToken) {
        cachedProfile = null;
        cachedAuth = false;
        emitProfileState();
        void SecureStore.deleteItemAsync(PROFILE_CACHE_KEY);
        setProfile(null);
        setIsAuthenticated(false);
        return;
      }
      cachedAuth = true;
      setIsAuthenticated(true);
      const data = await getProfile();
      cachedProfile = data;
      emitProfileState();
      void SecureStore.setItemAsync(PROFILE_CACHE_KEY, JSON.stringify(data));
      setProfile(data);
    } catch (reason) {
      const message = reason instanceof Error ? reason.message : 'Request failed';
      const isUnauthorized = message.includes('HTTP 401') || message.includes('HTTP 403');
      const isServerError =
        message.includes('HTTP 500') ||
        message.includes('HTTP 502') ||
        message.includes('HTTP 503') ||
        message.includes('HTTP 504');

      // Keep the current session on transient backend issues (5xx).
      // Only clear auth state when token/session is actually invalid.
      if (isUnauthorized) {
        cachedProfile = null;
        cachedAuth = false;
        emitProfileState();
        void SecureStore.deleteItemAsync(PROFILE_CACHE_KEY);
        setProfile(null);
        setIsAuthenticated(false);
      } else if (isServerError) {
        cachedAuth = true;
        emitProfileState();
        setIsAuthenticated(true);
      } else {
        cachedProfile = null;
        cachedAuth = false;
        emitProfileState();
        void SecureStore.deleteItemAsync(PROFILE_CACHE_KEY);
        setProfile(null);
        setIsAuthenticated(false);
      }

      setError(message);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void loadProfile();
  }, [loadProfile]);

  useEffect(() => {
    const unsubscribe = subscribeProfileState((nextProfile, nextIsAuthenticated) => {
      setProfile(nextProfile);
      setIsAuthenticated(nextIsAuthenticated);
      if (nextIsAuthenticated) {
        setError(null);
      }
    });
    return unsubscribe;
  }, []);

  const onLogin = useCallback(async () => {
    setAuthenticating(true);
    setError(null);
    try {
      await loginViaNeoId();
      // Immediately reflect auth state in UI, then fetch full profile.
      cachedAuth = true;
      emitProfileState();
      await loadProfile();
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : 'Auth failed');
    } finally {
      setAuthenticating(false);
    }
  }, [loadProfile]);

  const onLogout = useCallback(async () => {
    await clearStoredTokens();
    cachedProfile = null;
    cachedAuth = false;
    emitProfileState();
    await SecureStore.deleteItemAsync(PROFILE_CACHE_KEY);
    setProfile(null);
    setIsAuthenticated(false);
  }, []);

  const preferredName = useMemo(() => {
    const fullName = [profile?.first_name, profile?.last_name]
      .map((value) => (value || '').trim())
      .filter(Boolean)
      .join(' ');
    return fullName || profile?.name || profile?.display_name || profile?.email || 'Neo User';
  }, [profile?.display_name, profile?.email, profile?.first_name, profile?.last_name, profile?.name]);

  const role = (profile?.role || '').toLowerCase();
  const isAdmin =
    profile?.is_admin === true || profile?.role?.toLowerCase() === 'admin' || role === 'moderator';

  return {
    loading,
    authenticating,
    error,
    isAuthenticated,
    profile,
    preferredName,
    role,
    isAdmin,
    onLogin,
    onLogout,
    refresh: loadProfile,
  };
}
