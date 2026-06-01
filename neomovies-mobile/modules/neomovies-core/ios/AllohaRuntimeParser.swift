import Foundation

enum AllohaRuntimeParser {
    static func parsePayload(_ payload: String, baseURL: String, headers: [String: String]) -> [String: Any]? {
        guard let url = URL(string: baseURL) else { return nil }

        if let stream = parseAllohaBNsiStream(payload, baseURL: url, headers: headers) {
            return stream
        }

        if let fallback = firstPreferredStreamURL(in: payload, baseURL: url) {
            return [
                "videoURL": fallback.absoluteString,
                "audioTracks": [],
                "audioVariants": [],
                "subtitles": subtitleTracks(in: payload, baseURL: url),
                "qualityVariants": [],
                "httpHeaders": headers
            ]
        }

        return nil
    }

    private static func parseAllohaBNsiStream(_ payload: String, baseURL: URL, headers: [String: String]) -> [String: Any]? {
        let candidates = [payload] + embeddedJSONObjectCandidates(in: payload)

        for candidate in candidates {
            guard let data = candidate.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let source = object["hlsSource"] as? [[String: Any]] else {
                continue
            }

            var qualityVariants: [[String: Any]] = []
            var audioVariants: [[String: Any]] = []
            var masterURL: URL?
            var adaptiveURL: URL?

            for (index, item) in source.enumerated() {
                guard let quality = item["quality"] as? [String: Any] else { continue }
                var itemVariants: [[String: Any]] = []
                var itemMasterURL: URL?
                var itemAdaptiveURL: URL?

                for (label, rawValue) in quality {
                    for rawURL in qualityURLStrings(from: rawValue) {
                        let urls = allohaURLs(from: rawURL, baseURL: baseURL)
                        if masterURL == nil {
                            masterURL = urls.first(where: { $0.lastPathComponent.lowercased().contains("master.m3u8") })
                        }
                        if adaptiveURL == nil {
                            adaptiveURL = preferredAdaptiveURL(in: urls)
                        }
                        if itemMasterURL == nil {
                            itemMasterURL = urls.first(where: { $0.lastPathComponent.lowercased().contains("master.m3u8") })
                        }
                        if itemAdaptiveURL == nil {
                            itemAdaptiveURL = preferredAdaptiveURL(in: urls)
                        }
                        guard let target = urls.first(where: { !$0.lastPathComponent.lowercased().contains("master.m3u8") }) ?? urls.first else {
                            continue
                        }

                        let variant: [String: Any] = [
                            "label": normalizedQualityLabel(label),
                            "bandwidth": NSNull(),
                            "resolution": NSNull(),
                            "url": target.absoluteString
                        ]
                        itemVariants.append(variant)
                        qualityVariants.append(variant)
                    }
                }

                let sortedItemVariants = itemVariants.sorted { qualityHeight(($0["label"] as? String) ?? "") < qualityHeight(($1["label"] as? String) ?? "") }
                let chosenAudioURL = itemMasterURL
                    ?? itemAdaptiveURL
                    ?? sortedItemVariants.last.flatMap { URL(string: ($0["url"] as? String) ?? "") }
                if let chosenAudioURL {
                    audioVariants.append([
                        "id": "\(index)-\(chosenAudioURL.absoluteString)",
                        "title": audioVariantTitle(from: item, index: index),
                        "url": chosenAudioURL.absoluteString,
                        "qualityVariants": sortedItemVariants
                    ])
                }
            }

            qualityVariants.sort { qualityHeight(($0["label"] as? String) ?? "") < qualityHeight(($1["label"] as? String) ?? "") }
            let deduplicatedAudioVariants = deduplicatedAudioVariants(audioVariants)
            let firstURL = deduplicatedAudioVariants.first?["url"] as? String
            let pickedURL = masterURL?.absoluteString
                ?? adaptiveURL?.absoluteString
                ?? firstURL
                ?? (qualityVariants.last?["url"] as? String)
            guard let pickedURL else { continue }

            return [
                "videoURL": pickedURL,
                "audioTracks": [],
                "audioVariants": deduplicatedAudioVariants,
                "subtitles": subtitleTracks(in: payload, baseURL: baseURL),
                "qualityVariants": qualityVariants,
                "httpHeaders": headers
            ]
        }

        return nil
    }

