import { Hono } from "hono"
import { tmdb } from "../services/tmdb"
import { resolveAlloha, resolveTmdbInfoByKp } from "../services/alloha"
import { listCache, detailsCache, getCached, setCached } from "../services/cache"
import type { MediaDetailsDto, MediaResponse } from "../types/models"

export const mediaRouter = new Hono()

function parsePage(c: any): number {
  return Math.min(Math.max(1, parseInt(c.req.query("page") || "1", 10) || 1), 500)
}

function handleRouteError(c: any, err: any, defaultMessage: string) {
  const isNotFound = err?.status === 404 || err?.message?.includes("404") || err?.message?.toLowerCase().includes("not found")
  if (isNotFound) {
    return c.json({ status: "error", message: "Медиа или ресурс не найден" }, 404)
  }
  return c.json({ status: "error", message: err?.message || defaultMessage }, 500)
}

// GET /api/v1/search & /api/v1/discover
const handleSearchOrDiscover = async (c: any) => {
  const query = c.req.query("query") || c.req.query("q") || ""
  const page = parsePage(c)
  const genres = c.req.query("genres")
  const countries = c.req.query("countries")
  const type = c.req.query("type")
  const order = c.req.query("order")
  const ratingFrom = c.req.query("ratingFrom") ? parseFloat(c.req.query("ratingFrom")) : undefined
  const ratingTo = c.req.query("ratingTo") ? parseFloat(c.req.query("ratingTo")) : undefined
  const yearFrom = c.req.query("yearFrom") ? parseInt(c.req.query("yearFrom"), 10) : undefined
  const yearTo = c.req.query("yearTo") ? parseInt(c.req.query("yearTo"), 10) : undefined

  // 1. Text search if query is provided
  if (query.trim()) {
    const cacheKey = `search:${query.toLowerCase().trim()}:${page}`
    const cached = getCached<MediaResponse>(listCache, cacheKey)
    if (cached) {
      return c.json({ status: "success", data: cached })
    }

    try {
      const results = await tmdb.search(query, page)
      setCached(listCache, cacheKey, results)
      return c.json({ status: "success", data: results })
    } catch (err: any) {
      return c.json({ status: "error", message: err.message || "Search failed" }, 500)
    }
  }

  // 2. Discover if filters are provided (e.g. genre chips, country, type, order)
  if (genres || countries || type || order || ratingFrom || yearFrom) {
    const cacheKey = `discover:${type || "all"}:${genres || ""}:${countries || ""}:${order || ""}:${ratingFrom ?? ""}:${yearFrom ?? ""}:${page}`
    const cached = getCached<MediaResponse>(listCache, cacheKey)
    if (cached) {
      return c.json({ status: "success", data: cached })
    }

    try {
      const results = await tmdb.discover({
        genres,
        countries,
        type,
        order,
        ratingFrom,
        ratingTo,
        yearFrom,
        yearTo,
        page,
      })
      setCached(listCache, cacheKey, results)
      return c.json({ status: "success", data: results })
    } catch (err: any) {
      return c.json({ status: "error", message: err.message || "Discover failed" }, 500)
    }
  }

  return c.json({ status: "success", data: { results: [], items: [], page: 1, total_pages: 1, total_results: 0 } })
}

mediaRouter.get("/search", handleSearchOrDiscover)
mediaRouter.get("/discover", handleSearchOrDiscover)

// GET /api/v1/popular, /api/v1/movies/popular, /api/v1/tv/popular
const handlePopular = (defaultType: "movie" | "tv" = "movie") => async (c: any) => {
  const queryType = c.req.query("type")
  const type = (queryType === "tv" || queryType === "movie") ? queryType : defaultType
  const page = parsePage(c)

  const cacheKey = `popular:${type}:${page}`
  const cached = getCached<MediaResponse>(listCache, cacheKey)
  if (cached) {
    return c.json({ status: "success", data: cached })
  }

  try {
    const results = await tmdb.getPopular(type, page)
    setCached(listCache, cacheKey, results)
    return c.json({ status: "success", data: results })
  } catch (err: any) {
    return c.json({ status: "error", message: err.message }, 500)
  }
}
mediaRouter.get("/popular", handlePopular("movie"))
mediaRouter.get("/movies/popular", handlePopular("movie"))
mediaRouter.get("/tv/popular", handlePopular("tv"))

