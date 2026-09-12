import { config } from "../config"
import { localizeCountry, resolveCountryCode, localizePlaceOfBirth } from "../utils/countries"
import type {
  MediaDto,
  MediaDetailsDto,
  MediaResponse,
  CastMemberDto,
  CrewMemberDto,
  TrailerVideoDto,
  MovieCollectionDto,
  CollectionPartDto,
  PersonDetailsDto,
  TvSeasonDto,
  TvSeasonSummaryDto,
  TvSeasonEpisodeDto,
  TvNextEpisodeDto,
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

export class TmdbHttpError extends Error {
  status: number
  constructor(status: number, message: string) {
    super(message)
    this.name = "TmdbHttpError"
    this.status = status
  }
}

async function tmdbFetch<T>(endpoint: string, params: Record<string, string> = {}): Promise<T> {
  const url = buildUrl(endpoint, params)
  const res = await fetch(url, {
    headers: buildHeaders(),
    signal: AbortSignal.timeout(8000),
  })
  if (!res.ok) {
    throw new TmdbHttpError(res.status, `TMDB error ${res.status}: ${res.statusText} at ${endpoint}`)
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
  10765: "НФ и фэнтези",
  10766: "мыльная опера",
  10767: "ток-шоу",
  10768: "война и политика",
}

export function parseMovieAgeRating(releaseDates: any): string | undefined {
  if (!releaseDates?.results || !Array.isArray(releaseDates.results)) return undefined
  const ru = releaseDates.results.find((r: any) => r.iso_3166_1 === "RU")
  const ruCert = ru?.release_dates?.find((d: any) => d.certification && d.certification.trim())?.certification?.trim()
  if (ruCert) {
    if (ruCert.includes("18")) return "18+"
    if (ruCert.includes("16")) return "16+"
    if (ruCert.includes("12")) return "12+"
    if (ruCert.includes("6")) return "6+"
    if (ruCert.includes("0")) return "0+"
    return ruCert
  }
  const us = releaseDates.results.find((r: any) => r.iso_3166_1 === "US")
  const usCert = us?.release_dates?.find((d: any) => d.certification && d.certification.trim())?.certification?.trim()
  if (usCert) {
    const c = usCert.toUpperCase()
    if (c === "NC-17" || c === "R") return "18+"
    if (c === "PG-13") return "16+"
    if (c === "PG") return "12+"
    if (c === "G") return "6+"
    return usCert
  }
  return undefined
}

export function parseTvAgeRating(contentRatings: any): string | undefined {
  if (!contentRatings?.results || !Array.isArray(contentRatings.results)) return undefined
  const ru = contentRatings.results.find((r: any) => r.iso_3166_1 === "RU")
  const rating = ru?.rating?.trim()
  if (rating) {
    if (rating.includes("18")) return "18+"
    if (rating.includes("16")) return "16+"
    if (rating.includes("12")) return "12+"
    if (rating.includes("6")) return "6+"
    if (rating.includes("0")) return "0+"
    return rating
  }
  const us = contentRatings.results.find((r: any) => r.iso_3166_1 === "US")?.rating?.trim()
  if (us) {
    const r = us.toUpperCase()
    if (r === "TV-MA") return "18+"
    if (r === "TV-14") return "16+"
    if (r === "TV-PG") return "12+"
    if (r === "TV-G" || r === "TV-Y7") return "6+"
    if (r === "TV-Y") return "0+"
    return us
  }
  return undefined
}

export function resolveGenreIds(genres: string, isTv: boolean = false): string {
  if (!genres) return ""
  const tokens = genres.split(/[,|]/).map(t => t.trim().toLowerCase()).filter(Boolean)
  const result: string[] = []

  const movieMap: Record<string, string> = {
    "боевик": "28", "боевики": "28", "action": "28",
    "приключения": "12", "приключение": "12", "adventure": "12",
    "мультфильм": "16", "мультфильмы": "16", "анимация": "16", "animation": "16",
    "аниме": "16", "anime": "16",
    "комедия": "35", "комедии": "35", "comedy": "35",
    "криминал": "80", "криминальный": "80", "crime": "80",
    "документальный": "99", "документалка": "99", "documentary": "99",
    "драма": "18", "драмы": "18", "drama": "18",
    "семейный": "10751", "семейное": "10751", "семья": "10751", "family": "10751",
    "фэнтези": "14", "fantasy": "14",
    "история": "36", "исторический": "36", "history": "36",
    "ужасы": "27", "ужас": "27", "хоррор": "27", "horror": "27",
    "музыка": "10402", "мюзикл": "10402", "музыкальный": "10402", "music": "10402",
    "детектив": "9648", "детективы": "9648", "mystery": "9648",
    "мелодрама": "10749", "мелодрамы": "10749", "романтика": "10749", "romance": "10749",
    "фантастика": "878", "sci-fi": "878",
    "научная фантастика и фэнтези": "878|14", "нф и фэнтези": "878|14", "sci-fi & fantasy": "878|14",
    "телефильм": "10770",
    "триллер": "53", "триллеры": "53", "thriller": "53",
    "военный": "10752", "война": "10752", "war": "10752",
    "вестерн": "37", "вестерны": "37", "western": "37",
    "детский": "10751", "детские": "10751", "kids": "10751",
  }

  const tvMap: Record<string, string> = {
    ...movieMap,
    "боевик": "10759", "боевики": "10759", "приключения": "10759", "боевик и приключения": "10759", "action": "10759", "adventure": "10759",
    "детский": "10762", "kids": "10762",
    "новости": "10763", "news": "10763",
    "реалити-шоу": "10764", "reality": "10764",
    "научная фантастика и фэнтези": "10765", "фантастика": "10765", "фэнтези": "10765", "нф и фэнтези": "10765", "sci-fi": "10765", "fantasy": "10765", "sci-fi & fantasy": "10765",
    "мыльная опера": "10766", "soap": "10766",
    "ток-шоу": "10767", "talk": "10767",
    "война и политика": "10768", "военный": "10768", "война": "10768", "war": "10768",
  }

  const activeMap = isTv ? tvMap : movieMap

  for (const token of tokens) {
    if (/^\d+$/.test(token)) {
      if (!isTv && token === "10765") {
        result.push("878|14")
      } else if (isTv && (token === "878" || token === "14")) {
        result.push("10765")
      } else {
        result.push(token)
      }
    } else if (activeMap[token]) {
      result.push(activeMap[token])
    } else {
      const entry = Object.entries(activeMap).find(([k]) => token.includes(k) || k.includes(token))
      if (entry) {
        result.push(entry[1])
      }
    }
  }

  return [...new Set(result)].join(",")
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

  const hasAnimation = genres.some((g: any) => g.id === "16" || g.name === "мультфильм")
  const isJapanese = (m.original_language === "ja") || (rawCountries.some((c: any) => c.iso_3166_1 === "JP" || c.name === "Japan"))
  if (hasAnimation && isJapanese && !genres.some((g: any) => g.id === "anime" || g.name === "аниме")) {
    genres.push({ id: "anime", name: "аниме" })
  }

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

  const hasAnimation = genres.some((g: any) => g.id === "16" || g.name === "мультфильм")
  const isJapanese = (t.original_language === "ja") || (rawCountries.some((c: any) => c.iso_3166_1 === "JP" || c.name === "Japan"))
  if (hasAnimation && isJapanese && !genres.some((g: any) => g.id === "anime" || g.name === "аниме")) {
    genres.push({ id: "anime", name: "аниме" })
  }

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

export function extractCrew(data: any, isTv: boolean = false): {
  directors: CrewMemberDto[]
  writers: CrewMemberDto[]
  crew: CrewMemberDto[]
} {
  const crewList: any[] = data.credits?.crew || []
  const createdByList: any[] = data.created_by || []

  const directorsMap = new Map<number, CrewMemberDto>()
  const writersMap = new Map<number, CrewMemberDto>()
  const creatorsMap = new Map<number, CrewMemberDto>()

  // 1. TV created_by
  for (const c of createdByList) {
    if (!c.id || !c.name) continue
    const creatorDto: CrewMemberDto = {
      id: c.id,
      name: c.name || c.original_name,
      originalName: c.original_name || c.name,
      role: "Создатель",
      photo: formatImageUrl(c.profile_path, "w500") || null,
    }
    creatorsMap.set(c.id, creatorDto)
    if (isTv && !directorsMap.has(c.id)) {
      directorsMap.set(c.id, creatorDto)
    }
  }

  // 2. Directors from crew
  for (const c of crewList) {
    if (!c.id || !c.name) continue
    if (c.job === "Director") {
      if (!directorsMap.has(c.id)) {
        directorsMap.set(c.id, {
          id: c.id,
          name: c.name || c.original_name,
          originalName: c.original_name || c.name,
          role: "Режиссёр",
          photo: formatImageUrl(c.profile_path, "w500") || null,
        })
      }
    }
  }

  // 3. Writers from crew
  const writerJobs = new Set([
    "Screenplay", "Writer", "Story", "Author", "Co-Writer", "Comic Book", 
    "Novel", "Characters", "Head Writer", "Scenario"
  ])
  for (const c of crewList) {
    if (!c.id || !c.name) continue
    if (c.department === "Writing" || writerJobs.has(c.job)) {
      if (!writersMap.has(c.id)) {
        let role = "Сценарист"
        if (c.job === "Novel" || c.job === "Author") role = "Автор книги"
        else if (c.job === "Characters") role = "Персонажи"
        else if (c.job === "Story") role = "Автор сюжета"
        writersMap.set(c.id, {
          id: c.id,
          name: c.name || c.original_name,
          originalName: c.original_name || c.name,
          role,
          photo: formatImageUrl(c.profile_path, "w500") || null,
        })
      }
    }
  }

  // 4. Combined unified crew (deduplicated by id, combining roles)
  const unifiedMap = new Map<number, CrewMemberDto>()

  // Start with creators (for TV)
  for (const [id, m] of creatorsMap) {
    unifiedMap.set(id, { ...m })
  }

  // Merge directors
  for (const [id, m] of directorsMap) {
    if (unifiedMap.has(id)) {
      const existing = unifiedMap.get(id)!
      existing.role = `${existing.role}, режиссёр`
    } else {
      unifiedMap.set(id, { ...m })
    }
  }

  // Merge writers
  for (const [id, m] of writersMap) {
    if (unifiedMap.has(id)) {
      const existing = unifiedMap.get(id)!
      if (!existing.role.includes("сценарист") && !existing.role.includes("Сценарист")) {
        existing.role = `${existing.role}, сценарист`
      }
    } else {
      unifiedMap.set(id, { ...m })
    }
  }

  return {
    directors: Array.from(directorsMap.values()).slice(0, 10),
    writers: Array.from(writersMap.values()).slice(0, 10),
    crew: Array.from(unifiedMap.values()).slice(0, 15),
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

  async getAnime(page = 1, order: "popular" | "top" = "popular"): Promise<MediaResponse> {
    const isTop = order === "top"
    const tvParams: Record<string, string> = {
      page: String(page),
      with_genres: "16",
      with_original_language: "ja",
      include_adult: "false",
      sort_by: isTop ? "vote_average.desc" : "popularity.desc",
      "vote_count.gte": isTop ? "80" : "25",
    }
    const movieParams: Record<string, string> = {
      page: String(page),
      with_genres: "16",
      with_original_language: "ja",
      include_adult: "false",
      sort_by: isTop ? "vote_average.desc" : "popularity.desc",
      "vote_count.gte": isTop ? "80" : "25",
    }
    const [tvData, movieData] = await Promise.all([
      tmdbFetch<any>("/discover/tv", tvParams),
      tmdbFetch<any>("/discover/movie", movieParams),
    ])
    const tvResults = (tvData.results || []).map(mapRawTv)
    const movieResults = (movieData.results || []).map(mapRawMovie)

    // Interleave tv and movies: 2 TV, 1 Movie
    const results: MediaDto[] = []
    let t = 0, m = 0
    while (t < tvResults.length || m < movieResults.length) {
      if (t < tvResults.length) results.push(tvResults[t++])
      if (t < tvResults.length) results.push(tvResults[t++])
      if (m < movieResults.length) results.push(movieResults[m++])
    }
    const valid = results.filter((item: MediaDto) => item.poster && item.title.trim().length > 0)
    return {
      results: valid,
      items: valid,
      page,
      total_pages: Math.max(tvData.total_pages || 1, movieData.total_pages || 1),
      pages: Math.max(tvData.total_pages || 1, movieData.total_pages || 1),
      total_results: (tvData.total_results || 0) + (movieData.total_results || 0),
      total: (tvData.total_results || 0) + (movieData.total_results || 0),
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

    const rawItems: any[] = []
    const seenKeys = new Set<string>()

    for (const item of (data.results || [])) {
      if (item.media_type === "movie" || item.media_type === "tv") {
        const key = `${item.media_type}_${item.id}`
        if (!seenKeys.has(key)) {
          seenKeys.add(key)
          rawItems.push(item)
        }
      } else if (item.media_type === "person" && Array.isArray(item.known_for)) {
        for (const kf of item.known_for) {
          if (kf.media_type === "movie" || kf.media_type === "tv") {
            const key = `${kf.media_type}_${kf.id}`
            if (!seenKeys.has(key)) {
              seenKeys.add(key)
              rawItems.push(kf)
            }
          }
        }
      }
    }

    const results: MediaDto[] = rawItems
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
    const page = Math.min(Math.max(1, options.page || 1), 500)
    const rawType = (options.type || "").toLowerCase().trim()
    const isCartoon = rawType === "cartoon"
    const isTv = rawType === "tv" || rawType === "tv_series"
    const isAnime = rawType === "anime" || (options.genres || "").toLowerCase().includes("аниме") || (options.genres || "").toLowerCase().includes("anime")

    const endpoint = isTv ? "/discover/tv" : "/discover/movie"
    const params: Record<string, string> = {
      page: String(page),
      include_adult: "false",
    }

    // Genres
    let genreIds = resolveGenreIds(options.genres || "", isTv)
    if (isCartoon || isAnime) {
      genreIds = genreIds ? `${genreIds},16` : "16"
    }
    if (genreIds) {
      params.with_genres = genreIds
    }

    if (isAnime) {
      params.with_original_language = "ja"
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
    const todayISO = new Date().toISOString().split("T")[0]

    if (order === "RATING" || order === "vote_average.desc") {
      params.sort_by = "vote_average.desc"
      params["vote_count.gte"] = isAnime ? "30" : "50"
    } else if (order === "YEAR" || order === "release_date.desc") {
      params.sort_by = isTv ? "first_air_date.desc" : "primary_release_date.desc"
      if (!options.yearTo && !options.year) {
        if (isTv) {
          params["first_air_date.lte"] = todayISO
        } else {
          params["primary_release_date.lte"] = todayISO
        }
      }
      if (!params["vote_count.gte"]) {
        params["vote_count.gte"] = "5"
      }
    } else if (order === "NUM_VOTE" || order === "vote_count.desc") {
      params.sort_by = "vote_count.desc"
    } else {
      params.sort_by = "popularity.desc"
      params["vote_count.gte"] = isAnime ? "15" : "10"
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

    if (isAnime && (!rawType || rawType === "anime" || rawType === "all")) {
      const [tvData, movieData] = await Promise.all([
        tmdbFetch<any>("/discover/tv", params),
        tmdbFetch<any>("/discover/movie", params),
      ])
      const tvResults = (tvData.results || []).map(mapRawTv)
      const movieResults = (movieData.results || []).map(mapRawMovie)
      const interleaved: MediaDto[] = []
      let t = 0, m = 0
      while (t < tvResults.length || m < movieResults.length) {
        if (t < tvResults.length) interleaved.push(tvResults[t++])
        if (t < tvResults.length) interleaved.push(tvResults[t++])
        if (m < movieResults.length) interleaved.push(movieResults[m++])
      }
      const valid = interleaved.filter((item: MediaDto) => item.poster && item.title.trim().length > 0)
      return {
        results: valid,
        items: valid,
        page,
        total_pages: Math.max(tvData.total_pages || 1, movieData.total_pages || 1),
        pages: Math.max(tvData.total_pages || 1, movieData.total_pages || 1),
        total_results: (tvData.total_results || 0) + (movieData.total_results || 0),
        total: (tvData.total_results || 0) + (movieData.total_results || 0),
      }
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
      append_to_response: "credits,videos,images,recommendations,similar,external_ids,release_dates",
      include_image_language: "ru,en,null",
      include_video_language: "ru,en,null",
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

    // Directors, Writers, Crew
    const { directors, writers, crew } = extractCrew(data, false)

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
    const isAnimMovie = (data.genres || []).some((g: any) => g.id === 16 || g.name === "мультфильм")
    const isJapMovie = (data.original_language === "ja") || (data.production_countries || []).some((c: any) => c.iso_3166_1 === "JP")
    if (isAnimMovie && isJapMovie && !genreNames.includes("аниме")) {
      genreNames.push("аниме")
    }

    // Financials & Rating
    const budget = typeof data.budget === "number" && data.budget > 0 ? data.budget : undefined
    const revenue = typeof data.revenue === "number" && data.revenue > 0 ? data.revenue : undefined
    const status = data.status || undefined
    const ageRating = parseMovieAgeRating(data.release_dates)

    // Similar / Recommended Media
    const rawSimilar = [
      ...(data.recommendations?.results || []),
      ...(data.similar?.results || []),
    ]
    const seenSimilarIds = new Set<string>()
    const similar: MediaDto[] = []

    for (const item of rawSimilar) {
      const idStr = String(item.id)
      if (idStr !== String(id) && !seenSimilarIds.has(idStr) && item.poster_path && (item.title || item.original_title)) {
        seenSimilarIds.add(idStr)
        similar.push(mapRawMovie(item))
        if (similar.length >= 15) break
      }
    }

    // Smart Fallback: if TMDB recommendations/similar yielded fewer than 6 items, fill with discover by primary genre
    if (similar.length < 6 && data.genres && data.genres.length > 0) {
      try {
        const genreId = data.genres[0].id
        const disc = await tmdbFetch<any>("/discover/movie", {
          with_genres: String(genreId),
          sort_by: "popularity.desc",
          "vote_count.gte": "50",
          page: "1",
        })
        for (const item of (disc.results || [])) {
          const idStr = String(item.id)
          if (idStr !== String(id) && !seenSimilarIds.has(idStr) && item.poster_path && (item.title || item.original_title)) {
            seenSimilarIds.add(idStr)
            similar.push(mapRawMovie(item))
            if (similar.length >= 15) break
          }
        }
      } catch {
        // Ignore fallback error
      }
    }

    // Backdrops: prioritize clean textless backdrops (iso_639_1 is null/empty)
    const rawBackdrops = (data.images?.backdrops || []) as any[]
    const backdrops: string[] = []
    const seenBackdrops = new Set<string>()

    const primaryBackdrop = base.backdrop || (base.backdrop_path ? formatImageUrl(base.backdrop_path, "original") : undefined)
    if (primaryBackdrop) {
      backdrops.push(primaryBackdrop)
      seenBackdrops.add(primaryBackdrop)
      if (base.backdrop_path) seenBackdrops.add(base.backdrop_path)
    }

    const validRaw = rawBackdrops.filter((b: any) => b.file_path && (!b.aspect_ratio || b.aspect_ratio >= 1.2))
    const textless = validRaw.filter((b: any) => !b.iso_639_1)
    const withText = validRaw.filter((b: any) => Boolean(b.iso_639_1))

    textless.sort((a: any, b: any) => ((b.vote_count || 0) * (b.vote_average || 0)) - ((a.vote_count || 0) * (a.vote_average || 0)))
    withText.sort((a: any, b: any) => ((b.vote_count || 0) * (b.vote_average || 0)) - ((a.vote_count || 0) * (a.vote_average || 0)))

    const candidateList = textless.length >= 3 ? textless : [...textless, ...withText]

    for (const b of candidateList) {
      if (seenBackdrops.has(b.file_path)) continue
      const formatted = formatImageUrl(b.file_path, "original")
      if (formatted && !seenBackdrops.has(formatted)) {
        seenBackdrops.add(b.file_path)
        seenBackdrops.add(formatted)
        backdrops.push(formatted)
        if (backdrops.length >= 8) break
      }
    }

    return {
      ...base,
      genres: (genreNames.length > 0 ? genreNames : (base.genres || []).map((g: any) => g.name).filter(Boolean)) as any,
      backdrop: base.backdrop || base.poster,
      backdrops: backdrops.length > 0 ? backdrops : undefined,
      duration: data.runtime || undefined,
      countries: (data.production_countries || []).map(localizeCountry).filter(Boolean),
      logo: logoUrl,
      cast,
      directors,
      writers,
      crew,
      trailers,
      collection,
      productionCompanies,
      budget,
      revenue,
      ageRating,
      status,
      similar,
      externalIds: {
        tmdb: data.id,
        imdb: data.external_ids?.imdb_id || data.imdb_id,
      },
    }
  }

  async getTvDetails(id: number): Promise<MediaDetailsDto> {
    const data = await tmdbFetch<any>(`/tv/${id}`, {
      append_to_response: "credits,videos,images,recommendations,similar,external_ids,content_ratings",
      include_image_language: "ru,en,null",
      include_video_language: "ru,en,null",
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

    // Directors, Writers, Crew
    const { directors, writers, crew } = extractCrew(data, true)

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
    const isAnimTv = (data.genres || []).some((g: any) => g.id === 16 || g.name === "мультфильм")
    const isJapTv = (data.original_language === "ja") || (data.origin_country || []).includes("JP") || (data.production_countries || []).some((c: any) => c.iso_3166_1 === "JP")
    if (isAnimTv && isJapTv && !tvGenreNames.includes("аниме")) {
      tvGenreNames.push("аниме")
    }

    const ageRating = parseTvAgeRating(data.content_ratings)
    const status = data.status || undefined

    let nextEpisodeToAir: TvNextEpisodeDto | null = null
    if (data.next_episode_to_air) {
      const n = data.next_episode_to_air
      nextEpisodeToAir = {
        id: n.id,
        name: n.name || `Серия ${n.episode_number}`,
        overview: n.overview || "",
        airDate: n.air_date || "",
        episodeNumber: n.episode_number,
        seasonNumber: n.season_number,
      }
    }

    const seasons: TvSeasonSummaryDto[] = (data.seasons || [])
      .filter((s: any) => (s.season_number ?? 0) > 0)
      .map((s: any) => ({
        id: s.id,
        seasonNumber: s.season_number,
        name: s.name || `${s.season_number} сезон`,
        episodeCount: s.episode_count || 0,
        airDate: s.air_date || null,
        poster: formatImageUrl(s.poster_path, "w500") || null,
      }))

    // Similar / Recommended TV Series
    const rawTvSimilar = [
      ...(data.recommendations?.results || []),
      ...(data.similar?.results || []),
    ]
    const seenTvSimilarIds = new Set<string>()
    const similarTv: MediaDto[] = []

    for (const item of rawTvSimilar) {
      const idStr = String(item.id)
      if (idStr !== String(id) && !seenTvSimilarIds.has(idStr) && item.poster_path && (item.name || item.original_name)) {
        seenTvSimilarIds.add(idStr)
        similarTv.push(mapRawTv(item))
        if (similarTv.length >= 15) break
      }
    }

    // Smart Fallback: if TMDB recommendations/similar yielded fewer than 6 items, fill with discover by primary genre
    if (similarTv.length < 6 && data.genres && data.genres.length > 0) {
      try {
        const genreId = data.genres[0].id
        const disc = await tmdbFetch<any>("/discover/tv", {
          with_genres: String(genreId),
          sort_by: "popularity.desc",
          "vote_count.gte": "20",
          page: "1",
        })
        for (const item of (disc.results || [])) {
          const idStr = String(item.id)
          if (idStr !== String(id) && !seenTvSimilarIds.has(idStr) && item.poster_path && (item.name || item.original_name)) {
            seenTvSimilarIds.add(idStr)
            similarTv.push(mapRawTv(item))
            if (similarTv.length >= 15) break
          }
        }
      } catch {
        // Ignore fallback error
      }
    }

    const duration = data.episode_run_time?.[0] || data.last_episode_to_air?.runtime || undefined

    // Backdrops: prioritize clean textless backdrops (iso_639_1 is null/empty)
    const rawTvBackdrops = (data.images?.backdrops || []) as any[]
    const tvBackdrops: string[] = []
    const seenTvBackdrops = new Set<string>()

    const primaryTvBackdrop = base.backdrop || (base.backdrop_path ? formatImageUrl(base.backdrop_path, "original") : undefined)
    if (primaryTvBackdrop) {
      tvBackdrops.push(primaryTvBackdrop)
      seenTvBackdrops.add(primaryTvBackdrop)
      if (base.backdrop_path) seenTvBackdrops.add(base.backdrop_path)
    }

    const validRawTv = rawTvBackdrops.filter((b: any) => b.file_path && (!b.aspect_ratio || b.aspect_ratio >= 1.2))
    const textlessTv = validRawTv.filter((b: any) => !b.iso_639_1)
    const withTextTv = validRawTv.filter((b: any) => Boolean(b.iso_639_1))

    textlessTv.sort((a: any, b: any) => ((b.vote_count || 0) * (b.vote_average || 0)) - ((a.vote_count || 0) * (a.vote_average || 0)))
    withTextTv.sort((a: any, b: any) => ((b.vote_count || 0) * (b.vote_average || 0)) - ((a.vote_count || 0) * (a.vote_average || 0)))

    const candidateTvList = textlessTv.length >= 3 ? textlessTv : [...textlessTv, ...withTextTv]

    for (const b of candidateTvList) {
      if (seenTvBackdrops.has(b.file_path)) continue
      const formatted = formatImageUrl(b.file_path, "original")
      if (formatted && !seenTvBackdrops.has(formatted)) {
        seenTvBackdrops.add(b.file_path)
        seenTvBackdrops.add(formatted)
        tvBackdrops.push(formatted)
        if (tvBackdrops.length >= 8) break
      }
    }

    return {
      ...base,
      genres: (tvGenreNames.length > 0 ? tvGenreNames : (base.genres || []).map((g: any) => g.name).filter(Boolean)) as any,
      backdrop: base.backdrop || base.poster,
      backdrops: tvBackdrops.length > 0 ? tvBackdrops : undefined,
      duration,
      countries: (data.origin_country || (data.production_countries ? data.production_countries.map((c: any) => c.iso_3166_1 || c.name) : [])).map(localizeCountry).filter(Boolean),
      logo: logoUrl,
      cast,
      directors,
      writers,
      crew,
      trailers,
      networks,
      ageRating,
      status,
      nextEpisodeToAir,
      seasons,
      similar: similarTv,
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

  async getSeasonDetails(tvId: number, seasonNumber: number): Promise<TvSeasonDto> {
    const data = await tmdbFetch<any>(`/tv/${tvId}/season/${seasonNumber}`, {
      language: "ru-RU",
    })

    const episodes: TvSeasonEpisodeDto[] = (data.episodes || []).map((ep: any) => ({
      id: ep.id,
      name: ep.name || `Серия ${ep.episode_number}`,
      overview: ep.overview || "",
      airDate: ep.air_date || "",
      episodeNumber: ep.episode_number,
      seasonNumber: ep.season_number ?? seasonNumber,
      stillPath: formatImageUrl(ep.still_path, "w500") || null,
      voteAverage: ep.vote_average ? Math.round(ep.vote_average * 10) / 10 : 0,
      duration: ep.runtime || undefined,
    }))

    return {
      id: data.id,
      name: data.name || `${seasonNumber} сезон`,
      overview: data.overview || "",
      seasonNumber: data.season_number ?? seasonNumber,
      poster: formatImageUrl(data.poster_path, "w500") || null,
      airDate: data.air_date || null,
      episodes,
    }
  }

  async getPersonDetails(id: number): Promise<PersonDetailsDto> {
    const data = await tmdbFetch<any>(`/person/${id}`, {
      append_to_response: "combined_credits,images,external_ids",
    })

    const photo = formatImageUrl(data.profile_path, "w500")
    const photos = (data.images?.profiles || [])
      .slice(0, 20)
      .map((img: any) => formatImageUrl(img.file_path, "original"))
      .filter(Boolean) as string[]

    const rawCredits: any[] = [
      ...(data.combined_credits?.cast || []),
      ...(data.combined_credits?.crew || []),
    ]
    const seenIds = new Set<string>()
    const filmography: MediaDto[] = []

    const sorted = rawCredits
      .filter((c: any) => c.poster_path && (c.title || c.name))
      .sort((a: any, b: any) => (b.popularity || 0) - (a.popularity || 0))

    for (const c of sorted) {
      const type = c.media_type === "tv" ? "tv" : "movie"
      const key = `${type}_${c.id}`
      if (!seenIds.has(key)) {
        seenIds.add(key)
        filmography.push(type === "tv" ? mapRawTv(c) : mapRawMovie(c))
      }
      if (filmography.length >= 60) break
    }

    const placeOfBirth = data.place_of_birth ? localizePlaceOfBirth(data.place_of_birth) : undefined
    let department = data.known_for_department || "Acting"
    if (department === "Acting") {
      department = data.gender === 1 ? "Актриса" : "Актёр"
    } else if (department === "Directing") {
      department = "Режиссёр"
    } else if (department === "Writing") {
      department = "Сценарист"
    } else if (department === "Production") {
      department = "Продюсер"
    }

    // Clean and split biography into sections (awards, key projects, interesting facts)
    let rawBio = (data.biography || "").replace(/\p{Extended_Pictographic}/gu, "").replace(/\uFE0F/g, "").trim()
    let awards: string | undefined = undefined
    let keyProjects: string | undefined = undefined
    let interestingFact: string | undefined = undefined

    const awardsMatch = rawBio.match(/(?:^|\n)\s*Главные награды\s*:\s*([\s\S]*?)(?=(?:\n\s*(?:Главные проекты|Интересн))|$)/i)
    if (awardsMatch) {
      awards = awardsMatch[1].trim()
      rawBio = rawBio.replace(awardsMatch[0], "")
    }

    const projectsMatch = rawBio.match(/(?:^|\n)\s*Главные проекты\s*:\s*([\s\S]*?)(?=(?:\n\s*(?:Главные награды|Интересн))|$)/i)
    if (projectsMatch) {
      keyProjects = projectsMatch[1].trim()
      rawBio = rawBio.replace(projectsMatch[0], "")
    }

    const factsMatch = rawBio.match(/(?:^|\n)\s*Интересны[ей]\s+факты?\s*:\s*([\s\S]*?)(?=(?:\n\s*(?:Главные награды|Главные проекты))|$)/i)
    if (factsMatch) {
      interestingFact = factsMatch[1].trim()
      rawBio = rawBio.replace(factsMatch[0], "")
    }

    const biography = rawBio.replace(/\n\s*\n+/g, "\n\n").trim()

    return {
      id: data.id,
      name: data.name,
      originalName: data.also_known_as?.[0] || data.name,
      biography,
      birthday: data.birthday || undefined,
      deathday: data.deathday || undefined,
      placeOfBirth,
      photo: photo || null,
      knownForDepartment: data.known_for_department,
      department: department,
      gender: data.gender,
      filmography,
      photos,
      awards,
      keyProjects,
      interestingFact,
    }
  }
}

export const tmdb = new TMDBService()
