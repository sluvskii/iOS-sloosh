import Foundation

/// Parsed H.264 Sequence Parameter Set metadata extracted from an MPEG-TS prefix.
struct H264SpsInfo: Equatable, Sendable {
    let rawSps: Data
    let profileIdc: Int
    let levelIdc: Int
    let width: Int
    let height: Int
    let fps: Double?
}

/// Result of inspecting the initial packets of an MPEG-TS segment.
enum HlsPrefixInspectionResult: Equatable, Sendable {
    case pending
    case videoSps(H264SpsInfo)
    case audioOnlyOrNonH264
    case notTransportStream
}

/// Decision returned after evaluating a TS segment against the known stream baseline.
enum HlsSegmentVerdict: Equatable, Sendable {
    case clean(baselineSpsToRecord: Data?)
    case suspectAdSwap(reason: String)
}

/// Parsed ADTS AAC audio metadata extracted from an audio-only MPEG-TS segment.
struct HlsAudioStreamInfo: Equatable, Sendable {
    let adtsProfile: Int
    let sampleRateIndex: Int
    let sampleRate: Int
    let channelConfig: Int
    let frameCount: Int
    let decodedDuration: Double
    let firstPts90k: UInt64?
    let payloadFingerprint: UInt64
    let isDigitalSilence: Bool

    var formatKey: String { "\(adtsProfile)_\(sampleRateIndex)_\(channelConfig)" }
}

/// Result of inspecting an audio-only MPEG-TS segment.
enum HlsAudioInspectionResult: Equatable, Sendable {
    case pending
    case audioAdts(HlsAudioStreamInfo)
    case unexpectedVideoInAudio
    case nonAdtsAudio(firstPts90k: UInt64?)
    case notTransportStream
}

/// Decision returned after evaluating an audio TS segment.
enum HlsAudioVerdict: Equatable, Sendable {
    case clean(HlsAudioStreamInfo?)
    case suspectAdSwap(reason: String, info: HlsAudioStreamInfo?)
}

/// Lightweight, pure-Foundation MPEG-TS / H.264 SPS + ADTS AAC inspector and ad-swap detector.
/// Identifies server-side in-place banner replacements (such as 268,088B / 60fps segments
/// or swapped promo audio jingles) spliced under normal segment URLs without M3U8 discontinuity tags.
enum HlsSegmentShield {
    static let maxInspectionBytes = 65_536
    static let knownBannerByteLength: Int64 = 268_088
    static let knownBannerETagSuffix = "-41738\""

    /// Known H.264 High@L3.2 1280x720 @ 60fps SPS used by injected mid-stream promo banners.
    static let knownBannerSpsHex = "67640020acd9805005ba6a04040280000003008000003c078c18cd"