// GET /api/v1/top & /api/v1/movies/top-rated & /api/v1/tv/top-rated
const handleTopRated = (defaultType: "movie" | "tv") => async (c: any) => {
  const queryType = c.req.query("type")
  const type = (queryType === "tv" || queryType === "movie") ? queryType : defaultType
  const page = parsePage(c)

  const cacheKey = `top:${type}:${page}`
  const cached = getCached<MediaResponse>(listCache, cacheKey)
  if (cached) {
    return c.json({ status: "success", data: cached })
  }

  try {
    const results = await tmdb.getTopRated(type, page)
    setCached(listCache, cacheKey, results)
    return c.json({ status: "success", data: results })
  } catch (err: any) {
    return c.json({ status: "error", message: err.message }, 500)
  }
}
mediaRouter.get("/top", handleTopRated("movie"))
mediaRouter.get("/movies/top-rated", handleTopRated("movie"))
mediaRouter.get("/tv/top-rated", handleTopRated("tv"))

// GET /api/v1/trending
mediaRouter.get("/trending", async (c) => {
  const page = parsePage(c)
  const window = (c.req.query("window") === "day" ? "day" : "week") as "day" | "week"

  const cacheKey = `trending:${window}:${page}`
  const cached = getCached<MediaResponse>(listCache, cacheKey)
  if (cached) {
    return c.json({ status: "success", data: cached })
  }

  try {
    const results = await tmdb.getTrending("all", window, page)
    setCached(listCache, cacheKey, results)
    return c.json({ status: "success", data: results })
  } catch (err: any) {
    return c.json({ status: "error", message: err.message }, 500)
  }
})

// GET /api/v1/cartoons
mediaRouter.get("/cartoons", async (c) => {
  const page = parsePage(c)

  const cacheKey = `cartoons:${page}`
  const cached = getCached<MediaResponse>(listCache, cacheKey)
  if (cached) {
    return c.json({ status: "success", data: cached })
  }

  try {
    const results = await tmdb.getCartoons(page)
    setCached(listCache, cacheKey, results)
    return c.json({ status: "success", data: results })
  } catch (err: any) {
    return c.json({ status: "error", message: err.message }, 500)
  }
})

// GET /api/v1/anime
mediaRouter.get("/anime", async (c) => {
  const page = parsePage(c)
  const order = (c.req.query("order") === "top" ? "top" : "popular") as "popular" | "top"

  const cacheKey = `anime:${order}:${page}`
  const cached = getCached<MediaResponse>(listCache, cacheKey)
  if (cached) {
    return c.json({ status: "success", data: cached })
  }

  try {
    const results = await tmdb.getAnime(page, order)
    setCached(listCache, cacheKey, results)
    return c.json({ status: "success", data: results })
  } catch (err: any) {
    return c.json({ status: "error", message: err.message }, 500)
  }
})

// GET /api/v1/tv/:id/season/:season
mediaRouter.get("/tv/:id/season/:season", async (c) => {
  const origId = c.req.param("id")
  const isKp = origId.startsWith("kp_")
  const rawId = origId.replace(/^(tmdb_|kp_|tv_|movie_)/, "")
  let id = parseInt(rawId, 10)
  const season = parseInt(c.req.param("season"), 10)

  if (isNaN(id) || isNaN(season)) {
    return c.json({ status: "error", message: "Invalid parameters" }, 400)
  }

  let tmdbId = id
  if (isKp) {
    try {
      const info = await resolveTmdbInfoByKp(id)
      if (info?.tmdbId) tmdbId = info.tmdbId
    } catch {
      // Continue with id as fallback
    }
  }

  const cacheKey = `tv_season:v3:${tmdbId}:${season}`
  const cached = getCached<any>(detailsCache, cacheKey)
  if (cached) {
    c.header("Cache-Control", "public, s-maxage=86400, stale-while-revalidate=43200")
    return c.json({ status: "success", data: cached })
  }

  try {
    let seasonDetails: any
    try {
      seasonDetails = await tmdb.getSeasonDetails(tmdbId, season)
    } catch (firstErr) {
      if (!isKp) {
        const kpInfo = await resolveTmdbInfoByKp(id)
        if (kpInfo?.tmdbId && kpInfo.tmdbId !== id) {
          tmdbId = kpInfo.tmdbId
          seasonDetails = await tmdb.getSeasonDetails(tmdbId, season)
        } else {
          throw firstErr
        }
      } else {
        throw firstErr
      }
    }
    setCached(detailsCache, cacheKey, seasonDetails)
    c.header("Cache-Control", "public, s-maxage=86400, stale-while-revalidate=43200")
    return c.json({ status: "success", data: seasonDetails })
  } catch (err: any) {
    return handleRouteError(c, err, "Season details not found")
  }
})

