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
        preferredVoiceName: String? = nil,
        rewriteVariantUris: Bool = false,
        stripExistingSubtitles: Bool = false,
        port: Int = 8181,
        isCollaps: Bool = false
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
        let hasMediaTags = filteredLines.contains { $0.hasPrefix("#EXT-X-MEDIA") } || !subtitles.isEmpty
        var hasEmittedVersion = false

        let headerLines = Array(filteredLines[..<streamInfIndex])
        let audioReplacements = rewriteAudioMediaLines(in: headerLines, voices: voices, preferredVoiceName: preferredVoiceName)

        for (i, line) in headerLines.enumerated() {
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
            output.append(audioReplacements[i] ?? line)
        }

        if hasMediaTags && !hasEmittedVersion && !output.contains(where: { $0.hasPrefix("#EXT-X-VERSION:") }) {
            if let extm3uIdx = output.firstIndex(where: { $0.hasPrefix("#EXTM3U") }) {
                output.insert("#EXT-X-VERSION:4", at: extm3uIdx + 1)
            } else {
                output.insert("#EXT-X-VERSION:4", at: 0)
            }
        }

        let collapsDetected = isCollaps || master.contains("interkh.com") || master.contains("interkh") || voices.contains(where: { $0.contains("Дорожка") })
        if collapsDetected && !output.contains(where: { $0.hasPrefix("#EXT-X-START") }) {
            if let verIdx = output.firstIndex(where: { $0.hasPrefix("#EXT-X-VERSION") }) {
                output.insert("#EXT-X-START:TIME-OFFSET=4.0,PRECISE=YES", at: verIdx + 1)
            } else if let extm3uIdx = output.firstIndex(where: { $0.hasPrefix("#EXTM3U") }) {
                output.insert("#EXT-X-START:TIME-OFFSET=4.0,PRECISE=YES", at: extm3uIdx + 1)
            }
        }

        if !subtitles.isEmpty {
            for sub in subtitles {
                let lang = sub.lang.isEmpty ? "ru" : sub.lang
                let label = sub.label.isEmpty ? "Subtitle" : sub.label
                let rawUri = sub.url
                guard !rawUri.isEmpty else { continue }
                
                let subUri: String
                if rawUri.lowercased().contains(".m3u8") {
                    subUri = rawUri
                } else {
                    // Raw VTT or SRT file: encode as base64 URL parameter to /subtitles/stream.m3u8
                    let encoded = (rawUri.data(using: .utf8)?.base64EncodedString() ?? rawUri)
                        .replacingOccurrences(of: "+", with: "-")
                        .replacingOccurrences(of: "/", with: "_")
                        .replacingOccurrences(of: "=", with: "")
                    subUri = "http://127.0.0.1:\(port)/subtitles/stream.m3u8?url=\(encoded)"
                }
                
                output.append("#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID=\"\(subsGroupId)\",NAME=\"\(escapeAttr(label))\",DEFAULT=NO,AUTOSELECT=YES,LANGUAGE=\"\(escapeAttr(lang))\",URI=\"\(escapeAttr(subUri))\"")
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

                if height == 0 {
                    let lowerUri = uri.lowercased()
                    if lowerUri.contains("2160") || lowerUri.contains("4k") {
                        height = 2160; width = 3840
                    } else if lowerUri.contains("1440") || lowerUri.contains("2k") {
                        height = 1440; width = 2560
                    } else if lowerUri.contains("1080") {
                        height = 1080; width = 1920
                    } else if lowerUri.contains("720") {
                        height = 720; width = 1280
                    } else if lowerUri.contains("480") {
                        height = 480; width = 854
                    } else if lowerUri.contains("360") {
                        height = 360; width = 640
                    } else if bandwidth >= 3_500_000 {
                        height = 1080; width = 1920
                    } else if bandwidth >= 1_800_000 {
                        height = 720; width = 1280
                    } else if bandwidth >= 800_000 {
                        height = 480; width = 854
                    } else if bandwidth > 0 {
                        height = 360; width = 640
                    }
                }

                if !modifiedLine.contains("RESOLUTION="), width > 0, height > 0 {
                    modifiedLine = addOrReplaceAttribute(modifiedLine, key: "RESOLUTION", value: "\(width)x\(height)", quoted: false)
                }

                let resLabel = normalizeResolutionLabel(width: width, height: height)

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

        // Deduplicate variants so each resolution tier appears at most once (highest bitrate kept)
        var uniqueVariants: [ParsedVariant] = []
        var seenResolutions = Set<String>()
        for v in parsedVariants {
            let key = v.resolutionLabel.lowercased()
            if !seenResolutions.contains(key) {
                seenResolutions.insert(key)
                uniqueVariants.append(v)
            }
        }
        parsedVariants = uniqueVariants

        // Apply quality filter if requested (e.g. "1080p", "720p", "360p")
        var finalVariants = parsedVariants
        if let targetQuality, !targetQuality.isEmpty, targetQuality != "Авто", targetQuality.lowercased() != "auto" {
            let targetHeight: Int = {
                let clean = targetQuality.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                if clean.contains("4k") || clean.contains("2160") { return 2160 }
                if clean.contains("2k") || clean.contains("1440") { return 1440 }
                if clean.contains("1080") { return 1080 }
                if clean.contains("720") { return 720 }
                if clean.contains("480") { return 480 }
                if clean.contains("360") { return 360 }
                return Int(clean.replacingOccurrences(of: "p", with: "")) ?? 0
            }()
            let matches = parsedVariants.filter {
                $0.resolutionLabel.lowercased() == targetQuality.lowercased() ||
                (targetHeight > 0 && $0.height == targetHeight)
            }
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
    
    /// Rewrites a subplaylist (video/audio/master) to strip spliced ad blocks, normalize HDR flags,
    /// inject Collaps start offsets, and rewrite segment/key URIs cleanly.
    static func rewriteMediaPlaylist(
        content: String,
        baseUrl: URL,
        isCollaps: Bool = false,
        rewriteUri: (String) -> String
    ) -> String {
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        let strippedLines = stripSplicedAdBlocks(in: lines, baseUrl: baseUrl)

        var result: [String] = []
        var skipNextUri = false
        var hasEmittedStartOffset = false
        let collapsDetected = isCollaps || baseUrl.host?.contains("interkh.com") == true || baseUrl.absoluteString.contains("interkh")

        for line in strippedLines {
            if line.isEmpty {
                if !skipNextUri { result.append(line) }
                continue
            }
            if line.hasPrefix("#") {
                if collapsDetected && !hasEmittedStartOffset && line.hasPrefix("#EXTINF:") {
                    if !result.contains(where: { $0.hasPrefix("#EXT-X-START") }) {
                        result.append("#EXT-X-START:TIME-OFFSET=4.0,PRECISE=YES")
                    }
                    hasEmittedStartOffset = true
                }

                if line.hasPrefix("#EXT-X-STREAM-INF") {
                    if isUnsupportedCodec(line) {
                        skipNextUri = true
                        continue
                    }
                    skipNextUri = false
                    result.append(normalizeStreamInfVideoRange(line))
                    continue
                }

                if line.contains("URI=") {
                    var modifiedLine = line
                    if let range = modifiedLine.range(of: "URI=\"([^\"]+)\"", options: .regularExpression) {
                        let match = String(modifiedLine[range])
                        let uriString = match.replacingOccurrences(of: "URI=\"", with: "").replacingOccurrences(of: "\"", with: "")
                        if !uriString.isEmpty && uriString != "none" && !uriString.hasPrefix("http://127.0.0.1:") {
                            let proxied = rewriteUri(uriString)
                            modifiedLine.replaceSubrange(range, with: "URI=\"\(proxied)\"")
                        }
                    }
                    result.append(modifiedLine)
                } else {
                    result.append(line)
                }
            } else {
                if skipNextUri {
                    skipNextUri = false
                    continue
                }
                result.append(rewriteUri(line))
            }
        }
        return result.joined(separator: "\n")
    }

    private static func stripSplicedAdBlocks(in lines: [String], baseUrl: URL) -> [String] {
        var result: [String] = []
        var inCueAd = false
        var pendingBlock: [String] = []
        var pendingHasExternalHostOrAdMarker = false
        var insideDiscontinuityBlock = false

        let baseHost = baseUrl.host?.lowercased()
        let baseDomainRoot: String? = baseHost.map { host in
            let parts = host.split(separator: ".")
            return parts.count >= 2 ? parts.suffix(2).joined(separator: ".") : host
        }

        func isAdSegmentUri(_ rawUri: String, allowCrossDomain: Bool) -> Bool {
            let trimmed = rawUri.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }
            let lower = trimmed.lowercased()
            let adMarkers = ["/ad/", "/ads/", "preroll", "midroll", "postroll", "vast", "/promo/", "doubleclick", "googlesyndication", "distribrey", "/lift", "lift_", "-lift"]
            if adMarkers.contains(where: { lower.contains($0) }) {
                return true
            }
            if allowCrossDomain,
               let resolved = URL(string: trimmed, relativeTo: baseUrl)?.host?.lowercased(),
               let baseDomainRoot, !resolved.hasSuffix(baseDomainRoot) {
                return true
            }
            return false
        }

        func flushPendingBlock() {
            if !pendingBlock.isEmpty {
                let hasInitMap = pendingBlock.contains { $0.hasPrefix("#EXT-X-MAP:") }
                if !pendingHasExternalHostOrAdMarker || hasInitMap {
                    result.append(contentsOf: pendingBlock)
                }
                pendingBlock.removeAll()
                pendingHasExternalHostOrAdMarker = false
            }
            insideDiscontinuityBlock = false
        }

        var pendingRegularBlock: [String] = []

        func flushRegularOrAdSegment(uri: String) {
            if isAdSegmentUri(uri, allowCrossDomain: false) {
                pendingRegularBlock.removeAll()
                return
            }
            if !pendingRegularBlock.isEmpty {
                result.append(contentsOf: pendingRegularBlock)
                pendingRegularBlock.removeAll()
            }
            result.append(uri)
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("#EXT-X-CUE-OUT") || trimmed.hasPrefix("#EXT-X-OATCLS-SCTE35") || trimmed.hasPrefix("#EXT-X-SCTE35-OUT") {
                pendingRegularBlock.removeAll()
                inCueAd = true
                continue
            }
            if trimmed.hasPrefix("#EXT-X-CUE-IN") || trimmed.hasPrefix("#EXT-X-SCTE35-IN") {
                inCueAd = false
                continue
            }
            if inCueAd {
                continue
            }

            if trimmed == "#EXT-X-DISCONTINUITY" {
                pendingRegularBlock.removeAll()
                flushPendingBlock()
                insideDiscontinuityBlock = true
                pendingBlock.append(line)
                continue
            }

            if insideDiscontinuityBlock {
                if trimmed == "#EXT-X-ENDLIST" {
                    flushPendingBlock()
                    result.append(line)
                } else {
                    pendingBlock.append(line)
                    if !trimmed.isEmpty && !trimmed.hasPrefix("#") && isAdSegmentUri(trimmed, allowCrossDomain: true) {
                        pendingHasExternalHostOrAdMarker = true
                    }
                    if pendingBlock.count > 25 && !pendingHasExternalHostOrAdMarker {
                        flushPendingBlock()
                    }
                }
                continue
            }

            if trimmed.hasPrefix("#EXTINF:") || trimmed.hasPrefix("#EXT-X-BYTERANGE:") {
                pendingRegularBlock.append(line)
                continue
            }

            if !trimmed.isEmpty && !trimmed.hasPrefix("#") && !pendingRegularBlock.isEmpty {
                flushRegularOrAdSegment(uri: line)
                continue
            }

            if !pendingRegularBlock.isEmpty {
                result.append(contentsOf: pendingRegularBlock)
                pendingRegularBlock.removeAll()
            }
            result.append(line)
        }
        if !pendingRegularBlock.isEmpty {
            result.append(contentsOf: pendingRegularBlock)
        }
        flushPendingBlock()
        return result
    }

    private struct AudioTrackEntry {
        let lineIndex: Int
        let ordinal: Int
        let groupId: String
        let line: String
        let rawName: String?
        let uri: String?
        let language: String?
        let resolvedIndex: Int?
        let displayLabel: String
        let rewrittenLanguage: String
    }

    private static func rewriteAudioMediaLines(
        in headerLines: [String],
        voices: [String],
        preferredVoiceName: String?
    ) -> [Int: String] {
        var groupLineIndices: [String: [Int]] = [:]
        var groupOrder: [String] = []
        for (i, line) in headerLines.enumerated() {
            guard line.hasPrefix("#EXT-X-MEDIA"), line.contains("TYPE=AUDIO") else { continue }
            let groupId = extractQuotedAttr(line, key: "GROUP-ID") ?? "default"
            if groupLineIndices[groupId] == nil {
                groupOrder.append(groupId)
            }
            groupLineIndices[groupId, default: []].append(i)
        }

        var replacements: [Int: String] = [:]

        for groupId in groupOrder {
            guard let indices = groupLineIndices[groupId], !indices.isEmpty else { continue }
            let groupCount = indices.count
            var entries: [AudioTrackEntry] = []

            for (ordinal, lineIdx) in indices.enumerated() {
                let line = headerLines[lineIdx]
                let rawName = extractQuotedAttr(line, key: "NAME")
                let uri = extractQuotedAttr(line, key: "URI")
                let language = extractQuotedAttr(line, key: "LANGUAGE")

                let resolvedIndex: Int? = {
                    guard !voices.isEmpty else { return nil }
                    if groupCount == 1, voices.count > 1, let preferred = preferredVoiceName, !preferred.isEmpty {
                        if let exactIdx = voices.firstIndex(where: { allohaTranslationNamesMatch($0, preferred, exactOnly: true) }) {
                            return exactIdx
                        }
                        if let fuzzyIdx = voices.firstIndex(where: { allohaTranslationNamesMatch($0, preferred, exactOnly: false) }) {
                            return fuzzyIdx
                        }
                    }
                    if voices.count == groupCount {
                        return ordinal
                    }
                    if let uriIdx = extractAudioIndex(from: uri, isUri: true), uriIdx >= 0, uriIdx < voices.count {
                        return uriIdx
                    }
                    if let nameIdx = extractAudioIndex(from: rawName), nameIdx >= 0, nameIdx < voices.count {
                        return nameIdx
                    }
                    if let langIdx = extractAudioIndex(from: language), langIdx >= 0, langIdx < voices.count {
                        return langIdx
                    }
                    return ordinal < voices.count ? ordinal : nil
                }()

                let mappedVoice = resolvedIndex.map { voices[$0] }
                let shouldRename: Bool = {
                    guard mappedVoice != nil else { return false }
                    guard let rawName else { return true }
                    return isGenericTrackName(rawName)
                }()
                let displayLabel = shouldRename ? (mappedVoice ?? rawName ?? "") : (rawName ?? mappedVoice ?? "")
                let rewrittenLanguage: String = {
                    if isOriginalOrEnglishTranslation(displayLabel) { return "en" }
                    if detectLanguageTag(in: displayLabel) == "ukr" { return "uk" }
                    if detectLanguageTag(in: displayLabel) == "kaz" { return "kk" }
                    return "ru"
                }()

                entries.append(AudioTrackEntry(
                    lineIndex: lineIdx,
                    ordinal: ordinal,
                    groupId: groupId,
                    line: line,
                    rawName: rawName,
                    uri: uri,
                    language: language,
                    resolvedIndex: resolvedIndex,
                    displayLabel: displayLabel,
                    rewrittenLanguage: rewrittenLanguage
                ))
            }

            // Pick EXACTLY ONE winning default track per GROUP-ID
            var winningOrdinal: Int? = nil
            if let preferred = preferredVoiceName, !preferred.isEmpty {
                winningOrdinal = entries.first(where: {
                    allohaTranslationNamesMatch($0.displayLabel, preferred, exactOnly: true)
                })?.ordinal
                if winningOrdinal == nil {
                    winningOrdinal = entries.first(where: {
                        allohaTranslationNamesMatch($0.displayLabel, preferred, exactOnly: false)
                    })?.ordinal
                }
                if winningOrdinal == nil, !voices.isEmpty {
                    let voiceIdx = voices.firstIndex(where: { allohaTranslationNamesMatch($0, preferred, exactOnly: true) })
                        ?? voices.firstIndex(where: { allohaTranslationNamesMatch($0, preferred, exactOnly: false) })
                    if let voiceIdx {
                        winningOrdinal = entries.first(where: { $0.resolvedIndex == voiceIdx })?.ordinal
                    }
                }
                if winningOrdinal == nil && isRussianTranslation(preferred) {
                    winningOrdinal = entries.first(where: {
                        isRussianTranslation($0.displayLabel)
                    })?.ordinal
                }
            }

            for entry in entries {
                var output = entry.line
                if entry.resolvedIndex != nil, (entry.rawName == nil || isGenericTrackName(entry.rawName!)) {
                    output = addOrReplaceAttribute(output, key: "NAME", value: entry.displayLabel)
                    output = addOrReplaceAttribute(output, key: "LANGUAGE", value: entry.rewrittenLanguage)
                }
                if let winningOrdinal {
                    let isDefault = entry.ordinal == winningOrdinal
                    output = addOrReplaceAttribute(output, key: "DEFAULT", value: isDefault ? "YES" : "NO", quoted: false)
                    output = addOrReplaceAttribute(output, key: "AUTOSELECT", value: isDefault ? "YES" : "NO", quoted: false)
                }
                replacements[entry.lineIndex] = output
            }
        }

        return replacements
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
    
    private static func addOrReplaceAttribute(_ line: String, key: String, value: String, quoted: Bool = true) -> String {
        let pattern: String
        let newAttr: String
        if quoted {
            pattern = "\\b\(NSRegularExpression.escapedPattern(for: key))=\"([^\"]*)\""
            let escapedValue = escapeAttr(value)
            newAttr = "\(key)=\"\(escapedValue)\""
        } else {
            pattern = "\\b\(NSRegularExpression.escapedPattern(for: key))=([^,\\s]+)"
            newAttr = "\(key)=\(value)"
        }
        
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
        return s.replacingOccurrences(of: "\\", with: "")
            .replacingOccurrences(of: "\"", with: "'")
    }
}

