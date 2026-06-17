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
            var updatedMovie = movie
            if updatedMovie.voices.isEmpty || updatedMovie.voices.count == 1 {
                if let hlsUrl = updatedMovie.hlsUrl, !hlsUrl.isEmpty {
                    if let hlsVoices = try? await fetchVoicesFromHls(url: hlsUrl), !hlsVoices.isEmpty {
                        updatedMovie = CollapsMovie(
                            mpdUrl: updatedMovie.mpdUrl,
                            hlsUrl: updatedMovie.hlsUrl,
                            voices: hlsVoices,
                            subtitles: updatedMovie.subtitles
                        )
                    }
                }
            }
            return updatedMovie
        case .series:
            return nil
        }
    }
    
    private func fetchVoicesFromHls(url: String) async throws -> [String] {
        guard let fetchUrl = URL(string: url) else { return [] }
        var request = URLRequest(url: fetchUrl)
        request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64)", forHTTPHeaderField: "User-Agent")
        request.setValue("https://kinokrad.my", forHTTPHeaderField: "Origin")
        request.setValue("https://kinokrad.my/", forHTTPHeaderField: "Referer")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
              let m3u8 = String(data: data, encoding: .utf8) else {
            return []
        }
        
        var voices: [String] = []
        let lines = m3u8.components(separatedBy: .newlines)
        for line in lines {
            if line.hasPrefix("#EXT-X-MEDIA:TYPE=AUDIO") {
                if let name = extractQuotedAttr(line, key: "NAME") {
                    if !voices.contains(name) {
                        voices.append(name)
                    }
                }
            }
        }
        return voices
    }

    private func extractQuotedAttr(_ line: String, key: String) -> String? {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: key))=\"([^\"]+)\""
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: line, options: [], range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return String(line[range])
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
