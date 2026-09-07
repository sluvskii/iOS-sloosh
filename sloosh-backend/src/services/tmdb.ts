import { config } from "../config"
import type {
  MediaDto,
  MediaDetailsDto,
  MediaResponse,
  CastMemberDto,
  TrailerVideoDto,
  MovieCollectionDto,
  CollectionPartDto,
} from "../types/models"

const IMAGE_BASE = config.tmdb.imageBaseUrl

export function formatImageUrl(path: string | null | undefined, size: "w500" | "original" = "original"): string | undefined {
  if (!path) return undefined
  if (path.startsWith("http")) return path
  return `${IMAGE_BASE}/${size}${path}`
}

function buildHeaders(): Record<string, string> {
  const headers: Record<string, string> = {
    Accept: "application/json",
  }
  if (config.tmdb.token.length > 50) {
    headers.Authorization = `Bearer ${config.tmdb.token}`
  }
  return headers
}

function buildUrl(endpoint: string, params: Record<string, string> = {}): string {
  const url = new URL(`${config.tmdb.baseUrl}${endpoint}`)
  url.searchParams.set("language", config.tmdb.defaultLanguage)
  
  if (config.tmdb.token && config.tmdb.token.length <= 50) {
    url.searchParams.set("api_key", config.tmdb.token)
  }

  for (const [key, value] of Object.entries(params)) {
    if (value !== undefined && value !== null && value !== "") {
      url.searchParams.set(key, value)
    }
  }
  return url.toString()
}

async function tmdbFetch<T>(endpoint: string, params: Record<string, string> = {}): Promise<T> {
  const url = buildUrl(endpoint, params)
  const res = await fetch(url, {
    headers: buildHeaders(),
    signal: AbortSignal.timeout(8000),
  })
  if (!res.ok) {
    throw new Error(`TMDB error ${res.status}: ${res.statusText} at ${endpoint}`)
  }
  return res.json() as Promise<T>
}

export function mapRawMovie(m: any): MediaDto {
  const year = m.release_date ? parseInt(m.release_date.split("-")[0], 10) : undefined
  const poster = formatImageUrl(m.poster_path, "w500")
  const backdrop = formatImageUrl(m.backdrop_path, "original")
  const rating = m.vote_average ? Math.round(m.vote_average * 10) / 10 : 0

  return {
    id: String(m.id),
    title: m.title || m.original_title || "",
    originalTitle: m.original_title || m.title || "",
    description: m.overview || "",
    type: "movie",
    year,
    releaseDate: m.release_date,
    rating,
    ratings: {
      tmdb: rating,
    },
    poster,
    poster_path: m.poster_path,
    backdrop,
    backdrop_path: m.backdrop_path,
    genres: m.genres || (m.genre_ids ? m.genre_ids.map((gid: number) => ({ id: gid, name: "" })) : []),
    externalIds: {
      tmdb: m.id,
    },
  }
}

export function mapRawTv(t: any): MediaDto {
  const year = t.first_air_date ? parseInt(t.first_air_date.split("-")[0], 10) : undefined
  const poster = formatImageUrl(t.poster_path, "w500")
  const backdrop = formatImageUrl(t.backdrop_path, "original")
  const rating = t.vote_average ? Math.round(t.vote_average * 10) / 10 : 0

  return {
    id: String(t.id),
    title: t.name || t.original_name || "",
    name: t.name,
    originalTitle: t.original_name || t.name || "",
    description: t.overview || "",
    type: "tv",
    year,
    releaseDate: t.first_air_date,
    rating,
    ratings: {
      tmdb: rating,
    },
    poster,
    poster_path: t.poster_path,
    backdrop,
    backdrop_path: t.backdrop_path,
    genres: t.genres || (t.genre_ids ? t.genre_ids.map((gid: number) => ({ id: gid, name: "" })) : []),
    externalIds: {
      tmdb: t.id,
    },
  }
}

