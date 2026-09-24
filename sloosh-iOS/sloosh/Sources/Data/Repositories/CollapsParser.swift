import Foundation

final class CollapsParser {
    struct ParseResult {
        let catalog: CollapsCatalog
        let apiResult: AllohaApiResult
        let episodeSubtitles: [EpisodeKey: [PlaybackSubtitle]]
        let movieSubtitles: [PlaybackSubtitle]
    }

    static func parseCatalog(embedHtml: String, defaultTitle: String) -> ParseResult? {
        let trimmed = embedHtml.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 1. Try parsing as TV series
        if let seasonsJson = extractSeasonsJson(from: trimmed),
           let seriesData = parseSeries(seasonsJson: seasonsJson, title: defaultTitle) {
            return seriesData
        }

        // 2. Try parsing as movie
        if let movieData = parseMovie(from: trimmed, title: defaultTitle) {
            return movieData
        }

        return nil
    }

    // MARK: - TV Series Extraction

    private static func extractSeasonsJson(from html: String) -> String? {
        guard let pattern = try? NSRegularExpression(pattern: #"(?i)\bseasons\s*:\s*\["#, options: []),
              let match = pattern.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)) else {
            return nil
        }

        // Bracket balancing starting at the '['
        let bracketNSRange = NSRange(location: match.range.location + match.range.length - 1, length: 1)
        guard let startIndex = Range(bracketNSRange, in: html)?.lowerBound else { return nil }

        var depth = 0
        var isQuoted = false
        var isEscaped = false
        var index = startIndex

        while index < html.endIndex {
            let char = html[index]
            if isEscaped {
                isEscaped = false
            } else if char == "\\" {
                isEscaped = true
            } else if char == "\"" || char == "'" {
                isQuoted.toggle()
            } else if !isQuoted {
                if char == "[" {
                    depth += 1
                } else if char == "]" {
                    depth -= 1
                    if depth == 0 {
                        return String(html[startIndex...index])
                    }
                }
            }
            index = html.index(after: index)
        }

