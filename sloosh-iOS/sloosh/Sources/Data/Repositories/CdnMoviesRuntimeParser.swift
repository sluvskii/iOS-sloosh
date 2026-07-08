import Foundation

class CdnMoviesRuntimeParser {
    
    /// Extracts the highest quality stream URL (MP4 or HLS) from the player configuration
    static func extractStreamUrl(from html: String) -> String? {
        // Look for PlayerJS configuration: `file:"[1080p]https://.../1080.mp4,[720p]https://.../720.mp4"`
        // Or simply `file:"https://.../playlist.m3u8"`
        
        let fileRegex = try? NSRegularExpression(pattern: #"file\s*:\s*["']([^"']+)["']"#, options: [.caseInsensitive])
        
        if let match = fileRegex?.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html) {
            
            let fileValue = String(html[range])
            
            // If it contains brackets (e.g. [1080p]), we extract the highest quality
            if fileValue.contains("[") {
                return extractHighestQuality(from: fileValue)
            }
            
            // Otherwise it's a direct link
            return fileValue
        }
        
        // Fallback: look for any .m3u8 link in the HTML
        let m3u8Regex = try? NSRegularExpression(pattern: #"https?:\/\/[^\s"'<>]+\.m3u8"#, options: [.caseInsensitive])
        if let match = m3u8Regex?.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range, in: html) {
            return String(html[range])
        }
        
        return nil
    }
    
    private static func extractHighestQuality(from fileValue: String) -> String? {
        // e.g. "[1080p]https://...mp4,[720p]https://...mp4"
        let parts = fileValue.components(separatedBy: ",")
        
        var bestUrl: String?
        var bestQuality = 0
        
        for part in parts {
            guard let endBracket = part.firstIndex(of: "]") else {
                // No bracket, just a URL
                return part
            }
            
            let qualityStr = String(part[part.index(after: part.startIndex)..<endBracket]).replacingOccurrences(of: "p", with: "")
            let urlStr = String(part[part.index(after: endBracket)...])
            
            if let quality = Int(qualityStr), quality > bestQuality {
                bestQuality = quality
                bestUrl = urlStr
            }
        }
        
        return bestUrl
    }
}
