import * as SecureStore from 'expo-secure-store';
import { useCallback, useEffect, useState } from 'react';

export type ContentSource = 'collaps' | 'alloha';

const SOURCE_KEY = 'content_source_v1';
let sourceCache: ContentSource = 'collaps';
let sourceCacheReady = false;
let sourceInitPromise: Promise<void> | null = null;
const sourceListeners = new Set<(value: ContentSource, ready: boolean) => void>();

function notifySourceListeners() {
  for (const listener of sourceListeners) {
    listener(sourceCache, sourceCacheReady);
  }
}

async function ensureSourceInitialized() {
  if (sourceCacheReady) return;
  if (!sourceInitPromise) {
    sourceInitPromise = (async () => {
      try {
        const stored = await SecureStore.getItemAsync(SOURCE_KEY);
        if (stored === 'alloha' || stored === 'collaps') {
          sourceCache = stored;
        }
      } finally {
        sourceCacheReady = true;
        notifySourceListeners();
      }
    })();
  }
  await sourceInitPromise;
}

export function useContentSource() {
  const [source, setSourceState] = useState<ContentSource>(sourceCache);
  const [ready, setReady] = useState(sourceCacheReady);

  useEffect(() => {
    const onSourceUpdate = (nextSource: ContentSource, nextReady: boolean) => {
      setSourceState(nextSource);
      setReady(nextReady);
    };
    sourceListeners.add(onSourceUpdate);
    void ensureSourceInitialized();
    return () => {
      sourceListeners.delete(onSourceUpdate);
    };
  }, []);

  const setSource = useCallback(async (next: ContentSource) => {
    sourceCache = next;
    sourceCacheReady = true;
    notifySourceListeners();
    await SecureStore.setItemAsync(SOURCE_KEY, next);
  }, []);

  return { source, setSource, ready };
}
