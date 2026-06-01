import Foundation
import AVFoundation
import UIKit

/// Helper functions for AVPlayer operations
enum CollapsAVHelper {
    
    // MARK: - Quality Parsing
    
    static func parseHeight(from streamInf: String) -> Int? {
        let pattern = #"RESOLUTION=\d+x(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: streamInf, options: [], range: NSRange(streamInf.startIndex..., in: streamInf)),
              let range = Range(match.range(at: 1), in: streamInf) else {
            return nil
        }
        return Int(streamInf[range])
    }
    
    static func parseBitrate(from streamInf: String) -> Double {
        let pattern = #"BANDWIDTH=(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: streamInf, options: [], range: NSRange(streamInf.startIndex..., in: streamInf)),
              let range = Range(match.range(at: 1), in: streamInf),
              let value = Double(streamInf[range]) else {
            return 0
        }
        return value
    }
    
    static func parseCodecs(from streamInf: String) -> String {
        let pattern = #"CODECS=\"([^\"]+)\""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: streamInf, options: [], range: NSRange(streamInf.startIndex..., in: streamInf)),
              let range = Range(match.range(at: 1), in: streamInf) else {
            return ""
        }
        return String(streamInf[range])
    }
    
    static func heightFromQualityLabel(_ label: String) -> Int? {
        let pattern = #"(\d{3,4})p"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: label, options: [], range: NSRange(label.startIndex..., in: label)),
              let range = Range(match.range(at: 1), in: label) else {
            return nil
        }
        return Int(label[range])
    }
    
    static func qualityFromDictionary(_ quality: [String: Any]) -> CollapsAVQualityOption? {
        guard let qurl = quality["url"] as? String, !qurl.isEmpty else { return nil }
        let label = (quality["label"] as? String) ?? "Stream"
        let bitrate = quality["bitrate"] as? Double ?? quality["bandwidth"] as? Double ?? 0
        let height = quality["height"] as? Int ?? heightFromQualityLabel(label)
        return CollapsAVQualityOption(index: 0, bitrate: bitrate, height: height, label: label, isAuto: false, url: qurl)
    }
    
    // MARK: - Playlist Fetching
    
    static func fetchPlaylistText(urlString: String, headers: [String: String]) async throws -> String {
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if request.value(forHTTPHeaderField: "Referer") == nil {
            request.setValue(headers["referer"], forHTTPHeaderField: "Referer")
        }
        if request.value(forHTTPHeaderField: "Origin") == nil {
            request.setValue(headers["origin"], forHTTPHeaderField: "Origin")
        }
        if request.value(forHTTPHeaderField: "User-Agent") == nil {
            request.setValue(
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36",
                forHTTPHeaderField: "User-Agent"
            )
        }
        if request.value(forHTTPHeaderField: "Accept") == nil {
            request.setValue("*/*", forHTTPHeaderField: "Accept")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let text = String(data: data, encoding: .utf8) else {
            throw URLError(.badServerResponse)
        }
        return text
    }
    
    // MARK: - Proxy Routing
    
    static func localProxyRouteBase(for item: CollapsAVPlaylistItem) -> String {
        let rawMediaId = item.mediaId.trimmingCharacters(in: .whitespacesAndNewlines)
        let mediaPath = rawMediaId
            .replacingOccurrences(of: "[^A-Za-z0-9_-]+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        let base = mediaPath.isEmpty ? "stream" : mediaPath

        if let season = item.season, let episode = item.episode {
            return "\(base)/\(season)/\(episode)"
        }
        return base
    }
    
    static func shouldUseProxy(url: URL, headers: [String: String]) -> Bool {
        !headers.isEmpty && url.path.lowercased().contains(".m3u8")
    }
    
    // MARK: - Quality Recovery
    
    static func qualityRecoveryCandidates(from options: [CollapsAVQualityOption]) -> [Int] {
        let mediumOrLow = options.filter { option in
            let h = option.height ?? 0
            return h >= 480 && h < 1080
        }.map(\.index)
        
        let remaining = options.filter { option in
            let h = option.height ?? 0
            return h < 480 || h >= 1080
        }.map(\.index)
        
        return mediumOrLow + remaining
    }
    
    // MARK: - UI Helpers
    
    static func topViewController(base: UIViewController? = nil) -> UIViewController? {
        let base = base ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?.rootViewController

        if let nav = base as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }
        if let tab = base as? UITabBarController {
            return topViewController(base: tab.selectedViewController)
        }
        if let presented = base?.presentedViewController {
            return topViewController(base: presented)
        }
        return base
    }
    
    static func normalizedOverlayLabel(_ value: String, fallback: String = "") -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        // Remove leading "(Lang)" prefix and collapse extra spaces.
        let noLangPrefix = trimmed.replacingOccurrences(of: #"^\([^\)]*\)\s*"#, with: "", options: .regularExpression)
        let compact = noLangPrefix.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        if compact.isEmpty { return fallback }
        // Keep chip/title compact to avoid layout breakage.
        return String(compact.prefix(42))
    }
}
