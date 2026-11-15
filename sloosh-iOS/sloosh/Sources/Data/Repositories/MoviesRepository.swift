import Foundation
import UIKit

@MainActor
class MoviesRepository: ObservableObject {
    static let shared = MoviesRepository()

    // MARK: - List caches (in-memory, session-scoped)
    private var popularCache: [Int: [MediaDto]] = [:]
    private var topMoviesCache: [Int: [MediaDto]] = [:]
    private var popularTvCache: [Int: [MediaDto]] = [:]
    private var topTvCache: [Int: [MediaDto]] = [:]
    private var cartoonsCache: [Int: [MediaDto]] = [:]
    private var popularAnimeCache: [Int: [MediaDto]] = [:]
    private var topAnimeCache: [Int: [MediaDto]] = [:]
    private var trendingCache: [Int: [MediaDto]] = [:]
    private var episodeCache: [String: TvEpisodeDetailsDto] = [:]
    private var seasonCache: [String: TvSeasonDto] = [:]
    private var memoryWarningToken: Any?

    // MARK: - Details cache (memory + disk, 24h TTL)
    private var detailsMemory: [String: MediaDetailsDto] = [:]
    private var personMemory: [Int: PersonDetailsDto] = [:]
    private let detailsDiskCache = MediaDetailsDiskCache()
    private let listDiskCache = MediaListDiskCache()
    private let personDiskCache = PersonDetailsDiskCache()

