import Foundation

struct CollapsSubtitle: Codable, Hashable, Equatable {
    let url: String
    let label: String
    let lang: String
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
    private let base = "https://api.luxembd.ws"
    
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
            return movie
        case .series:
            return nil
        }
    }
    
    private func fetchEmbedHtml(url: String) async throws -> String {
        guard let fetchUrl = URL(string: url) else { throw URLError(.badURL) }
        var request = URLRequest(url: fetchUrl)
        request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64)", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        return String(data: data, encoding: .utf8) ?? ""
    }
    
    private func extractSeasonsJson(html: String) -> String? {
        guard let idx = html.range(of: "seasons:")?.upperBound else { return nil }
        let substr = html[idx...]
        guard let endIdx = substr.firstIndex(where: { $0 == "\n" || $0 == "\r" }) else { return nil }
        
        let extracted = String(substr[..<endIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
        if extracted.hasPrefix("[") {
            return extracted
        }
        return nil
    }
    
    private func extractFirstUrl(html: String, keys: [String], suffix: String) -> String? {
        for key in keys {
            let pattern = "(?is)\\b\(NSRegularExpression.escapedPattern(for: key))\\s*:\\s*['\"]([^'\"]+\(NSRegularExpression.escapedPattern(for: suffix))[^'\"]*)['\"]"
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)) {
                if let range = Range(match.range(at: 1), in: html) {
                    return String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        return nil
    }
    
    private func extractStringArrayFromObject(html: String, objectKey: String, arrayKey: String) -> [String] {
        let key1 = NSRegularExpression.escapedPattern(for: objectKey)
        let key2 = NSRegularExpression.escapedPattern(for: arrayKey)
        let patterns = [
            "(?is)\\b\(key1)\\s*:\\s*\\{.*?\\b\(key2)\\s*:\\s*(\\[[\\s\\S]*?\\])",
            "(?is)\\\"\(key1)\\\"\\s*:\\s*\\{.*?\\\"\(key2)\\\"\\s*:\\s*(\\[[\\s\\S]*?\\])"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let range = Range(match.range(at: 1), in: html) {
                let raw = String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if raw.hasPrefix("[") {
                    if let data = raw.data(using: .utf8),
                       let array = try? JSONSerialization.jsonObject(with: data) as? [String] {
                        return array.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                    } else {
                        return parseJsStringArray(raw: raw)
                    }
                }
            }
        }
        return []
    }
    
    private func extractVoiceNamesFromTranslations(html: String) -> [String] {
        let patterns = [
            "(?is)\\btranslations\\s*:\\s*(\\[[\\s\\S]*?\\])",
            "(?is)\\\"translations\\\"\\s*:\\s*(\\[[\\s\\S]*?\\])"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let range = Range(match.range(at: 1), in: html) {
                let raw = String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if raw.hasPrefix("["), let data = raw.data(using: .utf8),
                   let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    var names: [String] = []
                    for obj in array {
                        var name = (obj["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        if name.isEmpty { name = (obj["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
                        if !name.isEmpty { names.append(name) }
                    }
                    return names
                }
            }
        }
        return []
    }
    
    private func parseJsStringArray(raw: String) -> [String] {
        var result: [String] = []
        if let regex = try? NSRegularExpression(pattern: "['\"]([^'\"]+)['\"]") {
            let matches = regex.matches(in: raw, range: NSRange(raw.startIndex..., in: raw))
            for match in matches {
                if let range = Range(match.range(at: 1), in: raw) {
                    let str = String(raw[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !str.isEmpty { result.append(str) }
                }
            }
        }
        return result
    }
    
    private func extractSubtitlesArray(html: String) -> [CollapsSubtitle] {
        let pattern = "(?is)\\bcc\\s*:\\s*(\\[[^\\]]*\\])"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else {
            return []
        }
        
        let raw = String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.hasPrefix("[") { return [] }
        
        var subtitles: [CollapsSubtitle] = []
        if let data = raw.data(using: .utf8), let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            for sObj in array {
                let urlRaw = (sObj["url"] as? String ?? sObj["src"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if urlRaw.isEmpty { continue }
                
                var label = (sObj["name"] as? String ?? sObj["label"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if label.isEmpty { label = "Subtitle" }
                
                let langRaw = (sObj["lang"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let lang: String
                if !langRaw.isEmpty {
                    lang = langRaw
                } else if label.lowercased().contains("eng") || label.lowercased().contains("original") {
                    lang = "en"
                } else {
                    lang = "ru"
                }
                
                subtitles.append(CollapsSubtitle(url: urlRaw, label: label, lang: lang))
            }
        }
        return subtitles
    }
}
