import Foundation

struct AllohaTranslation: Codable, Hashable, Equatable {
    let id: String
    let name: String
    let iframeUrl: String
    /// Pre-resolved direct stream URL. Set for films where multiple dubs share a single
    /// iframe URL — bypasses runtime re-resolution and avoids name-matching ambiguity.
    let streamUrl: String?
}

struct AllohaEpisode: Codable, Hashable, Equatable {
    let season: Int
    let episode: Int
    let translations: [AllohaTranslation]
}

struct AllohaSeason: Codable, Hashable, Equatable {
    let season: Int
    let episodes: [AllohaEpisode]
}

struct AllohaMovie: Codable, Hashable, Equatable {
    let title: String
    let iframeUrl: String
    let translations: [AllohaTranslation]
}

struct AllohaApiResult: Codable, Hashable, Equatable {
    let title: String
    let isSerial: Bool
    let movie: AllohaMovie?
    let seasons: [AllohaSeason]
}

extension AllohaApiResult {
    var allTranslationNames: [String] {
        if isSerial {
            // Берём порядок из первого эпизода первого сезона (Alloha возвращает популярные первыми)
            // затем добавляем любые дополнительные имена из других эпизодов
            var names: [String] = []
            var seen = Set<String>()
            for season in seasons {
                for episode in season.episodes {
                    for t in episode.translations {
                        if seen.insert(t.name).inserted {
                            names.append(t.name)
                        }
                    }
                }
            }
            return names
        } else if let movie = movie {
            return movie.translations.map { $0.name }
        }
        return []
    }
}

func injectTranslationId(_ id: String, into urlString: String) -> String {
    guard var comps = URLComponents(string: urlString) else { return urlString }
    var items = comps.queryItems ?? []
    items.removeAll { $0.name == "translation" }
    items.append(URLQueryItem(name: "translation", value: id))
    comps.queryItems = items
    return comps.string ?? urlString
}

func injectSeasonEpisode(season: Int, episode: Int, into urlString: String) -> String {
    guard var comps = URLComponents(string: urlString) else { return urlString }
    var items = comps.queryItems ?? []
    items.removeAll { $0.name == "season" || $0.name == "episode" }
    items.append(URLQueryItem(name: "season", value: String(season)))
    items.append(URLQueryItem(name: "episode", value: String(episode)))
    comps.queryItems = items
    return comps.string ?? urlString
}

func normalizedAllohaTranslationName(_ raw: String?) -> String {
    guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
        return ""
    }

    value = value
        .replacingOccurrences(of: "(?i)\\b(?:AC3|E-AC3|EAC3|DDP|DD|DTS-HD|DTS|TrueHD|AAC|FLAC|MP3|PCM|LPCM)\\s*(?:5[.]?1|7[.]?1|2[.]?0|51)?(?:\\s*@\\s*\\d+\\s*(?:kbps|kbit|кбит/с|кб/с)?)?", with: "", options: .regularExpression)
        .replacingOccurrences(of: "(?i)@\\s*\\d+\\s*(?:kbps|kbit|кбит/с|кб/с)?", with: "", options: .regularExpression)
        .replacingOccurrences(of: "(?i)\\b\\d+\\s*(?:kbps|kbit|кбит/с|кб/с)\\b", with: "", options: .regularExpression)
        .replacingOccurrences(of: "(?i)\\b(?:Blu-ray(?:\\s*CEE)?|BDRip|WEB-DL|HDTV|Line)\\b", with: "", options: .regularExpression)
        .replacingOccurrences(of: "(?i)\\((?:Russian|Ukrainian|Kazakh|English|Uzbek|Turkish|Georgian|Japanese|Korean|Chinese)\\)", with: "", options: .regularExpression)
        .replacingOccurrences(of: "(?i)\\bDUB\\b", with: "Дубляж", options: .regularExpression)
        .replacingOccurrences(of: "(?i)\\bMVO\\b", with: "Многоголосый", options: .regularExpression)
        .replacingOccurrences(of: "(?i)\\bDVO\\b", with: "Двухголосый", options: .regularExpression)
        .replacingOccurrences(of: "(?i)\\bAVO\\b", with: "Авторский", options: .regularExpression)
        .replacingOccurrences(of: "(?i)\\bПМ\\b", with: "Проф. многоголосый", options: .regularExpression)
        .replacingOccurrences(of: "(?i)\\bПД\\b", with: "Проф. двухголосый", options: .regularExpression)
        .replacingOccurrences(of: "(?i)\\bЛМ\\b", with: "Люб. многоголосый", options: .regularExpression)
        .replacingOccurrences(of: "(?i)\\bЛД\\b", with: "Люб. двухголосый", options: .regularExpression)
        .replacingOccurrences(of: "[", with: " ")
        .replacingOccurrences(of: "]", with: " ")
        .replacingOccurrences(of: "(", with: " ")
        .replacingOccurrences(of: ")", with: " ")
        .replacingOccurrences(of: "|", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)

    while value.hasPrefix("-") || value.hasPrefix(",") || value.hasPrefix("–") || value.hasPrefix("—") {
        value = String(value.dropFirst()).trimmingCharacters(in: .whitespaces)
    }
    while value.hasSuffix("-") || value.hasSuffix(",") || value.hasSuffix("–") || value.hasSuffix("—") {
        value = String(value.dropLast()).trimmingCharacters(in: .whitespaces)
    }

    value = value
        .replacingOccurrences(of: "(?i)\\bHDrezka\\s+St(?:\\.|\\b)", with: "HDrezka Studio", options: .regularExpression)
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)

    return value
}

