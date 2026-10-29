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
        title: String? = nil,
        isTv: Bool? = nil
    ) async throws -> CollapsParser.ParseResult? {
        let effectiveKp = (kpId ?? 0) > 0 ? kpId : nil
        let effectiveImdb = (imdbId?.isEmpty == false) ? imdbId : nil

        guard effectiveKp != nil || effectiveImdb != nil else {
            return nil
        }

        let typeSuffix = isTv.map { $0 ? "_tv" : "_movie" } ?? ""
        let cacheKey = (effectiveKp.map { "kp_\($0)" } ?? "imdb_\(effectiveImdb!)") + typeSuffix

        cacheLock.lock()
        if let cached = cache[cacheKey], cached.expiresAt > Date() {
            cacheLock.unlock()
            return cached.result
        }
        cacheLock.unlock()

        func isValidType(_ parsed: CollapsParser.ParseResult) -> Bool {
            if let isTv = isTv {
                if isTv && !parsed.apiResult.isSerial {
                    return false
                }
                if !isTv && parsed.apiResult.isSerial {
                    return false
                }
            }
            return true
        }

        func queryEmbed(urlStr: String) async -> CollapsParser.ParseResult? {
            guard let url = URL(string: urlStr) else { return nil }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            for (k, v) in Self.embedHeaders {
                request.setValue(v, forHTTPHeaderField: k)
            }
            do {
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    return nil
                }
                guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1251) else {
                    return nil
                }
                let resolvedTitle = title ?? "Без названия"
                return CollapsParser.parseCatalog(embedHtml: html, defaultTitle: resolvedTitle)
            } catch {
                return nil
            }
        }

        // 1. Попытка через KP ID
        if let kp = effectiveKp {
            if let parsed = await queryEmbed(urlStr: "https://api.luxembd.ws/embed/kp/\(kp)"), isValidType(parsed) {
                cacheLock.lock()
                cache[cacheKey] = (result: parsed, expiresAt: Date().addingTimeInterval(cacheTtl))
                cacheLock.unlock()
                return parsed
            }
        }

        // 2. Попытка через IMDB ID (если KP не сработал или вернул не тот тип — например, сериал вместо фильма!)
        if let imdb = effectiveImdb {
            if let parsed = await queryEmbed(urlStr: "https://api.luxembd.ws/embed/imdb/\(imdb)"), isValidType(parsed) {
                cacheLock.lock()
                cache[cacheKey] = (result: parsed, expiresAt: Date().addingTimeInterval(cacheTtl))
                cacheLock.unlock()
                return parsed
            }
        }

        return nil
    }

    func invalidateCache() {
        cacheLock.lock()
        cache.removeAll()
        cacheLock.unlock()
    }
}
