import { Hono } from "hono"
import { config } from "../config"
import { tmdb } from "../services/tmdb"
import { listCache, getCached, setCached } from "../services/cache"
import type { CategorySectionDto, MediaResponse } from "../types/models"

export const categoriesRouter = new Hono()

// GET /api/v1/categories
categoriesRouter.get("/categories", (c) => {
  const studios = config.studios.filter((s) => !s.isNetwork).map((s) => ({
    id: s.id,
    name: s.name,
    slug: s.slug,
    type: "movie" as const,
    backdrop: null,
  }))

  const networks = config.studios.filter((s) => s.isNetwork).map((s) => ({
    id: s.id,
    name: s.name,
    slug: s.slug,
    type: "tv" as const,
    backdrop: null,
  }))

  const sections: CategorySectionDto[] = [
    { section: "Studios", items: studios },
    { section: "Networks", items: networks },
  ]

  return c.json({ status: "success", data: sections })
})

// GET /api/v1/collection/:id
categoriesRouter.get("/collection/:id", async (c) => {
  const idOrSlug = c.req.param("id").toLowerCase()
  const page = Math.min(Math.max(1, parseInt(c.req.query("page") || "1", 10) || 1), 500)

  const studio = config.studios.find((s) => s.id === idOrSlug || s.slug === idOrSlug || String(s.tmdbCompanyId) === idOrSlug || String(s.tmdbNetworkId) === idOrSlug)

  if (studio) {
    const cacheKey = `collection:${studio.id}:${page}`
    const cached = getCached<MediaResponse>(listCache, cacheKey)
    if (cached) return c.json({ status: "success", data: cached })

    try {
      let result: MediaResponse
      if (studio.isNetwork && studio.tmdbNetworkId) {
        result = await tmdb.getByNetwork(studio.tmdbNetworkId, page)
      } else if (studio.tmdbCompanyId) {
        result = await tmdb.getByCompany(studio.tmdbCompanyId, page)
      } else {
        result = { results: [], items: [], page: 1, total_pages: 1, total_results: 0 }
      }

      setCached(listCache, cacheKey, result)
      return c.json({ status: "success", data: result })
    } catch (err: any) {
      return c.json({ status: "error", message: err.message }, 500)
    }
  }

  // If numeric ID and not in studios list, check if it's a numeric company ID
  const numId = parseInt(idOrSlug, 10)
  if (!isNaN(numId)) {
    try {
      const result = await tmdb.getByCompany(numId, page)
      return c.json({ status: "success", data: result })
    } catch (err: any) {
      return c.json({ status: "error", message: err.message }, 500)
    }
  }

  return c.json({ status: "error", message: `Studio or collection '${idOrSlug}' not found` }, 404)
})

// GET /api/v1/media/:type/:id/related/studio
categoriesRouter.get("/media/:type/:id/related/studio", async (c) => {
  const type = c.req.param("type") === "tv" ? "tv" : "movie"
  const rawId = c.req.param("id").replace(/^(tmdb_|kp_)/, "")
  const id = parseInt(rawId, 10)
  const page = Math.min(Math.max(1, parseInt(c.req.query("page") || "1", 10) || 1), 500)

  if (isNaN(id)) {
    return c.json({ status: "error", message: "Invalid ID" }, 400)
  }

  try {
    let companyId: number | null = null
    let companyName = ""

    if (type === "tv") {
      const tv = await tmdb.getTvDetails(id)
      const firstNetwork = tv.networks?.[0]
      if (firstNetwork) {
        const response = await tmdb.getByNetwork(firstNetwork.id, page)
        const otherItems = response.results.filter((item) => item.id !== String(id))
        return c.json({
          status: "success",
          data: {
            results: otherItems,
            items: otherItems,
            label: firstNetwork.name,
            page: response.page,
            totalPages: response.total_pages,
            total_pages: response.total_pages,
            totalResults: otherItems.length,
            total_results: otherItems.length,
          }
        })
      }
    } else {
      const movie = await tmdb.getMovieDetails(id)
      const firstCompany = movie.productionCompanies?.[0]
      if (firstCompany) {
        companyId = firstCompany.id
        companyName = firstCompany.name
      }
    }

    if (!companyId) {
      return c.json({ status: "success", data: { results: [], items: [], label: "", page: 1, total_pages: 1, total_results: 0 } })
    }

    const response = await tmdb.getByCompany(companyId, page)
    const otherItems = response.results.filter((item) => item.id !== String(id))

    return c.json({
      status: "success",
      data: {
        results: otherItems,
        items: otherItems,
        label: companyName,
        page: response.page,
        totalPages: response.total_pages,
        total_pages: response.total_pages,
        totalResults: otherItems.length,
        total_results: otherItems.length,
      }
    })
  } catch (err: any) {
    return c.json({ status: "error", message: err.message }, 500)
  }
})

// GET /api/v1/media/movie/:id/collection
categoriesRouter.get("/media/movie/:id/collection", async (c) => {
  const rawId = c.req.param("id").replace(/^(tmdb_|kp_)/, "")
  const id = parseInt(rawId, 10)
  if (isNaN(id)) {
    return c.json({ status: "error", message: "Invalid movie ID" }, 400)
  }

  try {
    const movie = await tmdb.getMovieDetails(id)
    if (movie.collection) {
      return c.json({ status: "success", data: movie.collection })
    }
    return c.json({ status: "success", data: null })
  } catch (err: any) {
    return c.json({ status: "error", message: err.message }, 500)
  }
})
