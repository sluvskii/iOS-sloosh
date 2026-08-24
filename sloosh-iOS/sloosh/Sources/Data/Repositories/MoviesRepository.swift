import Foundation
import UIKit

@MainActor
class MoviesRepository: ObservableObject {
    static let shared = MoviesRepository()

    // MARK: - List caches (in-memory, session-scoped)
    private var popularCache: [Int: [MediaDto]] = [:]
    private var topMoviesCache: [Int: [MediaDto]] = [:]
    private var topTvCache: [Int: [MediaDto]] = [:]
    private var episodeCache: [String: TvEpisodeDetailsDto] = [:]
    private var memoryWarningToken: Any?

    // MARK: - Details cache (memory + disk, 24h TTL)
    private var detailsMemory: [String: MediaDetailsDto] = [:]
    private let detailsDiskCache = MediaDetailsDiskCache()
    private let listDiskCache = MediaListDiskCache()

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
        topTvCache.removeAll()
        episodeCache.removeAll()
        detailsMemory.removeAll()
        Task {
            await detailsDiskCache.cleanUpExpired()
            await listDiskCache.cleanUpExpired()
        }
    }

    // MARK: - Lists

    func getPopularMovies(page: Int = 1) async throws -> [MediaDto] {
        if let cached = popularCache[page] { return cached }
        if let diskCached = await listDiskCache.load(key: "popular_\(page)") {
            popularCache[page] = diskCached
            return diskCached
        }
        let response = try await MoviesApi.shared.getPopularMovies(page: page)
        let results = response.data?.results ?? []
        popularCache[page] = results
        await listDiskCache.save(results, key: "popular_\(page)")
        return results
    }

    func getTopMovies(page: Int = 1) async throws -> [MediaDto] {
        if let cached = topMoviesCache[page] { return cached }
        if let diskCached = await listDiskCache.load(key: "topMovies_\(page)") {
            topMoviesCache[page] = diskCached
            return diskCached
        }
        let response = try await MoviesApi.shared.getTopMovies(page: page)
        let results = response.data?.results ?? []
        topMoviesCache[page] = results
        await listDiskCache.save(results, key: "topMovies_\(page)")
        return results
    }

    func getTopTv(page: Int = 1) async throws -> [MediaDto] {
        if let cached = topTvCache[page] { return cached }
        if let diskCached = await listDiskCache.load(key: "topTv_\(page)") {
            topTvCache[page] = diskCached
            return diskCached
        }
        let response = try await MoviesApi.shared.getTopTv(page: page)
        let results = response.data?.results ?? []
        topTvCache[page] = results
        await listDiskCache.save(results, key: "topTv_\(page)")
        return results
    }

    // MARK: - Details (two-level: memory → disk → network)

    func getDetails(id: String) async throws -> MediaDetailsDto? {
        // 1. Memory hit
        if let hit = detailsMemory[id] { return hit }

        // 2. Disk hit
        if let hit = await detailsDiskCache.load(id: id) {
            detailsMemory[id] = hit
            return hit
        }

        // 3. Network
        let response = try await MoviesApi.shared.getDetails(id: id)
        if let details = response.data {
            detailsMemory[id] = details
            await detailsDiskCache.save(details, id: id)
        }
        return response.data
    }

    // MARK: - Episodes

    func getEpisodeDetails(id: String, season: Int, episode: Int) async throws -> TvEpisodeDetailsDto? {
        let cacheKey = "\(id)-\(season)-\(episode)"
        if let cached = episodeCache[cacheKey] { return cached }
        let response = try await MoviesApi.shared.getEpisodeDetails(id: id, season: season, episode: episode)
        if let data = response.data {
            episodeCache[cacheKey] = data
        }
        return response.data
    }

    // MARK: - Search

    /// Нормализует строку для сравнения: нижний регистр + замена ё→е,
    /// чтобы поиск "енола" находил "Ёнола" и наоборот.
    private func normalizeForSearch(_ s: String) -> String {
        return s.lowercased()
            .replacingOccurrences(of: "ё", with: "е")
    }

    func searchMovies(query: String, page: Int = 1) async throws -> [MediaDto] {
        let response = try await MoviesApi.shared.searchMovies(query: query, page: page)
        let rawResults = response.data?.results ?? []

        // Фильтруем результаты без плакатов или без названия, или с дефолтным "no-poster"
        let filtered = rawResults.filter { item in
            let poster = item.posterUrl ?? item.poster_path ?? ""
            let hasPoster = !poster.isEmpty && !poster.lowercased().contains("no-poster")
            let hasTitle = !(item.title ?? item.name ?? "").isEmpty
            return hasPoster && hasTitle
        }

        // Выполняем точный/подстрочный поиск по названию (для умного фолбэка)
        let normalizedQuery = normalizeForSearch(query)
        let sorted = filtered.sorted { a, b in
            let titleA = normalizeForSearch(a.title ?? a.name ?? "")
            let titleB = normalizeForSearch(b.title ?? b.name ?? "")

            let exactA = titleA == normalizedQuery
            let exactB = titleB == normalizedQuery
            if exactA != exactB { return exactA }

            let prefixA = titleA.hasPrefix(normalizedQuery)
            let prefixB = titleB.hasPrefix(normalizedQuery)
            if prefixA != prefixB { return prefixA }

            return false
        }

        return sorted
    }

    func searchMoviesResponse(query: String, page: Int = 1, filters: SearchFilters = SearchFilters()) async throws -> MediaResponse {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if !trimmedQuery.isEmpty {
            // Режим 1: Поиск по названию (v1 Kinopoisk Fuzzy Search)
            let response = try await MoviesApi.shared.searchMovies(query: trimmedQuery, page: page)
            guard let data = response.data else {
                return MediaResponse(page: page, results: [], pages: 1, total: 0, total_pages: 1, total_results: 0)
            }
            
            // Если заданы фильтры, мягко фильтруем результаты поиска на клиенте
            guard !filters.isEmpty, let rawResults = data.results else {
                return data
            }
            
            let filteredResults = applyFilters(rawResults, filters: filters)
            return MediaResponse(
                page: data.page,
                results: filteredResults,
                pages: data.pages,
                total: filteredResults.count,
                total_pages: data.total_pages,
                total_results: data.total_results
            )
        } else if !filters.isEmpty {
            // Режим 2: Просмотр каталога по фильтрам (v2 Discover/Filter Engine)
            let response = try await MoviesApi.shared.discoverMovies(filters: filters, page: page)
            guard let data = response.data else {
                return MediaResponse(page: page, results: [], pages: 1, total: 0, total_pages: 1, total_results: 0)
            }
            
            // Дополнительная клиентская фильтрация (например, по точному порогу рейтинга или года)
            if let rawResults = data.results {
                let filteredResults = applyFilters(rawResults, filters: filters)
                return MediaResponse(
                    page: data.page,
                    results: filteredResults,
                    pages: data.pages,
                    total: data.total,
                    total_pages: data.total_pages,
                    total_results: data.total_results
                )
            }
            return data
        } else {
            return MediaResponse(page: page, results: [], pages: 1, total: 0, total_pages: 1, total_results: 0)
        }
    }

    private func applyFilters(_ items: [MediaDto], filters: SearchFilters) -> [MediaDto] {
        return items.filter { item in
            // Фильтр по типу
            if let type = filters.type {
                switch type {
                case "FILM":
                    if item.type != "movie" || isCartoon(item) { return false }
                case "TV_SERIES":
                    if item.type != "tv" || isCartoon(item) { return false }
                case "CARTOON":
                    if !isCartoon(item) { return false }
                default:
                    break
                }
            }
            
            // Фильтр по рейтингу
            if let minRating = filters.ratingFrom {
                let rating = item.rating ?? item.ratings?.kp ?? item.ratings?.imdb ?? 0.0
                if rating < minRating { return false }
            }
            if let maxRating = filters.ratingTo {
                let rating = item.rating ?? item.ratings?.kp ?? item.ratings?.imdb ?? 0.0
                if rating > maxRating { return false }
            }
            
            // Фильтр по году
            let parsedYear: Int? = {
                guard let y = item.year else { return nil }
                switch y {
                case .int(let val): return val
                case .string(let str): return Int(str)
                case .double(let dbl): return Int(dbl)
                }
            }()
            
            if let minYear = filters.yearFrom, let year = parsedYear {
                if year < minYear { return false }
            }
            if let maxYear = filters.yearTo, let year = parsedYear {
                if year > maxYear { return false }
            }
            
            // Фильтр по жанру
            if let targetGenre = filters.genres?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines), !targetGenre.isEmpty {
                let itemGenres = item.genres?.compactMap { genreDto -> String? in
                    return genreDto.name?.lowercased() ?? genreDto.id?.lowercased()
                } ?? []
                let matches = itemGenres.contains { $0.contains(targetGenre) }
                if !matches { return false }
            }
            
            return true
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
            let dir = base.appendingPathComponent("sloosh.mediadetails", isDirectory: true)
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
            let dir = base.appendingPathComponent("sloosh.medialist", isDirectory: true)
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
