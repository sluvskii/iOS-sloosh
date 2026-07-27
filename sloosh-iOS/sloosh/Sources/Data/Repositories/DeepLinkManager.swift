import Foundation
import SwiftUI

@MainActor
final class DeepLinkManager: ObservableObject {
    static let shared = DeepLinkManager()
    
    @Published var targetMovieId: String? = nil
    
    private init() {}
    
    /// Handles incoming deep links such as `sloosh://details/301`, `sloosh://movie/301`, or `sloosh://301`.
    func handleURL(_ url: URL) {
        AppDiagnostics.shared.log("DeepLinkManager: handleURL called with \(url.absoluteString)")
        
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            return
        }
        
        var rawId: String? = nil
        
        let scheme = components.scheme?.lowercased()
        if scheme == "sloosh" {
            // e.g. sloosh://details/301 or sloosh://301 or sloosh://movie/301 or sloosh://details/kp_301
            let host = components.host?.lowercased() ?? ""
            let pathComponents = components.path.components(separatedBy: "/").filter { !$0.isEmpty }
            
            if !pathComponents.isEmpty {
                rawId = pathComponents.last
            } else if !host.isEmpty && host != "details" && host != "movie" && host != "tv" && host != "item" {
                rawId = host
            } else if let queryItems = components.queryItems, let id = queryItems.first(where: { $0.name == "id" })?.value {
                rawId = id
            }
        } else if scheme == "http" || scheme == "https" {
            let pathComponents = components.path.components(separatedBy: "/").filter { !$0.isEmpty }
            if let last = pathComponents.last, !last.isEmpty {
                rawId = last
            } else if let queryItems = components.queryItems, let id = queryItems.first(where: { $0.name == "id" })?.value {
                rawId = id
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
    
    /// Creates a native custom scheme URL (`sloosh://details/{id}`) for direct app opening
    func createShareURL(for movieId: String) -> URL {
        let cleanId = movieId.replacingOccurrences(of: "kp_", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(string: "sloosh://details/\(cleanId)")!
    }
    
    /// Formats a share text for a given title and movie ID
    func createShareMessage(title: String, movieId: String) -> String {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanId = movieId.replacingOccurrences(of: "kp_", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        let link = "sloosh://details/\(cleanId)"
        
        if cleanTitle.isEmpty {
            return "Смотри в sloosh! 🍿\n\(link)"
        }
        return "Смотри «\(cleanTitle)» в sloosh! 🍿\n\(link)"
    }
}
