import Foundation
import SwiftUI

@MainActor
final class DeepLinkManager: ObservableObject {
    static let shared = DeepLinkManager()
    
    @Published var targetMovieId: String? = nil
    
    private init() {}
    
    /// Handles incoming deep links such as `sloosh://details/301`, `sloosh://movie/301`, or `https://sloosh.app/details/301`.
    func handleURL(_ url: URL) {
        AppDiagnostics.shared.log("DeepLinkManager: handleURL called with \(url.absoluteString)")
        
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            return
        }
        
        var movieId: String? = nil
        
        let scheme = components.scheme?.lowercased()
        if scheme == "sloosh" {
            // e.g. sloosh://details/301 or sloosh://301 or sloosh://movie/301
            let host = components.host?.lowercased() ?? ""
            let pathComponents = components.path.components(separatedBy: "/").filter { !$0.isEmpty }
            
            if !pathComponents.isEmpty {
                movieId = pathComponents.last
            } else if !host.isEmpty && host != "details" && host != "movie" && host != "tv" && host != "item" {
                movieId = host
            } else if let queryItems = components.queryItems, let id = queryItems.first(where: { $0.name == "id" })?.value {
                movieId = id
            }
        } else if scheme == "http" || scheme == "https" {
            // e.g. https://sloosh.app/details/301 or https://sloosh.app/movie/301
            let pathComponents = components.path.components(separatedBy: "/").filter { !$0.isEmpty }
            if let last = pathComponents.last, !last.isEmpty {
                movieId = last
            } else if let queryItems = components.queryItems, let id = queryItems.first(where: { $0.name == "id" })?.value {
                movieId = id
            }
        }
        
        if let movieId, !movieId.isEmpty {
            AppDiagnostics.shared.log("DeepLinkManager: extracted movieId=\(movieId)")
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                self.targetMovieId = movieId
            }
        }
    }
    
    /// Creates a human-friendly web share URL for a given movie/series ID
    func createShareURL(for movieId: String) -> URL {
        return URL(string: "https://sloosh.app/details/\(movieId)") ?? URL(string: "sloosh://details/\(movieId)")!
    }
    
    /// Formats a share text for a given title and movie ID
    func createShareMessage(title: String, movieId: String) -> String {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanTitle.isEmpty {
            return "Смотри в sloosh! 🍿\nhttps://sloosh.app/details/\(movieId)"
        }
        return "Смотри «\(cleanTitle)» в sloosh! 🍿\nhttps://sloosh.app/details/\(movieId)"
    }
}