export class TMDBService {
  async getTrending(type: "movie" | "tv" | "all" = "all", timeWindow: "day" | "week" = "week", page = 1): Promise<MediaResponse> {
    const data = await tmdbFetch<any>(`/trending/${type}/${timeWindow}`, { page: String(page) })
    const results: MediaDto[] = (data.results || []).map((item: any) => {
      return item.media_type === "tv" || (!item.title && item.name) ? mapRawTv(item) : mapRawMovie(item)
    }).filter((item: MediaDto) => !item.poster?.includes("null") && item.title.trim().length > 0)

    return {
      results,
      items: results,
      page: data.page || page,
      total_pages: data.total_pages || 1,
      pages: data.total_pages || 1,
      total_results: data.total_results || results.length,
      total: data.total_results || results.length,
    }
  }

  async getPopular(type: "movie" | "tv" = "movie", page = 1): Promise<MediaResponse> {
    const data = await tmdbFetch<any>(`/${type}/popular`, { page: String(page) })
    const results = (data.results || []).map((item: any) => type === "tv" ? mapRawTv(item) : mapRawMovie(item))
      .filter((item: MediaDto) => item.poster && item.title.trim().length > 0)

    return {
      results,
      items: results,
      page: data.page || page,
      total_pages: data.total_pages || 1,
      pages: data.total_pages || 1,
      total_results: data.total_results || results.length,
      total: data.total_results || results.length,
    }
  }

  async getTopRated(type: "movie" | "tv" = "movie", page = 1): Promise<MediaResponse> {
    const data = await tmdbFetch<any>(`/${type}/top_rated`, { page: String(page) })
    const results = (data.results || []).map((item: any) => type === "tv" ? mapRawTv(item) : mapRawMovie(item))
      .filter((item: MediaDto) => item.poster && item.title.trim().length > 0)

    return {
      results,
      items: results,
      page: data.page || page,
      total_pages: data.total_pages || 1,
      pages: data.total_pages || 1,
      total_results: data.total_results || results.length,
      total: data.total_results || results.length,
    }
  }

  async getCartoons(page = 1): Promise<MediaResponse> {
    const data = await tmdbFetch<any>("/discover/movie", {
      page: String(page),
      with_genres: "16", // 16 = Animation
      sort_by: "popularity.desc",
      "vote_count.gte": "20",
    })
    const results = (data.results || []).map(mapRawMovie).filter((item: MediaDto) => item.poster && item.title.trim().length > 0)

    return {
      results,
      items: results,
      page: data.page || page,
      total_pages: data.total_pages || 1,
      pages: data.total_pages || 1,
      total_results: data.total_results || results.length,
      total: data.total_results || results.length,
    }
  }

  async getByCompany(companyId: number, page = 1): Promise<MediaResponse> {
    const data = await tmdbFetch<any>("/discover/movie", {
      page: String(page),
      with_companies: String(companyId),
      sort_by: "popularity.desc",
      "vote_count.gte": "5",
    })
    const results = (data.results || []).map(mapRawMovie).filter((item: MediaDto) => item.poster && item.title.trim().length > 0)

    return {
      results,
      items: results,
      page: data.page || page,
      total_pages: data.total_pages || 1,
      pages: data.total_pages || 1,
      total_results: data.total_results || results.length,
      total: data.total_results || results.length,
    }
  }

  async getByNetwork(networkId: number, page = 1): Promise<MediaResponse> {
    const data = await tmdbFetch<any>("/discover/tv", {
      page: String(page),
      with_networks: String(networkId),
      sort_by: "popularity.desc",
      "vote_count.gte": "5",
    })
    const results = (data.results || []).map(mapRawTv).filter((item: MediaDto) => item.poster && item.title.trim().length > 0)

    return {
      results,
      items: results,
      page: data.page || page,
      total_pages: data.total_pages || 1,
      pages: data.total_pages || 1,
      total_results: data.total_results || results.length,
      total: data.total_results || results.length,
    }
  }