// GET /api/v1/tv/:id/season/:season/episode/:episode
mediaRouter.get("/tv/:id/season/:season/episode/:episode", async (c) => {
  const origId = c.req.param("id")
  const isKp = origId.startsWith("kp_")
  const rawId = origId.replace(/^(tmdb_|kp_|tv_|movie_)/, "")
  let id = parseInt(rawId, 10)
  const season = parseInt(c.req.param("season"), 10)
  const episode = parseInt(c.req.param("episode"), 10)

  if (isNaN(id) || isNaN(season) || isNaN(episode)) {
    return c.json({ status: "error", message: "Invalid parameters" }, 400)
  }

  let tmdbId = id
  if (isKp) {
    try {
      const info = await resolveTmdbInfoByKp(id)
      if (info?.tmdbId) tmdbId = info.tmdbId
    } catch {
      // Continue
    }
  }

  // Handle episode 0 gracefully (pilot / prologue)
  if (episode === 0) {
    try {
      let tvDetails: any
      try {
        tvDetails = await tmdb.getTvDetails(tmdbId)
      } catch (firstErr) {
        if (!isKp) {
          const kpInfo = await resolveTmdbInfoByKp(id)
          if (kpInfo?.tmdbId && kpInfo.tmdbId !== id) {
            tmdbId = kpInfo.tmdbId
            tvDetails = await tmdb.getTvDetails(tmdbId)
          } else {
            throw firstErr
          }
        } else {
          throw firstErr
        }
      }

      const seasonData = await tmdb.getSeasonDetails(tmdbId, season).catch(() => null)
      c.header("Cache-Control", "public, s-maxage=86400, stale-while-revalidate=43200")
      return c.json({
        status: "success",
        data: {
          id: 0,
          name: "Пилотная серия",
          overview: tvDetails.description || "Пилотный выпуск сериала.",
          airDate: seasonData?.airDate || tvDetails.releaseDate || "",
          episodeNumber: 0,
          seasonNumber: season,
          stillPath: tvDetails.backdrop || tvDetails.poster || null,
          voteAverage: 0,
          duration: seasonData?.episodes?.[0]?.duration || undefined,
        }
      })
    } catch (err: any) {
      return handleRouteError(c, err, "Pilot episode not found")
    }
  }

  try {
    let epDetails: any
    try {
      epDetails = await tmdb.getEpisodeDetails(tmdbId, season, episode)
    } catch (firstErr) {
      if (!isKp) {
        const kpInfo = await resolveTmdbInfoByKp(id)
        if (kpInfo?.tmdbId && kpInfo.tmdbId !== id) {
          epDetails = await tmdb.getEpisodeDetails(kpInfo.tmdbId, season, episode)
        } else {
          throw firstErr
        }
      } else {
        throw firstErr
      }
    }
    return c.json({ status: "success", data: epDetails })
  } catch (err: any) {
    return handleRouteError(c, err, "Episode details not found")
  }
})

// Helper to attach Alloha streams & normalized IDs
async function attachAllohaAndIds(details: MediaDetailsDto, tmdbId: number) {
  const allohaInfo = await resolveAlloha(tmdbId)
  if (allohaInfo.kpId || allohaInfo.imdbId) {
    details.alloha = allohaInfo
    if (!details.externalIds) details.externalIds = {}
    if (allohaInfo.kpId) details.externalIds.kp = allohaInfo.kpId
    if (allohaInfo.imdbId) details.externalIds.imdb = allohaInfo.imdbId
  }
  details.ids = {
    tmdb: details.externalIds?.tmdb || tmdbId,
    imdb: details.externalIds?.imdb || undefined,
    kp: details.externalIds?.kp || undefined,
  }
}

async function handleTvDetails(id: number, isKp: boolean): Promise<MediaDetailsDto> {
  const cacheKey = `tv:v4:${isKp ? "kp_" : ""}${id}`
  const cached = getCached<MediaDetailsDto>(detailsCache, cacheKey)
  if (cached) return cached

  let tmdbId = id
  if (isKp) {
    const info = await resolveTmdbInfoByKp(id)
    if (info?.tmdbId) tmdbId = info.tmdbId
  }

  let details: MediaDetailsDto
  try {
    details = await tmdb.getTvDetails(tmdbId)
  } catch (lookupErr) {
    // If TV lookup failed, fallback to movie lookup
    try {
      details = await tmdb.getMovieDetails(tmdbId)
    } catch {
      if (!isKp) {
        const kpInfo = await resolveTmdbInfoByKp(id)
        if (kpInfo?.tmdbId && kpInfo.tmdbId !== id) {
          return kpInfo.isTv ? handleTvDetails(kpInfo.tmdbId, false) : handleMovieDetails(kpInfo.tmdbId, false)
        }
      }
      throw lookupErr
    }
  }

  await attachAllohaAndIds(details, tmdbId)
  setCached(detailsCache, cacheKey, details)
  return details
}

