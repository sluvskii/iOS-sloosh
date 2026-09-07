import { LRUCache } from "lru-cache"

export const listCache = new LRUCache<string, any>({
  max: 500,
  ttl: 1000 * 60 * 60, // 1 hour
})

export const detailsCache = new LRUCache<string, any>({
  max: 2000,
  ttl: 1000 * 60 * 60 * 24, // 24 hours
})

export function getCached<T>(cache: LRUCache<string, any>, key: string): T | undefined {
  return cache.get(key) as T | undefined
}

export function setCached<T>(cache: LRUCache<string, any>, key: string, value: T): void {
  cache.set(key, value)
}