  async search(query: string, page = 1): Promise<MediaResponse> {
    const data = await tmdbFetch<any>("/search/multi", {
      query,
      page: String(page),
      include_adult: "false",
    })
    const results: MediaDto[] = (data.results || [])
      .filter((item: any) => item.media_type === "movie" || item.media_type === "tv")
      .map((item: any) => item.media_type === "tv" ? mapRawTv(item) : mapRawMovie(item))
      .filter((item: MediaDto) => item.poster && item.title.trim().length > 0)

    return {
      results,
      items: results,
      page: data.page || page,
      total_pages: data.total_pages || 1,
      pages: data.total_pages || 1,
      total_results: data.total_results || results.length,
      total: data.total_results || results.length,
    }
  }

  async getMovieDetails(id: number): Promise<MediaDetailsDto> {
    const data = await tmdbFetch<any>(`/movie/${id}`, {
      append_to_response: "credits,videos,images,recommendations,similar,external_ids",
      include_image_language: "ru,en,null",
    })

    const base = mapRawMovie(data)
    
    // Cast
    const cast: CastMemberDto[] = (data.credits?.cast || []).slice(0, 25).map((c: any) => ({
      id: c.id,
      name: c.name || c.original_name,
      originalName: c.original_name || c.name,
      character: c.character || "",
      photo: formatImageUrl(c.profile_path, "w500") || null,
    }))

    // Trailers
    const trailers: TrailerVideoDto[] = (data.videos?.results || [])
      .filter((v: any) => v.site === "YouTube" && (v.type === "Trailer" || v.type === "Teaser"))
      .sort((a: any, b: any) => {
        if (a.iso_639_1 === "ru" && b.iso_639_1 !== "ru") return -1
        if (b.iso_639_1 === "ru" && a.iso_639_1 !== "ru") return 1
        return 0
      })
      .slice(0, 5)
      .map((v: any) => ({
        id: v.id,
        name: v.name,
        key: v.key,
        site: v.site,
        url: `https://www.youtube.com/watch?v=${v.key}`,
      }))

    // ClearLogo (Transparent Logo)
    let logoUrl: string | null = null
    const logos = data.images?.logos || []
    const ruLogo = logos.find((l: any) => l.iso_639_1 === "ru")
    const enLogo = logos.find((l: any) => l.iso_639_1 === "en")
    const fallbackLogo = logos[0]
    const chosenLogo = ruLogo || enLogo || fallbackLogo
    if (chosenLogo?.file_path) {
      logoUrl = formatImageUrl(chosenLogo.file_path, "original") || null
    }

    // Collection / Franchise
    let collection: MovieCollectionDto | null = null
    if (data.belongs_to_collection?.id) {
      try {
        const collData = await tmdbFetch<any>(`/collection/${data.belongs_to_collection.id}`)
        const parts: CollectionPartDto[] = (collData.parts || [])
          .sort((a: any, b: any) => {
            const dateA = a.release_date || "9999"
            const dateB = b.release_date || "9999"
            return dateA.localeCompare(dateB)
          })
          .map((p: any) => {
            const partYear = p.release_date ? parseInt(p.release_date.split("-")[0], 10) : null
            return {
              id: String(p.id),
              title: p.title || p.original_title || "",
              originalTitle: p.original_title || p.title || "",
              overview: p.overview || "",
              poster: formatImageUrl(p.poster_path, "w500") || null,
              backdrop: formatImageUrl(p.backdrop_path, "original") || null,
              year: partYear,
              rating: p.vote_average ? Math.round(p.vote_average * 10) / 10 : 0,
              type: "movie",
            }
          })

        collection = {
          id: collData.id,
          name: collData.name,
          overview: collData.overview || "",
          poster: formatImageUrl(collData.poster_path, "w500") || null,
          backdrop: formatImageUrl(collData.backdrop_path, "original") || null,
          parts,
        }
      } catch (err) {
        // Fallback without parts
      }
    }

    // Companies & Networks
    const productionCompanies = (data.production_companies || []).map((c: any) => ({
      id: c.id,
      name: c.name,
      logo: formatImageUrl(c.logo_path, "w500") || null,
    }))

    return {
      ...base,
      duration: data.runtime || undefined,
      countries: (data.production_countries || []).map((c: any) => c.name),
      logo: logoUrl,
      cast,
      trailers,
      collection,
      productionCompanies,
      externalIds: {
        tmdb: data.id,
        imdb: data.external_ids?.imdb_id || data.imdb_id,
      },
    }
  }

