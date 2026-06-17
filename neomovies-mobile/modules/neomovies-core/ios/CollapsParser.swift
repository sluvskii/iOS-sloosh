import Foundation
import os.log

public class CollapsParser {
    private static let logger = OSLog(subsystem: "com.neo.neomovies", category: "CollapsParser")
    
    public static func parseCollapsCatalog(embedHtml: String) -> [String: Any] {
        guard !embedHtml.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            os_log("Empty HTML", log: logger, type: .error)
            return [:]
        }
        
        os_log("HTML length: %d", log: logger, type: .info, embedHtml.count)
        os_log("HTML preview (first 500 chars): %@", log: logger, type: .info, String(embedHtml.prefix(500)))
        
        // Extract seasons JSON from embed HTML
        if let seasonsJson = extractSeasonsJson(from: embedHtml) {
            os_log("Found seasons JSON, length: %d", log: logger, type: .info, seasonsJson.count)
            os_log("Seasons JSON preview: %@", log: logger, type: .info, String(seasonsJson.prefix(500)))
            return parseSeries(seasonsJson: seasonsJson, source: "collaps")
        }
        
        os_log("No seasons JSON found, trying as movie", log: logger, type: .info)
        
        // Try to parse as movie
        if let movieData = extractMovieData(from: embedHtml) {
            os_log("Found movie data: %@", log: logger, type: .info, movieData)
            return parseMovie(movieData: movieData, source: "collaps")
        }
        
