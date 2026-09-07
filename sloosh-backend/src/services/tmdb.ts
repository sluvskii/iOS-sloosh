import { config } from "../config"
import { localizeCountry, resolveCountryCode } from "../utils/countries"
import type {
  MediaDto,
  MediaDetailsDto,
  MediaResponse,
  CastMemberDto,
  TrailerVideoDto,
  MovieCollectionDto,
  CollectionPartDto,
} from "../types/models"

export interface DiscoverOptions {
  query?: string
  genres?: string
  countries?: string
  type?: string
  order?: string
  ratingFrom?: number
  ratingTo?: number
  year?: number
  yearFrom?: number
  yearTo?: number
  page?: number
}

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

export const TMDB_GENRES: Record<number, string> = {
  28: "боевик",
  12: "приключения",
  16: "мультфильм",
  35: "комедия",
  80: "криминал",
  99: "документальный",
  18: "драма",
  10751: "семейный",
  14: "фэнтези",
  36: "история",
  27: "ужасы",
  10402: "музыка",
  9648: "детектив",
  10749: "мелодрама",
  878: "фантастика",
  10770: "телефильм",
  53: "триллер",
  10752: "военный",
  37: "вестерн",
  10759: "боевик и приключения",
  10762: "детский",
  10763: "новости",
  10764: "реалити-шоу",
  10765: "научная фантастика и фэнтези",
  10766: "мыльная опера",
  10767: "ток-шоу",
  10768: "война и политика",
}

export function resolveGenreIds(genres: string, isTv: boolean = false): string {
  if (!genres) return ""
  const tokens = genres.split(",").map(t => t.trim().toLowerCase()).filter(Boolean)
  const ids: number[] = []

  const movieMap: Record<string, number> = {
    "боевик": 28, "боевики": 28, "action": 28,
    "приключения": 12, "приключение": 12, "adventure": 12,
    "мультфильм": 16, "мультфильмы": 16, "анимация": 16, "аниме": 16, "animation": 16, "anime": 16,
    "комедия": 35, "комедии": 35, "comedy": 35,
    "криминал": 80, "криминальный": 80, "crime": 80,
    "документальный": 99, "документалка": 99, "documentary": 99,
    "драма": 18, "драмы": 18, "drama": 18,
    "семейный": 10751, "семейное": 10751, "семья": 10751, "family": 10751,
    "фэнтези": 14, "fantasy": 14,
    "история": 36, "исторический": 36, "history": 36,
    "ужасы": 27, "ужас": 27, "хоррор": 27, "horror": 27,
    "музыка": 10402, "мюзикл": 10402, "музыкальный": 10402, "music": 10402,
    "детектив": 9648, "детективы": 9648, "mystery": 9648,
    "мелодрама": 10749, "мелодрамы": 10749, "романтика": 10749, "romance": 10749,
    "фантастика": 878, "sci-fi": 878,
    "телефильм": 10770,
    "триллер": 53, "триллеры": 53, "thriller": 53,
    "военный": 10752, "война": 10752, "war": 10752,
    "вестерн": 37, "вестерны": 37, "western": 37,
    "детский": 10751, "детские": 10751, "kids": 10751,
  }

  const tvMap: Record<string, number> = {
    ...movieMap,
    "боевик": 10759, "боевики": 10759, "приключения": 10759, "боевик и приключения": 10759, "action": 10759, "adventure": 10759,
    "детский": 10762, "kids": 10762,
    "новости": 10763, "news": 10763,
    "реалити-шоу": 10764, "reality": 10764,
    "научная фантастика и фэнтези": 10765, "фантастика": 10765, "фэнтези": 10765, "sci-fi": 10765, "fantasy": 10765,
    "мыльная опера": 10766, "soap": 10766,
    "ток-шоу": 10767, "talk": 10767,
    "война и политика": 10768, "военный": 10768, "война": 10768, "war": 10768,
  }

  const activeMap = isTv ? tvMap : movieMap

  for (const token of tokens) {
    if (/^\d+$/.test(token)) {
      ids.push(parseInt(token, 10))
    } else if (activeMap[token]) {
      ids.push(activeMap[token])
    } else {
      const entry = Object.entries(activeMap).find(([k]) => token.includes(k) || k.includes(token))
      if (entry) {
        ids.push(entry[1])
      }
    }
  }

  return [...new Set(ids)].join(",")
}

export function mapRawMovie(m: any): MediaDto {
  const year = m.release_date ? parseInt(m.release_date.split("-")[0], 10) : undefined
  const poster = formatImageUrl(m.poster_path, "w500")
  const backdrop = formatImageUrl(m.backdrop_path, "original") || poster
  const rating = m.vote_average ? Math.round(m.vote_average * 10) / 10 : 0
  const genres = Array.isArray(m.genres)
    ? m.genres.map((g: any) => ({ id: String(g.id), name: g.name || TMDB_GENRES[g.id] || "" }))
    : (Array.isArray(m.genre_ids)
        ? m.genre_ids.map((gid: number) => ({ id: String(gid), name: TMDB_GENRES[gid] || "" }))
        : [])

  const rawCountries = m.production_countries || (m.origin_country ? m.origin_country.map((c: string) => ({ iso_3166_1: c })) : [])
  const countries = rawCountries.map(localizeCountry).filter(Boolean)

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
    posterUrl: poster,
    poster_path: m.poster_path,
    backdrop,
    backdropUrl: backdrop,
    backdrop_path: m.backdrop_path,
    genres,
    countries,
    externalIds: {
      tmdb: m.id,
    },
  }
}

