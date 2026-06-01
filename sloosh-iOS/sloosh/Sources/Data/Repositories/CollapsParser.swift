import Foundation

enum CollapsCatalogResult {
    case movie(CollapsMovie)
    case series([CollapsSeason])
}

enum CollapsParser {
    static func parseCatalog(embedHtml: String) -> CollapsCatalogResult? {
        let html = embedHtml.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !html.isEmpty else { return nil }

        if let seasonsJson = extractSeasonsJson(from: html),
           let seasons = parseSeries(seasonsJson: seasonsJson),
           !seasons.isEmpty {
            return .series(seasons)
        }

        if let movie = parseMovie(from: html) {
            return .movie(movie)
        }

        return nil
    }

    private static func extractSeasonsJson(from html: String) -> String? {
        guard let pattern = try? NSRegularExpression(pattern: #"(?i)\bseasons\s*:"#),
              let match = pattern.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let matchRange = Range(match.range, in: html) else {
            return nil
        }

        let start = matchRange.upperBound
        var end = start
        while end < html.endIndex {
            let character = html[end]
            if character == "\n" || character == "\r" {
                break
            }
            end = html.index(after: end)
        }

        let json = String(html[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        return json.hasPrefix("[") ? json : nil
    }

    private static func parseSeries(seasonsJson: String) -> [CollapsSeason]? {
        guard let jsonData = seasonsJson.data(using: .utf8),
              let seasonsArray = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else {
            return nil
        }

        var seasons: [CollapsSeason] = []

        for seasonObject in seasonsArray {
            let seasonNum: Int
            if let value = seasonObject["season"] as? Int {
                seasonNum = value
            } else if let value = seasonObject["season"] as? String, let parsed = Int(value) {
                seasonNum = parsed
            } else {
                continue
            }

            guard seasonNum > 0,
                  let episodesArray = seasonObject["episodes"] as? [[String: Any]] else {
                continue
            }

            var episodes: [CollapsEpisode] = []

            for episodeObject in episodesArray {
                let episodeNum: Int
                if let value = episodeObject["episode"] as? Int {
                    episodeNum = value
                } else if let value = episodeObject["episode"] as? String, let parsed = Int(value) {
                    episodeNum = parsed
                } else {
                    continue
                }

                let hls = normalizedURLString(episodeObject["hls"] as? String)
                let dasha = normalizedURLString(episodeObject["dasha"] as? String)
                let dash = normalizedURLString(episodeObject["dash"] as? String)
                let mpd = dasha ?? dash

                let voices = parseVoiceNames(from: episodeObject)
                let subtitles = parseSubtitles(from: episodeObject["cc"])

                episodes.append(
                    CollapsEpisode(
                        season: seasonNum,
                        episode: episodeNum,
                        mpdUrl: mpd,
                        hlsUrl: hls,
                        voices: voices,
                        subtitles: subtitles
                    )
                )
            }

            if !episodes.isEmpty {
                episodes.sort { $0.episode < $1.episode }
                seasons.append(CollapsSeason(season: seasonNum, episodes: episodes))
            }
        }

        seasons.sort { $0.season < $1.season }
        return seasons
    }

    private static func parseMovie(from html: String) -> CollapsMovie? {
        var hls = extractFirstUrl(in: html, keys: ["hls"], suffix: ".m3u8")
        let dash = extractFirstUrl(in: html, keys: ["dasha", "dash"], suffix: ".mpd")

        if hls == nil,
           let payloadData = extractHlsSourcePayload(from: html) {
            hls = payloadData["hls"]
        }

        let resolvedHls = hls ?? firstPreferredStreamURLString(in: html)
        let voices = extractVoiceNames(from: html)
        let subtitles = extractSubtitles(in: html)

        if (dash?.isEmpty ?? true) && (resolvedHls?.isEmpty ?? true) {
            return nil
        }

        return CollapsMovie(
            mpdUrl: dash,
            hlsUrl: resolvedHls,
            voices: voices,
            subtitles: subtitles
        )
    }

    private static func extractFirstUrl(in html: String, keys: [String], suffix: String) -> String? {
        for key in keys {
            let pattern = #"(?is)\b\#(NSRegularExpression.escapedPattern(for: key))\s*:\s*['"]([^'"]+\#(NSRegularExpression.escapedPattern(for: suffix))[^'"]*)['"]"#
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let range = Range(match.range(at: 1), in: html) {
                return normalizedURLString(String(html[range]))
            }
        }
        return nil
    }

    private static func extractVoiceNames(from html: String) -> [String] {
        let directNames = extractStringArrayFromObject(html: html, objectKey: "audio", arrayKey: "names")
        if !directNames.isEmpty {
            return directNames
        }

        let patterns = [
            #"(?is)\btranslations\s*:\s*(\[[\s\S]*?\])"#,
            #"(?is)\"translations\"\s*:\s*(\[[\s\S]*?\])"#
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let range = Range(match.range(at: 1), in: html) {
                let raw = String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if raw.hasPrefix("["),
                   let data = raw.data(using: .utf8),
                   let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    return array.compactMap { object in
                        let name = (object["name"] as? String ?? object["title"] as? String ?? "")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        return name.isEmpty ? nil : name
                    }
                }
            }
        }

        return []
    }

    private static func extractStringArrayFromObject(html: String, objectKey: String, arrayKey: String) -> [String] {
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
                if raw.hasPrefix("["),
                   let data = raw.data(using: .utf8),
                   let array = try? JSONSerialization.jsonObject(with: data) as? [String] {
                    return array
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                }
            }
        }

        return []
    }

