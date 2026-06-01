import Foundation

public struct CollapsSubtitle: Codable, Hashable, Equatable {
    public let url: String
    public let label: String
    public let lang: String
}

struct CollapsEpisode: Codable, Hashable, Equatable {
    let season: Int
    let episode: Int
    let mpdUrl: String?
    let hlsUrl: String?
    let voices: [String]
    let subtitles: [CollapsSubtitle]
}

struct CollapsSeason: Codable, Hashable, Equatable {
    let season: Int
    let episodes: [CollapsEpisode]
}

struct CollapsMovie: Codable, Hashable, Equatable {
    let mpdUrl: String?
    let hlsUrl: String?
    let voices: [String]
    let subtitles: [CollapsSubtitle]
}

class CollapsRepository {
    static let shared = CollapsRepository()
    private let base = "https://api.luxembd.ws"
    
    func getSeasonsByKpId(kpId: Int) async throws -> [CollapsSeason] {
        let html = try await fetchEmbedHtml(url: "\(base)/embed/kp/\(kpId)")
        let dict = CollapsParser.parseCollapsCatalog(embedHtml: html)
        
        guard let kind = dict["kind"] as? String, kind == "series",
              let seasonsArray = dict["seasons"] as? [[String: Any]] else {
            return []
        }
        
        var resultSeasons: [CollapsSeason] = []
        for sDict in seasonsArray {
            guard let seasonNum = sDict["season"] as? Int,
                  let epsArray = sDict["episodes"] as? [[String: Any]] else { continue }
            
            var resultEps: [CollapsEpisode] = []
            for eDict in epsArray {
                guard let epNum = eDict["episode"] as? Int,
                      let playlist = eDict["playlist"] as? [String: Any] else { continue }
                
                let hlsUrl = playlist["hlsUrl"] as? String
                let dashUrl = playlist["dashUrl"] as? String
                let voices = playlist["voiceovers"] as? [String] ?? []
                let subsDict = playlist["subtitles"] as? [[String: String]] ?? []
                let subtitles = subsDict.compactMap { dict -> CollapsSubtitle? in
                    guard let url = dict["url"], let label = dict["label"], let lang = dict["language"] else { return nil }
                    return CollapsSubtitle(url: url, label: label, lang: lang)
                }
                
                resultEps.append(CollapsEpisode(season: seasonNum, episode: epNum, mpdUrl: dashUrl, hlsUrl: hlsUrl, voices: voices, subtitles: subtitles))
            }
            if !resultEps.isEmpty {
                resultSeasons.append(CollapsSeason(season: seasonNum, episodes: resultEps))
            }
        }
        return resultSeasons
    }
    
    func getMovieByKpId(kpId: Int) async throws -> CollapsMovie? {
        let html = try await fetchEmbedHtml(url: "\(base)/embed/kp/\(kpId)")
        let dict = CollapsParser.parseCollapsCatalog(embedHtml: html)
        
        guard let kind = dict["kind"] as? String, kind == "movie",
              let playlist = dict["playlist"] as? [String: Any] else {
            return nil
        }
        
        let hlsUrl = playlist["hlsUrl"] as? String
        let dashUrl = playlist["dashUrl"] as? String
        let voices = playlist["voiceovers"] as? [String] ?? []
        let subsDict = playlist["subtitles"] as? [[String: String]] ?? []
        let subtitles = subsDict.compactMap { dict -> CollapsSubtitle? in
            guard let url = dict["url"], let label = dict["label"], let lang = dict["language"] else { return nil }
            return CollapsSubtitle(url: url, label: label, lang: lang)
        }
        
        return CollapsMovie(mpdUrl: dashUrl, hlsUrl: hlsUrl, voices: voices, subtitles: subtitles)
    }
    
    private func fetchEmbedHtml(url: String) async throws -> String {
        guard let fetchUrl = URL(string: url) else { throw URLError(.badURL) }
        var request = URLRequest(url: fetchUrl)
        request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64)", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        return String(data: data, encoding: .utf8) ?? ""
    }
}