    private init() {
        memoryWarningToken = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.clearMemoryCache()
            }
        }
    }

    @MainActor
    func clearMemoryCache() {
        popularCache.removeAll()
        topMoviesCache.removeAll()
        popularTvCache.removeAll()
        topTvCache.removeAll()
        cartoonsCache.removeAll()
        popularAnimeCache.removeAll()
        topAnimeCache.removeAll()
        trendingCache.removeAll()
        episodeCache.removeAll()
        seasonCache.removeAll()
        detailsMemory.removeAll()
        personMemory.removeAll()
        Task {
            await detailsDiskCache.cleanUpExpired()
            await listDiskCache.cleanUpExpired()
            await personDiskCache.cleanUpExpired()
        }
    }

    // MARK: - Lists

    func getPopularMovies(page: Int = 1, force: Bool = false) async throws -> [MediaDto] {
        if !force {
            if let cached = popularCache[page] { return cached }
            if let diskCached = await listDiskCache.load(key: "popular_\(page)") {
                popularCache[page] = diskCached
                return diskCached
            }
        }
        do {
            let response = try await MoviesApi.shared.getPopularMovies(page: page)
            let results = response.data?.results ?? []
            if !results.isEmpty {
                popularCache[page] = results
                await listDiskCache.save(results, key: "popular_\(page)")
            }
            return results
        } catch {
            if let cached = popularCache[page] { return cached }
            if let diskCached = await listDiskCache.load(key: "popular_\(page)") {
                popularCache[page] = diskCached
                return diskCached
            }
            throw error
        }
    }

    func getTopMovies(page: Int = 1, force: Bool = false) async throws -> [MediaDto] {
        if !force {
            if let cached = topMoviesCache[page] { return cached }
            if let diskCached = await listDiskCache.load(key: "topMovies_\(page)") {
                topMoviesCache[page] = diskCached
                return diskCached
            }
        }
        do {
            let response = try await MoviesApi.shared.getTopMovies(page: page)
            let results = response.data?.results ?? []
            if !results.isEmpty {
                topMoviesCache[page] = results
                await listDiskCache.save(results, key: "topMovies_\(page)")
            }
            return results
        } catch {
            if let cached = topMoviesCache[page] { return cached }
            if let diskCached = await listDiskCache.load(key: "topMovies_\(page)") {
                topMoviesCache[page] = diskCached
                return diskCached
            }
            throw error
        }
    }

    func getTopTv(page: Int = 1, force: Bool = false) async throws -> [MediaDto] {
        if !force {
            if let cached = topTvCache[page] { return cached }
            if let diskCached = await listDiskCache.load(key: "topTv_\(page)") {
                topTvCache[page] = diskCached
                return diskCached
            }
        }
        do {
            let response = try await MoviesApi.shared.getTopTv(page: page)
            let results = response.data?.results ?? []
            if !results.isEmpty {
                topTvCache[page] = results
                await listDiskCache.save(results, key: "topTv_\(page)")
            }
            return results
        } catch {
            if let cached = topTvCache[page] { return cached }
            if let diskCached = await listDiskCache.load(key: "topTv_\(page)") {
                topTvCache[page] = diskCached
                return diskCached
            }
            throw error
        }
    }

    func getPopularTv(page: Int = 1, force: Bool = false) async throws -> [MediaDto] {
        if !force {
            if let cached = popularTvCache[page] { return cached }
            if let diskCached = await listDiskCache.load(key: "tv_popular_\(page)") {
                popularTvCache[page] = diskCached
                return diskCached
            }
        }
        do {
            let response = try await MoviesApi.shared.getPopularTv(page: page)
            let results = response.data?.results ?? []
            if !results.isEmpty {
                popularTvCache[page] = results
                await listDiskCache.save(results, key: "tv_popular_\(page)")
                return results
            }
        } catch {
            // Fallback to top TV if popular endpoint is unavailable
        }
        return try await getTopTv(page: page, force: force)
    }

    func getCartoons(page: Int = 1, force: Bool = false) async throws -> [MediaDto] {
        if !force {
            if let cached = cartoonsCache[page] { return cached }
            if let diskCached = await listDiskCache.load(key: "cartoons_\(page)") {
                cartoonsCache[page] = diskCached
                return diskCached
            }
        }
        do {
            let response = try await MoviesApi.shared.getCartoons(page: page)
            let results = response.data?.results ?? []
            if !results.isEmpty {
                cartoonsCache[page] = results
                await listDiskCache.save(results, key: "cartoons_\(page)")
            }
            return results
        } catch {
            if let cached = cartoonsCache[page] { return cached }
            if let diskCached = await listDiskCache.load(key: "cartoons_\(page)") {
                cartoonsCache[page] = diskCached
                return diskCached
            }
            throw error
        }
    }

    func getPopularAnime(page: Int = 1, force: Bool = false) async throws -> [MediaDto] {
        if !force {
            if let cached = popularAnimeCache[page] { return cached }
            if let diskCached = await listDiskCache.load(key: "anime_popular_\(page)") {
                popularAnimeCache[page] = diskCached
                return diskCached
            }
        }
        do {
            let response = try await MoviesApi.shared.getAnime(page: page, order: "popular")
            let results = response.data?.results ?? []
            if !results.isEmpty {
                popularAnimeCache[page] = results
                await listDiskCache.save(results, key: "anime_popular_\(page)")
            }
            return results
        } catch {
            if let cached = popularAnimeCache[page] { return cached }
            if let diskCached = await listDiskCache.load(key: "anime_popular_\(page)") {
                popularAnimeCache[page] = diskCached
                return diskCached
            }
            throw error
        }
    }

    func getTopAnime(page: Int = 1, force: Bool = false) async throws -> [MediaDto] {
        if !force {
            if let cached = topAnimeCache[page] { return cached }
            if let diskCached = await listDiskCache.load(key: "anime_top_\(page)") {
                topAnimeCache[page] = diskCached
                return diskCached
            }
        }
        do {
            let response = try await MoviesApi.shared.getAnime(page: page, order: "top")
            let results = response.data?.results ?? []
            if !results.isEmpty {
                topAnimeCache[page] = results
                await listDiskCache.save(results, key: "anime_top_\(page)")
            }
            return results
        } catch {
            if let cached = topAnimeCache[page] { return cached }
            if let diskCached = await listDiskCache.load(key: "anime_top_\(page)") {
                topAnimeCache[page] = diskCached
                return diskCached
            }
            throw error
        }
    }

    func getTrending(page: Int = 1, force: Bool = false) async throws -> [MediaDto] {
        if !force {
            if let cached = trendingCache[page] { return cached }
            if let diskCached = await listDiskCache.load(key: "trending_\(page)") {
                trendingCache[page] = diskCached
                return diskCached
            }
        }
        do {
            let response = try await MoviesApi.shared.getTrending(page: page)
            let results = response.data?.allItems ?? response.data?.results ?? []
            if !results.isEmpty {
                trendingCache[page] = results
                await listDiskCache.save(results, key: "trending_\(page)")
            }
            return results
        } catch {
            if let cached = trendingCache[page] { return cached }
            if let diskCached = await listDiskCache.load(key: "trending_\(page)") {
                trendingCache[page] = diskCached
                return diskCached
            }
            throw error
        }
    }

    // MARK: - Details (two-level: memory → disk → network)

    func getCachedDetails(id: String, type: String? = nil) -> MediaDetailsDto? {
        let inferredType = type ?? (id.hasPrefix("tv_") ? "tv" : (id.hasPrefix("movie_") ? "movie" : nil))
        let cacheKey = inferredType != nil ? "\(inferredType!)_\(id)" : id
        if let hit = detailsMemory[cacheKey] { return hit }
        if let hit = detailsMemory[id], (inferredType == nil || hit.type == inferredType) { return hit }
        return nil
    }

    func getDetails(id: String, type: String? = nil) async throws -> MediaDetailsDto? {
        let inferredType = type ?? (id.hasPrefix("tv_") ? "tv" : (id.hasPrefix("movie_") ? "movie" : nil))
        let cacheKey = inferredType != nil ? "\(inferredType!)_\(id)" : id

        // 1. Memory hit
        if let hit = detailsMemory[cacheKey] { return hit }
        if let hit = detailsMemory[id], (inferredType == nil || hit.type == inferredType) { return hit }

        // 2. Disk hit
        if let hit = await detailsDiskCache.load(id: cacheKey) {
            detailsMemory[cacheKey] = hit
            return hit
        }
        if let hit = await detailsDiskCache.load(id: id), (inferredType == nil || hit.type == inferredType) {
            detailsMemory[cacheKey] = hit
            return hit
        }

        // 3. Network
        let response = try await MoviesApi.shared.getDetails(id: id, type: inferredType)
        if let details = response.data {
            detailsMemory[cacheKey] = details
            await detailsDiskCache.save(details, id: cacheKey)
            return details
        }
        return response.data
    }

    // MARK: - Seasons & Episodes

    func getSeason(id: String, season: Int) async throws -> TvSeasonDto? {
        let cacheKey = "\(id)-\(season)"
        if let cached = seasonCache[cacheKey] { return cached }
        let response = try await MoviesApi.shared.getSeason(id: id, season: season)
        if let data = response.data {
            seasonCache[cacheKey] = data
        }
        return response.data
    }

    func getEpisodeDetails(id: String, season: Int, episode: Int) async throws -> TvEpisodeDetailsDto? {
        let cacheKey = "\(id)-\(season)-\(episode)"
        if let cached = episodeCache[cacheKey] { return cached }
        let response = try await MoviesApi.shared.getEpisodeDetails(id: id, season: season, episode: episode)
        if let data = response.data {
            episodeCache[cacheKey] = data
        }
        return response.data
    }

    // MARK: - Person Details

    func getPersonDetails(id: Int) async throws -> PersonDetailsDto? {
        if let hit = personMemory[id] { return hit }
        if let diskHit = await personDiskCache.load(id: id) {
            personMemory[id] = diskHit
            return diskHit
        }
        let response = try await MoviesApi.shared.getPersonDetails(id: id)
        if let details = response.data {
            personMemory[id] = details
            await personDiskCache.save(details, id: id)
            return details
        }
        return response.data
    }

    // MARK: - Search

    func searchMovies(query: String, page: Int = 1) async throws -> [MediaDto] {
        let query = CatalogSearchQuery.text(query)
        guard !query.isEmpty else { return [] }
        var response = try await searchMoviesResponse(query: query, page: page)
        if page == 1, response.allItems.isEmpty {
            for alternative in CatalogSearchQuery.alternatives(query) {
                try Task.checkCancellation()
                response = try await searchMoviesResponse(query: alternative, page: page)
                if !response.allItems.isEmpty { break }
            }
        }
        return CatalogSearchPolicy.merge([], response.allItems, order: nil)
    }

    /// Keep server pagination intact even when this page is empty after local
    /// filtering. Never silently relax selected filters or hide posterless titles.
    func searchMoviesResponse(query: String, page: Int = 1, filters: SearchFilters = SearchFilters()) async throws -> MediaResponse {
        let query = CatalogSearchQuery.text(query)
        let filters = filters.normalized
        let data: MediaResponse
        let serverFiltered: Bool
        if !query.isEmpty {
            guard filters.studio == nil else { throw CatalogSearchError.studioWithTitle }
            let response = try await MoviesApi.shared.searchMovies(query: query, page: page)
            guard response.success != false, let value = response.data else { throw CatalogSearchError.invalidResponse }
            data = value
            serverFiltered = false
        } else if let studio = filters.studio {
            // A collection is an authoritative studio scope, not an excuse to
            // fall back to an unrelated catalog when its page is empty or fails.
            let response = try await MoviesApi.shared.getCollection(id: studio, page: page)
            guard response.success != false, let value = response.data else { throw CatalogSearchError.invalidResponse }
            data = value
            serverFiltered = false
        } else if !filters.isEmpty {
            let response = try await MoviesApi.shared.discoverMovies(filters: filters, page: page)
            guard response.success != false, let value = response.data else { throw CatalogSearchError.invalidResponse }
            data = value
            serverFiltered = true
        } else {
            return MediaResponse(page: page, results: [], pages: 1)
        }
        try Task.checkCancellation()
        guard data.results != nil || data.items != nil else { throw CatalogSearchError.invalidResponse }
        let items = data.allItems.filter { CatalogSearchPolicy.matches($0, filters: filters, serverFiltered: serverFiltered) }
        return MediaResponse(page: data.page ?? page,
                             results: CatalogSearchPolicy.merge([], items, order: filters.order),
                             pages: data.effectiveTotalPages)
    }

    // MARK: - Categories, Studios & Collections

    func getCategories() async -> [CategorySectionDto] {
        do {
            let response = try await MoviesApi.shared.getCategories()
            if let sections = response.data, !sections.isEmpty {
                return sections
            }
        } catch {
            // Graceful fallback: built-in studios and networks
        }
        
        return [
            CategorySectionDto(
                section: "Studios",
                items: StudioBrand.all.filter { !$0.isNetwork }.map {
                    CategoryItemDto(id: $0.id, name: $0.name, slug: $0.slug, type: "movie", backdrop: nil)
                }
            ),
            CategorySectionDto(
                section: "Networks",
                items: StudioBrand.all.filter { $0.isNetwork }.map {
                    CategoryItemDto(id: $0.id, name: $0.name, slug: $0.slug, type: "tv", backdrop: nil)
                }
            )
        ]
    }

    func getCollection(id: String, page: Int = 1) async throws -> (items: [MediaDto], totalPages: Int) {
        do {
            let response = try await MoviesApi.shared.getCollection(id: id, page: page)
            let items = response.data?.allItems ?? []
            let totalPages = response.data?.effectiveTotalPages ?? 1
            if !items.isEmpty {
                let cleaned = items.filter { Self.isQualityStudioItem($0) }
                return (cleaned.isEmpty ? items : cleaned, totalPages)
            }
        } catch {
            // Fallback for search
        }
        
        // Fallback: search by studio brand directly through API
        if let brand = StudioBrand.find(by: id) {
            let searchRes = try await searchMoviesResponse(query: brand.name, page: page)
            let rawItems = searchRes.allItems
            let cleaned = rawItems.filter { Self.isQualityStudioItem($0) }
            return (cleaned, searchRes.effectiveTotalPages)
        }
        
        return ([], 1)
    }

    nonisolated private static func isQualityStudioItem(_ item: MediaDto) -> Bool {
        // 1. Poster check: must have a real poster and not be a placeholder
        let rawPoster = item.posterUrl ?? item.poster_path ?? ""
        if rawPoster.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || rawPoster.contains("no-poster") {
            return false
        }
        guard let displayPoster = item.displayPosterUrl,
              !displayPoster.contains("no-poster"),
              !displayPoster.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        // 2. Rating check: valid rating (at least 5.0) or recent release
        let effRating = item.effectiveRating
        if effRating > 0 {
            if effRating < 5.0 {
                return false
            }
        } else {
            let currentYear = Calendar.current.component(.year, from: Date())
            let itemYear = item.effectiveYear ?? 0
            if itemYear < currentYear - 1 {
                return false
            }
        }

        // 3. Year check: must have a valid release year (not in distant future or missing)
        let currentYear = Calendar.current.component(.year, from: Date())
        if let year = item.effectiveYear {
            if year < 1930 || year > currentYear + 1 {
                return false
            }
        } else {
            return false
        }

        // 4. Genres check: discard shorts, documentaries, news, specials, talk-shows, ceremonies, etc.
        let junkGenres = [
            "короткометражк", "short",
            "документальн", "documentary",
            "новост", "news",
            "ток-шоу", "talk-show",
            "церемони", "ceremony",
            "концерт", "concert",
            "музык", "music"
        ]
        if let genres = item.genres {
            for g in genres {
                let gName = (g.name ?? "").lowercased()
                let gId = (g.id ?? "").lowercased()
                if junkGenres.contains(where: { gName.contains($0) || gId.contains($0) }) {
                    return false
                }
            }
        }

        // 5. Title & Original Title check: exclude promotional, reaction, behind the scenes, bloopers, etc.
        let title = (item.displayTitle).lowercased()
        let origTitle = (item.originalTitle ?? "").lowercased()
        let combinedTitle = "\(title) \(origTitle)"

        let junkKeywords = [
            "короткометражк", "one-shot", "ван-шот", "короткий метр",
            "фильм о фильме", "making of", "behind the scenes", "за кадром",
            "клип", "music video",
            "реагируют", "reaction", "реакци",
            "coca-cola", "реклам", "commercial",
            "holiday special", "спешл", "специальный выпуск",
            "bloopers", "неудачные дубли", "смешные дубли",
            "тизер", "трейлер", "trailer", "teaser",
            "промо", "promo",
            "интервью", "interview",
            "бонусы", "bonus"
        ]

        if junkKeywords.contains(where: { combinedTitle.contains($0) }) {
            return false
        }

        return true
    }

    func getRelatedByStudio(type: String, id: String, page: Int = 1) async -> RelatedStudioResponse? {
        do {
            let response = try await MoviesApi.shared.getRelatedByStudio(type: type, id: id, page: page)
            return response.data
        } catch {
            return nil
        }
    }

    func getMovieCollection(id: String) async -> MovieCollectionDto? {
        do {
            let response = try await MoviesApi.shared.getMovieCollection(id: id)
            return response.data
        } catch {
            return nil
        }
    }


}

