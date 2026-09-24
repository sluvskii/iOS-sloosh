import Foundation

class PlaybackHlsRewriter {
    static func normalizeResolutionLabel(width: Int, height: Int) -> String {
        if width >= 1900 || height >= 800 {
            return "1080p"
        } else if width >= 1200 || height >= 500 {
            return "720p"
        } else if width >= 800 || height >= 400 {
            return "480p"
        } else if width >= 600 || height >= 250 {
            return "360p"
        } else if height > 0 {
            return "\(height)p"
        } else {
            return "HD"
        }
    }

    private struct ParsedVariant {
        var streamInfLine: String
        var uriLine: String
        var resolutionLabel: String
        var bandwidth: Double
        var height: Int
        var width: Int
    }

    static func rewrite(
        master: String,
        voices: [String],
        subtitles: [PlaybackSubtitle] = [],
        mediaId: String,
        targetQuality: String? = nil,
        rewriteVariantUris: Bool = false,
        stripExistingSubtitles: Bool = false
    ) -> String {
        guard !master.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return master
        }
        
        let lines = master.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        
        var output: [String] = []
        let subsGroupId = "subs0"
        
        let rawFiltered = filterFailoverDuplicates(lines: lines)
        let filteredLines: [String]
        if lines.contains(where: { $0.hasPrefix("#EXT-X-STREAM-INF") }) && !rawFiltered.contains(where: { $0.hasPrefix("#EXT-X-STREAM-INF") }) {
            filteredLines = lines
        } else {
            filteredLines = rawFiltered
        }

        let streamInfIndex = filteredLines.firstIndex { $0.hasPrefix("#EXT-X-STREAM-INF") } ?? filteredLines.count
        let hasMediaTags = filteredLines.contains { $0.hasPrefix("#EXT-X-MEDIA") }
        var hasEmittedVersion = false
        
        for i in 0..<streamInfIndex {
            let line = filteredLines[i]
            if stripExistingSubtitles && isSubtitleMediaLine(line) {
                continue
            }
            if line.hasPrefix("#EXT-X-VERSION:") {
                hasEmittedVersion = true
                let vStr = line.replacingOccurrences(of: "#EXT-X-VERSION:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                // RFC 8216 Section 7: "A Playlist that contains an EXT-X-MEDIA tag MUST contain an EXT-X-VERSION tag with a value of 4 or higher."
                if let v = Int(vStr), v < 4, hasMediaTags {
                    output.append("#EXT-X-VERSION:4")
                    continue
                }
            }
            output.append(rewriteMediaLine(line, voices: voices))
        }

        if hasMediaTags && !hasEmittedVersion && !output.contains(where: { $0.hasPrefix("#EXT-X-VERSION:") }) {
            if let extm3uIdx = output.firstIndex(where: { $0.hasPrefix("#EXTM3U") }) {
                output.insert("#EXT-X-VERSION:4", at: extm3uIdx + 1)
            } else {
                output.insert("#EXT-X-VERSION:4", at: 0)
            }
        }

        if !subtitles.isEmpty {
            for sub in subtitles {
                let lang = sub.lang.isEmpty ? "ru" : sub.lang
                let label = sub.label.isEmpty ? "Subtitle" : sub.label
                let uri = sub.url
                guard !uri.isEmpty else { continue }
                
                output.append("#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID=\"\(subsGroupId)\",NAME=\"\(escapeAttr(label))\",DEFAULT=NO,AUTOSELECT=YES,LANGUAGE=\"\(escapeAttr(lang))\",URI=\"\(escapeAttr(uri))\"")
            }
        }
        
        // Parse variant entries: (#EXT-X-STREAM-INF, URI)
        var parsedVariants: [ParsedVariant] = []
        var idx = streamInfIndex
        while idx < filteredLines.count {
            let line = filteredLines[idx]
            if line.hasPrefix("#EXT-X-STREAM-INF") {
                var modifiedLine = normalizeStreamInfVideoRange(line)
                if !subtitles.isEmpty {
                    modifiedLine = addOrReplaceAttribute(modifiedLine, key: "SUBTITLES", value: subsGroupId)
                }

                var width = 0
                var height = 0
                if let resRange = line.range(of: "RESOLUTION=([0-9]+)x([0-9]+)", options: .regularExpression) {
                    let resStr = String(line[resRange]).replacingOccurrences(of: "RESOLUTION=", with: "")
                    let parts = resStr.components(separatedBy: "x")
                    if parts.count == 2 {
                        width = Int(parts[0]) ?? 0
                        height = Int(parts[1]) ?? 0
                    }
                }

                var bandwidth: Double = 0
                if let bwRange = line.range(of: "BANDWIDTH=([0-9]+)", options: .regularExpression) {
                    let bwStr = String(line[bwRange]).replacingOccurrences(of: "BANDWIDTH=", with: "")
                    bandwidth = Double(bwStr) ?? 0
                }

                let resLabel = normalizeResolutionLabel(width: width, height: height)

                var uri = ""
                var nextIdx = idx + 1
                while nextIdx < filteredLines.count {
                    let nextLine = filteredLines[nextIdx]
                    if !nextLine.hasPrefix("#") && !nextLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        uri = nextLine
                        nextIdx += 1
                        break
                    }
                    nextIdx += 1
                }

                if !uri.isEmpty {
                    parsedVariants.append(ParsedVariant(
                        streamInfLine: modifiedLine,
                        uriLine: uri,
                        resolutionLabel: resLabel,
                        bandwidth: bandwidth,
                        height: height,
                        width: width
                    ))
                }
                idx = nextIdx
            } else {
                idx += 1
            }
        }

