import { Hono } from "hono"
import { tmdb } from "../services/tmdb"
import { resolveAlloha } from "../services/alloha"
import { listCache, detailsCache, getCached, setCached } from "../services/cache"
import type { MediaDetailsDto, MediaResponse } from "../types/models"

export const mediaRouter = new Hono()

// GET /api/v1/movie/:id
mediaRouter.get("/movie/:id", async (c) => {
  const rawId = c.req.param("id").replace(/^(tmdb_|kp_)/, "")
  const id = parseInt(rawId, 10)
  if (isNaN(id)) {
    return c.json({ status: "error", message: "Invalid movie ID" }, 400)
  }

  const cacheKey = `movie:${id}`
  const cached = getCached<MediaDetailsDto>(detailsCache, cacheKey)
  if (cached) {
    return c.json({ status: "success", data: cached })
  }

  try {
    const details = await tmdb.getMovieDetails(id)
    
    // In parallel, resolve Alloha streams
    const allohaInfo = await resolveAlloha(id)
    if (allohaInfo.kpId || allohaInfo.imdbId) {
      details.alloha = allohaInfo
      if (!details.externalIds) details.externalIds = {}
      if (allohaInfo.kpId) details.externalIds.kp = allohaInfo.kpId
      if (allohaInfo.imdbId) details.externalIds.imdb = allohaInfo.imdbId
    }

    setCached(detailsCache, cacheKey, details)
    return c.json({ status: "success", data: details })
  } catch (err: any) {
    return c.json({ status: "error", message: err.message || "Failed to fetch movie details" }, 500)
  }
})

// GET /api/v1/tv/:id
mediaRouter.get("/tv/:id", async (c) => {
  const rawId = c.req.param("id").replace(/^(tmdb_|kp_)/, "")
  const id = parseInt(rawId, 10)
  if (isNaN(id)) {
    return c.json({ status: "error", message: "Invalid TV ID" }, 400)
  }

  const cacheKey = `tv:${id}`
  const cached = getCached<MediaDetailsDto>(detailsCache, cacheKey)
  if (cached) {
    return c.json({ status: "success", data: cached })
  }

  try {
    const details = await tmdb.getTvDetails(id)
    const allohaInfo = await resolveAlloha(id)
    if (allohaInfo.kpId || allohaInfo.imdbId) {
      details.alloha = allohaInfo
      if (!details.externalIds) details.externalIds = {}
      if (allohaInfo.kpId) details.externalIds.kp = allohaInfo.kpId
      if (allohaInfo.imdbId) details.externalIds.imdb = allohaInfo.imdbId
    }

    setCached(detailsCache, cacheKey, details)
    return c.json({ status: "success", data: details })
  } catch (err: any) {
    return c.json({ status: "error", message: err.message || "Failed to fetch TV details" }, 500)
  }
})

// GET /api/v1/tv/:id/season/:season/episode/:episode
mediaRouter.get("/tv/:id/season/:season/episode/:episode", async (c) => {
  const rawId = c.req.param("id").replace(/^(tmdb_|kp_)/, "")
  const id = parseInt(rawId, 10)
  const season = parseInt(c.req.param("season"), 10)
  const episode = parseInt(c.req.param("episode"), 10)

  if (isNaN(id) || isNaN(season) || isNaN(episode)) {
    return c.json({ status: "error", message: "Invalid parameters" }, 400)
  }

  try {
    const epDetails = await tmdb.getEpisodeDetails(id, season, episode)
    return c.json({ status: "success", data: epDetails })
  } catch (err: any) {
    return c.json({ status: "error", message: err.message || "Episode details not found" }, 500)
  }
})

// GET /api/v1/search
mediaRouter.get("/search", async (c) => {
  const query = c.req.query("query") || c.req.query("q") || ""
  const page = parseInt(c.req.query("page") || "1", 10)

  if (!query.trim()) {
    return c.json({ status: "success", data: { results: [], items: [], page: 1, total_pages: 1, total_results: 0 } })
  }

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
})

// GET /api/v1/popular & /api/v1/movies/popular
const handlePopular = async (c: any) => {
  const type = (c.req.query("type") === "tv" ? "tv" : "movie") as "movie" | "tv"
  const page = parseInt(c.req.query("page") || "1", 10)

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
mediaRouter.get("/popular", handlePopular)
mediaRouter.get("/movies/popular", handlePopular)

// GET /api/v1/top & /api/v1/movies/top-rated & /api/v1/tv/top-rated
const handleTopRated = (defaultType: "movie" | "tv") => async (c: any) => {
  const queryType = c.req.query("type")
  const type = (queryType === "tv" || queryType === "movie") ? queryType : defaultType
  const page = parseInt(c.req.query("page") || "1", 10)

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
  const page = parseInt(c.req.query("page") || "1", 10)
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
  const page = parseInt(c.req.query("page") || "1", 10)

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
