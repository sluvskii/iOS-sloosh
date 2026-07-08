import Foundation

class CdnMoviesRuntimeResolver {
    
    /// Resolves the CDNMovies iframe URL into a direct HLS/MP4 video stream URL
    static func resolve(iframeUrl: String) async throws -> String {
        guard let url = URL(string: iframeUrl) else {
            throw NSError(domain: "CdnMoviesRuntimeResolver", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid iframe URL"])
        }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        request.setValue("https://kinobox.tv/", forHTTPHeaderField: "Referer")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "CdnMoviesRuntimeResolver", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to load iframe"])
        }
        
        guard let html = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "CdnMoviesRuntimeResolver", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to decode HTML"])
        }
        
        guard let streamUrl = CdnMoviesRuntimeParser.extractStreamUrl(from: html) else {
            throw NSError(domain: "CdnMoviesRuntimeResolver", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to parse stream URL from HTML"])
        }
        
        return streamUrl
    }
}
