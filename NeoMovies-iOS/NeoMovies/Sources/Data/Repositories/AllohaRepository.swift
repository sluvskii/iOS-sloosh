import Foundation

struct AllohaTranslation: Codable {
    let id: String
    let name: String
    let iframeUrl: String
}

struct AllohaEpisode: Codable {
    let season: Int
    let episode: Int
    let translations: [AllohaTranslation]
}

struct AllohaSeason: Codable {
    let season: Int
    let episodes: [AllohaEpisode]
}

struct AllohaMovie: Codable {
    let title: String
    let iframeUrl: String
    let translations: [AllohaTranslation]
}

struct AllohaApiResult: Codable {
    let title: String
    let isSerial: Bool
    let movie: AllohaMovie?
    let seasons: [AllohaSeason]
}

class TrustAllSessionDelegate: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let serverTrust = challenge.protectionSpace.serverTrust {
            // Bypass SSL certificate validation for Alloha API
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
            return
        }
        completionHandler(.performDefaultHandling, nil)
    }
}

class AllohaRepository {
    static let shared = AllohaRepository()
    private let token = "ffbd312217e27c4245f2678afe1881"
    
    // Create a URLSession that ignores SSL certificate errors
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        let delegate = TrustAllSessionDelegate()
        return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }()
    
    func fetchByKpId(kpId: Int) async throws -> AllohaApiResult {
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
                          let eDict = eValue as? [String: Any],
                          let transObj = eDict["translation"] as? [String: Any] else { continue }
                    
                    var parsedTrans: [AllohaTranslation] = []
                    for (tKey, tValue) in transObj {
                        guard let tDict = tValue as? [String: Any],
                              let iframe = tDict["iframe"] as? String, !iframe.isEmpty else { continue }
                        let transName = tDict["translation"] as? String ?? "Unknown"
                        parsedTrans.append(AllohaTranslation(id: tKey, name: transName, iframeUrl: iframe))
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
            return AllohaApiResult(title: title, isSerial: true, movie: nil, seasons: parsedSeasons)
        } else {
            let iframe = dataObj["iframe"] as? String ?? ""
            var movie: AllohaMovie? = nil
            if !iframe.isEmpty {
                movie = AllohaMovie(title: title, iframeUrl: iframe, translations: [
                    AllohaTranslation(id: "default", name: title, iframeUrl: iframe)
                ])
            }
            return AllohaApiResult(title: title, isSerial: false, movie: movie, seasons: [])
        }
    }
}
