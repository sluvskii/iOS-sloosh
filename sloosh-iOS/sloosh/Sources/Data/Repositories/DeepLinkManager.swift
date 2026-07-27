import Foundation
import SwiftUI

@MainActor
final class DeepLinkManager: ObservableObject {
    static let shared = DeepLinkManager()
    
    @Published var targetMovieId: String? = nil
    
    private init() {}
    
    /// Handles incoming deep links such as `https://sluvskii.github.io/iOS-sloosh/details?id=301` or `sloosh://details/301`.
    func handleURL(_ url: URL) {
        AppDiagnostics.shared.log("DeepLinkManager: handleURL called with \(url.absoluteString)")
        
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            return
        }
        
        var rawId: String? = nil
        
        // 1. Check query parameter `id`
        if let queryItems = components.queryItems, let id = queryItems.first(where: { $0.name == "id" })?.value {
            rawId = id
        }
        
        // 2. If no query item, check path components
        if rawId == nil || rawId?.isEmpty == true {
            let pathComponents = components.path.components(separatedBy: "/").filter { !$0.isEmpty }
            if let last = pathComponents.last, last != "sloosh" && last != "iOS-sloosh" && last != "details" && last != "index.html" {
                rawId = last
            } else if let host = components.host, host != "details" && host != "movie" && host != "tv" && host != "sluvskii.github.io" && host != "sloosh.vercel.app" {
                rawId = host
            }
        }
        
        if let rawId, !rawId.isEmpty {
            let cleanId = rawId.replacingOccurrences(of: "kp_", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            AppDiagnostics.shared.log("DeepLinkManager: extracted cleanId=\(cleanId)")
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                self.targetMovieId = cleanId
            }
        }
    }
    
    /// Creates a 100% clickable HTTPS share URL (`https://sluvskii.github.io/iOS-sloosh/?id={id}`)
    func createShareURL(for movieId: String) -> URL {
        let cleanId = movieId.replacingOccurrences(of: "kp_", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(string: "https://sluvskii.github.io/iOS-sloosh/?id=\(cleanId)")!
    }
    
    /// Formats a share text for a given title and movie ID
    func createShareMessage(title: String, movieId: String) -> String {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanId = movieId.replacingOccurrences(of: "kp_", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        let link = "https://sluvskii.github.io/iOS-sloosh/?id=\(cleanId)"
        if cleanTitle.isEmpty {
            return "Смотри в sloosh! 🍿\n\(link)"
        }
        return "Смотри «\(cleanTitle)» в sloosh! 🍿\n\(link)"
    }
    
    /// Clears the pending targetMovieId and dismisses deep link details presentation
    func clear() {
        targetMovieId = nil
    }
}
