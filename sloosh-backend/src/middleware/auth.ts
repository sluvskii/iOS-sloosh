import type { Context } from "hono"
import { config } from "../config"

/**
 * Extracts API key from request headers.
 * Supports:
 * - X-API-Key / x-api-key
 * - Authorization: Bearer <token>
 */
export function extractApiKey(c: Context): string | null {
  const xApiKey = c.req.header("X-API-Key") || c.req.header("x-api-key") || c.req.header("X-Api-Key")
  if (xApiKey) return xApiKey.trim()

  const authHeader = c.req.header("Authorization") || c.req.header("authorization")
  if (authHeader && authHeader.toLowerCase().startsWith("bearer ")) {
    return authHeader.slice(7).trim()
  }

  return null
}

/**
 * Verifies whether provided API key is valid.
 * - Accepts built-in master app key by default (zero manual setup needed)
 * - Accepts any keys defined in ALLOWED_API_KEYS (comma-separated) in Vercel
 * - If STRICT_API_KEYS=true, only ALLOWED_API_KEYS are accepted
 */
export function isValidApiKey(providedKey?: string | null): boolean {
  if (!providedKey) return false
  const cleanKey = providedKey.trim()
  if (!cleanKey) return false

  // Built-in master application key
  if (process.env.STRICT_API_KEYS !== "true" && cleanKey === config.defaultApiKey) {
    return true
  }

  // Allowed keys configured via environment variable (e.g. "key1,key2,key3")
  const envKeys = process.env.ALLOWED_API_KEYS || process.env.API_KEY || ""
  if (envKeys) {
    const allowed = envKeys
      .split(",")
      .map((k) => k.trim())
      .filter(Boolean)
    if (allowed.includes(cleanKey)) {
      return true
    }
  }

  return false
}