// MARK: - MediaDetailsDiskCache

/// Кэширует MediaDetailsDto на диске (Library/Caches) с TTL 24 часа.
actor MediaDetailsDiskCache {
    private let ttl: TimeInterval = 24 * 60 * 60

    private struct Entry: Codable {
        let savedAt: Date
        let details: MediaDetailsDto
    }

    private let cacheDir: URL?

    init() {
        if let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            // Clean up legacy caches if present
            try? FileManager.default.removeItem(at: base.appendingPathComponent("sloosh.mediadetails", isDirectory: true))
            try? FileManager.default.removeItem(at: base.appendingPathComponent("sloosh.mediadetails.v3", isDirectory: true))
            try? FileManager.default.removeItem(at: base.appendingPathComponent("sloosh.mediadetails.v4", isDirectory: true))
            try? FileManager.default.removeItem(at: base.appendingPathComponent("sloosh.mediadetails.v5", isDirectory: true))
            try? FileManager.default.removeItem(at: base.appendingPathComponent("sloosh.mediadetails.v6", isDirectory: true))
            try? FileManager.default.removeItem(at: base.appendingPathComponent("sloosh.mediadetails.v7", isDirectory: true))
            try? FileManager.default.removeItem(at: base.appendingPathComponent("sloosh.mediadetails.v8", isDirectory: true))
            try? FileManager.default.removeItem(at: base.appendingPathComponent("sloosh.mediadetails.v9", isDirectory: true))
            try? FileManager.default.removeItem(at: base.appendingPathComponent("sloosh.mediadetails.v10", isDirectory: true))
            
            let dir = base.appendingPathComponent("sloosh.mediadetails.v11", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.cacheDir = dir
        } else {
            self.cacheDir = nil
        }
    }

    private func fileURL(for id: String) -> URL? {
        let safe = id.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
        return cacheDir?.appendingPathComponent("\(safe).json")
    }

    func load(id: String) -> MediaDetailsDto? {
        guard let url = fileURL(for: id) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let entry = try? JSONDecoder().decode(Entry.self, from: data) else { return nil }
        guard Date().timeIntervalSince(entry.savedAt) < ttl else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        // If entry has no similar media (from older build before similar was added), treat as cache miss
        if entry.details.similar == nil {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        // If entry has no crew or directors (from older build before crew was added), treat as cache miss
        if entry.details.crew == nil && entry.details.directors == nil {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        // If entry has no backdrops (from older build before backdrops was added), treat as cache miss
        if entry.details.backdrops == nil {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return entry.details
    }

    func save(_ details: MediaDetailsDto, id: String) {
        guard let url = fileURL(for: id) else { return }
        let entry = Entry(savedAt: Date(), details: details)
        guard let data = try? JSONEncoder().encode(entry) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func cleanUpExpired() {
        guard let dir = cacheDir, let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let now = Date()
        for file in files {
            if let values = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
               let modDate = values.contentModificationDate {
                if now.timeIntervalSince(modDate) >= ttl {
                    try? FileManager.default.removeItem(at: file)
                }
            }
        }
    }
}

// MARK: - MediaListDiskCache

/// Кэширует списки (popular, top) на диске с TTL 4 часа.
actor MediaListDiskCache {
    private let ttl: TimeInterval = 4 * 60 * 60

    private struct Entry: Codable {
        let savedAt: Date
        let items: [MediaDto]
    }

    private let cacheDir: URL?

    init() {
        if let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            // Clean up legacy caches if present
            try? FileManager.default.removeItem(at: base.appendingPathComponent("sloosh.medialist", isDirectory: true))
            try? FileManager.default.removeItem(at: base.appendingPathComponent("sloosh.medialist.v3", isDirectory: true))
            try? FileManager.default.removeItem(at: base.appendingPathComponent("sloosh.medialist.v4", isDirectory: true))
            
            let dir = base.appendingPathComponent("sloosh.medialist.v5", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.cacheDir = dir
        } else {
            self.cacheDir = nil
        }
    }

    private func fileURL(for key: String) -> URL? {
        return cacheDir?.appendingPathComponent("\(key).json")
    }

    func load(key: String) -> [MediaDto]? {
        guard let url = fileURL(for: key) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let entry = try? JSONDecoder().decode(Entry.self, from: data) else { return nil }
        guard Date().timeIntervalSince(entry.savedAt) < ttl else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return entry.items
    }

    func save(_ items: [MediaDto], key: String) {
        guard let url = fileURL(for: key) else { return }
        let entry = Entry(savedAt: Date(), items: items)
        guard let data = try? JSONEncoder().encode(entry) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func cleanUpExpired() {
        guard let dir = cacheDir, let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let now = Date()
        for file in files {
            if let values = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
               let modDate = values.contentModificationDate {
                if now.timeIntervalSince(modDate) >= ttl {
                    try? FileManager.default.removeItem(at: file)
                }
            }
        }
    }
}

// MARK: - PersonDetailsDiskCache

/// Кэширует PersonDetailsDto на диске (Library/Caches) с TTL 24 часа.
actor PersonDetailsDiskCache {
    private let ttl: TimeInterval = 24 * 60 * 60

    private struct Entry: Codable {
        let savedAt: Date
        let details: PersonDetailsDto
    }

    private let cacheDir: URL?

    init() {
        if let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let dir = base.appendingPathComponent("sloosh.persondetails.v1", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.cacheDir = dir
        } else {
            self.cacheDir = nil
        }
    }

    private func fileURL(for id: Int) -> URL? {
        return cacheDir?.appendingPathComponent("\(id).json")
    }

    func load(id: Int) -> PersonDetailsDto? {
        guard let url = fileURL(for: id) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let entry = try? JSONDecoder().decode(Entry.self, from: data) else { return nil }
        guard Date().timeIntervalSince(entry.savedAt) < ttl else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return entry.details
    }

    func save(_ details: PersonDetailsDto, id: Int) {
        guard let url = fileURL(for: id) else { return }
        let entry = Entry(savedAt: Date(), details: details)
        guard let data = try? JSONEncoder().encode(entry) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func cleanUpExpired() {
        guard let dir = cacheDir, let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let now = Date()
        for file in files {
            if let values = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
               let modDate = values.contentModificationDate {
                if now.timeIntervalSince(modDate) >= ttl {
                    try? FileManager.default.removeItem(at: file)
                }
            }
        }
    }
}
