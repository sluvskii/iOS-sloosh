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
    private let base = "https://api.bhcesh.me"
    
    func getSeasonsByKpId(kpId: Int) async throws -> [CollapsSeason] {
        let html = try await fetchEmbedHtml(url: "\(base)/embed/kp/\(kpId)")
        guard let result = CollapsParser.parseCatalog(embedHtml: html) else {
            return []
        }
        switch result {
        case .series(let seasons):
            return seasons
        case .movie:
            return []
        }
    }
    
    func getMovieByKpId(kpId: Int) async throws -> CollapsMovie? {
        let html = try await fetchEmbedHtml(url: "\(base)/embed/kp/\(kpId)")
        guard let result = CollapsParser.parseCatalog(embedHtml: html) else {
            return nil
        }
        switch result {
        case .movie(let movie):
            return movie
        case .series:
            return nil
        }
    }
    
    private func fetchEmbedHtml(url: String) async throws -> String {
        guard let fetchUrl = URL(string: url) else { throw URLError(.badURL) }
        var request = URLRequest(url: fetchUrl)
        request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64)", forHTTPHeaderField: "User-Agent")
        request.setValue("https://kinokrad.my", forHTTPHeaderField: "Origin")
        request.setValue("https://kinokrad.my/", forHTTPHeaderField: "Referer")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        return String(data: data, encoding: .utf8) ?? ""
    }
}
