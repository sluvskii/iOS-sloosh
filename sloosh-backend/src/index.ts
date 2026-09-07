import { Hono } from "hono"
import { cors } from "hono/cors"
import { logger } from "hono/logger"
import { config } from "./config"
import { mediaRouter } from "./routes/media"
import { categoriesRouter } from "./routes/categories"
import { tmdb } from "./services/tmdb"
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

// Mount Routers
app.route("/api/v1", mediaRouter)
app.route("/api/v2", mediaRouter)
app.route("/api/v1", categoriesRouter)
app.route("/api/v2", categoriesRouter)

// Backward compatible Image Redirection
app.get("/api/v1/images/logos/:id/original", async (c) => {
  const rawId = c.req.param("id").replace(/^(tmdb_|kp_)/, "")
  const id = parseInt(rawId, 10)
  if (isNaN(id)) return c.text("Not found", 404)

  const cached = getCached<MediaDetailsDto>(detailsCache, `movie:${id}`)
  if (cached?.logo) {
    return c.redirect(cached.logo, 302)
  }

  try {
    const movie = await tmdb.getMovieDetails(id)
    if (movie.logo) {
      return c.redirect(movie.logo, 302)
    }
  } catch {}

  return c.text("Logo not found", 404)
})

app.get("/api/v1/images/backdrops/:id/:size", async (c) => {
  const rawId = c.req.param("id").replace(/^(tmdb_|kp_)/, "")
  const id = parseInt(rawId, 10)
  if (isNaN(id)) return c.text("Not found", 404)

  const cached = getCached<MediaDetailsDto>(detailsCache, `movie:${id}`)
  if (cached?.backdrop) {
    return c.redirect(cached.backdrop, 302)
  }

  try {
    const movie = await tmdb.getMovieDetails(id)
    if (movie.backdrop) {
      return c.redirect(movie.backdrop, 302)
    }
  } catch {}

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
