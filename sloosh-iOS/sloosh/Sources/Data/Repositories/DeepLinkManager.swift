import Foundation
import SwiftUI

struct DeepLinkMovie: Identifiable, Hashable {
    let id: String
}

@MainActor
final class DeepLinkManager: ObservableObject {
    static let shared = DeepLinkManager()
    
    @Published var targetMovieId: String? = nil
    @Published var targetClipId: String? = nil
    
    private init() {}
    
    /// Handles incoming deep links such as `https://sluvskii.github.io/iOS-sloosh/details?id=301`, `?clipId=abc`, or `sloosh://...`.
    func handleURL(_ url: URL) {
        AppDiagnostics.shared.log("DeepLinkManager: handleURL called with \(url.absoluteString)")
        
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            return
        }
        
        // 1. Check clip parameters/paths first
        if let queryItems = components.queryItems,
           let clipId = queryItems.first(where: { $0.name == "clipId" || $0.name == "clip" })?.value,
           !clipId.isEmpty {
            let cleanClipId = clipId.trimmingCharacters(in: .whitespacesAndNewlines)
            AppDiagnostics.shared.log("DeepLinkManager: extracted clipId=\(cleanClipId)")
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                self.targetClipId = cleanClipId
            }
            return
        }

        let pathComponents = components.path.components(separatedBy: "/").filter { !$0.isEmpty }
        if let clipIdx = pathComponents.firstIndex(of: "clip"), clipIdx + 1 < pathComponents.count {
            let clipId = pathComponents[clipIdx + 1].trimmingCharacters(in: .whitespacesAndNewlines)
            if !clipId.isEmpty {
                AppDiagnostics.shared.log("DeepLinkManager: extracted clipId from path=\(clipId)")
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    self.targetClipId = clipId
                }
                return
            }
        }
        
        var rawId: String? = nil
        
        // 2. Check query parameter `id`
        if let queryItems = components.queryItems, let id = queryItems.first(where: { $0.name == "id" })?.value {
            rawId = id
        }
        
        // 3. If no query item, check path components
        if rawId == nil || rawId?.isEmpty == true {
            if let last = pathComponents.last, last != "sloosh" && last != "iOS-sloosh" && last != "details" && last != "index.html" && last != "clip" {
                rawId = last
            } else if let host = components.host, host != "details" && host != "movie" && host != "tv" && host != "clip" && host != "sluvskii.github.io" && host != "sloosh.vercel.app" {
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
        var components = URLComponents(string: "https://sluvskii.github.io/iOS-sloosh/")
        components?.queryItems = [URLQueryItem(name: "id", value: cleanId)]
        return components?.url ?? URL(string: "https://sluvskii.github.io/iOS-sloosh/")!
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

    /// Creates a 100% clickable HTTPS share URL for a movie moment (`https://sluvskii.github.io/iOS-sloosh/?clipId={id}`)
    func createClipShareURL(for clipId: String) -> URL {
        let cleanId = clipId.trimmingCharacters(in: .whitespacesAndNewlines)
        var components = URLComponents(string: "https://sluvskii.github.io/iOS-sloosh/")
        components?.queryItems = [URLQueryItem(name: "clipId", value: cleanId)]
        return components?.url ?? URL(string: "https://sluvskii.github.io/iOS-sloosh/")!
    }

    /// Formats a share text for a given clip
    func createClipShareMessage(title: String, clipId: String, caption: String? = nil) -> String {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanId = clipId.trimmingCharacters(in: .whitespacesAndNewlines)
        let link = "https://sluvskii.github.io/iOS-sloosh/?clipId=\(cleanId)"
        var text = cleanTitle.isEmpty ? "Смотри момент в sloosh! 🎬" : "Смотри момент из «\(cleanTitle)» в sloosh! 🎬"
        if let caption = caption?.trimmingCharacters(in: .whitespacesAndNewlines), !caption.isEmpty {
            text += "\n\(caption)"
        }
        text += "\n\(link)"
        return text
    }
    
    /// Clears the pending targetMovieId and dismisses deep link details presentation
    func clear() {
        targetMovieId = nil
        targetClipId = nil
    }
}