    static func isCollapsHostOrFlag(url: URL, isCollaps: Bool) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return isCollaps || host.contains("interkh.com") || host.contains("interkh")
    }

    static func isAudioSegmentUrl(_ url: URL) -> Bool {
        url.lastPathComponent.lowercased().range(of: #"-a\d+\.ts$"#, options: .regularExpression) != nil
    }

    static func isInspectableVideoSegment(url: URL, isCollaps: Bool, rangeHeader: String?) -> Bool {
        guard isCollapsHostOrFlag(url: url, isCollaps: isCollaps) else {
            return false
        }
        let lowerPath = url.path.lowercased()
        let ext = url.pathExtension.lowercased()
        guard ext == "ts" || lowerPath.contains(".ts") else {
            return false
        }
        if isAudioSegmentUrl(url) {
            return false
        }
        // Non-zero byte range offsets do not start with PAT/PMT/SPS
        if let rangeHeader = rangeHeader?.lowercased(),
           rangeHeader.hasPrefix("bytes="),
           !rangeHeader.hasPrefix("bytes=0-") {
            return false
        }
        return true
    }

    static func isInspectableAudioSegment(url: URL, isCollaps: Bool, rangeHeader: String?) -> Bool {
        guard isCollapsHostOrFlag(url: url, isCollaps: isCollaps),
              isAudioSegmentUrl(url) else {
            return false
        }
        if let rangeHeader = rangeHeader?.lowercased(),
           rangeHeader.hasPrefix("bytes="),
           !rangeHeader.hasPrefix("bytes=0-") {
            return false
        }
        return true
    }

    /// Groups baseline signatures by quality/audio tier (e.g. "v1", "a1") so track switches never mismatch.
    static func tierKey(for url: URL) -> String {
        let name = url.lastPathComponent.lowercased()
        if let regex = try? NSRegularExpression(pattern: #"-([va]\d+)\.ts$"#, options: []),
           let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
           let r = Range(match.range(at: 1), in: name) {
            return String(name[r])
        }
        return url.deletingLastPathComponent().path
    }

    static func evaluateSegment(
        prefixData: Data,
        isComplete: Bool,
        expectedContentLength: Int64?,
        eTag: String?,
        baselineSps: Data?,
        declaredMaxFps: Double?
    ) -> HlsSegmentVerdict? {
        let inspection = inspectVideoPrefix(prefixData, isComplete: isComplete)

        switch inspection {
        case .pending:
            if prefixData.count < maxInspectionBytes && !isComplete {
                return nil
            }
            // No SPS found within 64 KB: fallback to known size/ETag fingerprint
            if let expectedContentLength, expectedContentLength == knownBannerByteLength,
               eTag?.lowercased().hasSuffix(knownBannerETagSuffix) == true {
                return .suspectAdSwap(reason: "banner size/etag without SPS")
            }
            return .clean(baselineSpsToRecord: nil)

        case .audioOnlyOrNonH264, .notTransportStream:
            return .clean(baselineSpsToRecord: nil)

        case .videoSps(let spsInfo):
            let spsHex = spsInfo.rawSps.map { String(format: "%02x", $0) }.joined()
            if spsHex == knownBannerSpsHex {
                return .suspectAdSwap(reason: "known banner 60fps SPS")
            }

            if let expectedContentLength, expectedContentLength == knownBannerByteLength {
                let spsDiffers = baselineSps.map { $0 != spsInfo.rawSps } ?? true
                let highFps = (spsInfo.fps ?? 0) >= 50.0
                if spsDiffers || highFps {
                    return .suspectAdSwap(reason: "known 268088B banner payload (fps=\(spsInfo.fps ?? 0))")
                }
            }

            if let baselineSps, baselineSps != spsInfo.rawSps {
                return .suspectAdSwap(
                    reason: "SPS mismatch (got \(spsInfo.width)x\(spsInfo.height)@\(spsInfo.fps ?? 0)fps L\(spsInfo.levelIdc))"
                )
            }

            // Cold-start seek guard when master declared ~24/30fps and first fetched segment is 60fps low-size
            if baselineSps == nil,
               let declaredMaxFps, declaredMaxFps > 0, declaredMaxFps <= 35.0,
               let segFps = spsInfo.fps, segFps >= 50.0,
               (expectedContentLength ?? 0) < 1_000_000 {
                return .suspectAdSwap(reason: "cold-start FPS mismatch (\(segFps)fps vs master \(declaredMaxFps)fps)")
            }

            return .clean(baselineSpsToRecord: baselineSps == nil ? spsInfo.rawSps : nil)
        }
    }

    static func inspectVideoPrefix(_ data: Data, isComplete: Bool = false) -> HlsPrefixInspectionResult {
        scanVideoPrefix(data, isComplete: isComplete).inspection
    }

    // MARK: - Audio TS Inspection & Ad-Swap Detection

    private static let adtsSampleRates: [Int] = [
        96_000, 88_200, 64_000, 48_000, 44_100, 32_000,
        24_000, 22_050, 16_000, 12_000, 11_025, 8_000, 7_350
    ]

    static func inspectAudioPrefix(_ data: Data, isComplete: Bool = false) -> HlsAudioInspectionResult {
        guard data.count >= 188 else {
            return isComplete ? .notTransportStream : .pending
        }

        let maxSyncSearch = min(data.count - 188, 188 * 4)
        var syncOffset = -1
        for i in 0...max(0, maxSyncSearch) {
            if data[i] == 0x47 && (i + 188 >= data.count || data[i + 188] == 0x47) {
                syncOffset = i
                break
            }
        }
        guard syncOffset >= 0 else {
            return .notTransportStream
        }

        var pmtPid: Int? = nil
        var audioPid: Int? = nil
        var audioStreamType: UInt8 = 0
        var sawVideoInAudio = false
        var sawPmtStreams = false
        var audioEsBuffer = Data()
        var collectingPes = false
        var firstPts90k: UInt64? = nil

        var offset = syncOffset
        while offset + 188 <= data.count {
            guard data[offset] == 0x47 else {
                offset += 188
                continue
            }
            let b1 = data[offset + 1]
            let pusi = (b1 & 0x40) != 0
            let pid = (Int(b1 & 0x1F) << 8) | Int(data[offset + 2])
            let afc = (data[offset + 3] >> 4) & 0x03
            if afc == 0 || afc == 2 {
                offset += 188
                continue
            }
            var payloadPos = offset + 4
            if afc == 3 {
                guard payloadPos < offset + 188 else {
                    offset += 188
                    continue
                }
                payloadPos += 1 + Int(data[payloadPos])
            }
            guard payloadPos < offset + 188 else {
                offset += 188
                continue
            }
            let packetEnd = offset + 188

            if pid == 0 && pusi {
                let ptr = Int(data[payloadPos])
                let secStart = payloadPos + 1 + ptr
                if secStart + 12 <= packetEnd, data[secStart] == 0x00 {
                    let secLen = (Int(data[secStart + 1] & 0x0F) << 8) | Int(data[secStart + 2])
                    let end = min(packetEnd, secStart + 3 + max(0, secLen - 4))
                    var p = secStart + 8
                    while p + 4 <= end {
                        let prog = (Int(data[p]) << 8) | Int(data[p + 1])
                        let pPid = (Int(data[p + 2] & 0x1F) << 8) | Int(data[p + 3])
                        if prog != 0 && pmtPid == nil {
                            pmtPid = pPid
                        }
                        p += 4
                    }
                }
            } else if let pmtPid, pid == pmtPid && pusi {
                let ptr = Int(data[payloadPos])
                let secStart = payloadPos + 1 + ptr
                if secStart + 12 <= packetEnd, data[secStart] == 0x02 {
                    let secLen = (Int(data[secStart + 1] & 0x0F) << 8) | Int(data[secStart + 2])
                    let progInfoLen = (Int(data[secStart + 10] & 0x0F) << 8) | Int(data[secStart + 11])
                    let end = min(packetEnd, secStart + 3 + max(0, secLen - 4))
                    var p = secStart + 12 + progInfoLen
                    while p + 5 <= end {
                        sawPmtStreams = true
                        let st = data[p]
                        let ePid = (Int(data[p + 1] & 0x1F) << 8) | Int(data[p + 2])
                        let esInfoLen = (Int(data[p + 3] & 0x0F) << 8) | Int(data[p + 4])
                        if st == 0x1B || st == 0x24 {
                            sawVideoInAudio = true
                        } else if audioPid == nil && (st == 0x0F || st == 0x11 || st == 0x03 || st == 0x04 || st == 0x06 || st == 0x81 || st == 0x87) {
                            audioPid = ePid
                            audioStreamType = st
                        }
                        p += 5 + esInfoLen
                    }
                    if sawVideoInAudio {
                        return .unexpectedVideoInAudio
                    }
                    if sawPmtStreams && audioPid == nil {
                        return .nonAdtsAudio(firstPts90k: nil)
                    }
                }
            } else if let audioPid, pid == audioPid {
                if pusi {
                    if payloadPos + 9 <= packetEnd,
                       data[payloadPos] == 0x00,
                       data[payloadPos + 1] == 0x00,
                       data[payloadPos + 2] == 0x01 {
                        if firstPts90k == nil {
                            firstPts90k = parsePesPts90k(from: data, pesOffset: payloadPos, packetEnd: packetEnd)
                        }
                        let pesHdrLen = Int(data[payloadPos + 8])
                        let esStart = payloadPos + 9 + pesHdrLen
                        collectingPes = true
                        if esStart < packetEnd {
                            audioEsBuffer.append(data[esStart..<packetEnd])
                        }
                    } else if collectingPes {
                        audioEsBuffer.append(data[payloadPos..<packetEnd])
                    }
                } else if collectingPes {
                    audioEsBuffer.append(data[payloadPos..<packetEnd])
                }
            }

            offset += 188
        }

        if audioPid == nil {
            return isComplete ? .nonAdtsAudio(firstPts90k: firstPts90k) : .pending
        }

        if audioStreamType != 0x0F && audioStreamType != 0x00 {
            return isComplete ? .nonAdtsAudio(firstPts90k: firstPts90k) : .pending
        }

        guard let info = parseAdtsAudioStream(from: audioEsBuffer, firstPts90k: firstPts90k, isComplete: isComplete) else {
            return isComplete ? .nonAdtsAudio(firstPts90k: firstPts90k) : .pending
        }
        return .audioAdts(info)
    }

    static func evaluateAudioSegment(
        data: Data,
        isComplete: Bool,
        expectedDurationSeconds: Double?,
        expectedStartPts90k: UInt64?,
        baseline: HlsAudioStreamInfo?,
        knownBannerFingerprints: Set<UInt64>
    ) -> HlsAudioVerdict? {
        let inspection = inspectAudioPrefix(data, isComplete: isComplete)
        switch inspection {
        case .pending:
            if !isComplete && data.count < maxInspectionBytes {
                return nil
            }
            return .clean(nil)

        case .unexpectedVideoInAudio:
            return .suspectAdSwap(reason: "audio chunk contains video stream", info: nil)

        case .nonAdtsAudio, .notTransportStream:
            return .clean(nil)

        case .audioAdts(let info):
            if !info.isDigitalSilence && knownBannerFingerprints.contains(info.payloadFingerprint) {
                return .suspectAdSwap(reason: "known banner audio fingerprint", info: info)
            }

            if let baseline, baseline.formatKey != info.formatKey {
                return .suspectAdSwap(
                    reason: "ADTS format mismatch (\(info.sampleRate)Hz/\(info.channelConfig)ch vs \(baseline.sampleRate)Hz/\(baseline.channelConfig)ch)",
                    info: info
                )
            }

            if isComplete,
               let expectedDurationSeconds,
               expectedDurationSeconds >= 5.0,
               info.decodedDuration > 0,
               info.decodedDuration < expectedDurationSeconds * 0.65 {
                return .suspectAdSwap(
                    reason: "short audio segment (\(String(format: "%.2fs", info.decodedDuration)) vs \(String(format: "%.2fs", expectedDurationSeconds)))",
                    info: info
                )
            }

            if let expectedStartPts90k, expectedStartPts90k > 0, let actualPts = info.firstPts90k {
                let diffTicks = abs(Int64(actualPts) - Int64(expectedStartPts90k))
                if diffTicks > 3 * 90_000 {
                    return .suspectAdSwap(
                        reason: "audio PTS mismatch (\(actualPts / 90_000)s vs \(expectedStartPts90k / 90_000)s)",
                        info: info
                    )
                }
            }

            return .clean(info)
        }
    }

    private static func parsePesPts90k(from data: Data, pesOffset: Int, packetEnd: Int) -> UInt64? {
        let ptsDtsFlags = (data[pesOffset + 7] >> 6) & 0x03
        guard (ptsDtsFlags & 0x02) != 0, pesOffset + 14 <= packetEnd else {
            return nil
        }
        let b0 = UInt64(data[pesOffset + 9])
        let b1 = UInt64(data[pesOffset + 10])
        let b2 = UInt64(data[pesOffset + 11])
        let b3 = UInt64(data[pesOffset + 12])
        let b4 = UInt64(data[pesOffset + 13])
        return ((b0 & 0x0E) << 29)
            | ((b1 & 0xFF) << 22)
            | ((b2 & 0xFE) << 14)
            | ((b3 & 0xFF) << 7)
            | ((b4 & 0xFE) >> 1)
    }

    private static func parseAdtsAudioStream(from es: Data, firstPts90k: UInt64?, isComplete: Bool) -> HlsAudioStreamInfo? {
        let bytes = [UInt8](es)
        guard bytes.count >= 14 else { return nil }

        var pos = 0
        while pos + 7 <= bytes.count {
            if bytes[pos] == 0xFF && (bytes[pos + 1] & 0xF6) == 0xF0 {
                break
            }
            pos += 1
        }
        guard pos + 7 <= bytes.count else { return nil }

        let firstHdrLen = (bytes[pos + 1] & 0x01) != 0 ? 7 : 9
        let firstProfile = Int((bytes[pos + 2] >> 6) & 0x03)
        let firstFreqIdx = Int((bytes[pos + 2] >> 2) & 0x0F)
        let firstChCfg = Int(((bytes[pos + 2] & 0x01) << 2) | ((bytes[pos + 3] >> 6) & 0x03))
        guard firstFreqIdx < adtsSampleRates.count else { return nil }
        let sampleRate = adtsSampleRates[firstFreqIdx]

        var frameCount = 0
        var maxRawLen = 0
        var fnvHash: UInt64 = 14_695_981_039_346_656_037
        var hashedBytes = 0
        var firstPayloadSample: [UInt8]? = nil
        var uniformPayload = true

        var cursor = pos
        while cursor + 7 <= bytes.count {
            guard bytes[cursor] == 0xFF && (bytes[cursor + 1] & 0xF6) == 0xF0 else {
                cursor += 1
                continue
            }
            let hdrLen = (bytes[cursor + 1] & 0x01) != 0 ? 7 : 9
            let frameLen = (Int(bytes[cursor + 3] & 0x03) << 11)
                | (Int(bytes[cursor + 4]) << 3)
                | (Int(bytes[cursor + 5] & 0xE0) >> 5)
            guard frameLen >= hdrLen else { break }
            if cursor + frameLen > bytes.count {
                break
            }
            frameCount += 1
            let rawStart = cursor + hdrLen
            let rawEnd = cursor + frameLen
            let rawLen = rawEnd - rawStart
            maxRawLen = max(maxRawLen, rawLen)

            let frameSlice = Array(bytes[rawStart..<rawEnd])
            if let sample = firstPayloadSample {
                if sample != frameSlice { uniformPayload = false }
            } else {
                firstPayloadSample = frameSlice
            }

            if hashedBytes < 1024 {
                for b in frameSlice {
                    fnvHash ^= UInt64(b)
                    fnvHash = fnvHash &* 1_099_511_628_211
                    hashedBytes += 1
                    if hashedBytes >= 1024 { break }
                }
            }
            cursor += frameLen
        }

        // Wait until we have either enough hashed AAC frames (~20 frames or full chunk)
        if !isComplete && frameCount < 10 && bytes.count < 8_192 {
            return nil
        }
        guard frameCount > 0 else { return nil }
        let decodedDuration = Double(frameCount * 1024) / Double(sampleRate)
        let isSilence = (maxRawLen <= 24 && uniformPayload)

        return HlsAudioStreamInfo(
            adtsProfile: firstProfile,
            sampleRateIndex: firstFreqIdx,
            sampleRate: sampleRate,
            channelConfig: firstChCfg > 0 ? firstChCfg : 2,
            frameCount: frameCount,
            decodedDuration: decodedDuration,
            firstPts90k: firstPts90k,
            payloadFingerprint: fnvHash,
            isDigitalSilence: isSilence
        )
    }

    static func extractFirstVideoPts90k(from data: Data) -> UInt64? {
        scanVideoPrefix(data, isComplete: false).firstPts90k
    }

    private static func scanVideoPrefix(_ data: Data, isComplete: Bool) -> (inspection: HlsPrefixInspectionResult, firstPts90k: UInt64?) {
        guard data.count >= 188 else {
            return (isComplete ? .notTransportStream : .pending, nil)
        }

        let maxSyncSearch = min(data.count - 188, 188 * 4)
        var syncOffset = -1
        for i in 0...max(0, maxSyncSearch) {
            if data[i] == 0x47 && (i + 188 >= data.count || data[i + 188] == 0x47) {
                syncOffset = i
                break
            }
        }
        guard syncOffset >= 0 else {
            return (.notTransportStream, nil)
        }

        var pmtPid: Int? = nil
        var videoPid: Int? = nil
        var sawNonH264Video = false
        var sawPmtStreams = false
        var videoEsBuffer = Data()
        var collectingVideoPes = false
        var firstPts90k: UInt64? = nil

        var offset = syncOffset
        while offset + 188 <= data.count {
            guard data[offset] == 0x47 else {
                offset += 188
                continue
            }
            let b1 = data[offset + 1]
            let pusi = (b1 & 0x40) != 0
            let pid = (Int(b1 & 0x1F) << 8) | Int(data[offset + 2])
            let afc = (data[offset + 3] >> 4) & 0x03
            if afc == 0 || afc == 2 {
                offset += 188
                continue
            }
            var payloadPos = offset + 4
            if afc == 3 {
                guard payloadPos < offset + 188 else {
                    offset += 188
                    continue
                }
                payloadPos += 1 + Int(data[payloadPos])
            }
            guard payloadPos < offset + 188 else {
                offset += 188
                continue
            }
            let packetEnd = offset + 188

            if pid == 0 && pusi {
                let ptr = Int(data[payloadPos])
                let secStart = payloadPos + 1 + ptr
                if secStart + 12 <= packetEnd, data[secStart] == 0x00 {
                    let secLen = (Int(data[secStart + 1] & 0x0F) << 8) | Int(data[secStart + 2])
                    let end = min(packetEnd, secStart + 3 + max(0, secLen - 4))
                    var p = secStart + 8
                    while p + 4 <= end {
                        let prog = (Int(data[p]) << 8) | Int(data[p + 1])
                        let pPid = (Int(data[p + 2] & 0x1F) << 8) | Int(data[p + 3])
                        if prog != 0 && pmtPid == nil {
                            pmtPid = pPid
                        }
                        p += 4
                    }
                }
            } else if let pmtPid, pid == pmtPid && pusi {
                let ptr = Int(data[payloadPos])
                let secStart = payloadPos + 1 + ptr
                if secStart + 12 <= packetEnd, data[secStart] == 0x02 {
                    let secLen = (Int(data[secStart + 1] & 0x0F) << 8) | Int(data[secStart + 2])
                    let progInfoLen = (Int(data[secStart + 10] & 0x0F) << 8) | Int(data[secStart + 11])
                    let end = min(packetEnd, secStart + 3 + max(0, secLen - 4))
                    var p = secStart + 12 + progInfoLen
                    while p + 5 <= end {
                        sawPmtStreams = true
                        let st = data[p]
                        let ePid = (Int(data[p + 1] & 0x1F) << 8) | Int(data[p + 2])
                        let esInfoLen = (Int(data[p + 3] & 0x0F) << 8) | Int(data[p + 4])
                        if st == 0x1B && videoPid == nil {
                            videoPid = ePid
                        } else if st == 0x24 {
                            sawNonH264Video = true
                        }
                        p += 5 + esInfoLen
                    }
                    if (sawPmtStreams || sawNonH264Video) && videoPid == nil {
                        return (.audioOnlyOrNonH264, nil)
                    }
                }
            } else if let videoPid, pid == videoPid {
                if pusi {
                    if payloadPos + 9 <= packetEnd,
                       data[payloadPos] == 0x00,
                       data[payloadPos + 1] == 0x00,
                       data[payloadPos + 2] == 0x01 {
                        if firstPts90k == nil {
                            firstPts90k = parsePesPts90k(from: data, pesOffset: payloadPos, packetEnd: packetEnd)
                        }
                        let pesHdrLen = Int(data[payloadPos + 8])
                        let esStart = payloadPos + 9 + pesHdrLen
                        collectingVideoPes = true
                        if esStart < packetEnd {
                            videoEsBuffer.append(data[esStart..<packetEnd])
                        }
                    } else if collectingVideoPes {
                        videoEsBuffer.append(data[payloadPos..<packetEnd])
                    }
                } else if collectingVideoPes {
                    videoEsBuffer.append(data[payloadPos..<packetEnd])
                }

                if let spsData = extractCompleteFirstSps(fromAnnexB: videoEsBuffer, allowAtEnd: false) {
                    if let parsed = parseH264Sps(spsData) {
                        return (.videoSps(parsed), firstPts90k)
                    }
                    return (.audioOnlyOrNonH264, firstPts90k)
                }
            }

            offset += 188
        }

        if isComplete, let spsData = extractCompleteFirstSps(fromAnnexB: videoEsBuffer, allowAtEnd: true),
           let parsed = parseH264Sps(spsData) {
            return (.videoSps(parsed), firstPts90k)
        }
        return (.pending, firstPts90k)
    }

    static func buildFailoverRequest(
        from originalRequest: URLRequest,
        failoverHost: String?,
        stripRefererOrigin: Bool = false
    ) -> URLRequest? {
        guard let originalUrl = originalRequest.url else { return nil }
        var request = originalRequest
        if let failoverHost, !failoverHost.isEmpty,
           var components = URLComponents(url: originalUrl, resolvingAgainstBaseURL: false),
           components.host?.lowercased() != failoverHost.lowercased() {
            components.host = failoverHost
            if let swappedUrl = components.url {
                request.url = swappedUrl
            }
        }
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        if stripRefererOrigin {
            request.setValue(nil, forHTTPHeaderField: "Referer")
            request.setValue(nil, forHTTPHeaderField: "Origin")
        }
        return request
    }

    // MARK: - Clean Black Video & Silent Audio MPEG-TS Replacement (Zero-Ad Guarantee)

    private static let black360KeyRle = "000000016742c01e8c680a02ff966e021a020f08846c2000007d2000177010800000000168ce3c800000000165b80004053ffffe1e8a00067c,38*9c,9d,219*75d75d,75d75e"
    private static let black360DeltaRles = [
        "0000000161e0007e408fdfff89e00e56",
        "0000000161e000be42e00e66",
        "0000000161e000fe417ee32eeeeeeeeeeeeeeef13b8273ef3f006df0",
        "0000000161e0013e40be00e660",
        "0000000161e0017e4047803998",
        "0000000161e001be405f803998",
        "0000000161e001fe4077803998",
        "0000000161e0023e4077803998"
    ]
    private static let black720KeyRle = "0000000167640c1fac18d00a00b74dc0434041e1108d8400000fa40002ee02100000000168ce3c800000000165b80004051fffff87a280019f,79*27,220*5d75d7,80000000016500782e00010147ffffe1e8a00067,79*c9,220*d75d75,e00000000165003c0b80004051fffff87a280019f2,78*72,220*75d75d,780000000165001682e00010147ffffe1e8a00067c,78*9c,9d,159*75d75d,75d75e"
    private static let black720DeltaRles = [
        "0000000161e0007e4041e00a060000000161005038001f9010780786000000016100230e0007e4041e00a060000000016100370e0007e4041e007318",
        "0000000161e000be40a7803c180000000161007838002f9029e00a06000000016100320e000be40a7801406000000001610016838002f9029e00b460",
        "0000000161e000fe411e00a0600000000161005038003f90478032180000000161002d0e000fe411e00f0600000001610012c38003f90478012c60",
        "0000000161e0013e43780321800000000161006438004f90de00c860000000016100320e0013e43780321800000001610012c38004f90de004b180",
        "0000000161e0017e4097803c180000000161007838005f9025e00f060000000161003c0e0017e4097803218000000001610015438005f9025e00dc60",
        "0000000161e001be40f7803c180000000161007838006f903de00f060000000161003c0e001be40f7803218000000001610015438006f903de00dc60",
        "0000000161e001fe4055e00c860000000161006438007f901578032180000000016100320e001fe4055e00c86000000001610012c38007f901578012c6",
        "0000000161e0023e406de0046180000000016100230e0023e406de00461800000001610011838008f901b780321800000001610017c38008f901b7802318"
    ]
    private static let black1080KeyRle = "0000000167640c28ac18d00f0044fcb37010d0107844236100000303e90000bb80840000000168ce3c800000000165b80004051fffff87a280019f,119*27,450*5d75d7,800000000165003c0b80004051fffff87a280019f2,118*72,450*75d75d,780000000165001e02e00010147ffffe1e8a00067c,118*9c,9d,449*75d75d,75d75e0000000165000b40b80004051fffff87a280019f,119*27,570*5d75d7,80"
    private static let black1080DeltaRles = [
        "0000000161e0007e4051e005a1800000000161002d0e0007e4051e0021c60000000161001c238001f90147801a460000000161000a50e0007e4051e002d060",
        "0000000161e000be40e7801a46000000016100348e000be40e7801e0600000000161001c238002f9039e0078180000000161000ac8e000be40e7800a5180",
        "0000000161e000fe40878009618000000001610012c38003f9021e005a180000000161001e038003f9021e00f0600000000161000960e000fe4087800d2180",
        "0000000161e0013e42780168600000000161002d0e0013e427801e060000000161001a438004f909e00781800000000161000a50e0013e427800b418",
        "0000000161e0017e415e00258600000001610012c38005f9057801e0600000000161000870e0017e415e0078180000000161000c30e0017e415e007818",
        "0000000161e001be40b7801e060000000161003c0e001be40b780168600000000161001a438006f902de0021c60000000161000ac8e001be40b7800a5180",
        "0000000161e001fe4045e005a1800000000161002d0e001fe4045e0078180000000161001a438007f90117801e060000000161000a50e001fe4045e002d060",
        "0000000161e0023e405de002586000000001610012c38008f90177801e060000000161000870e0023e405de00691800000000161000bb8e0023e405de0021c60"
    ]

    private static let silentAac1ChRaw: [UInt8] = [0x06, 0xC8, 0x00, 0x07]
    private static let silentAac2ChRaw: [UInt8] = [0x21, 0x10, 0x04, 0x60, 0x8C, 0x1C]
    private static let silentAac6ChRaw: [UInt8] = [
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x11,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x03, 0x00, 0x00, 0x00, 0x38
    ]

    private static func decodePatternRle(_ spec: String) -> Data? {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(4096)

        func parseHexBytes(_ hex: Substring) -> [UInt8]? {
            guard hex.count % 2 == 0 else { return nil }
            var result: [UInt8] = []
            result.reserveCapacity(hex.count / 2)
            var idx = hex.startIndex
            while idx < hex.endIndex {
                let next = hex.index(idx, offsetBy: 2)
                guard let byte = UInt8(hex[idx..<next], radix: 16) else { return nil }
                result.append(byte)
                idx = next
            }
            return result
        }

        for token in spec.split(separator: ",") {
            if let star = token.firstIndex(of: "*") {
                guard let count = Int(token[..<star]),
                      count > 0,
                      let pat = parseHexBytes(token[token.index(after: star)...]) else {
                    return nil
                }
                for _ in 0..<count {
                    bytes.append(contentsOf: pat)
                }
            } else if let lit = parseHexBytes(token) {
                bytes.append(contentsOf: lit)
            } else {
                return nil
            }
        }
        return bytes.isEmpty ? nil : Data(bytes)
    }

    static func resolveStreamDimensions(fromBaselineSps baselineSps: Data?) -> (width: Int, height: Int) {
        guard let baselineSps, let parsed = parseH264Sps(baselineSps) else {
            return (1280, 720)
        }
        return (parsed.width, parsed.height)
    }

    private static func crc32Mpeg2(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc ^= UInt32(byte) << 24
            for _ in 0..<8 {
                crc = (crc & 0x8000_0000) != 0 ? ((crc << 1) ^ 0x04C1_1DB7) : (crc << 1)
            }
        }
        return crc
    }

    private static func makePsiPacket(pid: UInt16, body: [UInt8]) -> Data {
        var pkt = [UInt8](repeating: 0xFF, count: 188)
        pkt[0] = 0x47
        pkt[1] = 0x40 | UInt8((pid >> 8) & 0x1F)
        pkt[2] = UInt8(pid & 0xFF)
        pkt[3] = 0x10
        pkt[4] = 0x00 // pointer_field
        for (i, b) in body.enumerated() where 5 + i < 184 {
            pkt[5 + i] = b
        }
        let crc = crc32Mpeg2(body)
        let crcPos = 5 + body.count
        if crcPos + 4 <= 188 {
            pkt[crcPos] = UInt8((crc >> 24) & 0xFF)
            pkt[crcPos + 1] = UInt8((crc >> 16) & 0xFF)
            pkt[crcPos + 2] = UInt8((crc >> 8) & 0xFF)
            pkt[crcPos + 3] = UInt8(crc & 0xFF)
        }
        return Data(pkt)
    }

    private static func emitElementaryPesPackets(
        into tsData: inout Data,
        streamId: UInt8,
        payload: Data,
        pts90k: UInt64,
        includePcr: Bool,
        continuityCounter: inout UInt8
    ) {
        let t = pts90k & 0x1_FFFF_FFFF
        let pesHeader: [UInt8] = [
            0x00, 0x00, 0x01, streamId, 0x00, 0x00, 0x80, 0x80, 0x05,
            0x21 | UInt8((t >> 29) & 0x0E),
            UInt8((t >> 22) & 0xFF),
            0x01 | UInt8((t >> 14) & 0xFE),
            UInt8((t >> 7) & 0xFF),
            0x01 | UInt8((t << 1) & 0xFE)
        ]
        var fullPayload = Data(pesHeader)
        fullPayload.append(payload)

        let payloadBytes = [UInt8](fullPayload)
        var offset = 0
        var isFirst = true
        while offset < payloadBytes.count {
            let remaining = payloadBytes.count - offset
            var pkt = [UInt8](repeating: 0xFF, count: 188)
            pkt[0] = 0x47
            pkt[1] = (isFirst ? 0x40 : 0x00) | 0x01
            pkt[2] = 0x00

            let pcrLen = (isFirst && includePcr) ? 6 : 0
            let maxData = 182 - pcrLen
            if remaining >= 184 && pcrLen == 0 {
                pkt[3] = 0x10 | continuityCounter
                for i in 0..<184 {
                    pkt[4 + i] = payloadBytes[offset + i]
                }
                offset += 184
            } else {
                let take = min(remaining, maxData)
                let afLen = 183 - take
                pkt[3] = 0x30 | continuityCounter
                pkt[4] = UInt8(afLen)
                pkt[5] = pcrLen > 0 ? 0x50 : 0x00
                if pcrLen > 0 {
                    pkt[6] = UInt8((t >> 25) & 0xFF)
                    pkt[7] = UInt8((t >> 17) & 0xFF)
                    pkt[8] = UInt8((t >> 9) & 0xFF)
                    pkt[9] = UInt8((t >> 1) & 0xFF)
                    pkt[10] = UInt8(((t & 1) << 7) | 0x7E)
                    pkt[11] = 0x00
                }
                let dataStart = 5 + afLen
                for i in 0..<take {
                    pkt[dataStart + i] = payloadBytes[offset + i]
                }
                offset += take
            }
            continuityCounter = (continuityCounter + 1) & 0x0F
            isFirst = false
            tsData.append(contentsOf: pkt)
        }
    }

    /// Synthesizes a valid, zero-banner black H.264 MPEG-TS segment with VUI timing & paced P-skip frames.
    static func buildBlackReplacementTs(
        width: Int,
        height: Int,
        ptsStart90k: UInt64,
        durationSeconds: Double
    ) -> Data? {
        let keyRle: String
        let deltaRles: [String]
        if width > 1440 || height > 900 {
            keyRle = black1080KeyRle
            deltaRles = black1080DeltaRles
        } else if width <= 800 && height <= 500 {
            keyRle = black360KeyRle
            deltaRles = black360DeltaRles
        } else {
            keyRle = black720KeyRle
            deltaRles = black720DeltaRles
        }

        guard let keyAnnexB = decodePatternRle(keyRle) else {
            return nil
        }
        let deltaFrames = deltaRles.compactMap { decodePatternRle($0) }
        guard !deltaFrames.isEmpty else {
            return nil
        }

        let patBody: [UInt8] = [0x00, 0xB0, 13, 0x00, 0x01, 0xC1, 0x00, 0x00, 0x00, 0x01, 0xF0, 0x00]
        let pmtBody: [UInt8] = [0x02, 0xB0, 18, 0x00, 0x01, 0xC1, 0x00, 0x00, 0xE1, 0x00, 0xF0, 0x00, 0x1B, 0xE1, 0x00, 0xF0, 0x00]

        var tsData = Data()
        tsData.append(makePsiPacket(pid: 0x0000, body: patBody))
        tsData.append(makePsiPacket(pid: 0x1000, body: pmtBody))

        var continuityCounter: UInt8 = 0
        let audPrefix = Data([0x00, 0x00, 0x00, 0x01, 0x09, 0xF0])

        var keyPayload = audPrefix
        keyPayload.append(keyAnnexB)
        emitElementaryPesPackets(
            into: &tsData,
            streamId: 0xE0,
            payload: keyPayload,
            pts90k: ptsStart90k,
            includePcr: true,
            continuityCounter: &continuityCounter
        )

        let clampedDuration = max(0.5, min(30.0, durationSeconds))
        let totalTicks = max(UInt64(45_000), UInt64((clampedDuration * 90_000.0).rounded()))
        let frameSpanTicks = max(UInt64(3_754), totalTicks &- 3_754)
        let activeDeltaCount = min(deltaFrames.count, max(1, Int(floor(clampedDuration))))
        let stepTicks = frameSpanTicks / UInt64(activeDeltaCount)

        for idx in 0..<activeDeltaCount {
            var deltaPayload = audPrefix
            deltaPayload.append(deltaFrames[idx])
            let offsetTicks = (idx == activeDeltaCount - 1) ? frameSpanTicks : UInt64(idx + 1) * stepTicks
            emitElementaryPesPackets(
                into: &tsData,
                streamId: 0xE0,
                payload: deltaPayload,
                pts90k: ptsStart90k &+ offsetTicks,
                includePcr: false,
                continuityCounter: &continuityCounter
            )
        }
        return tsData
    }

    /// Synthesizes a valid silent ADTS AAC MPEG-TS segment matching the track's sample rate, channels, PTS & duration.
    static func buildSilentAudioReplacementTs(
        sampleRateIndex: Int,
        channelConfig: Int,
        ptsStart90k: UInt64,
        durationSeconds: Double
    ) -> Data {
        let safeFreqIdx = (sampleRateIndex >= 0 && sampleRateIndex < adtsSampleRates.count) ? sampleRateIndex : 4
        let sampleRate = adtsSampleRates[safeFreqIdx]
        let safeCh: Int
        let rawAac: [UInt8]
        switch channelConfig {
        case 1:
            safeCh = 1
            rawAac = silentAac1ChRaw
        case 6:
            safeCh = 6
            rawAac = silentAac6ChRaw
        default:
            safeCh = 2
            rawAac = silentAac2ChRaw
        }

        let frameLen = 7 + rawAac.count
        var adtsFrame = [UInt8](repeating: 0, count: frameLen)
        adtsFrame[0] = 0xFF
        adtsFrame[1] = 0xF1 // MPEG-4, Layer 0, protection_absent = 1
        adtsFrame[2] = UInt8((1 << 6) | ((safeFreqIdx & 0x0F) << 2) | ((safeCh >> 2) & 0x01))
        adtsFrame[3] = UInt8(((safeCh & 0x03) << 6) | ((frameLen >> 11) & 0x03))
        adtsFrame[4] = UInt8((frameLen >> 3) & 0xFF)
        adtsFrame[5] = UInt8(((frameLen & 0x07) << 5) | 0x1F)
        adtsFrame[6] = 0xFC
        for (i, b) in rawAac.enumerated() {
            adtsFrame[7 + i] = b
        }

        let patBody: [UInt8] = [0x00, 0xB0, 13, 0x00, 0x01, 0xC1, 0x00, 0x00, 0x00, 0x01, 0xF0, 0x00]
        let pmtBody: [UInt8] = [0x02, 0xB0, 18, 0x00, 0x01, 0xC1, 0x00, 0x00, 0xE1, 0x00, 0xF0, 0x00, 0x0F, 0xE1, 0x00, 0xF0, 0x00]

        var tsData = Data()
        tsData.append(makePsiPacket(pid: 0x0000, body: patBody))
        tsData.append(makePsiPacket(pid: 0x1000, body: pmtBody))

        let clampedDuration = max(0.5, min(30.0, durationSeconds))
        let totalFrames = max(4, Int((clampedDuration * Double(sampleRate) / 1024.0).rounded()))
        let framesPerPes = 22
        var continuityCounter: UInt8 = 0
        var frameIdx = 0

        while frameIdx < totalFrames {
            let chunkCount = min(framesPerPes, totalFrames - frameIdx)
            var pesAudio = Data(capacity: chunkCount * frameLen)
            for _ in 0..<chunkCount {
                pesAudio.append(contentsOf: adtsFrame)
            }
            let offsetTicks = (UInt64(frameIdx) * 1024 * 90_000) / UInt64(sampleRate)
            emitElementaryPesPackets(
                into: &tsData,
                streamId: 0xC0,
                payload: pesAudio,
                pts90k: ptsStart90k &+ offsetTicks,
                includePcr: frameIdx == 0,
                continuityCounter: &continuityCounter
            )
            frameIdx += chunkCount
        }

        return tsData
    }

    // MARK: - Annex-B & H.264 SPS Parsing

    private static func extractCompleteFirstSps(fromAnnexB data: Data, allowAtEnd: Bool) -> Data? {
        let count = data.count
        guard count >= 5 else { return nil }

        var i = 0
        var spsDataStart: Int? = nil

        while i + 3 < count {
            let is4Byte = (data[i] == 0 && data[i + 1] == 0 && data[i + 2] == 0 && data[i + 3] == 1)
            let is3Byte = !is4Byte && (data[i] == 0 && data[i + 1] == 0 && data[i + 2] == 1)
            if is4Byte || is3Byte {
                let scLen = is4Byte ? 4 : 3
                if let start = spsDataStart {
                    if i > start {
                        return data.subdata(in: start..<i)
                    }
                    return nil
                }
                let nalHeaderPos = i + scLen
                if nalHeaderPos < count && (data[nalHeaderPos] & 0x1F) == 7 {
                    spsDataStart = nalHeaderPos
                }
                i += scLen
                continue
            }
            i += 1
        }

        if allowAtEnd, let start = spsDataStart, count > start {
            return data.subdata(in: start..<count)
        }
        return nil
    }

    static func parseH264Sps(_ sps: Data) -> H264SpsInfo? {
        guard sps.count >= 4 else { return nil }
        let rbsp = removeEmulationPrevention(sps.subdata(in: 1..<sps.count))
        var reader = BitReader(data: rbsp)

        guard let profileRaw = reader.readBits(8),
              let _ = reader.readBits(8),
              let levelRaw = reader.readBits(8),
              let _ = reader.readUE() else {
            return nil
        }

        let profileIdc = Int(profileRaw)
        let levelIdc = Int(levelRaw)
        let highProfiles: Set<Int> = [100, 110, 122, 244, 44, 83, 86, 118, 128, 138, 139, 134, 135]
        if highProfiles.contains(profileIdc) {
            guard let chromaFormat = reader.readUE() else { return nil }
            if chromaFormat == 3 {
                guard reader.readBit() != nil else { return nil }
            }
            guard reader.readUE() != nil,
                  reader.readUE() != nil,
                  reader.readBit() != nil,
                  let scalingPresent = reader.readBit() else { return nil }
            if scalingPresent == 1 {
                let listCount = (chromaFormat != 3) ? 8 : 12
                for idx in 0..<listCount {
                    guard let present = reader.readBit() else { return nil }
                    if present == 1 {
                        let size = idx < 6 ? 16 : 64
                        var lastScale = 8
                        var nextScale = 8
                        for _ in 0..<size {
                            if nextScale != 0 {
                                guard let delta = reader.readSE() else { return nil }
                                nextScale = (lastScale + delta + 256) % 256
                            }
                            lastScale = (nextScale == 0) ? lastScale : nextScale
                        }
                    }
                }
            }
        }

        guard reader.readUE() != nil,
              let picOrderCntType = reader.readUE() else { return nil }
        if picOrderCntType == 0 {
            guard reader.readUE() != nil else { return nil }
        } else if picOrderCntType == 1 {
            guard reader.readBit() != nil,
                  reader.readSE() != nil,
                  reader.readSE() != nil,
                  let numRef = reader.readUE() else { return nil }
            for _ in 0..<min(numRef, 256) {
                guard reader.readSE() != nil else { return nil }
            }
        }

        guard reader.readUE() != nil,
              reader.readBit() != nil,
              let widthMbsMinus1 = reader.readUE(),
              let heightMapMinus1 = reader.readUE(),
              let frameMbsOnly = reader.readBit() else { return nil }
        if frameMbsOnly == 0 {
            guard reader.readBit() != nil else { return nil }
        }
        guard reader.readBit() != nil,
              let cropping = reader.readBit() else { return nil }

        var cropLeft = 0, cropRight = 0, cropTop = 0, cropBottom = 0
        if cropping == 1 {
            guard let l = reader.readUE(),
                  let r = reader.readUE(),
                  let t = reader.readUE(),
                  let b = reader.readUE() else { return nil }
            cropLeft = l; cropRight = r; cropTop = t; cropBottom = b
        }

        let width = (widthMbsMinus1 + 1) * 16 - (cropLeft + cropRight) * 2
        let height = (2 - frameMbsOnly) * (heightMapMinus1 + 1) * 16 - (cropTop + cropBottom) * 2

        var fps: Double? = nil
        if reader.readBit() == 1 {
            // aspect_ratio_info_present_flag
            if reader.readBit() == 1 {
                if let idc = reader.readBits(8), idc == 255 {
                    _ = reader.readBits(16)
                    _ = reader.readBits(16)
                }
            }
            // overscan_info_present_flag
            if reader.readBit() == 1 { _ = reader.readBit() }
            // video_signal_type_present_flag
            if reader.readBit() == 1 {
                _ = reader.readBits(4)
                if reader.readBit() == 1 { _ = reader.readBits(24) }
            }
            // chroma_loc_info_present_flag
            if reader.readBit() == 1 {
                _ = reader.readUE()
                _ = reader.readUE()
            }
            // timing_info_present_flag
            if reader.readBit() == 1,
               let numUnits = reader.readBits(32),
               let timeScale = reader.readBits(32),
               numUnits > 0, timeScale > 0 {
                fps = (Double(timeScale) / (2.0 * Double(numUnits)) * 1000.0).rounded() / 1000.0
            }
        }

        return H264SpsInfo(
            rawSps: sps,
            profileIdc: profileIdc,
            levelIdc: levelIdc,
            width: width,
            height: height,
            fps: fps
        )
    }

    private static func removeEmulationPrevention(_ data: Data) -> Data {
        var out = Data(capacity: data.count)
        let bytes = [UInt8](data)
        for i in 0..<bytes.count {
            if i >= 2 && bytes[i] == 0x03 && bytes[i - 1] == 0x00 && bytes[i - 2] == 0x00 {
                continue
            }
            out.append(bytes[i])
        }
        return out
    }

    private struct BitReader {
        private let bytes: [UInt8]
        private var byteOffset = 0
        private var bitOffset = 0

        init(data: Data) {
            self.bytes = [UInt8](data)
        }

        mutating func readBit() -> Int? {
            guard byteOffset < bytes.count else { return nil }
            let bit = Int((bytes[byteOffset] >> (7 - bitOffset)) & 1)
            bitOffset += 1
            if bitOffset == 8 {
                bitOffset = 0
                byteOffset += 1
            }
            return bit
        }

        mutating func readBits(_ count: Int) -> UInt32? {
            guard count >= 0 && count <= 32 else { return nil }
            var value: UInt32 = 0
            for _ in 0..<count {
                guard let bit = readBit() else { return nil }
                value = (value << 1) | UInt32(bit)
            }
            return value
        }

        mutating func readUE() -> Int? {
            var leadingZeros = 0
            while true {
                guard let bit = readBit() else { return nil }
                if bit == 1 { break }
                leadingZeros += 1
                if leadingZeros >= 31 { return nil }
            }
            if leadingZeros == 0 { return 0 }
            guard let suffix = readBits(leadingZeros) else { return nil }
            return (1 << leadingZeros) - 1 + Int(suffix)
        }

        mutating func readSE() -> Int? {
            guard let ue = readUE() else { return nil }
            return (ue & 1) == 1 ? ((ue + 1) >> 1) : -(ue >> 1)
        }
    }
}
