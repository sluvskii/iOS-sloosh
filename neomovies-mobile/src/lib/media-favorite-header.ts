export type MediaFavoriteHeaderState = {
  visible: boolean;
  isFavorite: boolean;
  busy: boolean;
  onPress: (() => void) | null;
};

const defaultState: MediaFavoriteHeaderState = {
  visible: false,
  isFavorite: false,
  busy: false,
  onPress: null,
};

let state: MediaFavoriteHeaderState = defaultState;
const listeners = new Set<(next: MediaFavoriteHeaderState) => void>();

export function setMediaFavoriteHeader(next: MediaFavoriteHeaderState) {
  state = next;
  for (const listener of listeners) {
    listener(state);
  }
}

export function resetMediaFavoriteHeader() {
  setMediaFavoriteHeader(defaultState);
}

export function getMediaFavoriteHeader() {
  return state;
}

export function subscribeMediaFavoriteHeader(listener: (next: MediaFavoriteHeaderState) => void) {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}
