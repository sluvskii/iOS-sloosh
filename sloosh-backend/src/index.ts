import { Hono } from "hono"
import { cors } from "hono/cors"
import { logger } from "hono/logger"
import { config } from "./config"
import { mediaRouter } from "./routes/media"
import { categoriesRouter } from "./routes/categories"
import { tmdb } from "./services/tmdb"
import { resolveTmdbIdByKp } from "./services/alloha"
import { detailsCache, getCached } from "./services/cache"
import type { MediaDetailsDto } from "./types/models"

const app = new Hono()

// Middlewares
app.use("*", logger())
app.use("*", cors({
  origin: "*",
  allowMethods: ["GET", "POST", "OPTIONS"],
  allowHeaders: ["Content-Type", "Authorization", "X-API-KEY"],
}))

// Health Check
app.get("/", (c) => c.json({
  service: "sloosh-backend",
  status: "online",
  version: "1.0.0",
  endpoints: [
    "/api/v1/popular",
    "/api/v1/top",
    "/api/v1/trending",
    "/api/v1/cartoons",
    "/api/v1/search?query=...",
    "/api/v1/movie/:id",
    "/api/v1/tv/:id",
    "/api/v1/categories",
    "/api/v1/collection/:id",
    "/api/v1/media/:type/:id/related/studio",
    "/api/v1/media/movie/:id/collection",
  ]
}))

app.get("/health", (c) => c.json({ status: "ok" }))

// Edge CDN Caching Middleware for sub-50ms responses & rate-limit protection
app.use("/api/*", async (c, next) => {
  await next()
  if (c.req.method === "GET" && c.res.status === 200 && !c.res.headers.has("Cache-Control")) {
    const path = c.req.path
    if (path.includes("/movie/") || path.includes("/tv/") || path.includes("/person/") || path.includes("/collection/")) {
      c.header("Cache-Control", "public, max-age=300, s-maxage=86400, stale-while-revalidate=604800")
    } else if (path.includes("/search") || path.includes("/discover")) {
      c.header("Cache-Control", "public, max-age=60, s-maxage=600, stale-while-revalidate=3600")
    } else {
      c.header("Cache-Control", "public, max-age=120, s-maxage=1800, stale-while-revalidate=86400")
    }
  }
})

// Mount Routers
app.route("/api/v1", mediaRouter)
app.route("/api/v2", mediaRouter)
app.route("/api/v1", categoriesRouter)
app.route("/api/v2", categoriesRouter)

// Direct streaming proxy helper to bypass ISP blocking of image.tmdb.org
async function streamImageFromUrl(url: string): Promise<Response | null> {
  try {
    const res = await fetch(url, {
      headers: {
        "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15",
        "Referer": "https://www.themoviedb.org/",
      },
    })
    if (!res.ok) return null
    const contentType = res.headers.get("content-type") || "image/jpeg"
    return new Response(res.body, {
      status: 200,
      headers: {
        "Content-Type": contentType,
        "Cache-Control": "public, max-age=31536000, immutable",
        "Access-Control-Allow-Origin": "*",
      },
    })
  } catch {
    return null
  }
}

// TMDB Image Proxy: streams any TMDB image with long-term Edge caching
app.get("/api/v1/images/tmdb/:size/*", async (c) => {
  const size = c.req.param("size")
  const prefix = `/api/v1/images/tmdb/${size}`
  const imagePath = c.req.path.startsWith(prefix) ? c.req.path.slice(prefix.length) : ""
  if (!imagePath) return c.text("Bad request", 400)

  const tmdbUrl = `https://image.tmdb.org/t/p/${size}${imagePath}`
  const streamed = await streamImageFromUrl(tmdbUrl)
  if (streamed) return streamed
  return c.text("Image not found", 404)
})

// Backward compatible Image Proxy
app.get("/api/v1/images/logos/:id/original", async (c) => {
  const rawId = c.req.param("id").replace(/^(tmdb_|kp_)/, "")
  let id = parseInt(rawId, 10)
  if (isNaN(id)) return c.text("Not found", 404)

  const cached = getCached<MediaDetailsDto>(detailsCache, `movie:${id}`)
  if (cached?.logo) {
    const streamed = await streamImageFromUrl(cached.logo)
    if (streamed) return streamed
  }

  try {
    const movie = await tmdb.getMovieDetails(id)
    if (movie.logo) {
      const streamed = await streamImageFromUrl(movie.logo)
      if (streamed) return streamed
    }
  } catch {
    // Might be Kinopoisk ID -> resolve TMDB ID via Alloha
    const tmdbId = await resolveTmdbIdByKp(id)
    if (tmdbId) {
      try {
        const movie = await tmdb.getMovieDetails(tmdbId)
        if (movie.logo) {
          const streamed = await streamImageFromUrl(movie.logo)
          if (streamed) return streamed
        }
      } catch {}
    }
  }

  return c.text("Logo not found", 404)
})

app.get("/api/v1/images/backdrops/:id/:size", async (c) => {
  const rawId = c.req.param("id").replace(/^(tmdb_|kp_)/, "")
  let id = parseInt(rawId, 10)
  if (isNaN(id)) return c.text("Not found", 404)

  const cached = getCached<MediaDetailsDto>(detailsCache, `movie:${id}`)
  if (cached?.backdrop) {
    const streamed = await streamImageFromUrl(cached.backdrop)
    if (streamed) return streamed
  }

  try {
    const movie = await tmdb.getMovieDetails(id)
    if (movie.backdrop) {
      const streamed = await streamImageFromUrl(movie.backdrop)
      if (streamed) return streamed
    }
  } catch {
    const tmdbId = await resolveTmdbIdByKp(id)
    if (tmdbId) {
      try {
        const movie = await tmdb.getMovieDetails(tmdbId)
        if (movie.backdrop) {
          const streamed = await streamImageFromUrl(movie.backdrop)
          if (streamed) return streamed
        }
      } catch {}
    }
  }

  return c.text("Backdrop not found", 404)
})

// 404 Handler
app.notFound((c) => {
  return c.json({ status: "error", message: `Route ${c.req.path} not found` }, 404)
})

// Error Handler
app.onError((err, c) => {
  console.error("Server Error:", err)
  return c.json({ status: "error", message: err.message || "Internal server error" }, 500)
})

export default app