export function mapRawTv(t: any): MediaDto {
  const year = t.first_air_date ? parseInt(t.first_air_date.split("-")[0], 10) : undefined
  const poster = formatImageUrl(t.poster_path, "w500")
  const backdrop = formatImageUrl(t.backdrop_path, "original") || poster
  const rating = t.vote_average ? Math.round(t.vote_average * 10) / 10 : 0
  const genres = Array.isArray(t.genres)
    ? t.genres.map((g: any) => ({ id: String(g.id), name: g.name || TMDB_GENRES[g.id] || "" }))
    : (Array.isArray(t.genre_ids)
        ? t.genre_ids.map((gid: number) => ({ id: String(gid), name: TMDB_GENRES[gid] || "" }))
        : [])

  const rawCountries = t.origin_country || (t.production_countries ? t.production_countries.map((c: any) => c.iso_3166_1 || c.name) : [])
  const countries = rawCountries.map(localizeCountry).filter(Boolean)

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
    posterUrl: poster,
    poster_path: t.poster_path,
    backdrop,
    backdropUrl: backdrop,
    backdrop_path: t.backdrop_path,
    genres,
    countries,
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

  async discover(options: DiscoverOptions = {}): Promise<MediaResponse> {
    const page = Math.max(1, options.page || 1)
    const rawType = (options.type || "").toLowerCase().trim()
    const isCartoon = rawType === "cartoon"
    const isTv = rawType === "tv" || rawType === "tv_series"

    const endpoint = isTv ? "/discover/tv" : "/discover/movie"
    const params: Record<string, string> = {
      page: String(page),
      include_adult: "false",
    }

    // Genres
    let genreIds = resolveGenreIds(options.genres || "", isTv)
    if (isCartoon) {
      genreIds = genreIds ? `${genreIds},16` : "16"
    }
    if (genreIds) {
      params.with_genres = genreIds
    }

    // Origin Country
    if (options.countries) {
      const countryCode = resolveCountryCode(options.countries)
      if (countryCode) {
        params.with_origin_country = countryCode
      }
    }

    // Sorting Order
    const order = (options.order || "").trim()
    if (order === "RATING" || order === "vote_average.desc") {
      params.sort_by = "vote_average.desc"
      params["vote_count.gte"] = "50"
    } else if (order === "YEAR" || order === "release_date.desc") {
      params.sort_by = isTv ? "first_air_date.desc" : "primary_release_date.desc"
    } else if (order === "NUM_VOTE" || order === "vote_count.desc") {
      params.sort_by = "vote_count.desc"
    } else {
      params.sort_by = "popularity.desc"
      params["vote_count.gte"] = "10"
    }

    // Years
    if (options.year) {
      if (isTv) {
        params.first_air_date_year = String(options.year)
      } else {
        params.primary_release_year = String(options.year)
      }
    }
    if (options.yearFrom) {
      if (isTv) {
        params["first_air_date.gte"] = `${options.yearFrom}-01-01`
      } else {
        params["primary_release_date.gte"] = `${options.yearFrom}-01-01`
      }
    }
    if (options.yearTo) {
      if (isTv) {
        params["first_air_date.lte"] = `${options.yearTo}-12-31`
      } else {
        params["primary_release_date.lte"] = `${options.yearTo}-12-31`
      }
    }

    // Rating thresholds
    if (options.ratingFrom !== undefined && options.ratingFrom > 0) {
      params["vote_average.gte"] = String(options.ratingFrom)
    }
    if (options.ratingTo !== undefined && options.ratingTo < 10) {
      params["vote_average.lte"] = String(options.ratingTo)
    }

    const data = await tmdbFetch<any>(endpoint, params)
    const results: MediaDto[] = (data.results || [])
      .map((item: any) => isTv ? mapRawTv(item) : mapRawMovie(item))
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

    const genreNames = (data.genres || []).map((g: any) => g.name || TMDB_GENRES[g.id] || "").filter(Boolean)

    return {
      ...base,
      genres: (genreNames.length > 0 ? genreNames : (base.genres || []).map((g: any) => g.name).filter(Boolean)) as any,
      backdrop: base.backdrop || base.poster,
      duration: data.runtime || undefined,
      countries: (data.production_countries || []).map(localizeCountry).filter(Boolean),
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

    const tvGenreNames = (data.genres || []).map((g: any) => g.name || TMDB_GENRES[g.id] || "").filter(Boolean)

    return {
      ...base,
      genres: (tvGenreNames.length > 0 ? tvGenreNames : (base.genres || []).map((g: any) => g.name).filter(Boolean)) as any,
      backdrop: base.backdrop || base.poster,
      duration: data.episode_run_time?.[0] || undefined,
      countries: (data.origin_country || (data.production_countries ? data.production_countries.map((c: any) => c.iso_3166_1 || c.name) : [])).map(localizeCountry).filter(Boolean),
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
