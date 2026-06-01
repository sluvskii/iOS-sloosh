type RouteKey = 'home' | 'explore' | 'favorites' | 'category' | 'media';

const cacheByRoute: Record<RouteKey, boolean> = {
  home: false,
  explore: false,
  favorites: false,
  category: false,
  media: false,
};

const listeners = new Set<() => void>();

function emit() {
  for (const listener of listeners) listener();
}

export function setRouteHasCache(route: RouteKey, hasCache: boolean) {
  if (cacheByRoute[route] === hasCache) return;
  cacheByRoute[route] = hasCache;
  emit();
}

export function getRouteHasCache(route: RouteKey) {
  return cacheByRoute[route];
}

export function subscribeRouteCache(listener: () => void) {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}