    private static func extractSubtitles(in html: String) -> [CollapsSubtitle] {
        let pattern = #"(?is)\bcc\s*:\s*(\[[^\]]*\])"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else {
            return []
        }

        let raw = String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.hasPrefix("["),
              let data = raw.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        return array.compactMap { item in
            subtitle(from: item)
        }
    }

    private static func parseSubtitles(from rawValue: Any?) -> [CollapsSubtitle] {
        guard let array = rawValue as? [[String: Any]] else { return [] }
        return array.compactMap { subtitle(from: $0) }
    }

    private static func subtitle(from object: [String: Any]) -> CollapsSubtitle? {
        let url = normalizedURLString((object["url"] as? String) ?? (object["src"] as? String))
        guard let url, !url.isEmpty else { return nil }

        let rawLabel = (object["name"] as? String ?? object["label"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let label = rawLabel.isEmpty ? "Subtitle" : rawLabel

        let rawLanguage = (object["lang"] as? String ?? object["language"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let language: String
        if !rawLanguage.isEmpty {
            language = rawLanguage
        } else if label.lowercased().contains("eng") || label.lowercased().contains("original") {
            language = "en"
        } else {
            language = "ru"
        }

        return CollapsSubtitle(url: url, label: label, lang: language)
    }

    private static func parseVoiceNames(from episodeObject: [String: Any]) -> [String] {
        guard let audio = episodeObject["audio"] as? [String: Any],
              let names = audio["names"] as? [String] else {
            return []
        }
        return names
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
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
                            resolvedHls = normalizedURLString(decoded)
                        }
                        if resolvedDash == nil && decoded.lowercased().contains(".mpd") {
                            resolvedDash = normalizedURLString(decoded)
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

    private static func firstPreferredStreamURLString(in payload: String) -> String? {
        let patterns = [
            #"https?:\\/\\/[^\"'\s>]+\\.m3u8[^\"'\s>]*"#,
            #"https?:\\/\\/[^\"'\s>]+\\.mpd[^\"'\s>]*"#,
            #"(?:\"|')((?:https?:)?//[^\"'\s>]+(?:m3u8|mpd)[^\"'\s>]*)"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(payload.startIndex..<payload.endIndex, in: payload)
            guard let match = regex.firstMatch(in: payload, range: range) else { continue }
            let targetRange = match.numberOfRanges > 1 ? match.range(at: 1) : match.range(at: 0)
            guard let valueRange = Range(targetRange, in: payload) else { continue }
            return normalizedURLString(String(payload[valueRange]))
        }
        return nil
    }

    private static func normalizedURLString(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value
            .replacingOccurrences(of: "\\/", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        if cleaned.hasPrefix("//") {
            return "https:" + cleaned
        }
        return cleaned
    }
}
