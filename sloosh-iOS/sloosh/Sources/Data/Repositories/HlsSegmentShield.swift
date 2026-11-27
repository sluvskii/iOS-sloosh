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
        var videoPid: Int? = nil
        var sawNonH264Video = false
        var sawPmtStreams = false
        var videoEsBuffer = Data()
        var collectingVideoPes = false

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
                    if sawPmtStreams && videoPid == nil && !sawNonH264Video {
                        return .audioOnlyOrNonH264
                    }
                    if sawNonH264Video && videoPid == nil {
                        return .audioOnlyOrNonH264
                    }
                }
            } else if let videoPid, pid == videoPid {
                if pusi {
                    if payloadPos + 9 <= packetEnd,
                       data[payloadPos] == 0x00,
                       data[payloadPos + 1] == 0x00,
                       data[payloadPos + 2] == 0x01 {
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
                        return .videoSps(parsed)
                    }
                    return .audioOnlyOrNonH264
                }
            }

            offset += 188
        }

        if isComplete, let spsData = extractCompleteFirstSps(fromAnnexB: videoEsBuffer, allowAtEnd: true),
           let parsed = parseH264Sps(spsData) {
            return .videoSps(parsed)
        }
        return .pending
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
        } else if !stripRefererOrigin && failoverHost != nil {
            // Even when targeting same failover host on second pass, preserve URL
        }
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        if stripRefererOrigin {
            request.setValue(nil, forHTTPHeaderField: "Referer")
            request.setValue(nil, forHTTPHeaderField: "Origin")
        }
        return request
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