async function handleMovieDetails(id: number, isKp: boolean): Promise<MediaDetailsDto> {
  const cacheKey = `movie:v4:${isKp ? "kp_" : ""}${id}`
  const cached = getCached<MediaDetailsDto>(detailsCache, cacheKey)
  if (cached) return cached

  let tmdbId = id
  let isTv = false
  if (isKp) {
    const info = await resolveTmdbInfoByKp(id)
    if (info?.tmdbId) {
      tmdbId = info.tmdbId
      isTv = info.isTv
    }
  }

  // If Alloha specifically flagged this KP entry as a TV serial (category 2), resolve TV details!
  if (isTv) {
    return handleTvDetails(tmdbId, false)
  }

  let details: MediaDetailsDto
  try {
    details = await tmdb.getMovieDetails(tmdbId)
  } catch (lookupErr) {
    // If movie lookup failed (e.g. 404), fallback to TV lookup!
    try {
      details = await tmdb.getTvDetails(tmdbId)
    } catch {
      if (!isKp) {
        const kpInfo = await resolveTmdbInfoByKp(id)
        if (kpInfo?.tmdbId && kpInfo.tmdbId !== id) {
          return kpInfo.isTv ? handleTvDetails(kpInfo.tmdbId, false) : handleMovieDetails(kpInfo.tmdbId, false)
        }
      }
      throw lookupErr
    }
  }

  await attachAllohaAndIds(details, tmdbId)
  setCached(detailsCache, cacheKey, details)
  return details
}

// GET /api/v1/movie/:id & /api/v2/movie/:id
mediaRouter.get("/movie/:id", async (c) => {
  const origId = c.req.param("id")
  const isTvParam = c.req.query("type") === "tv" || origId.startsWith("tv_")
  const isKp = origId.startsWith("kp_")
  const rawId = origId.replace(/^(tmdb_|kp_|tv_|movie_)/, "")
  const id = parseInt(rawId, 10)
  if (isNaN(id)) {
    return c.json({ status: "error", message: "Invalid movie ID" }, 400)
  }

  try {
    const details = isTvParam ? await handleTvDetails(id, isKp) : await handleMovieDetails(id, isKp)
    return c.json({ status: "success", data: details })
  } catch (err: any) {
    return handleRouteError(c, err, "Failed to fetch movie details")
  }
})

// GET /api/v1/tv/:id & /api/v2/tv/:id
mediaRouter.get("/tv/:id", async (c) => {
  const origId = c.req.param("id")
  const isMovieParam = c.req.query("type") === "movie" || origId.startsWith("movie_")
  const isKp = origId.startsWith("kp_")
  const rawId = origId.replace(/^(tmdb_|kp_|tv_|movie_)/, "")
  const id = parseInt(rawId, 10)
  if (isNaN(id)) {
    return c.json({ status: "error", message: "Invalid TV ID" }, 400)
  }

  try {
    const details = isMovieParam ? await handleMovieDetails(id, isKp) : await handleTvDetails(id, isKp)
    return c.json({ status: "success", data: details })
  } catch (err: any) {
    return handleRouteError(c, err, "Failed to fetch TV details")
  }
})

// GET /api/v1/media/:id & /api/v2/media/:id
mediaRouter.get("/media/:id", async (c) => {
  const origId = c.req.param("id")
  const isTvParam = c.req.query("type") === "tv" || origId.startsWith("tv_")
  const isMovieParam = c.req.query("type") === "movie" || origId.startsWith("movie_")
  const isKp = origId.startsWith("kp_")
  const rawId = origId.replace(/^(tmdb_|kp_|tv_|movie_)/, "")
  const id = parseInt(rawId, 10)
  if (isNaN(id)) {
    return c.json({ status: "error", message: "Invalid media ID" }, 400)
  }

  try {
    let details: MediaDetailsDto
    if (isTvParam) {
      details = await handleTvDetails(id, isKp)
    } else if (isMovieParam) {
      details = await handleMovieDetails(id, isKp)
    } else {
      details = await handleMovieDetails(id, isKp)
    }
    return c.json({ status: "success", data: details })
  } catch (err: any) {
    return handleRouteError(c, err, "Failed to fetch media details")
  }
})

// GET /api/v1/person/:id & /api/v2/person/:id
mediaRouter.get("/person/:id", async (c) => {
  const rawId = c.req.param("id").replace(/\D/g, "")
  const id = parseInt(rawId, 10)
  if (isNaN(id) || id <= 0) {
    return c.json({ status: "error", message: "Invalid Person ID" }, 400)
  }

  const cacheKey = `person:${id}`
  const cached = getCached<any>(detailsCache, cacheKey)
  if (cached) {
    return c.json({ status: "success", data: cached })
  }

  try {
    const details = await tmdb.getPersonDetails(id)
    setCached(detailsCache, cacheKey, details)
    return c.json({ status: "success", data: details })
  } catch (err: any) {
    return handleRouteError(c, err, "Failed to fetch person details")
  }
})
