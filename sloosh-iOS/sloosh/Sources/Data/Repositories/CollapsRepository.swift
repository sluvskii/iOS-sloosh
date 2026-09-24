import Foundation

final class CollapsRepository: @unchecked Sendable {
    static let shared = CollapsRepository()

    static let streamHeaders: [String: String] = [
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
        "Referer": "https://kinokrad.my/",
        "Origin": "https://kinokrad.my",
        "Accept": "*/*"
    ]

    static let embedHeaders: [String: String] = [
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
        "Referer": "https://kinokrad.my/",
        "Origin": "https://kinokrad.my",
        "Accept": "text/html,application/xhtml+xml"
    ]

    private let cacheLock = NSLock()
    private var cache: [String: (result: CollapsParser.ParseResult, expiresAt: Date)] = [:]
    private let cacheTtl: TimeInterval = 5 * 60 // 5 minutes

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    private init() {}

    func fetchMedia(
        kpId: Int?,
        imdbId: String? = nil,
        title: String? = nil
    ) async throws -> CollapsParser.ParseResult? {
        let effectiveKp = (kpId ?? 0) > 0 ? kpId : nil
        let effectiveImdb = (imdbId?.isEmpty == false) ? imdbId : nil

        guard effectiveKp != nil || effectiveImdb != nil else {
            return nil
        }

        let cacheKey = effectiveKp.map { "kp_\($0)" } ?? "imdb_\(effectiveImdb!)"

        cacheLock.lock()
        if let cached = cache[cacheKey], cached.expiresAt > Date() {
            cacheLock.unlock()
            return cached.result
        }
        cacheLock.unlock()

        let embedUrlString: String
        if let kp = effectiveKp {
            embedUrlString = "https://api.luxembd.ws/embed/kp/\(kp)"
        } else {
            embedUrlString = "https://api.luxembd.ws/embed/imdb/\(effectiveImdb!)"
        }

        guard let url = URL(string: embedUrlString) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (k, v) in Self.embedHeaders {
            request.setValue(v, forHTTPHeaderField: k)
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            return nil
        }

        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1251) else {
            return nil
        }

        let resolvedTitle = title ?? "Без названия"
        guard let parsed = CollapsParser.parseCatalog(embedHtml: html, defaultTitle: resolvedTitle) else {
            return nil
        }

        cacheLock.lock()
        cache[cacheKey] = (result: parsed, expiresAt: Date().addingTimeInterval(cacheTtl))
        cacheLock.unlock()

        return parsed
    }

    func invalidateCache() {
        cacheLock.lock()
        cache.removeAll()
        cacheLock.unlock()
    }
}
