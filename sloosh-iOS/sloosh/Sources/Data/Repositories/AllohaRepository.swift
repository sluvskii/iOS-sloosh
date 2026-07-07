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
    let left = normalizedAllohaTranslationName(lhs).lowercased()
    let right = normalizedAllohaTranslationName(rhs).lowercased()
    guard !left.isEmpty, !right.isEmpty else { return false }
    
    if left == right {
        return true
    }
    
    // Instead of raw contains, which causes "rudub".contains("dub") to be true,
    // we split into words and check for significant word overlap.
    let leftWords = Set(left.components(separatedBy: " ").filter { $0.count > 2 })
    let rightWords = Set(right.components(separatedBy: " ").filter { $0.count > 2 })
    
    if !leftWords.isEmpty && !rightWords.isEmpty {
        if leftWords.isSubset(of: rightWords) || rightWords.isSubset(of: leftWords) {
            return true
        }
    } else if left.contains(right) || right.contains(left) {
        // Fallback for very short names (like "en", "ru", "qtv")
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
    
    let isRussianOrDub: (String) -> Bool = { name in
        let n = name.lowercased()
        return n.contains("russian") || n.contains("русский") || n.contains("rus") || n == "ru" || n.contains("дубляж") || n.contains("dub")
    }
    
    if isRussianOrDub(left) && isRussianOrDub(right) {
        return true
    }
    
    return false
}

// MARK: - Selective SSL Delegate
// Bypasses certificate validation only for Alloha CDN hosts that use self-signed certs.
// This is intentionally narrow — all other hosts still go through default cert validation.
class AllohaTrustedSessionDelegate: NSObject, @preconcurrency URLSessionDelegate, @unchecked Sendable {
    
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
}

// Legacy alias kept for compilation — remove when all usages are updated
typealias TrustAllSessionDelegate = AllohaTrustedSessionDelegate


final class AllohaRepository: @unchecked Sendable {
    static let shared = AllohaRepository()
    
    /// Reads AllohaToken from Info.plist (set via ALLOHA_TOKEN build variable or Secrets.xcconfig).
    /// Never hardcode this value in source — it lives in the project's build settings instead.
    private static let token: String = {
        if let t = Bundle.main.object(forInfoDictionaryKey: "AllohaToken") as? String, !t.isEmpty, t != "$(ALLOHA_TOKEN)" {
            return t
        }
        // Fallback for local dev without xcconfig: read from environment
        if let t = ProcessInfo.processInfo.environment["ALLOHA_TOKEN"], !t.isEmpty {
            return t
        }
        assertionFailure("AllohaToken not set. Add ALLOHA_TOKEN to your Secrets.xcconfig or build settings.")
        return ""
    }()
    private var token: String { Self.token }
    
    private var catalogCache: [Int: (result: AllohaApiResult, expiresAt: Date)] = [:]
    private let cacheTtl: TimeInterval = 5 * 60 // 5 minutes
    private let cacheQueue = DispatchQueue(label: "ru.neomovies.alloharepo.cache", attributes: .concurrent)

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
                            let transName = tDict["translation"] as? String ?? "Unknown"
                            