        // Sort parsed variants descending so highest resolution & bitrate is always first
        parsedVariants.sort { (a, b) -> Bool in
            let scoreA = a.height * 100_000_000 + Int(a.bandwidth)
            let scoreB = b.height * 100_000_000 + Int(b.bandwidth)
            return scoreA > scoreB
        }

        // Apply quality filter if requested (e.g. "1080p", "720p", "360p")
        var finalVariants = parsedVariants
        if let targetQuality, !targetQuality.isEmpty, targetQuality != "Авто", targetQuality.lowercased() != "auto" {
            let matches = parsedVariants.filter { $0.resolutionLabel.lowercased() == targetQuality.lowercased() }
            if !matches.isEmpty {
                finalVariants = matches
            } else if let maxHeight = parsedVariants.map({ $0.height }).max(), maxHeight > 0 {
                // If requested resolution (e.g. 1080p) exceeds available, lock to highest available resolution (e.g. 720p)
                finalVariants = parsedVariants.filter { $0.height == maxHeight }
            }
        }

        if !finalVariants.isEmpty {
            var variantIndex = 0
            for v in finalVariants {
                output.append(v.streamInfLine)
                if rewriteVariantUris {
                    let newUri = "\(mediaId)_\(variantIndex).m3u8"
                    output.append(newUri)
                } else {
                    output.append(v.uriLine)
                }
                variantIndex += 1
            }
        } else {
            // Fallback to original loop if no variant pairs could be parsed
            var variantIndex = 0
            for i in streamInfIndex..<filteredLines.count {
                let line = filteredLines[i]
                if line.hasPrefix("#EXT-X-STREAM-INF") {
                    var modifiedLine = normalizeStreamInfVideoRange(line)
                    if !subtitles.isEmpty {
                        modifiedLine = addOrReplaceAttribute(modifiedLine, key: "SUBTITLES", value: subsGroupId)
                    }
                    output.append(modifiedLine)
                } else if !line.hasPrefix("#") && !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if rewriteVariantUris {
                        let newUri = "\(mediaId)_\(variantIndex).m3u8"
                        output.append(newUri)
                    } else {
                        output.append(line)
                    }
                    variantIndex += 1
                } else {
                    output.append(line)
                }
            }
        }
        
        return output.joined(separator: "\n")
    }
    
    private static func filterFailoverDuplicates(lines: [String]) -> [String] {
        var filtered: [String] = []
        var seenVariantKeys = Set<String>()
        var i = 0
        
        while i < lines.count {
            let line = lines[i]
            
            if line.hasPrefix("#EXT-X-MEDIA") {
                if let groupId = extractQuotedAttr(line, key: "GROUP-ID"),
                   groupId.lowercased().hasPrefix("failover-") {
                    i += 1
                    continue
                }
                filtered.append(line)
                i += 1
                continue
            }
            
            if line.hasPrefix("#EXT-X-STREAM-INF") {
                if isUnsupportedCodec(line) {
                    i += 2
                    continue
                }

                if let audioGroup = extractQuotedAttr(line, key: "AUDIO"),
                   audioGroup.lowercased().hasPrefix("failover-") {
                    i += 2
                    continue
                }
                
                let resolution = extractAttrValue(line, key: "RESOLUTION")
                let bandwidth = extractAttrValue(line, key: "BANDWIDTH")
                let codecs = extractQuotedAttr(line, key: "CODECS")
                let audioGroup = extractQuotedAttr(line, key: "AUDIO")
                let key = [resolution, bandwidth, codecs, audioGroup].compactMap { $0 }.joined(separator: "|")
                
                if !key.isEmpty && !seenVariantKeys.insert(key).inserted {
                    i += 2
                    continue
                }
                
                filtered.append(line)
                if i + 1 < lines.count {
                    filtered.append(lines[i + 1])
                }
                i += 2
                continue
            }
            
            filtered.append(line)
            i += 1
        }
        
        return filtered
    }
    
    private static func isUnsupportedCodec(_ line: String) -> Bool {
        let lower = line.lowercased()
        // AV1 is unsupported on older iOS decoders
        if lower.contains("av01.") || lower.contains("av1") { return true }
        
        // Filter out resolutions with height > 1080 (e.g. 1440p, 2160p, 4K)
        if let resRange = line.range(of: "RESOLUTION=([^,\\s]+)", options: .regularExpression) {
            let resStr = String(line[resRange]).replacingOccurrences(of: "RESOLUTION=", with: "")
            let parts = resStr.components(separatedBy: "x")
            if parts.count == 2, let h = Int(parts[1]), h > 1080 {
                return true
            }
        }
        return false
    }

    /// Strips VIDEO-RANGE=PQ and VIDEO-RANGE=HLG from non-HEVC/Dolby-Vision STREAM-INF lines.
    /// iOS AVPlayer does not support H.264 with HDR transfer functions — this causes -11848 / -16190.
    private static func normalizeStreamInfVideoRange(_ line: String) -> String {
        let lower = line.lowercased()
        let isHdrCapable = lower.contains("hvc1") || lower.contains("hev1") || lower.contains("dvh1") || lower.contains("dvhe")
        guard !isHdrCapable else { return line }
        
        var result = line
        if let regex = try? NSRegularExpression(pattern: ",?\\s*VIDEO-RANGE=[^,\\s]+", options: .caseInsensitive) {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }
        return result
    }
    
    private static func rewriteMediaLine(_ line: String, voices: [String]) -> String {
        guard line.hasPrefix("#EXT-X-MEDIA") else { return line }
        guard line.contains("TYPE=AUDIO") else { return line }
        guard !voices.isEmpty else { return line }

        let rawName = extractQuotedAttr(line, key: "NAME")
        let uri = extractQuotedAttr(line, key: "URI")
        let language = extractQuotedAttr(line, key: "LANGUAGE")

        let index = extractAudioIndex(from: rawName)
            ?? extractAudioIndex(from: uri, isUri: true)
            ?? extractAudioIndex(from: language)

        guard let index, index >= 0, index < voices.count else { return line }

        // Only rewrite if rawName is missing or generic (e.g. "rus0", "fin3", "ukr4", "audio0")
        if let raw = rawName, !isGenericTrackName(raw) {
            return line
        }

        let voiceName = voices[index]
        let normalizedLang: String
        let lower = voiceName.lowercased()
        if lower.contains("eng") || lower.contains("original") || lower.contains("англ") {
            normalizedLang = "en"
        } else {
            normalizedLang = "ru"
        }

        var output = addOrReplaceAttribute(line, key: "NAME", value: voiceName)
        output = addOrReplaceAttribute(output, key: "LANGUAGE", value: normalizedLang)
        return output
    }

    private static func isGenericTrackName(_ name: String) -> Bool {
        let lower = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let patterns = [
            #"^[a-z]{2,4}\d*$"#,
            #"^audio[_-]?\d*$"#,
            #"^track[_-]?\d*$"#,
            #"^stream[_-]?\d*$"#
        ]
        for p in patterns {
            if let regex = try? NSRegularExpression(pattern: p),
               regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)) != nil {
                return true
            }
        }
        return false
    }

    private static func extractAudioIndex(from raw: String?, isUri: Bool = false) -> Int? {
        guard let raw, !raw.isEmpty else { return nil }
        if isUri {
            if let regex = try? NSRegularExpression(pattern: #"index-a(\d+)"#, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: raw, options: [], range: NSRange(raw.startIndex..<raw.endIndex, in: raw)),
               let idxRange = Range(match.range(at: 1), in: raw),
               let num = Int(raw[idxRange]), num >= 1 {
                return num - 1
            }
        }
        let patterns = [
            #"(?:^|[^a-z0-9])(?:[a-z]{2,4}|audio[_-]?|track[_-]?)(\d+)(?:$|[^a-z0-9])"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
            guard let match = regex.firstMatch(in: raw, options: [], range: range),
                  let idxRange = Range(match.range(at: 1), in: raw),
                  let idx = Int(raw[idxRange]) else {
                continue
            }
            return idx
        }
        return nil
    }

    private static func isSubtitleMediaLine(_ line: String) -> Bool {
        guard line.hasPrefix("#EXT-X-MEDIA") else { return false }
        let upper = line.uppercased()
        return upper.contains("TYPE=SUBTITLES") || upper.contains("TYPE=CLOSED-CAPTIONS")
    }
    
    private static func addOrReplaceAttribute(_ line: String, key: String, value: String) -> String {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: key))=\"([^\"]*)\""
        let escapedValue = escapeAttr(value)
        let newAttr = "\(key)=\"\(escapedValue)\""
        
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: line, options: [], range: NSRange(line.startIndex..., in: line)),
           let range = Range(match.range, in: line) {
            var result = line
            result.replaceSubrange(range, with: newAttr)
            return result
        } else if let colonIndex = line.firstIndex(of: ":") {
            let prefix = line[...colonIndex]
            let rest = line[line.index(after: colonIndex)...]
            return "\(prefix)\(newAttr),\(rest)"
        } else {
            return "\(line),\(newAttr)"
        }
    }
    
    private static func extractQuotedAttr(_ line: String, key: String) -> String? {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: key))=\"([^\"]+)\""
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: line, options: [], range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return String(line[range])
    }
    
    private static func extractAttrValue(_ line: String, key: String) -> String? {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: key))=([^,\\s]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: line, options: [], range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return String(line[range])
    }
    
    private static func escapeAttr(_ s: String) -> String {
        return s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
