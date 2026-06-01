import {
  MAINTENANCE_ERROR_CODE,
  NETWORK_ERROR_CODE,
  disableOfflineMode,
  enableMaintenanceOfflineMode,
  enableNetworkOfflineMode,
  isMaintenancePayload,
} from '@/lib/offline-mode';

type HttpRequestInit = RequestInit & { trackOffline?: boolean };

export async function httpGet<T>(url: string, init?: HttpRequestInit): Promise<T> {
  const { trackOffline = true, ...requestInit } = init ?? {};
  let response: Response;
  try {
    response = await fetch(url, {
      method: 'GET',
      headers: {
        Accept: 'application/json',
        ...requestInit.headers,
      },
      ...requestInit,
    });
  } catch {
    if (trackOffline) enableNetworkOfflineMode();
    throw new Error(NETWORK_ERROR_CODE);
  }

  if (!response.ok) {
    const message = await response.text();
    if (isMaintenancePayload(response.status, message)) {
      if (trackOffline) enableMaintenanceOfflineMode();
      throw new Error(MAINTENANCE_ERROR_CODE);
    }
    if (trackOffline) disableOfflineMode();
    throw new Error(`HTTP ${response.status}: ${message || 'Request failed'}`);
  }

  if (trackOffline) disableOfflineMode();
  return (await response.json()) as T;
}

export async function httpGetText(url: string, init?: HttpRequestInit): Promise<string> {
  const { trackOffline = true, ...requestInit } = (init ?? {}) as HttpRequestInit;
  let response: Response;
  try {
    response = await fetch(url, {
      method: 'GET',
      headers: {
        Accept: 'text/html, text/plain, */*',
        ...requestInit.headers,
      },
      ...requestInit,
    });
  } catch {
    if (trackOffline) enableNetworkOfflineMode();
    throw new Error(NETWORK_ERROR_CODE);
  }

  const text = await response.text();
  if (!response.ok) {
    if (isMaintenancePayload(response.status, text)) {
      if (trackOffline) enableMaintenanceOfflineMode();
      throw new Error(MAINTENANCE_ERROR_CODE);
    }
    if (trackOffline) disableOfflineMode();
    throw new Error(`HTTP ${response.status}: ${text || 'Request failed'}`);
  }

  if (trackOffline) disableOfflineMode();
  return text;
}
