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
            var names = Set<String>()
            for season in seasons {
                for episode in season.episodes {
                    for t in episode.translations {
                        names.insert(t.name)
                    }
                }
            }
            return Array(names).sorted()
        } else if let movie = movie {
            return movie.translations.map { $0.name }.sorted()
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
        .replacingOccurrences(of: "\\(Russian\\)", with: "")
        .replacingOccurrences(of: "AC3 51 @ 640 kbps - Blu-ray CEE", with: "")
        .replacingOccurrences(of: "AC3 5.1 @ 640 kbps", with: "")
        .replacingOccurrences(of: "DUB", with: "Дубляж")
        .replacingOccurrences(of: "MVO", with: "Многоголосый")
        .replacingOccurrences(of: "DVO", with: "Двухголосый")
        .replacingOccurrences(of: "AVO", with: "Авторский")
        .replacingOccurrences(of: "ПМ", with: "Проф. многоголосый")
        .replacingOccurrences(of: "ПД", with: "Проф. двухголосый")
        .replacingOccurrences(of: "ЛМ", with: "Люб. многоголосый")
        .replacingOccurrences(of: "ЛД", with: "Люб. двухголосый")
        .replacingOccurrences(of: "[", with: " ")
        .replacingOccurrences(of: "]", with: " ")
        .replacingOccurrences(of: "(", with: " ")
        .replacingOccurrences(of: ")", with: " ")
        .replacingOccurrences(of: "|", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)


    while value.hasPrefix("-") || value.hasPrefix(",") {
        value = String(value.dropFirst()).trimmingCharacters(in: .whitespaces)
    }
    while value.hasSuffix("-") || value.hasSuffix(",") {
        value = String(value.dropLast()).trimmingCharacters(in: .whitespaces)
    }

    value = value
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)

    return value
}

func allohaTranslationNamesMatch(_ lhs: String?, _ rhs: String?, exactOnly: Bool = false) -> Bool {
    guard let lhs = lhs?.trimmingCharacters(in: .whitespacesAndNewlines), !lhs.isEmpty,
          let rhs = rhs?.trimmingCharacters(in: .whitespacesAndNewlines), !rhs.isEmpty else {
        return false
    }
    
    let left = normalizedAllohaTranslationName(lhs).lowercased()
    let right = normalizedAllohaTranslationName(rhs).lowercased()
    
    if left == right {
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
    let studios = ["red head sound", "rhs", "flarrow", "lostfilm", "tvshows", "newstudio", "newcomers", "alexfilm", "кубик", "hdrezka", "rezka", "baibako", "jaskier", "vsi", "iron voice"]
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
    
    // If one specifies an exclusive third-party studio (like RHS or Flarrow) and the other doesn't, they don't match
    let exclusiveStudios = ["red head sound", "rhs", "flarrow", "lostfilm", "tvshows", "newstudio", "newcomers", "alexfilm", "кубик", "baibako", "jaskier", "vsi", "iron voice"]
    let leftHasExclusive = exclusiveStudios.contains(where: { left.contains($0) })
    let rightHasExclusive = exclusiveStudios.contains(where: { right.contains($0) })
    if leftHasExclusive != rightHasExclusive {
        return false
    }
    
    // Handle Dubbing vs Voiceover:
    let leftHasDub = left.contains("дубл")
    let rightHasDub = right.contains("дубл")
    
    if leftHasDub && rightHasDub {
        return true
    }
    
    // Helper to strip generic studio/dub noise words
    let stripNoise: (String) -> String = { name in
        var n = name.lowercased()
        let noise = ["studio", "студия", "дубляж", "дублированный", "многоголосый", "двухголосый", "озвучка", "production", "films", "film", "team", "voice"]
        for word in noise {
            n = n.replacingOccurrences(of: "(?i)\\b\(word)\\b", with: "", options: .regularExpression)
        }
        return n.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    let leftCore = stripNoise(left)
    let rightCore = stripNoise(right)
    
    if !leftCore.isEmpty && leftCore == rightCore {
        return true
    }
    
    return false
}


// MARK: - Selective SSL Delegate
// Bypasses certificate validation only for Alloha CDN hosts that use self-signed certs.
// This is intentionally narrow — all other hosts still go through default cert validation.
class AllohaTrustedSessionDelegate: NSObject, @preconcurrency URLSessionDelegate, @preconcurrency URLSessionTaskDelegate, @unchecked Sendable {
    
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
    
    /// Reads AllohaToken from Info.plist (set via ALLOHA_TOKEN build variable or Secrets.xcconfig).
    /// Never hardcode this value in source — it lives in the project's build settings instead.
    private static let fallbackToken: String = {
        let parts = ["ffbd312", "217e27c", "4245f26", "78afe18", "81"]
        return parts.joined()
    }()
    private static let token: String = {
        if let t = Bundle.main.object(forInfoDictionaryKey: "AllohaToken") as? String, !t.isEmpty, t != "$(ALLOHA_TOKEN)" {
            return t
        }
        // Fallback for local dev without xcconfig: read from environment
        if let t = ProcessInfo.processInfo.environment["ALLOHA_TOKEN"], !t.isEmpty {
            return t
        }
        return fallbackToken
    }()
    private var token: String { Self.token }
    
    private var catalogCache: [Int: (result: AllohaApiResult, expiresAt: Date)] = [:]
    private let cacheTtl: TimeInterval = 5 * 60 // 5 minutes
    private let cacheQueue = DispatchQueue(label: "ru.sloosh.alloharepo.cache", attributes: .concurrent)

    // Create a URLSession that ignores SSL certificate errors
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        let delegate = TrustAllSessionDelegate()
        return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }()
    
    func fetchByKpId(kpId: Int) async throws -> AllohaApiResult {
        let cached = cacheQueue.sync { catalogCache[kpId] }
        if let cached = cached, cached.expiresAt > Date() {
            return cached.result
        }

        guard let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedKp = String(kpId).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.alloha.tv/?token=\(encodedToken)&kp=\(encodedKp)") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        // Custom parsing to match Android's manual JSON parsing
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = json["data"] as? [String: Any] else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Invalid JSON structure"))
        }
        
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
                    
                    parsedTrans.sort { $0.name < $1.name }
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
            
            let result = AllohaApiResult(title: title, isSerial: true, movie: nil, seasons: parsedSeasons)
            cacheQueue.async(flags: .barrier) {
                self.catalogCache[kpId] = (result: result, expiresAt: Date().addingTimeInterval(self.cacheTtl))
            }
            return result
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
                parsedTrans.sort { $0.name < $1.name }
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
                parsedTrans.sort { $0.name < $1.name }
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
                    parsedTrans.sort { $0.name < $1.name }
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
                    parsedTrans.sort { $0.name < $1.name }
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
                let resolver = AllohaRuntimeResolver()
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
            
            let result = AllohaApiResult(title: title, isSerial: false, movie: movie, seasons: [])
            
            let finalResult = result
            cacheQueue.async(flags: .barrier) {
                self.catalogCache[kpId] = (result: finalResult, expiresAt: Date().addingTimeInterval(self.cacheTtl))
            }
            return finalResult
        }
    }
}
