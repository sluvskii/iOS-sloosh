import { config } from "../config"

interface AllohaData {
  id_kp?: number
  id_imdb?: string
  id_tmdb?: number
  name?: string
  iframe?: string
}

interface AllohaResponse {
  status: string
  data?: AllohaData
}

export async function resolveAlloha(tmdbId: number): Promise<{
  kpId: number | null
  imdbId: string | null
  iframeUrl: string | null
}> {
  if (!config.alloha.token) {
    return { kpId: null, imdbId: null, iframeUrl: null }
  }

  try {
    const url = `${config.alloha.baseUrl}/?token=${config.alloha.token}&tmdb=${tmdbId}`
    const res = await fetch(url, {
      headers: { Accept: "application/json" },
      signal: AbortSignal.timeout(5000),
    })

    if (!res.ok) {
      return { kpId: null, imdbId: null, iframeUrl: null }
    }

    const json = (await res.json()) as AllohaResponse
    if (json.status !== "success" || !json.data) {
      return { kpId: null, imdbId: null, iframeUrl: null }
    }

    const kpId = json.data.id_kp ?? null
    const imdbId = json.data.id_imdb ?? null
    const iframeUrl = json.data.iframe ?? (kpId ? `https://stream.alloha.tv/?token=${config.alloha.token}&kp=${kpId}` : null)

    return { kpId, imdbId, iframeUrl }
  } catch (err) {
    return { kpId: null, imdbId: null, iframeUrl: null }
  }
}
