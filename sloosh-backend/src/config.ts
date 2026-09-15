export const config = {
  port: parseInt(process.env.PORT || "3000", 10),
  apiKey: (process.env.SLOOSH_API_KEY || process.env.API_KEY || "").trim(),
  allowedApiKeys: (process.env.ALLOWED_API_KEYS ? process.env.ALLOWED_API_KEYS.split(",").map((k: string) => k.trim()) : []).filter(Boolean) as string[],
  tmdb: {
    baseUrl: "https://api.themoviedb.org/3",
    imageBaseUrl: "https://api-sloosh.vercel.app/api/v1/images/tmdb",
    token: process.env.TMDB_TOKEN || "",
    defaultLanguage: process.env.DEFAULT_LANGUAGE || "ru-RU",
  },
  alloha: {
    baseUrl: "https://api.alloha.tv",
    token: (process.env.ALLOHA_TOKEN || "").trim(),
    get backupTokens(): string[] {
      const fromComma = (process.env.ALLOHA_BACKUP_TOKENS || "")
        .split(",")
        .map((t: string) => t.trim())
        .filter(Boolean)

      const individual: string[] = []
      for (let i = 1; i <= 10; i++) {
        const b = process.env[`ALLOHA_BACKUP_TOKEN_${i}`]?.trim()
        if (b) individual.push(b)
        const t = process.env[`ALLOHA_TOKEN_${i}`]?.trim()
        if (t && i > 1) individual.push(t) // TOKEN_1 is primary
      }

      return Array.from(new Set([...fromComma, ...individual]))
    },
    get allTokens(): string[] {
      // Check if all tokens were provided in a single comma-separated variable ALLOHA_TOKENS
      const fromAll = (process.env.ALLOHA_TOKENS || "")
        .split(",")
        .map((t: string) => t.trim())
        .filter(Boolean)

      const primary = (process.env.ALLOHA_TOKEN || process.env.ALLOHA_TOKEN_1 || fromAll[0] || "").trim()
      const list = [primary, ...fromAll.slice(1), ...this.backupTokens].filter(Boolean)
      return Array.from(new Set(list))
    }
  },
  studios: [
    { id: "marvel", name: "Marvel", slug: "marvel", tmdbCompanyId: 420, isNetwork: false },
    { id: "dc", name: "DC", slug: "dc", tmdbCompanyId: 128064, isNetwork: false },
    { id: "pixar", name: "Pixar", slug: "pixar", tmdbCompanyId: 3, isNetwork: false },
    { id: "disney", name: "Disney", slug: "disney", tmdbCompanyId: 2, isNetwork: false },
    { id: "warner-bros", name: "Warner Bros.", slug: "warner-bros", tmdbCompanyId: 174, isNetwork: false },
    { id: "universal", name: "Universal", slug: "universal", tmdbCompanyId: 33, isNetwork: false },
    { id: "paramount", name: "Paramount", slug: "paramount", tmdbCompanyId: 4, isNetwork: false },
    { id: "sony", name: "Sony Pictures", slug: "sony", tmdbCompanyId: 34, isNetwork: false },
    { id: "netflix", name: "Netflix", slug: "netflix", tmdbNetworkId: 213, isNetwork: true },
    { id: "apple-tv", name: "Apple TV+", slug: "apple-tv", tmdbNetworkId: 2552, isNetwork: true },
    { id: "hbo", name: "HBO", slug: "hbo", tmdbNetworkId: 49, isNetwork: true },
    { id: "amazon", name: "Prime Video", slug: "amazon", tmdbNetworkId: 1024, isNetwork: true },
  ]
}
