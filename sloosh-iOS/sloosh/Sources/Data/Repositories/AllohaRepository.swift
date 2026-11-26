import Foundation

// Models and translation matching helpers live in AllohaTranslationPolicy.swift.


// Bypasses certificate validation only for Alloha CDN hosts that use self-signed certs.
// This is intentionally narrow — all other hosts still go through default cert validation.
class AllohaTrustedSessionDelegate: NSObject, @preconcurrency URLSessionDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    
    private static let trustedHosts: Set<String> = [
        "alloha.tv", "alloh.tv",
        "feeds.alloha.tv", "static.alloha.tv",
        "cdn.alloha.tv",
        "vgif.ru", "allohalive.ru",
        "videocdn.tv", "dhklxm.ru", "cdnhl.ru",
        "vkvideo.cloud", "stravers.live",
        "interkh.com", "luxembd.ws", "kinokrad.my"
    ]
    
    nonisolated func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        let host = challenge.protectionSpace.host.lowercased()
        let dynamicBalancerHost = URL(string: AllohaRepository.activeBalancerBaseURL)?.host?.lowercased()
        let isDynamicHost = dynamicBalancerHost.map { host == $0 || host.hasSuffix("." + $0) } ?? false
        let isTrustedHost = isDynamicHost || Self.trustedHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) })
        if isTrustedHost {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        var redirectedRequest = request
        if let originalRequest = task.originalRequest {
            let headersToPreserve = ["Range", "Referer", "Origin", "Accept", "User-Agent"]
            for header in headersToPreserve {
                if let value = originalRequest.value(forHTTPHeaderField: header) {
                    redirectedRequest.setValue(value, forHTTPHeaderField: header)
                }
            }
        }
        completionHandler(redirectedRequest)
    }
}

// Legacy alias kept for compilation — remove when all usages are updated
typealias TrustAllSessionDelegate = AllohaTrustedSessionDelegate


final class AllohaRepository: @unchecked Sendable {
    static let shared = AllohaRepository()
    
    // MARK: - Dynamic Balancer Endpoint
    private static let balancerUserDefaultsKey = "sloosh_cached_balancer_base_url"

    /// Активный базовый адрес балансера (по умолчанию https://api.alloha.tv, управляется через endpoint.json)
    public static var activeBalancerBaseURL: String {
        get {
            if let cached = UserDefaults.standard.string(forKey: balancerUserDefaultsKey),
               !cached.isEmpty {
                return cached
            }
            return "https://api.alloha.tv"
        }
        set {
            let clean = newValue.hasSuffix("/") ? String(newValue.dropLast()) : newValue
            UserDefaults.standard.set(clean, forKey: balancerUserDefaultsKey)
        }
    }

    // Динамические токены балансера. Пул выдаётся бэкендом только по валидному Firebase ID токену
    // и никогда не лежит в бинарнике или публичном конфиге. Последний успешно полученный пул
    // персистится локально и служит офлайн-фоллбэком до восстановления связи с бэкендом.
    private var remoteTokens: [String] = []
    private static let cachedTokensKey = "sloosh_cached_stream_tokens"
    private var lastFetchDate: Date?
    private let tokensFetchTtl: TimeInterval = 10 * 60 // 10 minutes cache
    private var activeFetchTask: Task<[String], Never>?

    private var failedTokens: [String: Date] = [:]
    private let tokenCooldownDuration: TimeInterval = 5 * 60 // 5 minutes cooldown
    private let tokenQueue = DispatchQueue(label: "ru.sloosh.alloharepo.tokens", attributes: .concurrent)

    /// Background prefetch of streaming tokens upon app launch
    func warmup() async {
        _ = await ensureTokensLoaded()
    }