        return nil
    }

    private static func parseSeries(seasonsJson: String, title: String) -> ParseResult? {
        guard let jsonData = seasonsJson.data(using: .utf8),
              let seasonsArray = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else {
            return nil
        }

        var collapsSeasons: [CollapsSeason] = []
        var allohaSeasons: [AllohaSeason] = []
        var epSubtitlesMap: [EpisodeKey: [PlaybackSubtitle]] = [:]

        for seasonObj in seasonsArray {
            let seasonNum: Int
            if let val = seasonObj["season"] as? Int {
                seasonNum = val
            } else if let str = seasonObj["season"] as? String, let parsed = Int(str) {
                seasonNum = parsed
            } else {
                continue
            }

            guard seasonNum > 0,
                  let episodesArray = seasonObj["episodes"] as? [[String: Any]] else {
                continue
            }

            var collapsEpisodes: [CollapsEpisode] = []
            var allohaEpisodes: [AllohaEpisode] = []

            for epObj in episodesArray {
                let episodeNum: Int
                if let val = epObj["episode"] as? Int {
                    episodeNum = val
                } else if let str = epObj["episode"] as? String, let parsed = Int(str) {
                    episodeNum = parsed
                } else {
                    continue
                }

                let rawHls = (epObj["hls"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let rawDasha = (epObj["dasha"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let rawDash = (epObj["dash"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let rawMpd = rawDasha ?? rawDash

                let hls = rawHls.flatMap { $0.isEmpty ? nil : normalizeStreamUrl($0) }
                let mpd = rawMpd.flatMap { $0.isEmpty ? nil : normalizeStreamUrl($0) }
                let primaryUrl = hls ?? mpd ?? ""

                var voices: [String] = []
                if let audio = epObj["audio"] as? [String: Any] {
                    voices = extractOrderedVoices(from: audio)
                }
                if voices.isEmpty {
                    voices = ["Основная"]
                }

                var collapsSubs: [CollapsSubtitle] = []
                var playbackSubs: [PlaybackSubtitle] = []
                if let cc = epObj["cc"] as? [[String: Any]] {
                    for subObj in cc {
                        let url = (subObj["url"] as? String ?? subObj["src"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !url.isEmpty else { continue }
                        let label = (subObj["name"] as? String ?? subObj["label"] as? String ?? "Русские").trimmingCharacters(in: .whitespacesAndNewlines)
                        let langRaw = (subObj["lang"] as? String ?? subObj["language"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        let lang = langRaw.isEmpty
                            ? ((label.lowercased().contains("eng") || label.lowercased().contains("original")) ? "en" : "ru")
                            : langRaw

                        collapsSubs.append(CollapsSubtitle(url: url, label: label, language: lang))
                        playbackSubs.append(PlaybackSubtitle(url: url, label: label, lang: lang))
                    }
                }

                let playlist = CollapsPlaylist(
                    primaryUrl: primaryUrl,
                    hlsUrl: hls,
                    dashUrl: mpd,
                    voiceovers: voices,
                    subtitles: collapsSubs
                )
                let collapsEp = CollapsEpisode(
                    season: seasonNum,
                    episode: episodeNum,
                    title: "\(episodeNum) серия",
                    playlist: playlist
                )
                collapsEpisodes.append(collapsEp)

                epSubtitlesMap[EpisodeKey(season: seasonNum, episode: episodeNum)] = playbackSubs

                let translations = voices.map { voiceName in
                    AllohaTranslation(
                        id: voiceName,
                        name: voiceName,
                        iframeUrl: "",
                        streamUrl: primaryUrl
                    )
                }
                allohaEpisodes.append(AllohaEpisode(season: seasonNum, episode: episodeNum, translations: translations))
            }

            if !collapsEpisodes.isEmpty {
                collapsEpisodes.sort { $0.episode < $1.episode }
                allohaEpisodes.sort { $0.episode < $1.episode }

                collapsSeasons.append(CollapsSeason(season: seasonNum, title: "\(seasonNum) сезон", episodes: collapsEpisodes))
                allohaSeasons.append(AllohaSeason(season: seasonNum, episodes: allohaEpisodes))
            }
        }

        guard !allohaSeasons.isEmpty else { return nil }

        collapsSeasons.sort { $0.season < $1.season }
        allohaSeasons.sort { $0.season < $1.season }

        let catalog = CollapsCatalog.series(source: "collaps", seasons: collapsSeasons)
        let apiResult = AllohaApiResult(
            title: title,
            isSerial: true,
            movie: nil,
            seasons: allohaSeasons
        )

        return ParseResult(
            catalog: catalog,
            apiResult: apiResult,
            episodeSubtitles: epSubtitlesMap,
            movieSubtitles: []
        )
    }

    private static func normalizeStreamUrl(_ urlString: String) -> String {
        var str = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if str.hasPrefix("//") {
            str = "https:" + str
        }
        str = str.replacingOccurrences(of: "\\/", with: "/")
        if !str.isEmpty && !str.contains("vp") && !str.contains("&vp") && !str.contains("?vp") {
            str += str.contains("?") ? "&vp" : "?vp"
        }
        return str
    }

    private static func extractOrderedVoices(from audioObj: [String: Any]) -> [String] {
        guard let names = audioObj["names"] as? [String] else { return [] }

        var result: [String] = []
        for (idx, raw) in names.enumerated() {
            var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.lowercased() == "delete" {
                name = "Дорожка \(idx + 1)"
            }
            // Sanitize inner double quotes which break HLS EXT-X-MEDIA attributes in AVPlayer
            name = name.replacingOccurrences(of: "\"", with: "'")
            result.append(name)
        }

        return result.filter { !$0.isEmpty }
    }


    // MARK: - Movie Extraction

    private static func parseMovie(from html: String, title: String) -> ParseResult? {
        var hlsUrl: String?
        var dashUrl: String?

        // 1. Regex for hls
        if let hlsPattern = try? NSRegularExpression(pattern: #"(?i)\bhls\s*:\s*['\"]([^'\"]+\.m3u8[^'\"]*)['\"]"#, options: []),
           let match = hlsPattern.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html) {
            hlsUrl = String(html[range])
        }

        // 2. Regex for dash
        if let dashPattern = try? NSRegularExpression(pattern: #"(?i)\b(dasha|dash)\s*:\s*['\"]([^'\"]+\.mpd[^'\"]*)['\"]"#, options: []),
           let match = dashPattern.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 2), in: html) {
            dashUrl = String(html[range])
        }

        // 3. Embedded JSON hlsSource fallback
        if hlsUrl == nil {
            if let payload = extractHlsSourcePayload(from: html) {
                hlsUrl = payload["hls"]
                if dashUrl == nil { dashUrl = payload["dash"] }
            }
        }

        // 4. URL scan fallback
        if hlsUrl == nil {
            hlsUrl = firstPreferredStreamURLString(in: html)
        }

        if let rawHls = hlsUrl {
            hlsUrl = normalizeStreamUrl(rawHls)
        }
        if let rawDash = dashUrl {
            dashUrl = normalizeStreamUrl(rawDash)
        }

        guard let primaryUrl = hlsUrl ?? dashUrl, !primaryUrl.isEmpty else { return nil }

        // Extract audio names for movie if present (e.g. audio: {"names": ["Дублированный", ...], "order": [...]})
        var voices: [String] = []
        if let audioPattern = try? NSRegularExpression(pattern: #"(?i)\baudio\s*:\s*(\{[^\r\n]+\})"#, options: []),
           let match = audioPattern.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html),
           let data = String(html[range]).data(using: .utf8),
           let audioObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            voices = extractOrderedVoices(from: audioObj)
        }
        if voices.isEmpty {
            voices = ["Основная дорожка"]
        }

        // Extract subtitles for movie if present (e.g. cc: [{url: "...", name: "..."}])
        var collapsSubs: [CollapsSubtitle] = []
        var playbackSubs: [PlaybackSubtitle] = []
        if let ccPattern = try? NSRegularExpression(pattern: #"(?i)\bcc\s*:\s*(\[[^\r\n]+\])"#, options: []),
           let match = ccPattern.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html),
           let data = String(html[range]).data(using: .utf8),
           let ccArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            for subObj in ccArray {
                let url = (subObj["url"] as? String ?? subObj["src"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !url.isEmpty else { continue }
                let label = (subObj["name"] as? String ?? subObj["label"] as? String ?? "Русские").trimmingCharacters(in: .whitespacesAndNewlines)
                let langRaw = (subObj["lang"] as? String ?? subObj["language"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let lang = langRaw.isEmpty
                    ? ((label.lowercased().contains("eng") || label.lowercased().contains("original")) ? "en" : "ru")
                    : langRaw

                collapsSubs.append(CollapsSubtitle(url: url, label: label, language: lang))
                playbackSubs.append(PlaybackSubtitle(url: url, label: label, lang: lang))
            }
        }

        let playlist = CollapsPlaylist(
            primaryUrl: primaryUrl,
            hlsUrl: hlsUrl,
            dashUrl: dashUrl,
            voiceovers: voices,
            subtitles: collapsSubs
        )

        let catalog = CollapsCatalog.movie(source: "collaps", playlist: playlist)
        let translations = voices.map { voice in
            AllohaTranslation(
                id: voice,
                name: voice,
                iframeUrl: "",
                streamUrl: primaryUrl
            )
        }
        let allohaMovie = AllohaMovie(
            title: title,
            iframeUrl: "",
            translations: translations
        )
        let apiResult = AllohaApiResult(
            title: title,
            isSerial: false,
            movie: allohaMovie,
            seasons: []
        )

        return ParseResult(
            catalog: catalog,
            apiResult: apiResult,
            episodeSubtitles: [:],
            movieSubtitles: playbackSubs
        )
    }

    // MARK: - Stream URL Fallbacks

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
        let candidates = balancedJSONObjectCandidates(containing: "hlsSource", in: payload)
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
            return text.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        if let nested = value as? [Any] {
            return nested.flatMap { qualityURLStrings(from: $0) }
        }
        if let nestedDict = value as? [String: Any] {
            return nestedDict.values.flatMap { qualityURLStrings(from: $0) }
        }
        return []
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
}
