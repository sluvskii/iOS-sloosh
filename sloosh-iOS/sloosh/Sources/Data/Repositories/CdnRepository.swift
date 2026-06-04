import Foundation

enum CdnRepositoryError: Error {
    case notFound
    case invalidData
    case networkError(Error)
    case missingCdnId
}

struct CdnContentInfo: Decodable {
    let id: Int
    let title: String
    let hasMultipleEpisodes: Bool
    let trailerUrls: [String]?
}

struct CdnEpisodeSeason: Decodable {
    let id: Int
    let order: Int
}

struct CdnEpisodeVariant: Decodable {
    let filepath: String
}

struct CdnEpisode: Decodable {
    let id: Int
    let title: String
    let order: Int
    let season: CdnEpisodeSeason
    let episodeVariants: [CdnEpisodeVariant]?
}

struct CdnPlayerData {
    let isSeries: Bool
    let title: String
    let initialM3u8: String
    let seasons: [CdnResolvedSeason]?
}

struct CdnResolvedSeason: Identifiable {
    let id = UUID()
    let season: Int
    let episodes: [CdnResolvedEpisode]
}

struct CdnResolvedEpisode: Identifiable {
    let id = UUID()
    let episode: Int
    let title: String
    let filepath: String
}

class CdnRepository {
    static let shared = CdnRepository()
    
    private let cdnBase = "https://api.rstprgapipt.com/balancer-api/proxy/playlists/catalog-api"
    private let cdnToken = "eyJhbGciOiJIUzI1NiJ9.eyJ3ZWJTaXRlIjoiMzQiLCJpc3MiOiJhcGktd2VibWFzdGVyIiwic3ViIjoiNDEiLCJpYXQiOjE3NDMwNjA3ODAsImp0aSI6IjIzMTQwMmE0LTM3NTMtNGQ3OS1hNDBjLTA2YTY0MTE0MzNhOSIsInNjb3BlIjoiRExFIn0.4PmKGf512P-ov-tEjwr3gfOVxccjx8SSt28slJXypYU"
    
    private func makeRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(cdnToken, forHTTPHeaderField: "DLE-API-TOKEN")
        request.setValue("7f2a4c1b-ca44-4858-b6ab-71894c7bb1aa", forHTTPHeaderField: "Iframe-Request-Id")
        return request
    }
    
    func resolveCdnId(kpId: Int) async throws -> Int {
        let urlString = "https://api.rstprgapipt.com/balancer-api/iframe?kp=\(kpId)&token=\(cdnToken)&disabled_share=1"
        guard let url = URL(string: urlString) else { throw CdnRepositoryError.invalidData }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let html = String(data: data, encoding: .utf8) else { throw CdnRepositoryError.invalidData }
        
        // Find window.MOVIE_ID=([0-9]+);
        if let range = html.range(of: "window.MOVIE_ID=") {
            let substring = html[range.upperBound...]
            if let endRange = substring.range(of: ";") {
                let idString = substring[..<endRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
                if let id = Int(idString) {
                    return id
                }
            }
        }
        throw CdnRepositoryError.missingCdnId
    }
    
    func fetchContentInfo(cdnId: Int) async throws -> CdnContentInfo {
        let urlString = "\(cdnBase)/contents/\(cdnId)"
        guard let url = URL(string: urlString) else { throw CdnRepositoryError.invalidData }
        
        let (data, _) = try await URLSession.shared.data(for: makeRequest(url: url))
        return try JSONDecoder().decode(CdnContentInfo.self, from: data)
    }
    
    func fetchEpisodes(cdnId: Int) async throws -> [CdnEpisode] {
        let urlString = "\(cdnBase)/episodes?content-id=\(cdnId)"
        guard let url = URL(string: urlString) else { throw CdnRepositoryError.invalidData }
        
        let (data, _) = try await URLSession.shared.data(for: makeRequest(url: url))
        return try JSONDecoder().decode([CdnEpisode].self, from: data)
    }
    
    func resolveM3u8(filepath: String) async throws -> String {
        guard let url = URL(string: filepath) else { return filepath }
        var request = URLRequest(url: url)
        // URLSession will automatically follow 307/302 redirects by default.
        // We can just use dataTask and check the response URL.
        let (_, response) = try await URLSession.shared.data(for: request)
        if let finalUrl = response.url {
            return finalUrl.absoluteString
        }
        return filepath
    }
    
    func getPlayerData(kpId: Int) async throws -> CdnPlayerData {
        let cdnId = try await resolveCdnId(kpId: kpId)
        let info = try await fetchContentInfo(cdnId: cdnId)
        
        if !info.hasMultipleEpisodes {
            guard let filepath = info.trailerUrls?.first else {
                throw CdnRepositoryError.notFound
            }
            let m3u8 = try await resolveM3u8(filepath: filepath)
            return CdnPlayerData(isSeries: false, title: info.title, initialM3u8: m3u8, seasons: nil)
        }
        
        let rawEpisodes = try await fetchEpisodes(cdnId: cdnId)
        
        // Group by season
        var seasonMap: [Int: [CdnResolvedEpisode]] = [:]
        
        for ep in rawEpisodes {
            guard let filepath = ep.episodeVariants?.first?.filepath else { continue }
            let resolvedEp = CdnResolvedEpisode(episode: ep.order, title: ep.title, filepath: filepath)
            seasonMap[ep.season.order, default: []].append(resolvedEp)
        }
        
        let resolvedSeasons = seasonMap.keys.sorted().map { s in
            CdnResolvedSeason(season: s, episodes: seasonMap[s]!.sorted { $0.episode < $1.episode })
        }
        
        guard let firstSeason = resolvedSeasons.first, let firstEp = firstSeason.episodes.first else {
            throw CdnRepositoryError.notFound
        }
        
        let m3u8 = try await resolveM3u8(filepath: firstEp.filepath)
        
        return CdnPlayerData(isSeries: true, title: info.title, initialM3u8: m3u8, seasons: resolvedSeasons)
    }
}
