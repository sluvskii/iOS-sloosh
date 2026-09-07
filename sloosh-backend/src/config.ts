export const config = {
  port: parseInt(process.env.PORT || "3000", 10),
  tmdb: {
    baseUrl: "https://api.themoviedb.org/3",
    imageBaseUrl: "https://image.tmdb.org/t/p",
    token: process.env.TMDB_TOKEN || "",
    defaultLanguage: process.env.DEFAULT_LANGUAGE || "ru-RU",
  },
  alloha: {
    baseUrl: "https://api.alloha.tv",
    token: process.env.ALLOHA_TOKEN || "ffbd312217e27c4245f2678afe1881",
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