func detectLanguageTag(in text: String) -> String? {
    let lower = text.lowercased()
    if lower.contains("украин") || lower.contains("ukrain") || lower.contains("укр") || lower.contains("ukr") {
        return "ukr"
    }
    if lower.contains("казах") || lower.contains("kazakh") || lower.contains("каз") || lower.contains("kaz") {
        return "kaz"
    }
    if lower.contains("узбек") || lower.contains("uzbek") || lower.contains("узб") || lower.contains("uzb") {
        return "uzb"
    }
    if lower.contains("оригинал") || lower.contains("original") || lower.contains("english") || lower.contains("английск") || lower.contains("eng") || lower == "en" {
        return "eng"
    }
    if lower.contains("грузин") || lower.contains("georgian") || lower.contains("geo") {
        return "geo"
    }
    if lower.contains("турец") || lower.contains("turkish") || lower.contains("turk") {
        return "tur"
    }
    if lower.contains("япон") || lower.contains("japan") || lower.contains("jap") {
        return "jap"
    }
    if lower.contains("корей") || lower.contains("korean") || lower.contains("kor") {
        return "kor"
    }
    if lower.contains("китай") || lower.contains("chinese") || lower.contains("chi") {
        return "chi"
    }
    if lower.contains("русск") || lower.contains("rus") {
        return "rus"
    }
    return nil
}

func isTranslationNoiseWord(_ word: String) -> Bool {
    let noise: Set<String> = [
        "studio", "студия", "дубляж", "дублированный", "дублирование", "полное",
        "многоголосый", "двухголосый", "одноголосый", "авторский", "закадровый", "озвучка",
        "профессиональный", "проф", "любительский", "люб", "production", "films", "film",
        "team", "voice", "line", "перевод", "голос", "звук", "чистый", "версия", "театральная",
        "расширенная", "режиссерская", "режиссёрская"
    ]
    return noise.contains(word.lowercased())
}

