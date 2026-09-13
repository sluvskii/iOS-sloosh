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
}

export interface ResolveAllohaOptions {
  imdbId?: string | null
  kpId?: number | null
  title?: string | null
  originalTitle?: string | null
  year?: number | null
}

async function queryAlloha(params: Record<string, string | number | undefined>): Promise<AllohaResponse | null> {
  if (!config.alloha.token) return null
  const searchParams = new URLSearchParams()
  searchParams.set("token", config.alloha.token)
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

    if (!res.ok) return null
    const json = (await res.json()) as AllohaResponse
    if (json.status === "success" && json.data) {
      return json
    }
    return null
  } catch {
    return null
  }
}

export async function resolveAlloha(
  tmdbId: number,
  options?: ResolveAllohaOptions
): Promise<{
  kpId: number | null
  imdbId: string | null
  iframeUrl: string | null
}> {
  if (!config.alloha.token) {
    return { kpId: null, imdbId: null, iframeUrl: null }
  }

  let res: AllohaResponse | null = null

  // 1. Try TMDB ID
  if (tmdbId > 0) {
    res = await queryAlloha({ tmdb: tmdbId })
  }

  // 2. Try IMDB ID if TMDB failed
  if (!res?.data && options?.imdbId) {
    res = await queryAlloha({ imdb: options.imdbId })
  }

  // 3. Try KP ID if available
  if (!res?.data && options?.kpId && options.kpId > 0) {
    res = await queryAlloha({ kp: options.kpId })
  }

  // 4. Try title + year
  if (!res?.data && options?.title) {
    if (options.year) {
      res = await queryAlloha({ name: options.title, year: options.year })
    }
    if (!res?.data) {
      res = await queryAlloha({ name: options.title })
    }
  }

  // 5. Try original title + year
  if (!res?.data && options?.originalTitle && options.originalTitle !== options.title) {
    if (options.year) {
      res = await queryAlloha({ name: options.originalTitle, year: options.year })
    }
    if (!res?.data) {
      res = await queryAlloha({ name: options.originalTitle })
    }
  }

  if (!res?.data) {
    return { kpId: null, imdbId: null, iframeUrl: null }
  }

  const kpId = res.data.id_kp ?? null
  const imdbId = res.data.id_imdb ?? options?.imdbId ?? null
  const iframeUrl = res.data.iframe ?? (kpId ? `https://stream.alloha.tv/?token=${config.alloha.token}&kp=${kpId}` : null)

  return { kpId, imdbId, iframeUrl }
}

export async function resolveTmdbInfoByKp(kpId: number): Promise<{
  tmdbId: number | null
  isTv: boolean
} | null> {
  if (!config.alloha.token) return null
  try {
    const url = `${config.alloha.baseUrl}/?token=${config.alloha.token}&kp=${kpId}`
    const res = await fetch(url, {
      headers: { Accept: "application/json" },
      signal: AbortSignal.timeout(5000),
    })
    if (!res.ok) return null
    const json = (await res.json()) as AllohaResponse
    if (!json.data?.id_tmdb) return null
    const isTv = json.data.category === 2 || (json.data.seasons_count !== undefined && json.data.seasons_count > 0)
    return { tmdbId: json.data.id_tmdb, isTv }
  } catch {
    return null
  }
}

export async function resolveTmdbIdByKp(kpId: number): Promise<number | null> {
  const info = await resolveTmdbInfoByKp(kpId)
  return info?.tmdbId ?? null
}
