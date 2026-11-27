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

/// Lightweight, pure-Foundation MPEG-TS / H.264 SPS inspector and ad-swap detector.
/// Identifies server-side in-place banner replacements (such as 268,088B / 60fps segments
/// spliced under normal segment URLs without M3U8 discontinuity tags) within the first ~1 KB.
enum HlsSegmentShield {
    static let maxInspectionBytes = 65_536
    static let knownBannerByteLength: Int64 = 268_088
    static let knownBannerETagSuffix = "-41738\""

    /// Known H.264 High@L3.2 1280x720 @ 60fps SPS used by injected mid-stream promo banners.
    static let knownBannerSpsHex = "67640020acd9805005ba6a04040280000003008000003c078c18cd"

    static func isInspectableVideoSegment(url: URL, isCollaps: Bool, rangeHeader: String?) -> Bool {
        let host = url.host?.lowercased() ?? ""
        guard isCollaps || host.contains("interkh.com") || host.contains("interkh") else {
            return false
        }
        let lowerPath = url.path.lowercased()
        let ext = url.pathExtension.lowercased()
        guard ext == "ts" || lowerPath.contains(".ts") else {
            return false
        }
        // Skip audio-only TS chunks (e.g. seg-12-a1.ts)
        let lastComponent = url.lastPathComponent.lowercased()
        if lastComponent.range(of: #"-a\d+\.ts$"#, options: .regularExpression) != nil {
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

    /// Groups baseline SPS signatures by video quality tier (e.g. "v1", "v2") so ABR switches never mismatch.
    static func tierKey(for url: URL) -> String {
        let name = url.lastPathComponent.lowercased()
        if let regex = try? NSRegularExpression(pattern: #"-(v\d+)\.ts$"#, options: []),
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
                            let ptsDtsFlags = (data[payloadPos + 7] >> 6) & 0x03
                            if (ptsDtsFlags & 0x02) != 0, payloadPos + 14 <= packetEnd {
                                let b0 = UInt64(data[payloadPos + 9])
                                let b1 = UInt64(data[payloadPos + 10])
                                let b2 = UInt64(data[payloadPos + 11])
                                let b3 = UInt64(data[payloadPos + 12])
                                let b4 = UInt64(data[payloadPos + 13])
                                firstPts90k = ((b0 & 0x0E) << 29)
                                    | ((b1 & 0xFF) << 22)
                                    | ((b2 & 0xFE) << 14)
                                    | ((b3 & 0xFF) << 7)
                                    | ((b4 & 0xFE) >> 1)
                            }
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
        stripRefererOrigin: Bool = false,
        forceCloseConnection: Bool = false
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
        if forceCloseConnection {
            request.setValue("close", forHTTPHeaderField: "Connection")
        }
        if stripRefererOrigin {
            request.setValue(nil, forHTTPHeaderField: "Referer")
            request.setValue(nil, forHTTPHeaderField: "Origin")
        }
        return request
    }

    // MARK: - Clean Black MPEG-TS Replacement (Zero-Ad Guarantee)

    private static let black360KeyDeflateB64 = "Y2BgYEx3OiDXk8HF9H9aHpMUEz9HSxYDAwNjxjmbBhCduoOBhdX+/z+5Lga2mjlEgbml12NH0SgaTCgOAA=="
    private static let black360DeltaDeflateB64 = "Y2BgYEx8wFDnENxgOQMA"
    private static let black720KeyDeflateB64 = "Y2BgYExP4ZFfI3GBi2G77wFnB8eHAr0ODAwMjBnnbBpAdOoOBhZW+f//2xc1MM5Xpy6ILb0+ikbRoEKQRM9QocfAyOj+///DFwsY0k9SF4yG8igabOgBJNnbcDcwOAT+//+jSoNB8lMRVcFoKI+iwYYqIMlerOkBg4BI/f9/cl0MbDVzqArmjobysEZxAA=="
    private static let black720DeltaDeflateB64 = "Y2BgYEx8wFDnEPiAn40BxGGosGCQnyBSwXywAcK34WNgf8Iqx/AhAcIXa25g/Mno3qArAQA="
    private static let black1080KeyDeflateB64 = "Y2BgYExP4dFYI3GBn8Hlz+YCgQsCFS7KAQwMDIwZ52waQHTqDgYWVvn//9sXNTDOVx8YEFt6fRSNolE0ikYR2QhSnDPYcDcwOAT+//+jSoNB8lPRgIDR6BhFo2gUjSJKUAWkQJdjesAgIFL//59cFwNbzZwBAXNHY2MUjaJRNIooQHGQAp3bYXTMZRSNolE0ikbRKCJmbAsA"
    private static let black1080DeltaDeflateB64 = "Y2BgYEx8wFDnEPiAbWIDA4jHYNLHwP6EVY5B8RiEL8fcwPiT0b1BrA3C5wqAaGC6kAAA"

    private static func decompressRawDeflate(_ base64: String) -> Data? {
        guard let compressed = Data(base64Encoded: base64) else { return nil }
        return try? (compressed as NSData).decompressed(using: .zlib) as Data
    }

    static func resolveStreamDimensions(fromBaselineSps baselineSps: Data?) -> (width: Int, height: Int) {
        guard let baselineSps, let parsed = parseH264Sps(baselineSps) else {
            return (1280, 720)
        }
        return (parsed.width, parsed.height)
    }

    /// Synthesizes a valid, zero-banner black H.264 MPEG-TS segment aligned to the replaced segment's PTS & duration.
    static func buildBlackReplacementTs(
        width: Int,
        height: Int,
        ptsStart90k: UInt64,
        durationSeconds: Double
    ) -> Data? {
        let keyB64: String
        let dltB64: String
        if width > 1440 || height > 900 {
            keyB64 = black1080KeyDeflateB64
            dltB64 = black1080DeltaDeflateB64
        } else if width <= 800 && height <= 500 {
            keyB64 = black360KeyDeflateB64
            dltB64 = black360DeltaDeflateB64
        } else {
            keyB64 = black720KeyDeflateB64
            dltB64 = black720DeltaDeflateB64
        }

        guard let keyAnnexB = decompressRawDeflate(keyB64),
              let deltaAnnexB = decompressRawDeflate(dltB64) else {
            return nil
        }

        func crc32Mpeg2(_ bytes: [UInt8]) -> UInt32 {
            var crc: UInt32 = 0xFFFF_FFFF
            for byte in bytes {
                crc ^= UInt32(byte) << 24
                for _ in 0..<8 {
                    crc = (crc & 0x8000_0000) != 0 ? ((crc << 1) ^ 0x04C1_1DB7) : (crc << 1)
                }
            }
            return crc
        }

        func makePsiPacket(pid: UInt16, body: [UInt8]) -> Data {
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

        let patBody: [UInt8] = [0x00, 0xB0, 13, 0x00, 0x01, 0xC1, 0x00, 0x00, 0x00, 0x01, 0xF0, 0x00]
        let pmtBody: [UInt8] = [0x02, 0xB0, 18, 0x00, 0x01, 0xC1, 0x00, 0x00, 0xE1, 0x00, 0xF0, 0x00, 0x1B, 0xE1, 0x00, 0xF0, 0x00]

        var tsData = Data()
        tsData.append(makePsiPacket(pid: 0x0000, body: patBody))
        tsData.append(makePsiPacket(pid: 0x1000, body: pmtBody))

        var continuityCounter: UInt8 = 0
        func emitPes(annexB: Data, pts90k: UInt64, includePcr: Bool) {
            let t = pts90k & 0x1_FFFF_FFFF
            let pesHeader: [UInt8] = [
                0x00, 0x00, 0x01, 0xE0, 0x00, 0x00, 0x80, 0x80, 0x05,
                0x21 | UInt8((t >> 29) & 0x0E),
                UInt8((t >> 22) & 0xFF),
                0x01 | UInt8((t >> 14) & 0xFE),
                UInt8((t >> 7) & 0xFF),
                0x01 | UInt8((t << 1) & 0xFE)
            ]
            var fullPayload = Data(pesHeader)
            fullPayload.append(Data([0x00, 0x00, 0x00, 0x01, 0x09, 0xF0])) // AUD
            fullPayload.append(annexB)

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

        let clampedDuration = max(0.5, min(30.0, durationSeconds))
        let deltaTicks = max(UInt64(3_754), UInt64((clampedDuration * 90_000.0).rounded()) - 3_754)
        emitPes(annexB: keyAnnexB, pts90k: ptsStart90k, includePcr: true)
        emitPes(annexB: deltaAnnexB, pts90k: ptsStart90k &+ deltaTicks, includePcr: false)
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