func allohaTranslationNamesMatch(_ lhs: String?, _ rhs: String?, exactOnly: Bool = false) -> Bool {
    guard let lhsRaw = lhs?.trimmingCharacters(in: .whitespacesAndNewlines), !lhsRaw.isEmpty,
          let rhsRaw = rhs?.trimmingCharacters(in: .whitespacesAndNewlines), !rhsRaw.isEmpty else {
        return false
    }
    
    let left = normalizedAllohaTranslationName(lhsRaw).lowercased()
    let right = normalizedAllohaTranslationName(rhsRaw).lowercased()
    
    if left == right {
        return true
    }
    
    // Strict language mismatch check on raw strings
    let langLeft = detectLanguageTag(in: lhsRaw)
    let langRight = detectLanguageTag(in: rhsRaw)
    
    // If one side specifies a non-Russian language (e.g. Ukrainian, Kazakh, English),
    // the other side MUST specify the exact same language!
    if let langLeft, langLeft != "rus" {
        if langRight != langLeft { return false }
    }
    if let langRight, langRight != "rus" {
        if langLeft != langRight { return false }
    }
    if let langLeft, let langRight, langLeft != langRight {
        return false
    }
    
    // Both are Ukrainian, Kazakh, Uzbek or another non-Russian regional language:
    if let langLeft, let langRight, langLeft == langRight && langLeft != "rus" {
        return true
    }

    let isOriginalOrEnglish: (String) -> Bool = { name in
        let n = name.lowercased()
        return n.contains("original") || n.contains("оригинал") || n.contains("english") || n.contains("английский") || n.contains("eng") || n == "en"
    }
    
    if isOriginalOrEnglish(left) && isOriginalOrEnglish(right) {
        return true
    }
    
    if exactOnly {
        return false
    }
    
    // Check for specific studio names
    let studios = [
        "red head sound", "rhs", "flarrow", "lostfilm", "tvshows", "newstudio", "newcomers",
        "alexfilm", "кубик", "hdrezka", "rezka", "baibako", "jaskier", "vsi", "iron voice",
        "кураж бамбей", "лостфильм", "ньюстудио"
    ]
    let leftStudios = studios.filter { left.contains($0) }
    let rightStudios = studios.filter { right.contains($0) }
    
    if !leftStudios.isEmpty && !rightStudios.isEmpty {
        // Both mention studios: they MUST share at least one studio
        let shared = Set(leftStudios).intersection(Set(rightStudios))
        if shared.isEmpty {
            return false
        }
        let leftHasDub = left.contains("дубл")
        let rightHasDub = right.contains("дубл")
        if leftHasDub != rightHasDub {
            return false
        }
        return true
    }
    
    // If one specifies an exclusive third-party studio and the other doesn't, they don't match
    let exclusiveStudios = [
        "red head sound", "rhs", "flarrow", "lostfilm", "tvshows", "newstudio", "newcomers",
        "alexfilm", "кубик", "baibako", "jaskier", "vsi", "iron voice", "кураж бамбей"
    ]
    let leftHasExclusive = exclusiveStudios.contains(where: { left.contains($0) })
    let rightHasExclusive = exclusiveStudios.contains(where: { right.contains($0) })
    if leftHasExclusive != rightHasExclusive {
        return false
    }
    
    // Handle Dubbing vs Voiceover:
    let leftHasDub = left.contains("дубл")
    let rightHasDub = right.contains("дубл")
    
    if leftHasDub && rightHasDub {
        if let langLeft, let langRight {
            return langLeft == langRight
        }
        return true
    }
    
    // Helper to strip generic studio/dub noise words
    let noiseWords = [
        "studio", "студия", "дубляж", "дублированный", "дублирование", "полное",
        "многоголосый", "двухголосый", "одноголосый", "авторский", "закадровый", "озвучка",
        "профессиональный", "проф", "любительский", "люб", "production", "films", "film",
        "team", "voice", "line", "перевод", "голос", "звук", "чистый", "версия", "театральная",
        "расширенная", "режиссерская", "режиссёрская"
    ]
    let stripNoise: (String) -> String = { name in
        var n = name.lowercased()
        for word in noiseWords {
            n = n.replacingOccurrences(of: "(?i)\\b\(word)\\b", with: "", options: .regularExpression)
        }
        return n.replacingOccurrences(of: "[-–—,]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    let leftCore = stripNoise(left)
    let rightCore = stripNoise(right)
    
    if !leftCore.isEmpty && leftCore == rightCore {
        return true
    }
    
    // Distinctive author / studio word matching (e.g. "Есарев", "Сербин", "Гаврилов")
    let extractDistinctiveWords: (String) -> [String] = { s in
        s.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 4 && !isTranslationNoiseWord($0) }
    }
    
    let rightWords = extractDistinctiveWords(right)
    let leftWords = extractDistinctiveWords(left)
    
    if !rightWords.isEmpty {
        let hasSharedDistinctive = rightWords.contains { rw in
            leftWords.contains { lw in lw == rw || lw.contains(rw) || rw.contains(lw) }
        }
        if hasSharedDistinctive {
            return true
        }
    }
    
    // Substring check on core if long enough
    if leftCore.count >= 4 && rightCore.count >= 4 {
        if leftCore.contains(rightCore) || rightCore.contains(leftCore) {
            return true
        }
    }
    
    return false
}

/// Находит наиболее подходящий вариант аудиодорожки из audioVariants для заданной целевой озвучки
func findMatchingAudioVariant(
    in audioVariants: [[String: Any]],
    for targetVoice: String?,
    isDedicatedIframe: Bool = false
) -> [String: Any]? {
    guard !audioVariants.isEmpty else { return nil }
    guard let target = targetVoice?.trimmingCharacters(in: .whitespacesAndNewlines), !target.isEmpty else {
        return audioVariants.first(where: { (($0["url"] as? String) ?? "").isEmpty == false })
    }

    // 1. Точное совпадение по названию
    if let match = audioVariants.first(where: { allohaTranslationNamesMatch($0["title"] as? String, target, exactOnly: true) }) {
        return match
    }

    // 2. Нестрогое / студийное / авторское совпадение
    if let match = audioVariants.first(where: { allohaTranslationNamesMatch($0["title"] as? String, target, exactOnly: false) }) {
        return match
    }

    // 3. Совпадение по языковому тегу (Украинский, Казахский, Английский и т.д.)
    if let targetLang = detectLanguageTag(in: target) {
        if let match = audioVariants.first(where: {
            guard let title = $0["title"] as? String else { return false }
            return detectLanguageTag(in: title) == targetLang
        }) {
            return match
        }
    }

    // 4. Поиск по значимым словам (фамилия автора/студии: «Есарев», «Сербин», «Гаврилов»)
    let targetWords = target
        .lowercased()
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { $0.count >= 4 && !isTranslationNoiseWord($0) }
    if !targetWords.isEmpty {
        for word in targetWords {
            if let match = audioVariants.first(where: {
                let t = (($0["title"] as? String) ?? "").lowercased()
                return t.contains(word)
            }) {
                return match
            }
        }
    }

    // 5. Для выделенного iframe (загруженного под конкретную озвучку translation=ID):
    // Если целевая озвучка — НЕ русский дубляж, но вариант 0 — русский дубляж,
    // а в iframe есть вариант 1 — выбираем вариант 1 (это именно та озвучка, под которую создан iframe!)
    if isDedicatedIframe && audioVariants.count > 1 {
        let isTargetDub = target.lowercased().contains("дубл")
        if !isTargetDub {
            if let nonDub = audioVariants.first(where: {
                let t = (($0["title"] as? String) ?? "").lowercased()
                return !t.contains("дубл") && !t.contains("dub")
            }) {
                return nonDub
            }
            return audioVariants[1]
        }
    }

    return nil
}


// Bypasses certificate validation only for Alloha CDN hosts that use self-signed certs.
// This is intentionally narrow — all other hosts still go through default cert validation.
class AllohaTrustedSessionDelegate: NSObject, @preconcurrency URLSessionDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    
    private static let trustedHosts: Set<String> = [
        "alloha.tv", "alloh.tv",
        "feeds.alloha.tv", "static.alloha.tv",
        "cdn.alloha.tv",
        "vgif.ru", "allohalive.ru",
        "videocdn.tv", "dhklxm.ru", "cdnhl.ru"
    ]
    
    @MainActor
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping @MainActor @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        let host = challenge.protectionSpace.host.lowercased()
        let isTrustedHost = Self.trustedHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) })
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
    
    // Dynamic stream tokens delivered securely from the backend API (zero tokens in client binary)
    private var remoteTokens: [String] = []
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
        let (cachedTokens, shouldRefresh) = tokenQueue.sync {
            let tokens = self.remoteTokens
            let expired = self.lastFetchDate.map { now.timeIntervalSince($0) > self.tokensFetchTtl } ?? true
            return (tokens, tokens.isEmpty || expired)
        }

        if !shouldRefresh && !cachedTokens.isEmpty {
            return getHealthyCandidateTokens()
        }

        let fetchTask: Task<[String], Never> = tokenQueue.sync {
            if let inFlight = self.activeFetchTask {
                return inFlight
            }
            let task = Task<[String], Never> {
                do {
                    let tokens = try await MoviesApi.shared.getStreamTokens()
                    if !tokens.isEmpty {
                        self.tokenQueue.async(flags: .barrier) {
                            self.remoteTokens = tokens
                            self.lastFetchDate = Date()
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
                return self.tokenQueue.sync { self.remoteTokens }
            }
            self.activeFetchTask = task
            return task
        }

        _ = await fetchTask.value
        tokenQueue.async(flags: .barrier) {
            self.activeFetchTask = nil
        }

        return getHealthyCandidateTokens()
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
    
    private var catalogCache: [Int: (result: AllohaApiResult, expiresAt: Date)] = [:]
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
        let delegate = TrustAllSessionDelegate()
        return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }()
    
    func fetchByKpId(
        kpId: Int,
        tmdbId: Int? = nil,
        imdbId: String? = nil,
        title: String? = nil,
        originalTitle: String? = nil,
        year: Int? = nil
    ) async throws -> AllohaApiResult {
        let cacheKey = kpId > 0 ? kpId : (tmdbId ?? 0)
        if cacheKey > 0 {
            let cached = cacheQueue.sync { catalogCache[cacheKey] }
            if let cached = cached, cached.expiresAt > Date() {
                return cached.result
            }
        }

        func saveToCache(_ result: AllohaApiResult) {
            if cacheKey > 0 {
                cacheQueue.async(flags: .barrier) { [weak self] in
                    guard let self = self else { return }
                    self.catalogCache[cacheKey] = (result: result, expiresAt: Date().addingTimeInterval(self.cacheTtl))
                }
            }
        }

        // 1. Try KP ID first if positive
        if kpId > 0 {
            if let result = try? await performAllohaQuery(params: ["kp": String(kpId)]) {
                saveToCache(result)
                return result
            }
        }

        // 2. Fallback to TMDB ID if available
        if let tmdb = tmdbId, tmdb > 0 {
            if let result = try? await performAllohaQuery(params: ["tmdb": String(tmdb)]) {
                saveToCache(result)
                return result
            }
        }

        // 3. Fallback to IMDB ID if available (crucial when provider has id_tmdb = null)
        if let imdb = imdbId?.trimmingCharacters(in: .whitespacesAndNewlines), !imdb.isEmpty {
            if let result = try? await performAllohaQuery(params: ["imdb": imdb]) {
                saveToCache(result)
                return result
            }
        }

        // 4. Fallback to Russian title + year
        if let cleanTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !cleanTitle.isEmpty,
           !cleanTitle.hasPrefix("Без названия") {
            if let yr = year, yr > 1900 {
                if let result = try? await performAllohaQuery(params: ["name": cleanTitle, "year": String(yr)]) {
                    saveToCache(result)
                    return result
                }
            }
            if let result = try? await performAllohaQuery(params: ["name": cleanTitle]) {
                saveToCache(result)
                return result
            }
        }

        // 5. Fallback to Original title + year
        if let cleanOrig = originalTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !cleanOrig.isEmpty,
           cleanOrig != title {
            if let yr = year, yr > 1900 {
                if let result = try? await performAllohaQuery(params: ["name": cleanOrig, "year": String(yr)]) {
                    saveToCache(result)
                    return result
                }
            }
            if let result = try? await performAllohaQuery(params: ["name": cleanOrig]) {
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
        year: Int? = nil
    ) async throws -> AllohaApiResult {
        let validKp = (kpId ?? 0) > 0 ? (kpId ?? 0) : 0
        let validTmdb = (tmdbId ?? 0) > 0 ? tmdbId : nil
        return try await fetchByKpId(
            kpId: validKp,
            tmdbId: validTmdb,
            imdbId: imdbId,
            title: title,
            originalTitle: originalTitle,
            year: year
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
            guard var comps = URLComponents(string: "https://api.alloha.tv/") else {
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
                    if let transObj = eDict["translation"] as? [String: Any] {
                        for (tKey, tValue) in transObj {
                            guard let tDict = tValue as? [String: Any],
                                  var iframe = tDict["iframe"] as? String, !iframe.isEmpty else { continue }
                            if iframe.hasPrefix("//") {
                                iframe = "https:" + iframe
                            }
                            iframe = injectTranslationId(tKey, into: iframe)
                            iframe = injectSeasonEpisode(season: seasonNum, episode: episodeNum, into: iframe)
                            let transName = tDict["translation"] as? String ?? "Unknown"

                            let cleanTitle = normalizedAllohaTranslationName(transName)
                            let lower = cleanTitle.lowercased()
                            if !lower.contains("субтитр") && !lower.contains("subtitle") {
                                parsedTrans.append(AllohaTranslation(id: tKey, name: cleanTitle, iframeUrl: iframe, streamUrl: nil))
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
                            let lower = cleanTitle.lowercased()
                            if !lower.contains("субтитр") && !lower.contains("subtitle") {
                                parsedTrans.append(AllohaTranslation(id: translationId, name: cleanTitle, iframeUrl: iframe, streamUrl: nil))
                            }
                        }
                    }

                    // Порядок озвучек сохраняем как отдаёт Alloha (популярные первыми)
                    if !parsedTrans.isEmpty {
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
                    let lower = cleanTitle.lowercased()
                    if !lower.contains("субтитр") && !lower.contains("subtitle") {
                        parsedTrans.append(AllohaTranslation(id: tKey, name: cleanTitle, iframeUrl: iframe, streamUrl: nil))
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
                    let lower = cleanTitle.lowercased()
                    if !lower.contains("субтитр") && !lower.contains("subtitle") {
                        parsedTrans.append(AllohaTranslation(id: translationId, name: cleanTitle, iframeUrl: iframe, streamUrl: nil))
                    }
                }
                // Порядок озвучек сохраняем как отдаёт Alloha (популярные первыми)
            }

            // 2. Если translation_iframe не дал результатов, проверяем translation и translations
            if parsedTrans.isEmpty {
                let transSource = dataObj["translation"] ?? dataObj["translations"]
                if let transObj = transSource as? [String: Any] {
                    for (tKey, tValue) in transObj {
                        guard let tDict = tValue as? [String: Any],
                              var iframe = tDict["iframe"] as? String, !iframe.isEmpty else { continue }
                        if iframe.hasPrefix("//") { iframe = "https:" + iframe }
                        iframe = injectTranslationId(tKey, into: iframe)
                        let transName = tDict["translation"] as? String ?? tDict["name"] as? String ?? "Unknown"
                        let cleanTitle = normalizedAllohaTranslationName(transName)
                        let lower = cleanTitle.lowercased()
                        if !lower.contains("субтитр") && !lower.contains("subtitle") {
                            parsedTrans.append(AllohaTranslation(id: tKey, name: cleanTitle, iframeUrl: iframe, streamUrl: nil))
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
                        let lower = cleanTitle.lowercased()
                        if !lower.contains("субтитр") && !lower.contains("subtitle") {
                            parsedTrans.append(AllohaTranslation(id: translationId, name: cleanTitle, iframeUrl: iframe, streamUrl: nil))
                        }
                    }
                    // Порядок озвучек сохраняем как отдаёт Alloha (популярные первыми)
                } else if let transStr = transSource as? String {
                    var iframe = dataObj["iframe"] as? String ?? ""
                    if iframe.hasPrefix("//") { iframe = "https:" + iframe }
                    if !iframe.isEmpty {
                        let cleanTitle = normalizedAllohaTranslationName(transStr)
                        let lower = cleanTitle.lowercased()
                        if !lower.contains("субтитр") && !lower.contains("subtitle") {
                            let finalName = cleanTitle.isEmpty ? transStr : cleanTitle
                            parsedTrans.append(AllohaTranslation(id: "default", name: finalName, iframeUrl: iframe, streamUrl: nil))
                        }
                    }
                }
            }

            // 3. Если для фильма доступен один мастер-iframe со скрытыми bnsi audioVariants
            var defaultIframe = dataObj["iframe"] as? String ?? parsedTrans.first?.iframeUrl ?? ""
            if defaultIframe.hasPrefix("//") { defaultIframe = "https:" + defaultIframe }

            if parsedTrans.count <= 1 && !defaultIframe.isEmpty {
                let resolver = await AllohaRuntimeResolver()
                if let resolved = try? await resolver.resolve(iframeUrl: defaultIframe),
                   let audioVariants = resolved["audioVariants"] as? [[String: Any]],
                   audioVariants.count > 1 {
                    var dynamicTrans: [AllohaTranslation] = []
                    for (idx, variant) in audioVariants.enumerated() {
                        let vTitle = (variant["title"] as? String) ?? "Озвучка \(idx + 1)"
                        let vUrl = (variant["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                        let cleanTitle = normalizedAllohaTranslationName(vTitle)
                        let lower = cleanTitle.lowercased()
                        if !lower.contains("субтитр") && !lower.contains("subtitle") {
                            dynamicTrans.append(AllohaTranslation(id: "\(idx)", name: cleanTitle, iframeUrl: defaultIframe, streamUrl: vUrl))
                        }
                    }
                    if !dynamicTrans.isEmpty {
                        parsedTrans = dynamicTrans
                    }
                }
            }

            // 4. Финальный фолбэк — если ничего не найдено, ставим дефолтную дорожку "Основной"
            if parsedTrans.isEmpty && !defaultIframe.isEmpty {
                parsedTrans = [
                    AllohaTranslation(id: "default", name: "Основной", iframeUrl: defaultIframe, streamUrl: nil)
                ]
            }

            var movie: AllohaMovie? = nil
            if !parsedTrans.isEmpty {
                let movieIframe = defaultIframe.isEmpty ? parsedTrans.first!.iframeUrl : defaultIframe
                movie = AllohaMovie(title: title, iframeUrl: movieIframe, translations: parsedTrans)
            }

            return AllohaApiResult(title: title, isSerial: false, movie: movie, seasons: [])
        }
    }
}
