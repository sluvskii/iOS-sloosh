import * as SecureStore from 'expo-secure-store';

const OFFLINE_MODE_KEY = 'neomovies_offline_mode_v1';
const OFFLINE_MODE_TTL_MS = 1000 * 60 * 15;
const FAILURE_WINDOW_MS = 1000 * 20;
const FAILURES_TO_ENABLE = 2;
export const MAINTENANCE_ERROR_CODE = 'MAINTENANCE_MODE';
export const NETWORK_ERROR_CODE = 'NETWORK_UNAVAILABLE';

type OfflineModeState = {
  enabled: boolean;
  reason: 'maintenance' | 'network' | null;
  updatedAt: number;
};

let state: OfflineModeState = {
  enabled: false,
  reason: null,
  updatedAt: 0,
};

const listeners = new Set<(next: OfflineModeState) => void>();
let maintenanceFailures: number[] = [];
let networkFailures: number[] = [];

function emit() {
  for (const listener of listeners) listener(state);
}

export function getOfflineModeSnapshot() {
  return state;
}

export function subscribeOfflineMode(listener: (next: OfflineModeState) => void) {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

export async function hydrateOfflineMode() {
  try {
    const raw = await SecureStore.getItemAsync(OFFLINE_MODE_KEY);
    if (!raw) return;
    const parsed = JSON.parse(raw) as Partial<OfflineModeState>;
    if (parsed && typeof parsed.enabled === 'boolean') {
      const updatedAt = typeof parsed.updatedAt === 'number' ? parsed.updatedAt : 0;
      const isLegacyWithoutTimestamp = parsed.enabled === true && updatedAt === 0;
      const isExpired = isLegacyWithoutTimestamp || (updatedAt > 0 && Date.now() - updatedAt > OFFLINE_MODE_TTL_MS);
      state = {
        enabled: isExpired ? false : parsed.enabled,
        reason: parsed.reason === 'maintenance' || parsed.reason === 'network' ? parsed.reason : null,
        updatedAt: isExpired ? 0 : updatedAt,
      };
      emit();
    }
  } catch {
    // ignore
  }
}

export function enableMaintenanceOfflineMode() {
  const now = Date.now();
  maintenanceFailures = [...maintenanceFailures.filter((ts) => now - ts <= FAILURE_WINDOW_MS), now];
  if (maintenanceFailures.length < FAILURES_TO_ENABLE) return;
  if (state.enabled && state.reason === 'maintenance') return;
  state = { enabled: true, reason: 'maintenance', updatedAt: now };
  emit();
  void SecureStore.setItemAsync(OFFLINE_MODE_KEY, JSON.stringify(state));
}

export function enableNetworkOfflineMode() {
  const now = Date.now();
  networkFailures = [...networkFailures.filter((ts) => now - ts <= FAILURE_WINDOW_MS), now];
  if (networkFailures.length < FAILURES_TO_ENABLE) return;
  if (state.enabled && state.reason === 'network') return;
  state = { enabled: true, reason: 'network', updatedAt: now };
  emit();
  void SecureStore.setItemAsync(OFFLINE_MODE_KEY, JSON.stringify(state));
}

export function disableOfflineMode() {
  maintenanceFailures = [];
  networkFailures = [];
  if (!state.enabled) return;
  state = { enabled: false, reason: null, updatedAt: Date.now() };
  emit();
  void SecureStore.setItemAsync(OFFLINE_MODE_KEY, JSON.stringify(state));
}

export function isMaintenancePayload(status: number, bodyText: string) {
  if (status !== 503) return false;
  const text = bodyText.trim();
  if (!text) return false;
  if (text.includes(`"${MAINTENANCE_ERROR_CODE}"`)) return true;
  try {
    const parsed = JSON.parse(text) as { code?: string };
    return parsed.code === MAINTENANCE_ERROR_CODE;
  } catch {
    return false;
  }
}