        os_log("No movie data found, returning HTML for debugging", log: logger, type: .error)
        return [
            "kind": "debug",
            "html": embedHtml
        ]
    }
    
    private static func extractSeasonsJson(from html: String) -> String? {
        // Look for seasons: and extract until end of line (matching Android implementation)
        os_log("Searching for 'seasons:' in HTML (case-insensitive)", log: logger, type: .info)
        
        // Use regex for case-insensitive search with flexible spacing
        guard let pattern = try? NSRegularExpression(pattern: #"(?i)\bseasons\s*:"#, options: []),
              let match = pattern.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)),
              let matchRange = Range(match.range, in: html) else {
            os_log("'seasons:' not found in HTML", log: logger, type: .error)
            return nil
        }
        
        os_log("Found 'seasons:' at position", log: logger, type: .info)
        
        // Start exactly after "seasons:"; do not skip the first JSON character.
        let start = matchRange.upperBound
        var end = start
        
        while end < html.endIndex {
            let char = html[end]
            if char == "\n" || char == "\r" {
                break
            }
            end = html.index(after: end)
        }
        
        let jsonStr = String(html[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        os_log("Extracted JSON string: %@", log: logger, type: .info, jsonStr)
        
        return jsonStr.hasPrefix("[") ? jsonStr : nil
    }
    
    private static func extractMovieData(from html: String) -> [String: Any]? {
        // Extract movie playlist data (matching Android implementation)
        var data: [String: Any] = [:]
        
        os_log("Searching for dasha/dash: pattern with .mpd suffix", log: logger, type: .info)
        
        // Extract DASH URL (dasha or dash with .mpd suffix)
        if let dashPattern = try? NSRegularExpression(pattern: #"(?i)\b(dasha|dash)\s*:\s*['\"]([^'\"]+\.mpd[^'\"]*)['\"]"#, options: []),
           let dashMatch = dashPattern.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)),
           let dashRange = Range(dashMatch.range(at: 2), in: html) {
            let dash = String(html[dashRange])
            os_log("Found dash: %@", log: logger, type: .info, dash)
            data["dash"] = dash
        } else {
            os_log("dash: pattern not found", log: logger, type: .error)
        }
        
        os_log("Searching for hls: pattern with .m3u8 suffix", log: logger, type: .info)
        
        // Extract HLS URL (hls with .m3u8 suffix)
        if let hlsPattern = try? NSRegularExpression(pattern: #"(?i)\bhls\s*:\s*['\"]([^'\"]+\.m3u8[^'\"]*)['\"]"#, options: []),
           let hlsMatch = hlsPattern.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)),
           let hlsRange = Range(hlsMatch.range(at: 1), in: html) {
            let hls = String(html[hlsRange])
            os_log("Found hls: %@", log: logger, type: .info, hls)
            data["hls"] = hls
        } else {
            os_log("hls: pattern not found", log: logger, type: .error)
        }
        
        os_log("Movie data extracted: %@", log: logger, type: .info, data)
        if data.isEmpty, let payloadData = extractHlsSourcePayload(from: html) {
            let hls = payloadData["hls"] ?? ""
            if !hls.isEmpty {
                data["hls"] = hls
            }
            let dash = payloadData["dash"] ?? ""
            if !dash.isEmpty {
                data["dash"] = dash
            }
        }

        if data["hls"] == nil,
           let fallback = firstPreferredStreamURLString(in: html) {
            data["hls"] = fallback
        }

        return data.isEmpty ? nil : data
    }

    private static func firstPreferredStreamURLString(in payload: String) -> String? {
        let patterns = [
            #"https?:\\/\\/[^\"'\s>]+\\.m3u8[^\"'\s>]*"#,
            #"https?:\\/\\/[^\"'\s>]+\\.mpd[^\"'\s>]*"#,
            #"(?:\"|')((?:https?:)?//[^\"'\s>]+(?:m3u8|mpd)[^\"'\s>]*)"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(payload.startIndex..<payload.endIndex, in: payload)
            guard let match = regex.firstMatch(in: payload, options: [], range: range) else { continue }
            let targetRange = match.numberOfRanges > 1 ? match.range(at: 1) : match.range(at: 0)
            guard let valueRange = Range(targetRange, in: payload) else { continue }
            var value = String(payload[valueRange])
            value = value.replacingOccurrences(of: "\\/", with: "/")
            if value.hasPrefix("//") {
                value = "https:" + value
            }
            return value
        }
        return nil
    }

    private static func extractHlsSourcePayload(from payload: String) -> [String: String]? {
        let candidates = embeddedJSONObjectCandidates(in: payload)
        for candidate in candidates {
            guard let data = candidate.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let source = object["hlsSource"] as? [[String: Any]] else {
                continue
            }

            var resolvedHls: String?
            var resolvedDash: String?
            for item in source {
                guard let quality = item["quality"] as? [String: Any] else { continue }
                for (_, rawValue) in quality {
                    let values = qualityURLStrings(from: rawValue)
                    for value in values {
                        let decoded = value.replacingOccurrences(of: "\\/", with: "/")
                        if resolvedHls == nil && decoded.lowercased().contains(".m3u8") {
                            resolvedHls = decoded
                        }
                        if resolvedDash == nil && decoded.lowercased().contains(".mpd") {
                            resolvedDash = decoded
                        }
                    }
                }
            }

            if resolvedHls != nil || resolvedDash != nil {
                return ["hls": resolvedHls ?? "", "dash": resolvedDash ?? ""]
            }
        }
        return nil
    }

    private static func qualityURLStrings(from value: Any) -> [String] {
        if let text = value as? String {
            return splitURLParts(text)
        }
        if let nested = value as? [Any] {
            return nested.flatMap { qualityURLStrings(from: $0) }
        }
        if let nestedDict = value as? [String: Any] {
            return nestedDict.values.flatMap { qualityURLStrings(from: $0) }
        }
        return []
    }

    private static func splitURLParts(_ text: String) -> [String] {
        text
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func embeddedJSONObjectCandidates(in payload: String) -> [String] {
        var candidates = balancedJSONObjectCandidates(containing: #"\"hlsSource\""#, in: payload)
        candidates.append(contentsOf: balancedJSONObjectCandidates(containing: "hlsSource", in: payload))
        var seen = Set<String>()
        return candidates.filter { seen.insert($0).inserted }
    }

    private static func balancedJSONObjectCandidates(containing marker: String, in payload: String) -> [String] {
        var candidates: [String] = []
        var searchStart = payload.startIndex
        while let markerRange = payload.range(of: marker, options: [.caseInsensitive], range: searchStart..<payload.endIndex) {
            guard let objectStart = payload[..<markerRange.lowerBound].lastIndex(of: "{"),
                  let objectEnd = balancedObjectEnd(from: objectStart, in: payload) else {
                searchStart = markerRange.upperBound
                continue
            }
            candidates.append(String(payload[objectStart...objectEnd]))
            searchStart = markerRange.upperBound
        }
        return candidates
    }

    private static func balancedObjectEnd(from start: String.Index, in payload: String) -> String.Index? {
        var depth = 0
        var isQuoted = false
        var isEscaped = false
        var index = start

        while index < payload.endIndex {
            let character = payload[index]
            if isEscaped {
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else if character == "\"" {
                isQuoted.toggle()
            } else if !isQuoted {
                if character == "{" {
                    depth += 1
                } else if character == "}" {
                    depth -= 1
                    if depth == 0 { return index }
                }
            }
            index = payload.index(after: index)
        }
        return nil
    }
    
    private static func parseSeries(seasonsJson: String, source: String) -> [String: Any] {
        guard let jsonData = seasonsJson.data(using: .utf8),
              let seasonsArray = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else {
            return [:]
        }
        
        var seasons: [[String: Any]] = []
        
        for seasonObj in seasonsArray {
            let seasonNum: Int
            if let value = seasonObj["season"] as? Int {
                seasonNum = value
            } else if let value = seasonObj["season"] as? String, let parsed = Int(value) {
                seasonNum = parsed
            } else {
                continue
            }
            
            guard seasonNum > 0,
                  let episodesArray = seasonObj["episodes"] as? [[String: Any]] else {
                continue
            }
            
            var episodes: [[String: Any]] = []
            
            for episodeObj in episodesArray {
                let episodeNum: Int
                if let value = episodeObj["episode"] as? Int {
                    episodeNum = value
                } else if let value = episodeObj["episode"] as? String, let parsed = Int(value) {
                    episodeNum = parsed
                } else {
                    continue
                }
                
                let hls = (episodeObj["hls"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let dasha = (episodeObj["dasha"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let dash = (episodeObj["dash"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let mpd = dasha ?? dash
                
                var voices: [String] = []
                if let audio = episodeObj["audio"] as? [String: Any],
                   let names = audio["names"] as? [String] {
                    voices = names.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                }
                
                var subtitles: [[String: String]] = []
                if let cc = episodeObj["cc"] as? [[String: Any]] {
                    for subObj in cc {
                        let url = (subObj["url"] as? String ?? subObj["src"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !url.isEmpty else { continue }
                        
                        let label = (subObj["name"] as? String ?? subObj["label"] as? String ?? "Subtitle").trimmingCharacters(in: .whitespacesAndNewlines)
                        let langRaw = (subObj["lang"] as? String ?? subObj["language"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        let lang = langRaw.isEmpty
                            ? ((label.lowercased().contains("eng") || label.lowercased().contains("original")) ? "en" : "ru")
                            : langRaw
                        
                        subtitles.append([
                            "url": url,
                            "label": label.isEmpty ? "Subtitle" : label,
                            "language": lang.isEmpty ? "ru" : lang
                        ])
                    }
                }
                
                let primaryUrl = hls ?? mpd ?? ""
                
                let playlist: [String: Any] = [
                    "primaryUrl": primaryUrl,
                    "hlsUrl": hls as Any,
                    "dashUrl": mpd as Any,
                    "voiceovers": voices,
                    "subtitles": subtitles
                ]
                
                episodes.append([
                    "season": seasonNum,
                    "episode": episodeNum,
                    "title": "Episode \(episodeNum)",
                    "playlist": playlist
                ])
            }
            
            if !episodes.isEmpty {
                episodes.sort { (lhs, rhs) in
                    let lhsEpisode = lhs["episode"] as? Int ?? Int.max
                    let rhsEpisode = rhs["episode"] as? Int ?? Int.max
                    return lhsEpisode < rhsEpisode
                }
                
                seasons.append([
                    "season": seasonNum,
                    "title": "Season \(seasonNum)",
                    "episodes": episodes
                ])
            }
        }
        
        seasons.sort { (lhs, rhs) in
            let lhsSeason = lhs["season"] as? Int ?? Int.max
            let rhsSeason = rhs["season"] as? Int ?? Int.max
            return lhsSeason < rhsSeason
        }
        
        return [
            "kind": "series",
            "source": source,
            "seasons": seasons
        ]
    }
    
    private static func parseMovie(movieData: [String: Any], source: String) -> [String: Any] {
        let hls = movieData["hls"] as? String
        let dash = movieData["dash"] as? String
        let primaryUrl = hls ?? dash ?? ""
        
        let playlist: [String: Any] = [
            "primaryUrl": primaryUrl,
            "hlsUrl": hls as Any,
            "dashUrl": dash as Any,
            "voiceovers": [],
            "subtitles": []
        ]
        
        return [
            "kind": "movie",
            "source": source,
            "playlist": playlist
        ]
    }
}