    private static func deduplicatedAudioVariants(_ variants: [[String: Any]]) -> [[String: Any]] {
        var seen = Set<String>()
        return variants.filter { variant in
            let key = variant["url"] as? String ?? ""
            return seen.insert(key).inserted
        }
    }

    private static func audioVariantTitle(from item: [String: Any], index: Int) -> String {
        if let title = firstAudioTitle(in: item) { return title }
        return "Озвучка \(index + 1)"
    }

    private static func qualityURLStrings(from value: Any) -> [String] {
        if let string = value as? String {
            return [string]
        }
        if let values = value as? [Any] {
            return values.flatMap { qualityURLStrings(from: $0) }
        }
        if let dictionary = value as? [String: Any] {
            let preferredKeys = ["url", "file", "src", "hls", "master", "manifest", "link"]
            let preferredValues = preferredKeys.compactMap { dictionary[$0] }.flatMap(qualityURLStrings)
            if !preferredValues.isEmpty { return preferredValues }
            return dictionary.values.flatMap(qualityURLStrings)
        }
        return []
    }

    private static func allohaURLs(from raw: String, baseURL: URL) -> [URL] {
        splitAllohaURLList(raw)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .compactMap { makeURL(from: $0, baseURL: baseURL) }
            .filter(isPlayable)
    }

    private static func normalizedQualityLabel(_ label: String) -> String {
        let clean = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.lowercased().hasSuffix("p") { return clean }
        if Int(clean) != nil { return "\(clean)p" }
        return clean.isEmpty ? "Поток" : clean
    }

    private static func qualityHeight(_ label: String) -> Int {
        Int(label.lowercased().replacingOccurrences(of: "p", with: "")) ?? 0
    }

    private static func preferredAdaptiveURL(in urls: [URL]) -> URL? {
        if let master = urls.first(where: { $0.lastPathComponent.lowercased().contains("master.m3u8") }) {
            return master
        }
        if urls.count > 1 {
            let second = urls[1]
            if second.absoluteString.lowercased().contains(".m3u8") {
                return second
            }
        }
        return urls.first(where: { $0.absoluteString.lowercased().contains(".m3u8") })
    }

    private static func firstPreferredStreamURL(in payload: String, baseURL: URL) -> URL? {
        for key in ["hls", "dash", "mp4", "file", "url", "src", "stream", "manifest"] {
            let patterns = [
                #"\b"# + key + #"\s*:\s*"([^"]+)""#,
                #"\b"# + key + #"\s*:\s*'([^']+)'"#,
                #"""# + key + #""\s*:\s*"([^"]+)""#,
                #"""# + key + #""\s*:\s*'([^']+)'"#,
                #"\b"# + key + #"\s*=\s*"([^"]+)""#,
                #"\b"# + key + #"\s*=\s*'([^']+)'"#
            ]

            for pattern in patterns {
                if let value = firstCapture(in: payload, pattern: pattern),
                   let url = makeURL(from: value, baseURL: baseURL),
                   isPlayable(url) {
                    return url
                }
            }
        }

        return firstURL(in: payload, matchingExtensions: ["m3u8", "mp4", "mpd"], baseURL: baseURL)
            ?? firstEscapedURL(in: payload, matchingExtensions: ["m3u8", "mp4", "mpd"], baseURL: baseURL)
    }