  async getTvDetails(id: number): Promise<MediaDetailsDto> {
    const data = await tmdbFetch<any>(`/tv/${id}`, {
      append_to_response: "credits,videos,images,recommendations,similar,external_ids",
      include_image_language: "ru,en,null",
    })

    const base = mapRawTv(data)
    
    // Cast
    const cast: CastMemberDto[] = (data.credits?.cast || []).slice(0, 25).map((c: any) => ({
      id: c.id,
      name: c.name || c.original_name,
      originalName: c.original_name || c.name,
      character: c.character || "",
      photo: formatImageUrl(c.profile_path, "w500") || null,
    }))

    // Trailers
    const trailers: TrailerVideoDto[] = (data.videos?.results || [])
      .filter((v: any) => v.site === "YouTube" && (v.type === "Trailer" || v.type === "Teaser"))
      .sort((a: any, b: any) => {
        if (a.iso_639_1 === "ru" && b.iso_639_1 !== "ru") return -1
        if (b.iso_639_1 === "ru" && a.iso_639_1 !== "ru") return 1
        return 0
      })
      .slice(0, 5)
      .map((v: any) => ({
        id: v.id,
        name: v.name,
        key: v.key,
        site: v.site,
        url: `https://www.youtube.com/watch?v=${v.key}`,
      }))

    // Logo
    let logoUrl: string | null = null
    const logos = data.images?.logos || []
    const ruLogo = logos.find((l: any) => l.iso_639_1 === "ru")
    const enLogo = logos.find((l: any) => l.iso_639_1 === "en")
    const fallbackLogo = logos[0]
    const chosenLogo = ruLogo || enLogo || fallbackLogo
    if (chosenLogo?.file_path) {
      logoUrl = formatImageUrl(chosenLogo.file_path, "original") || null
    }

    const networks = (data.networks || []).map((n: any) => ({
      id: n.id,
      name: n.name,
      logo: formatImageUrl(n.logo_path, "w500") || null,
    }))

    return {
      ...base,
      duration: data.episode_run_time?.[0] || undefined,
      countries: (data.origin_country || []),
      logo: logoUrl,
      cast,
      trailers,
      networks,
      externalIds: {
        tmdb: data.id,
        imdb: data.external_ids?.imdb_id,
      },
    }
  }

  async getCollection(id: number): Promise<MovieCollectionDto> {
    const data = await tmdbFetch<any>(`/collection/${id}`)
    const parts: CollectionPartDto[] = (data.parts || [])
      .sort((a: any, b: any) => {
        const dateA = a.release_date || "9999"
        const dateB = b.release_date || "9999"
        return dateA.localeCompare(dateB)
      })
      .map((p: any) => {
        const partYear = p.release_date ? parseInt(p.release_date.split("-")[0], 10) : null
        return {
          id: String(p.id),
          title: p.title || p.original_title || "",
          originalTitle: p.original_title || p.title || "",
          overview: p.overview || "",
          poster: formatImageUrl(p.poster_path, "w500") || null,
          backdrop: formatImageUrl(p.backdrop_path, "original") || null,
          year: partYear,
          rating: p.vote_average ? Math.round(p.vote_average * 10) / 10 : 0,
          type: "movie",
        }
      })

    return {
      id: data.id,
      name: data.name,
      overview: data.overview || "",
      poster: formatImageUrl(data.poster_path, "w500") || null,
      backdrop: formatImageUrl(data.backdrop_path, "original") || null,
      parts,
    }
  }

  async getEpisodeDetails(tvId: number, season: number, episode: number): Promise<any> {
    const data = await tmdbFetch<any>(`/tv/${tvId}/season/${season}/episode/${episode}`)
    return {
      id: data.id,
      name: data.name || `Серия ${episode}`,
      overview: data.overview || "",
      airDate: data.air_date,
      seasonNumber: data.season_number,
      episodeNumber: data.episode_number,
      stillPath: formatImageUrl(data.still_path, "original"),
      voteAverage: data.vote_average,
    }
  }
}

export const tmdb = new TMDBService()
