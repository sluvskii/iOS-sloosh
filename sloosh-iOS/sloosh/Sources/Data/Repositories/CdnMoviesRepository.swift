import Foundation

class CdnMoviesRepository {
    static let shared = CdnMoviesRepository()
    
    private init() {}
    
    /// Fetches CDNmovies iframe via Kinobox and maps it to AllohaApiResult so SourceSelectionView can use it
    func getDetails(kpId: Int, title: String, isSerial: Bool) async throws -> AllohaApiResult {
        // 1. Fetch iframe from API
        let iframeUrl = try await CdnMoviesApi.shared.getCdnMoviesIframeUrl(kpId: kpId)
        
        // 2. Map to UI Model
        if isSerial {
            // For series, CDNMovies renders episodes dynamically inside its JS player.
            // We return a "placeholder" season 1 episode 1 to allow the player to open,
            // where the internal iframe logic would theoretically handle episodes,
            // OR we'd need a headless WKWebView to parse the episodes list.
            let placeholderTranslation = AllohaTranslation(id: "cdn_serial", name: "CDNMovies (Авто)", iframeUrl: iframeUrl, streamUrl: nil)
            let placeholderEpisode = AllohaEpisode(season: 1, episode: 1, translations: [placeholderTranslation])
            let placeholderSeason = AllohaSeason(season: 1, episodes: [placeholderEpisode])
            
            return AllohaApiResult(
                title: title,
                isSerial: true,
                movie: nil,
                seasons: [placeholderSeason]
            )
        } else {
            // For movies, it's straightforward
            let translation = AllohaTranslation(id: "cdn_movie", name: "CDNMovies", iframeUrl: iframeUrl, streamUrl: nil)
            let movie = AllohaMovie(title: title, iframeUrl: iframeUrl, translations: [translation])
            
            return AllohaApiResult(
                title: title,
                isSerial: false,
                movie: movie,
                seasons: []
            )
        }
    }
}