    private static func subtitleTracks(in payload: String, baseURL: URL) -> [[String: Any]] {
        let patterns = [
            #"\{\s*"url"\s*:\s*"([^"]+\.(?:vtt|srt)(?:\?[^"]*)?)"\s*,\s*"name"\s*:\s*"([^"]+)""#,
            #"\{\s*url\s*:\s*"([^"]+\.(?:vtt|srt)(?:\?[^"]*)?)"\s*,\s*name\s*:\s*"([^"]+)""#,
            #"\{\s*"name"\s*:\s*"([^"]+)"\s*,\s*"url"\s*:\s*"([^"]+\.(?:vtt|srt)(?:\?[^"]*)?)""#
        ]

        var tracks: [[String: Any]] = []
        for pattern in patterns {
            tracks.append(contentsOf: subtitleTracks(in: payload, pattern: pattern, baseURL: baseURL))
        }
        if tracks.isEmpty, let url = firstURL(in: payload, matchingExtensions: ["vtt", "srt"], baseURL: baseURL) {
            tracks.append(["name": "Субтитры", "url": url.absoluteString])
        }
        var seen = Set<String>()
        return tracks.filter { track in
            let key = track["url"] as? String ?? ""
            return seen.insert(key).inserted
        }
    }

    private static func embeddedJSONObjectCandidates(in payload: String) -> [String] {
        var candidates = balancedJSONObjectCandidates(containing: #"\"hlsSource\""#, in: payload)
        candidates.append(contentsOf: balancedJSONObjectCandidates(containing: "hlsSource", in: payload))
        let pattern = #"\{[^{}]*"hlsSource"\s*:\s*\[[\s\S]*?\]\s*(?:,[\s\S]*?)?\}"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
            let range = NSRange(payload.startIndex..<payload.endIndex, in: payload)
            candidates.append(contentsOf: regex.matches(in: payload, range: range).compactMap { match in
                guard let r = Range(match.range, in: payload) else { return nil }
                return String(payload[r])
            })
        }
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
        var quoted = false
        var escaped = false
        var index = start
        while index < payload.endIndex {
            let char = payload[index]
            if escaped {
                escaped = false
            } else if char == "\\" {
                escaped = true
            } else if char == "\"" {
                quoted.toggle()
            } else if !quoted {
                if char == "{" {
                    depth += 1
                } else if char == "}" {
                    depth -= 1
                    if depth == 0 { return index }
                }
            }
            index = payload.index(after: index)
        }
        return nil
    }