    /// Ensures stream tokens are loaded from backend and up to date
    func ensureTokensLoaded() async -> [String] {
        let now = Date()
        let (cachedTokens, shouldRefresh) = tokenQueue.sync(flags: .barrier) { () -> ([String], Bool) in
            if self.remoteTokens.isEmpty {
                let persisted = UserDefaults.standard.stringArray(forKey: Self.cachedTokensKey) ?? []
                if !persisted.isEmpty {
                    self.remoteTokens = persisted
                }
            }
            let tokens = self.remoteTokens
            let expired = self.lastFetchDate.map { now.timeIntervalSince($0) > self.tokensFetchTtl } ?? true
            return (tokens, tokens.isEmpty || expired)
        }

        if !shouldRefresh && !cachedTokens.isEmpty {
            let candidates = getHealthyCandidateTokens()
            if !candidates.isEmpty {
                return candidates
            }
        }

        let fetchTask: Task<[String], Never> = tokenQueue.sync(flags: .barrier) {
            if let inFlight = self.activeFetchTask {
                return inFlight
            }
            let task = Task<[String], Never> {
                defer {
                    self.tokenQueue.async(flags: .barrier) {
                        self.activeFetchTask = nil
                    }
                }
                do {
                    let tokens = try await MoviesApi.shared.getStreamTokens()
                    if !tokens.isEmpty {
                        self.tokenQueue.sync(flags: .barrier) {
                            self.remoteTokens = tokens
                            self.lastFetchDate = Date()
                            // Персистим последний реально полученный пул — офлайн-фоллбэк на следующий запуск
                            UserDefaults.standard.set(tokens, forKey: Self.cachedTokensKey)
                        }
                        #if DEBUG
                        print("[AllohaRepository] Dynamic stream tokens loaded from backend: \(tokens.count) tokens")
                        #endif
                        return tokens
                    }
                } catch {
                    #if DEBUG
                    print("[AllohaRepository] Failed to fetch stream tokens from backend: \(error)")
                    #endif
                }
                let existing = self.tokenQueue.sync { self.remoteTokens }
                if !existing.isEmpty {
                    // Не дёргаем заблокированный шлюз на каждый клик, если пул уже есть
                    self.tokenQueue.async(flags: .barrier) {
                        self.lastFetchDate = Date()
                    }
                    return existing
                }
                let persisted = UserDefaults.standard.stringArray(forKey: Self.cachedTokensKey) ?? []
                if !persisted.isEmpty {
                    #if DEBUG
                    print("[AllohaRepository] Using \(persisted.count) persisted stream tokens (offline fallback)")
                    #endif
                    self.tokenQueue.sync(flags: .barrier) {
                        self.remoteTokens = persisted
                        self.lastFetchDate = Date()
                    }
                    return persisted
                }
                return []
            }
            self.activeFetchTask = task
            return task
        }

        // Если сохранённые здоровые токены уже есть — сразу отдаём их плееру (0 мс ожидания),
        // а обновление пула с бэкенда спокойно добежит в фоне.
        let cachedCandidates = getHealthyCandidateTokens()
        if !cachedCandidates.isEmpty {
            return cachedCandidates
        }

        // Если здоровых токенов в кэше нет — обязательно дожидаемся свежего ответа с сервера
        _ = await fetchTask.value
        let freshCandidates = getHealthyCandidateTokens()
        return freshCandidates.isEmpty ? (try? await fetchTask.value) ?? [] : freshCandidates
    }

    private func getHealthyCandidateTokens() -> [String] {
        let allTokens = tokenQueue.sync { self.remoteTokens }
        var unique: [String] = []
        for t in allTokens where !t.isEmpty {
            if !unique.contains(t) {
                unique.append(t)
            }
        }

        let now = Date()
        let available = tokenQueue.sync {
            unique.filter { candidate in
                guard let cooldownUntil = failedTokens[candidate] else { return true }
                return now >= cooldownUntil
            }
        }

        if available.isEmpty {
            tokenQueue.async(flags: .barrier) { [weak self] in
                self?.failedTokens.removeAll()
            }
            return unique
        }

        return available
    }

