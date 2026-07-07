import Foundation

@MainActor
class MoviesRepository: ObservableObject {
    static let shared = MoviesRepository()

    // MARK: - List caches (in-memory, session-scoped)
    private var popularCache: [Int: [MediaDto]] = [:]
    private var topMoviesCache: [Int: [MediaDto]] = [:]
    private var topTvCache: [Int: [MediaDto]] = [:]
    private var episodeCache: [String: TvEpisodeDetailsDto] = [:]

    // MARK: - Details cache (memory + disk, 24h TTL)
    private var detailsMemory: [String: MediaDetailsDto] = [:]
    private let detailsDiskCache = MediaDetailsDiskCache()

    // MARK: - Lists

    func getPopularMovies(page: Int = 1) async throws -> [MediaDto] {
        if let cached = popularCache[page] { return cached }
        let response = try await MoviesApi.shared.getPopularMovies(page: page)
        let results = response.data?.results ?? []
        popularCache[page] = results
        return results
    }

    func getTopMovies(page: Int = 1) async throws -> [MediaDto] {
        if let cached = topMoviesCache[page] { return cached }
        let response = try await MoviesApi.shared.getTopMovies(page: page)
        let results = response.data?.results ?? []
        topMoviesCache[page] = results
        return results
    }

    func getTopTv(page: Int = 1) async throws -> [MediaDto] {
        if let cached = topTvCache[page] { return cached }
        let response = try await MoviesApi.shared.getTopTv(page: page)
        let results = response.data?.results ?? []
        topTvCache[page] = results
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
            detailsDiskCache.save(details, id: id)
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

    func searchMovies(query: String, page: Int = 1) async throws -> [MediaDto] {
        let response = try await MoviesApi.shared.searchMovies(query: query, page: page)
        return response.data?.results ?? []
    }

    func searchMoviesResponse(query: String, page: Int = 1) async throws -> MediaResponse {
        let response = try await MoviesApi.shared.searchMovies(query: query, page: page)
        return response.data ?? MediaResponse(page: page, results: [], pages: 1, total: 0, total_pages: 1, total_results: 0)
    }
}

// MARK: - MediaDetailsDiskCache

/// Кэширует MediaDetailsDto на диске (Library/Caches) с TTL 24 часа.
/// Не блокирует main thread — все операции через фоновую очередь.
final class MediaDetailsDiskCache {
    private let ttl: TimeInterval = 24 * 60 * 60
    private let queue = DispatchQueue(label: "ru.sloosh.mediadetails.diskcache", qos: .utility)

    private struct Entry: Codable {
        let savedAt: Date
        let details: MediaDetailsDto
    }

    private var cacheDir: URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("sloosh.mediadetails", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func fileURL(for id: String) -> URL? {
        // Sanitize id to be filename-safe
        let safe = id.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
        return cacheDir?.appendingPathComponent("\(safe).json")
    }

    /// Загрузка через фоновый Task, чтобы не блокировать UI
    func load(id: String) async -> MediaDetailsDto? {
        return await Task.detached(priority: .userInitiated) { [weak self] () -> MediaDetailsDto? in
            guard let self = self else { return nil }
            guard let url = self.fileURL(for: id) else { return nil }
            guard let data = try? Data(contentsOf: url) else { return nil }
            guard let entry = try? JSONDecoder().decode(Entry.self, from: data) else { return nil }
            guard Date().timeIntervalSince(entry.savedAt) < self.ttl else {
                // Устаревший — удаляем
                self.queue.async { try? FileManager.default.removeItem(at: url) }
                return nil
            }
            return entry.details
        }.value
    }

    func save(_ details: MediaDetailsDto, id: String) {
        guard let url = fileURL(for: id) else { return }
        let entry = Entry(savedAt: Date(), details: details)
        queue.async {
            guard let data = try? JSONEncoder().encode(entry) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
}
