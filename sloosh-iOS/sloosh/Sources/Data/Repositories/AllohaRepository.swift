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
        .lowercased()
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)

    return value
}

func allohaTranslationNamesMatch(_ lhs: String?, _ rhs: String?, exactOnly: Bool = false) -> Bool {
    let left = normalizedAllohaTranslationName(lhs)
    let right = normalizedAllohaTranslationName(rhs)
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

class TrustAllSessionDelegate: NSObject, @preconcurrency URLSessionDelegate, @unchecked Sendable {
    @MainActor
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping @MainActor @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let serverTrust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
            return
        }
        completionHandler(.performDefaultHandling, nil)
    }
}

class AllohaRepository {
    static let shared = AllohaRepository()
    private let token = "ffbd312217e27c4245f2678afe1881"
    
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
            
            // For series, the API often returns translations that aren't actually in the video player.
            // We resolve the first episode's iframe to get the definitive audioVariants list,
            // and filter out API translations that don't match anything in the player.
            if let firstIframe = parsedSeasons.first?.episodes.first?.translations.first?.iframeUrl {
                let resolver = AllohaRuntimeResolver()
                if let resolved = try? await resolver.resolve(iframeUrl: firstIframe),
                   let audioVariants = resolved["audioVariants"] as? [[String: Any]], !audioVariants.isEmpty {
                    
                    let validVariantTitles = audioVariants.compactMap { $0["title"] as? String }
                    
                    var filteredSeasons: [AllohaSeason] = []
                    for season in parsedSeasons {
                        var filteredEpisodes: [AllohaEpisode] = []
                        for episode in season.episodes {
                            let filteredTranslations = episode.translations.filter { apiTrans in
                                validVariantTitles.contains { variantTitle in
                                    allohaTranslationNamesMatch(apiTrans.name, variantTitle)
                                }
                            }
                            // Only add the episode if it still has translations
                            if !filteredTranslations.isEmpty {
                                filteredEpisodes.append(AllohaEpisode(season: episode.season, episode: episode.episode, translations: filteredTranslations))
                            } else {
                                // If filtering removed everything, keep the original translations as a safety fallback
                                filteredEpisodes.append(episode)
                            }
                        }
                        if !filteredEpisodes.isEmpty {
                            filteredSeasons.append(AllohaSeason(season: season.season, episodes: filteredEpisodes))
                        }
                    }
                    parsedSeasons = filteredSeasons
                }
            }
            
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
                let resolver = AllohaRuntimeResolver()
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
                            streamUrl: streamUrl  // pre-resolved: used directly at playback, no re-matching needed
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
