import { config } from "../config"

interface AllohaData {
  id_kp?: number
  id_imdb?: string
  id_tmdb?: number
  name?: string
  iframe?: string
  category?: number
  seasons_count?: number
}

interface AllohaResponse {
  status: string
  data?: AllohaData
  error_info?: string
}

export interface ResolveAllohaOptions {
  imdbId?: string | null
  kpId?: number | null
  title?: string | null
  originalTitle?: string | null
  year?: number | null
}

interface QueryResult {
  response: AllohaResponse | null
  usedToken: string | null
}

export class AllohaTokenPool {
  private failedTokens = new Map<string, number>()
  private cooldownMs = 5 * 60 * 1000 // 5 minutes cooldown

  getCandidates(): string[] {
    const now = Date.now()
    const all = config.alloha.allTokens
    if (all.length === 0) return []

    const available = all.filter(token => {
      const cooldownUntil = this.failedTokens.get(token)
      if (!cooldownUntil) return true
      if (now >= cooldownUntil) {
        this.failedTokens.delete(token)
        return true
      }
      return false
    })

    if (available.length === 0) {
      // All tokens are on cooldown; reset and retry full list
      this.failedTokens.clear()
      return all
    }

    return available
  }

  markFailed(token: string): void {
    this.failedTokens.set(token, Date.now() + this.cooldownMs)
    console.warn(`[AllohaTokenPool] Token ...${token.slice(-6)} marked failed for 5m cooldown`)
  }

  markSuccess(token: string): void {
    if (this.failedTokens.has(token)) {
      this.failedTokens.delete(token)
    }
  }

  reset(): void {
    this.failedTokens.clear()
  }
}

export const tokenPool = new AllohaTokenPool()

function isTokenFailure(httpStatus: number, json: any): boolean {
  if (httpStatus === 401 || httpStatus === 403 || httpStatus === 429 || httpStatus >= 500) {
    return true
  }
  if (json && typeof json === "object") {
    if (json.status === "error") {
      const err = String(json.error_info || "").toLowerCase()
      // "not movie" means the token is HEALTHY and working, but content isn't in Alloha
      if (err.includes("not movie")) {
        return false
      }
      // Explicit token / auth / rate limit failure
      if (
        err.includes("token") ||
        err.includes("limit") ||
        err.includes("block") ||
        err.includes("ban") ||
        err.includes("auth") ||
        err.includes("access")
      ) {
        return true
      }
    }
  }
  return false
}

async function queryAlloha(params: Record<string, string | number | undefined>): Promise<QueryResult> {
  const candidates = tokenPool.getCandidates()
  if (candidates.length === 0) return { response: null, usedToken: null }

  for (const token of candidates) {
    const searchParams = new URLSearchParams()
    searchParams.set("token", token)
    for (const [key, val] of Object.entries(params)) {
      if (val !== undefined && val !== null && val !== "") {
        searchParams.set(key, String(val))
      }
    }

    try {
      const url = `${config.alloha.baseUrl}/?${searchParams.toString()}`
      const res = await fetch(url, {
        headers: { Accept: "application/json" },
        signal: AbortSignal.timeout(5000),
      })

      if (!res.ok) {
        if (isTokenFailure(res.status, null)) {
          tokenPool.markFailed(token)
          continue
        }
        return { response: null, usedToken: null }
      }

      const json = (await res.json()) as AllohaResponse
      if (isTokenFailure(res.status, json)) {
        tokenPool.markFailed(token)
        continue
      }

      // Token is confirmed healthy!
      tokenPool.markSuccess(token)

      if (json.status === "success" && json.data) {
        return { response: json, usedToken: token }
      }

      // "not movie" or empty: title not found on Alloha. Do NOT query other tokens.
      return { response: null, usedToken: token }
    } catch {
      tokenPool.markFailed(token)
      continue
    }
  }

  return { response: null, usedToken: null }
}

export async function resolveAlloha(
  tmdbId: number,
  options?: ResolveAllohaOptions
): Promise<{
  kpId: number | null
  imdbId: string | null
  iframeUrl: string | null
}> {
  let result: QueryResult = { response: null, usedToken: null }

  // 1. Try TMDB ID
  if (tmdbId > 0) {
    result = await queryAlloha({ tmdb: tmdbId })
  }

  // 2. Try IMDB ID if TMDB failed
  if (!result.response?.data && options?.imdbId) {
    result = await queryAlloha({ imdb: options.imdbId })
  }

  // 3. Try KP ID if available
  if (!result.response?.data && options?.kpId && options.kpId > 0) {
    result = await queryAlloha({ kp: options.kpId })
  }

  // 4. Try title + year
  if (!result.response?.data && options?.title) {
    if (options.year) {
      result = await queryAlloha({ name: options.title, year: options.year })
    }
    if (!result.response?.data) {
      result = await queryAlloha({ name: options.title })
    }
  }

  // 5. Try original title + year
  if (!result.response?.data && options?.originalTitle && options.originalTitle !== options.title) {
    if (options.year) {
      result = await queryAlloha({ name: options.originalTitle, year: options.year })
    }
    if (!result.response?.data) {
      result = await queryAlloha({ name: options.originalTitle })
    }
  }

  const res = result.response
  if (!res?.data) {
    return { kpId: null, imdbId: null, iframeUrl: null }
  }

  const activeToken = result.usedToken || config.alloha.token
  const kpId = res.data.id_kp ?? null
  const imdbId = res.data.id_imdb ?? options?.imdbId ?? null
  const iframeUrl = res.data.iframe ?? (kpId ? `https://stream.alloha.tv/?token=${activeToken}&kp=${kpId}` : null)

  return { kpId, imdbId, iframeUrl }
}

export async function resolveTmdbInfoByKp(kpId: number): Promise<{
  tmdbId: number | null
  isTv: boolean
} | null> {
  const result = await queryAlloha({ kp: kpId })
  const res = result.response
  if (!res?.data?.id_tmdb) return null
  const isTv = res.data.category === 2 || (res.data.seasons_count !== undefined && res.data.seasons_count > 0)
  return { tmdbId: res.data.id_tmdb, isTv }
}

export async function resolveTmdbIdByKp(kpId: number): Promise<number | null> {
  const info = await resolveTmdbInfoByKp(kpId)
  return info?.tmdbId ?? null
}