                            let cleanTitle = normalizedAllohaTranslationName(transName)
                            parsedTrans.append(AllohaTranslation(id: tKey, name: cleanTitle, iframeUrl: iframe, streamUrl: nil))
                        }
                    } else if let transArray = eDict["translation"] as? [[String: Any]] {
                        for (index, tDict) in transArray.enumerated() {
                            guard var iframe = tDict["iframe"] as? String, !iframe.isEmpty else { continue }
                            if iframe.hasPrefix("//") {
                                iframe = "https:" + iframe
                            }
                            let transName = tDict["translation"] as? String ?? "Unknown"
                            
                            let cleanTitle = normalizedAllohaTranslationName(transName)
                            parsedTrans.append(AllohaTranslation(id: String(index), name: cleanTitle, iframeUrl: iframe, streamUrl: nil))
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
            
            if let transObj = dataObj["translation"] as? [String: Any] {
                for (tKey, tValue) in transObj {
                    guard let tDict = tValue as? [String: Any],
                          var iframe = tDict["iframe"] as? String, !iframe.isEmpty else { continue }
                    if iframe.hasPrefix("//") {
                        iframe = "https:" + iframe
                    }
                    let transName = tDict["translation"] as? String ?? "Unknown"
                    
                    let cleanTitle = normalizedAllohaTranslationName(transName)
                    parsedTrans.append(AllohaTranslation(id: tKey, name: cleanTitle, iframeUrl: iframe, streamUrl: nil))
                }
                parsedTrans.sort { $0.name < $1.name }
            } else if let transArray = dataObj["translation"] as? [[String: Any]] {
                for (index, tDict) in transArray.enumerated() {
                    guard var iframe = tDict["iframe"] as? String, !iframe.isEmpty else { continue }
                    if iframe.hasPrefix("//") {
                        iframe = "https:" + iframe
                    }
                    let transName = tDict["translation"] as? String ?? "Unknown"
                    
                    let cleanTitle = normalizedAllohaTranslationName(transName)
                    parsedTrans.append(AllohaTranslation(id: String(index), name: cleanTitle, iframeUrl: iframe, streamUrl: nil))
                }
                parsedTrans.sort { $0.name < $1.name }
            } else if let transStr = dataObj["translation"] as? String {
                // Если translation пришел как просто строка с названием озвучки
                var iframe = dataObj["iframe"] as? String ?? ""
                if iframe.hasPrefix("//") {
                    iframe = "https:" + iframe
                }
                if !iframe.isEmpty {
                    let cleanTitle = normalizedAllohaTranslationName(transStr)
                    let finalName = cleanTitle.isEmpty ? transStr : cleanTitle
                    parsedTrans.append(AllohaTranslation(id: "default", name: finalName, iframeUrl: iframe, streamUrl: nil))
                }
            }
            
            var movie: AllohaMovie? = nil
            if !parsedTrans.isEmpty {
                // Ищем дефолтный iframe на всякий случай
                var iframe = dataObj["iframe"] as? String ?? parsedTrans.first!.iframeUrl
                if iframe.hasPrefix("//") { iframe = "https:" + iframe }
                movie = AllohaMovie(title: title, iframeUrl: iframe, translations: parsedTrans)
            } else {
                // Фолбэк на старую логику, если нет объекта translation
                var iframe = dataObj["iframe"] as? String ?? ""
                if iframe.hasPrefix("//") { iframe = "https:" + iframe }
                if !iframe.isEmpty {
                    movie = AllohaMovie(title: title, iframeUrl: iframe, translations: [
                        AllohaTranslation(id: "default", name: title, iframeUrl: iframe, streamUrl: nil)
                    ])
                }
            }
            
            var result = AllohaApiResult(title: title, isSerial: false, movie: movie, seasons: [])
            
            if let m = result.movie, let firstIframe = m.translations.first?.iframeUrl {
                let resolver = await AllohaRuntimeResolver()
                if let resolved = try? await resolver.resolve(iframeUrl: firstIframe),
                   let audioVariants = resolved["audioVariants"] as? [[String: Any]], !audioVariants.isEmpty {
                    let newTranslations = audioVariants.enumerated().compactMap { index, variant -> AllohaTranslation? in
                        guard let vTitle = variant["title"] as? String, !vTitle.isEmpty,
                              let streamUrl = variant["url"] as? String, !streamUrl.isEmpty else { return nil }
                        let cleanTitle = normalizedAllohaTranslationName(vTitle)
                        return AllohaTranslation(
                            id: "dub_\(index)",
                            name: cleanTitle.isEmpty ? vTitle : cleanTitle,
                            iframeUrl: m.iframeUrl,
                            streamUrl: nil
                        )
                    }
                    if !newTranslations.isEmpty {
                        let newMovie = AllohaMovie(title: m.title, iframeUrl: m.iframeUrl, translations: newTranslations)
                        result = AllohaApiResult(title: result.title, isSerial: false, movie: newMovie, seasons: [])
                    }
                }
            }
            
            let finalResult = result
            cacheQueue.async(flags: .barrier) {
                self.catalogCache[kpId] = (result: finalResult, expiresAt: Date().addingTimeInterval(self.cacheTtl))
            }
            return finalResult
        }
    }
}
