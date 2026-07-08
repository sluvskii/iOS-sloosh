import Foundation

enum CdnMoviesApiError: Error {
    case invalidUrl
    case noData
    case playerNotFound
    case decodingError
}

struct KinoboxPlayer: Codable {
    let source: String
    let iframeUrl: String?
}

class CdnMoviesApi {
    static let shared = CdnMoviesApi()
    
    // We use Kinobox as a free aggregator to reliably get the CDNmovies iframe link
    private let baseURL = "https://kinobox.tv/api/players"
    
    private init() {}
    
    func getCdnMoviesIframeUrl(kpId: Int) async throws -> String {
        guard let url = URL(string: "\(baseURL)?kinopoisk=\(kpId)") else {
            throw CdnMoviesApiError.invalidUrl
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 10.0
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw CdnMoviesApiError.noData
        }
        
        let players = try JSONDecoder().decode([KinoboxPlayer].self, from: data)
        
        // Find CDNmovies in the list
        if let cdnPlayer = players.first(where: { $0.source.lowercased() == "cdnmovies" }),
           let iframeUrl = cdnPlayer.iframeUrl {
            
            // Normalize URL
            if iframeUrl.starts(with: "//") {
                return "https:\(iframeUrl)"
            }
            return iframeUrl
        }
        
        throw CdnMoviesApiError.playerNotFound
    }
}