    private func markTokenFailed(_ failedToken: String) {
        tokenQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            self.failedTokens[failedToken] = Date().addingTimeInterval(self.tokenCooldownDuration)
            #if DEBUG
            print("[AllohaRepository] Token ending with ...\(failedToken.suffix(6)) marked failed for 5m cooldown")
            #endif
        }
    }

    private func markTokenSuccess(_ healthyToken: String) {
        tokenQueue.async(flags: .barrier) { [weak self] in
            self?.failedTokens.removeValue(forKey: healthyToken)
        }
    }
    
    private var catalogCache: [String: (result: AllohaApiResult, expiresAt: Date)] = [:]
    private let cacheTtl: TimeInterval = 5 * 60 // 5 minutes
    private let cacheQueue = DispatchQueue(label: "ru.sloosh.alloharepo.cache", attributes: .concurrent)

    /// Сбрасывает локальный кеш результатов Alloha
    func invalidateCache() {
        cacheQueue.async(flags: .barrier) { [weak self] in
            self?.catalogCache.removeAll()
        }
    }

    // Create a URLSession that ignores SSL certificate errors
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        // Таймаут «простоя»: если балансер заблокирован провайдером, соединение висит
        // до системных 60 с — на это время зависает вся карточка фильма.
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20
        let delegate = TrustAllSessionDelegate()
        return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }()
    
    func fetchByKpId(
        kpId: Int,
        tmdbId: Int? = nil,
        imdbId: String? = nil,
        title: String? = nil,
        originalTitle: String? = nil,
        year: Int? = nil,
        isTv: Bool? = nil
    ) async throws -> AllohaApiResult {
        let typeSuffix = isTv.map { $0 ? "_tv" : "_movie" } ?? ""
        let baseKey: String? = {
            if kpId > 0 { return "kp_\(kpId)" }
            if let tmdb = tmdbId, tmdb > 0 { return "tmdb_\(tmdb)" }
            if let imdb = imdbId?.trimmingCharacters(in: .whitespacesAndNewlines), !imdb.isEmpty { return "imdb_\(imdb)" }
            if let t = title?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { return "title_\(t)" }
            return nil
        }()
        let cacheKey = baseKey.map { $0 + typeSuffix }

        if let cacheKey {
            let cached = cacheQueue.sync { catalogCache[cacheKey] }
            if let cached = cached, cached.expiresAt > Date() {
                return cached.result
            }
        }

        func saveToCache(_ result: AllohaApiResult) {
            if let cacheKey {
                cacheQueue.async(flags: .barrier) { [weak self] in
                    guard let self = self else { return }
                    self.catalogCache[cacheKey] = (result: result, expiresAt: Date().addingTimeInterval(self.cacheTtl))
                }
            }
        }

        func isValidType(_ result: AllohaApiResult) -> Bool {
            if let isTv = isTv {
                if isTv && !result.isSerial {
                    return false
                }
                if !isTv && result.isSerial {
                    return false
                }
            }
            return true
        }

        let categoryParam = isTv.map { $0 ? "2" : "1" }

        // 1. Try KP ID first if positive
        if kpId > 0 {
            var params = ["kp": String(kpId)]
            if let categoryParam { params["category"] = categoryParam }
            if let result = try? await performAllohaQuery(params: params), isValidType(result) {
                saveToCache(result)
                return result
            }
        }

        // 2. Fallback to TMDB ID if available
        if let tmdb = tmdbId, tmdb > 0 {
            var params = ["tmdb": String(tmdb)]
            if let categoryParam { params["category"] = categoryParam }
            if let result = try? await performAllohaQuery(params: params), isValidType(result) {
                saveToCache(result)
                return result
            }
        }

        // 3. Fallback to IMDB ID if available (crucial when provider has id_tmdb = null)
        if let imdb = imdbId?.trimmingCharacters(in: .whitespacesAndNewlines), !imdb.isEmpty {
            var params = ["imdb": imdb]
            if let categoryParam { params["category"] = categoryParam }
            if let result = try? await performAllohaQuery(params: params), isValidType(result) {
                saveToCache(result)
                return result
            }
        }

        // 4. Fallback to Russian title + year
        if let cleanTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !cleanTitle.isEmpty,
           !cleanTitle.hasPrefix("Без названия") {
            if let yr = year, yr > 1900 {
                var params = ["name": cleanTitle, "year": String(yr)]
                if let categoryParam { params["category"] = categoryParam }
                if let result = try? await performAllohaQuery(params: params), isValidType(result) {
                    saveToCache(result)
                    return result
                }
            }
            var params = ["name": cleanTitle]
            if let categoryParam { params["category"] = categoryParam }
            if let result = try? await performAllohaQuery(params: params), isValidType(result) {
                saveToCache(result)
                return result
            }
        }

        // 5. Fallback to Original title + year
        if let cleanOrig = originalTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !cleanOrig.isEmpty,
           cleanOrig != title {
            if let yr = year, yr > 1900 {
                var params = ["name": cleanOrig, "year": String(yr)]
                if let categoryParam { params["category"] = categoryParam }
                if let result = try? await performAllohaQuery(params: params), isValidType(result) {
                    saveToCache(result)
                    return result
                }
            }
            var params = ["name": cleanOrig]
            if let categoryParam { params["category"] = categoryParam }
            if let result = try? await performAllohaQuery(params: params), isValidType(result) {
                saveToCache(result)
                return result
            }
        }

        throw URLError(.badURL)
    }

    func fetchMedia(
        kpId: Int?,
        tmdbId: Int?,
        imdbId: String? = nil,
        title: String? = nil,
        originalTitle: String? = nil,
        year: Int? = nil,
        isTv: Bool? = nil
    ) async throws -> AllohaApiResult {
        let validKp = (kpId ?? 0) > 0 ? (kpId ?? 0) : 0
        let validTmdb = (tmdbId ?? 0) > 0 ? tmdbId : nil
        return try await fetchByKpId(
            kpId: validKp,
            tmdbId: validTmdb,
            imdbId: imdbId,
            title: title,
            originalTitle: originalTitle,
            year: year,
            isTv: isTv
        )
    }

    private func performAllohaQuery(param: String, value: String) async throws -> AllohaApiResult {
        return try await performAllohaQuery(params: [param: value])
    }

    private func performAllohaQuery(params: [String: String]) async throws -> AllohaApiResult {
        let candidates = await ensureTokensLoaded()
        guard !candidates.isEmpty else {
            throw URLError(.userAuthenticationRequired)
        }

        var lastError: Error = URLError(.badServerResponse)

        for candidateToken in candidates {
            var queryItems = [URLQueryItem(name: "token", value: candidateToken)]
            for (key, val) in params {
                queryItems.append(URLQueryItem(name: key, value: val))
            }
            guard var comps = URLComponents(string: "\(AllohaRepository.activeBalancerBaseURL)/") else {
                throw URLError(.badURL)
            }
            comps.queryItems = queryItems
            guard let url = comps.url else {
                throw URLError(.badURL)
            }

            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")

            do {
                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    markTokenFailed(candidateToken)
                    continue
                }

                if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 || httpResponse.statusCode == 429 || httpResponse.statusCode >= 500 {
                    markTokenFailed(candidateToken)
                    lastError = URLError(.badServerResponse)
                    continue
                }

                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    markTokenFailed(candidateToken)
                    continue
                }

                let status = (json["status"] as? String)?.lowercased() ?? ""
                if status == "error" {
                    let errorInfo = (json["error_info"] as? String)?.lowercased() ?? ""
                    if errorInfo.contains("not movie") {
                        // Token is healthy! The title simply does not exist for this search query.
                        markTokenSuccess(candidateToken)
                        // DO NOT query backup tokens! Re-throw to advance caller to next param.
                        throw URLError(.resourceUnavailable)
                    }
                    // Real token / auth / ban failure
                    markTokenFailed(candidateToken)
                    lastError = URLError(.userAuthenticationRequired)
                    continue
                }

                guard status == "success", let dataObj = json["data"] as? [String: Any] else {
                    markTokenFailed(candidateToken)
                    continue
                }

                markTokenSuccess(candidateToken)
                return try await parseAllohaData(dataObj)
            } catch let error as URLError where error.code == .resourceUnavailable {
                // Short-circuit: movie not found with a healthy token. Advance caller immediately.
                throw error
            } catch {
                markTokenFailed(candidateToken)
                lastError = error
                continue
            }
        }

        throw lastError
    }

    private func parseAllohaData(_ dataObj: [String: Any]) async throws -> AllohaApiResult {
        let title = dataObj["name"] as? String ?? "Unknown"

        if let seasonsObj = dataObj["seasons"] as? [String: Any] {
            var parsedSeasons: [AllohaSeason] = []

            for (sKey, sValue) in seasonsObj {
                guard let seasonNum = Int(sKey),
                      let sDict = sValue as? [String: Any],
                      let episodesObj = sDict["episodes"] as? [String: Any] else { continue }

                var parsedEpisodes: [AllohaEpisode] = []
                for (eKey, eValue) in episodesObj {
                    guard let episodeNum = Int(eKey),
                          let eDict = eValue as? [String: Any] else { continue }

                    var parsedTrans: [AllohaTranslation] = []
                    var fallbackSubTrans: [AllohaTranslation] = []
                    if let transObj = eDict["translation"] as? [String: Any] {
                        for (tKey, tValue) in transObj {
                            guard let tDict = tValue as? [String: Any],
                                  var iframe = tDict["iframe"] as? String, !iframe.isEmpty else { continue }
                            if iframe.hasPrefix("//") {
                                iframe = "https:" + iframe
                            }
                            iframe = injectTranslationId(tKey, into: iframe)
                            iframe = injectSeasonEpisode(season: seasonNum, episode: episodeNum, into: iframe)
                            let transName = tDict["translation"] as? String ?? tDict["name"] as? String ?? "Unknown"
                            let cleanTitle = normalizedAllohaTranslationName(transName)
                            let finalTitle = cleanTitle.isEmpty ? transName : cleanTitle
                            let lower = finalTitle.lowercased()
                            if lower.contains("субтитр") || lower.contains("subtitle") {
                                fallbackSubTrans.append(AllohaTranslation(id: tKey, name: "Оригинал", iframeUrl: iframe, streamUrl: nil))
                            } else {
                                parsedTrans.append(AllohaTranslation(id: tKey, name: finalTitle, iframeUrl: iframe, streamUrl: nil))
                            }
                        }
                    } else if let transArray = eDict["translation"] as? [[String: Any]] {
                        for (index, tDict) in transArray.enumerated() {
                            guard var iframe = tDict["iframe"] as? String, !iframe.isEmpty else { continue }
                            if iframe.hasPrefix("//") {
                                iframe = "https:" + iframe
                            }
                            // Prefer real translation ID from the element if available,
                            // fall back to numeric index for backward compatibility
                            let translationId = (tDict["id"] as? String)
                                ?? (tDict["translation_id"] as? String)
                                ?? ((tDict["id"] as? Int).map { String($0) })
                                ?? String(index)
                            iframe = injectTranslationId(translationId, into: iframe)
                            iframe = injectSeasonEpisode(season: seasonNum, episode: episodeNum, into: iframe)
                            let transName = tDict["translation"] as? String ?? "Unknown"

                            let cleanTitle = normalizedAllohaTranslationName(transName)
                            let finalTitle = cleanTitle.isEmpty ? transName : cleanTitle
                            let lower = finalTitle.lowercased()
                            if lower.contains("субтитр") || lower.contains("subtitle") {
                                fallbackSubTrans.append(AllohaTranslation(id: translationId, name: "Оригинал", iframeUrl: iframe, streamUrl: nil))
                            } else {
                                parsedTrans.append(AllohaTranslation(id: translationId, name: finalTitle, iframeUrl: iframe, streamUrl: nil))
                            }
                        }
                    }

                    if parsedTrans.isEmpty && !fallbackSubTrans.isEmpty {
                        parsedTrans = fallbackSubTrans
                    }

                    // Порядок озвучек: сортируем так, чтобы русский дубляж был первым
                    if !parsedTrans.isEmpty {
                        parsedTrans.sort { translationRank($0.name) < translationRank($1.name) }
                        parsedEpisodes.append(AllohaEpisode(season: seasonNum, episode: episodeNum, translations: parsedTrans))
                    }
                }

                parsedEpisodes.sort { $0.episode < $1.episode }
                if !parsedEpisodes.isEmpty {
                    parsedSeasons.append(AllohaSeason(season: seasonNum, episodes: parsedEpisodes))
                }
            }

            parsedSeasons.sort { $0.season < $1.season }

            return AllohaApiResult(title: title, isSerial: true, movie: nil, seasons: parsedSeasons)
        } else {
            var parsedTrans: [AllohaTranslation] = []
            var fallbackSubTrans: [AllohaTranslation] = []

            // 1. Проверяем translation_iframe (основной формат Alloha для фильмов)
            if let transIframeDict = dataObj["translation_iframe"] as? [String: Any] {
                for (tKey, tValue) in transIframeDict {
                    var iframe = ""
                    var transName = ""
                    if let tDict = tValue as? [String: Any] {
                        iframe = tDict["iframe"] as? String ?? tDict["url"] as? String ?? ""
                        transName = tDict["name"] as? String ?? tDict["translation"] as? String ?? tDict["title"] as? String ?? ""
                    } else if let str = tValue as? String {
                        iframe = str
                    }
                    guard !iframe.isEmpty else { continue }
                    if iframe.hasPrefix("//") { iframe = "https:" + iframe }
                    iframe = injectTranslationId(tKey, into: iframe)

                    if transName.isEmpty {
                        if let nameDict = (dataObj["translation"] as? [String: Any]) ?? (dataObj["translations"] as? [String: Any]) {
                            if let n = nameDict[tKey] as? String {
                                transName = n
                            } else if let nDict = nameDict[tKey] as? [String: Any] {
                                transName = nDict["translation"] as? String ?? nDict["name"] as? String ?? ""
                            }
                        }
                    }
                    let cleanTitle = normalizedAllohaTranslationName(transName.isEmpty ? "Озвучка \(tKey)" : transName)
                    let finalTitle = cleanTitle.isEmpty ? transName : cleanTitle
                    let lower = finalTitle.lowercased()
                    if lower.contains("субтитр") || lower.contains("subtitle") {
                        fallbackSubTrans.append(AllohaTranslation(id: tKey, name: "Оригинал", iframeUrl: iframe, streamUrl: nil))
                    } else {
                        parsedTrans.append(AllohaTranslation(id: tKey, name: finalTitle, iframeUrl: iframe, streamUrl: nil))
                    }
                }
                // Порядок озвучек сохраняем как отдаёт Alloha (популярные первыми)
            } else if let transIframeArray = dataObj["translation_iframe"] as? [[String: Any]] {
                for (index, tDict) in transIframeArray.enumerated() {
                    guard var iframe = tDict["iframe"] as? String ?? tDict["url"] as? String, !iframe.isEmpty else { continue }
                    if iframe.hasPrefix("//") { iframe = "https:" + iframe }
                    let translationId = (tDict["id"] as? String)
                        ?? (tDict["translation_id"] as? String)
                        ?? ((tDict["id"] as? Int).map { String($0) })
                        ?? String(index)
                    iframe = injectTranslationId(translationId, into: iframe)
                    let transName = tDict["name"] as? String ?? tDict["translation"] as? String ?? tDict["title"] as? String ?? "Озвучка \(index + 1)"
                    let cleanTitle = normalizedAllohaTranslationName(transName)
                    let finalTitle = cleanTitle.isEmpty ? transName : cleanTitle
                    let lower = finalTitle.lowercased()
                    if lower.contains("субтитр") || lower.contains("subtitle") {
                        fallbackSubTrans.append(AllohaTranslation(id: translationId, name: "Оригинал", iframeUrl: iframe, streamUrl: nil))
                    } else {
                        parsedTrans.append(AllohaTranslation(id: translationId, name: finalTitle, iframeUrl: iframe, streamUrl: nil))
                    }
                }
                // Порядок озвучек сохраняем как отдаёт Alloha (популярные первыми)
            }

            // 2. Если translation_iframe не дал результатов, проверяем translation и translations
            if parsedTrans.isEmpty && fallbackSubTrans.isEmpty {
                let transSource = dataObj["translation"] ?? dataObj["translations"]
                if let transObj = transSource as? [String: Any] {
                    for (tKey, tValue) in transObj {
                        guard let tDict = tValue as? [String: Any],
                              var iframe = tDict["iframe"] as? String, !iframe.isEmpty else { continue }
                        if iframe.hasPrefix("//") { iframe = "https:" + iframe }
                        iframe = injectTranslationId(tKey, into: iframe)
                        let transName = tDict["translation"] as? String ?? tDict["name"] as? String ?? "Unknown"
                        let cleanTitle = normalizedAllohaTranslationName(transName)
                        let finalTitle = cleanTitle.isEmpty ? transName : cleanTitle
                        let lower = finalTitle.lowercased()
                        if lower.contains("субтитр") || lower.contains("subtitle") {
                            fallbackSubTrans.append(AllohaTranslation(id: tKey, name: "Оригинал", iframeUrl: iframe, streamUrl: nil))
                        } else {
                            parsedTrans.append(AllohaTranslation(id: tKey, name: finalTitle, iframeUrl: iframe, streamUrl: nil))
                        }
                    }
                    // Порядок озвучек сохраняем как отдаёт Alloha (популярные первыми)
                } else if let transArray = transSource as? [[String: Any]] {
                    for (index, tDict) in transArray.enumerated() {
                        guard var iframe = tDict["iframe"] as? String, !iframe.isEmpty else { continue }
                        if iframe.hasPrefix("//") { iframe = "https:" + iframe }
                        let translationId = (tDict["id"] as? String)
                            ?? (tDict["translation_id"] as? String)
                            ?? ((tDict["id"] as? Int).map { String($0) })
                            ?? String(index)
                        iframe = injectTranslationId(translationId, into: iframe)
                        let transName = tDict["translation"] as? String ?? tDict["name"] as? String ?? "Unknown"
                        let cleanTitle = normalizedAllohaTranslationName(transName)
                        let finalTitle = cleanTitle.isEmpty ? transName : cleanTitle
                        let lower = finalTitle.lowercased()
                        if lower.contains("субтитр") || lower.contains("subtitle") {
                            fallbackSubTrans.append(AllohaTranslation(id: translationId, name: "Оригинал", iframeUrl: iframe, streamUrl: nil))
                        } else {
                            parsedTrans.append(AllohaTranslation(id: translationId, name: finalTitle, iframeUrl: iframe, streamUrl: nil))
                        }
                    }
                    // Порядок озвучек сохраняем как отдаёт Alloha (популярные первыми)
                } else if let transStr = transSource as? String {
                    var iframe = dataObj["iframe"] as? String ?? ""
                    if iframe.hasPrefix("//") { iframe = "https:" + iframe }
                    if !iframe.isEmpty {
                        let cleanTitle = normalizedAllohaTranslationName(transStr)
                        let finalName = cleanTitle.isEmpty ? transStr : cleanTitle
                        let lower = finalName.lowercased()
                        if lower.contains("субтитр") || lower.contains("subtitle") {
                            fallbackSubTrans.append(AllohaTranslation(id: "default", name: "Оригинал", iframeUrl: iframe, streamUrl: nil))
                        } else {
                            parsedTrans.append(AllohaTranslation(id: "default", name: finalName, iframeUrl: iframe, streamUrl: nil))
                        }
                    }
                }
            }

            if parsedTrans.isEmpty && !fallbackSubTrans.isEmpty {
                parsedTrans = fallbackSubTrans
            }

            // 3. Финальный фолбэк — если ничего не найдено, ставим дефолтную дорожку "Основной"
            var defaultIframe = dataObj["iframe"] as? String ?? parsedTrans.first?.iframeUrl ?? ""
            if defaultIframe.hasPrefix("//") { defaultIframe = "https:" + defaultIframe }

            if parsedTrans.isEmpty && !defaultIframe.isEmpty {
                parsedTrans = [
                    AllohaTranslation(id: "default", name: "Основной", iframeUrl: defaultIframe, streamUrl: nil)
                ]
            }

            var movie: AllohaMovie? = nil
            if !parsedTrans.isEmpty {
                parsedTrans.sort { translationRank($0.name) < translationRank($1.name) }
                let movieIframe = defaultIframe.isEmpty ? parsedTrans.first!.iframeUrl : defaultIframe
                movie = AllohaMovie(title: title, iframeUrl: movieIframe, translations: parsedTrans)
            }

            return AllohaApiResult(title: title, isSerial: false, movie: movie, seasons: [])
        }
    }
}