    private static func splitAllohaURLList(_ rawValue: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"\s+or\s+"#, options: [.caseInsensitive]) else {
            return rawValue.components(separatedBy: " or ")
        }
        let range = NSRange(rawValue.startIndex..<rawValue.endIndex, in: rawValue)
        let normalized = regex.stringByReplacingMatches(in: rawValue, range: range, withTemplate: "\u{0}")
        return normalized.components(separatedBy: "\u{0}")
    }

    private static func decodeJavaScriptString(_ value: String) -> String {
        let quoted = "\"\(value)\""
        if let data = quoted.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(String.self, from: data) {
            return decoded
        }
        // Fallback: manual decode of common sequences
        return value
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\\u0026", with: "&")
            .replacingOccurrences(of: "\\u003d", with: "=")
            .replacingOccurrences(of: "\\u002f", with: "/")
            .replacingOccurrences(of: "\\u003a", with: ":")
            .replacingOccurrences(of: "\\u0025", with: "%")
            .replacingOccurrences(of: "\\n", with: "")
            .replacingOccurrences(of: "\\t", with: "")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    private static func makeURL(from rawValue: String, baseURL: URL) -> URL? {
        let cleanValue = decodeJavaScriptString(rawValue)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#x2F;", with: "/")
            .replacingOccurrences(of: "&#47;", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        guard !cleanValue.isEmpty else { return nil }
        if cleanValue.hasPrefix("//") {
            return URL(string: "https:\(cleanValue)")
        }
        if let absolute = URL(string: cleanValue), absolute.scheme != nil {
            return absolute
        }
        return URL(string: cleanValue, relativeTo: baseURL)?.absoluteURL
    }

    private static func isPlayable(_ url: URL) -> Bool {
        let path = url.absoluteString.lowercased()
        return path.contains(".m3u8") || path.contains(".mpd") || path.contains(".mp4")
    }

    private static func firstCapture(in text: String, pattern: String, captureGroup: Int = 1) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > captureGroup,
              let r = Range(match.range(at: captureGroup), in: text) else {
            return nil
        }
        return String(text[r])
    }

    private static func firstURL(in text: String, matchingExtensions extensions: [String], baseURL: URL) -> URL? {
        let escaped = extensions.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        let pattern = #"https?:\/\/[^\s"'<>\\]+\.("# + escaped + #")(?:\?[^\s"'<>\\]*)?"#
        guard let value = firstCapture(in: text, pattern: pattern, captureGroup: 0) else { return nil }
        return makeURL(from: value, baseURL: baseURL)
    }

    private static func firstEscapedURL(in text: String, matchingExtensions extensions: [String], baseURL: URL) -> URL? {
        let escaped = extensions.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        let pattern = #"https?:\\\/\\\/[^\s"'<>]+\.("# + escaped + #")(?:\?[^\s"'<>\\]*)?"#
        guard let value = firstCapture(in: text, pattern: pattern, captureGroup: 0) else { return nil }
        return makeURL(from: value, baseURL: baseURL)
    }

    private static func subtitleTracks(in text: String, pattern: String, baseURL: URL) -> [[String: Any]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges >= 3,
                  let firstRange = Range(match.range(at: 1), in: text),
                  let secondRange = Range(match.range(at: 2), in: text) else {
                return nil
            }
            let first = String(text[firstRange])
            let second = String(text[secondRange])
            let urlCandidate = first.contains(".vtt") || first.contains(".srt") ? first : second
            let nameCandidate = urlCandidate == first ? second : first
            guard let url = makeURL(from: urlCandidate, baseURL: baseURL) else { return nil }
            return ["name": decodeJavaScriptString(nameCandidate), "url": url.absoluteString]
        }
    }

    private static func firstAudioTitle(in value: Any) -> String? {
        if let dictionary = value as? [String: Any] {
            for key in preferredAudioTitleKeys {
                if let title = stringTitle(from: dictionary[key]) {
                    return title
                }
            }
            let candidates = dictionary
                .filter { key, val in isLikelyAudioTitleKey(key) && stringTitle(from: val) != nil }
                .compactMap { stringTitle(from: $0.value) }
            if let title = candidates.first {
                return title
            }
            for key in preferredAudioContainerKeys {
                if let nested = dictionary[key], let title = firstAudioTitle(in: nested) {
                    return title
                }
            }
            for (key, nested) in dictionary where !isIgnoredAudioTitleContainer(key) {
                if let title = firstAudioTitle(in: nested) {
                    return title
                }
            }
        }
        if let array = value as? [Any] {
            for item in array {
                if let title = firstAudioTitle(in: item) {
                    return title
                }
            }
        }
        return nil
    }

    private static var preferredAudioTitleKeys: [String] {
        [
            "translation", "translationName", "translation_name", "translator", "translatorName", "translator_name",
            "studio", "studioName", "studio_name", "voice", "voiceName", "voice_name", "voiceover", "dub",
            "dubbing", "name", "title", "label"
        ]
    }

    private static var preferredAudioContainerKeys: [String] {
        ["translation", "translator", "voice", "voiceover", "dub", "dubbing", "studio", "data"]
    }

    private static func isLikelyAudioTitleKey(_ key: String) -> Bool {
        let lower = key.lowercased()
        return lower.contains("translation") ||
            lower.contains("translator") ||
            lower.contains("studio") ||
            lower.contains("voice") ||
            lower.contains("dub") ||
            lower == "name" ||
            lower == "title" ||
            lower == "label"
    }

    private static func isIgnoredAudioTitleContainer(_ key: String) -> Bool {
        let lower = key.lowercased()
        return lower == "quality" ||
            lower.contains("source") ||
            lower.contains("hls") ||
            lower.contains("url") ||
            lower.contains("file")
    }

    private static func stringTitle(from value: Any?) -> String? {
        guard let value else { return nil }
        if let string = value as? String {
            let clean = decodeJavaScriptString(string)
                .replacingOccurrences(of: "_", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty,
                  !clean.localizedCaseInsensitiveContains(".m3u8"),
                  URL(string: clean)?.scheme == nil else {
                return nil
            }
            return clean
        }
        if value is NSNumber { return nil }
        return nil
    }
}
