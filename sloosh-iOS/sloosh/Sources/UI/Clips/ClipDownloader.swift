import Foundation
import AVFoundation
import Photos
import UIKit
import CommonCrypto

/// Фоновый менеджер для скачивания и нарезки фрагментов моментов (MovieClip) в чистый MP4 из HLS и прямых потоков
@MainActor
public final class ClipDownloader: ObservableObject {
    public static let shared = ClipDownloader()

    @Published public var isDownloading: Bool = false
    @Published public var currentClipId: String? = nil

    private init() {}

    public func download(clip: MovieClip) {
        guard !isDownloading else {
            ToastManager.shared.show(
                title: "Загрузка уже выполняется",
                icon: "arrow.down.circle.fill",
                iconColor: .white
            )
            return
        }

        isDownloading = true
        currentClipId = clip.id
        ToastManager.shared.show(
            title: "Скачивание момента...",
            subtitle: clip.title,
            icon: "arrow.down.circle",
            iconColor: .white,
            duration: 6.0
        )
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        Task {
            do {
                guard let playbackInfo = await ClipStreamResolver.shared.resolveClip(for: clip) else {
                    throw NSError(domain: "sloosh.clip", code: -1, userInfo: [NSLocalizedDescriptionKey: "Не удалось получить видеопоток"])
                }

                AppDiagnostics.shared.log("[ClipDownloader] Starting download for clip=\(clip.id), start=\(clip.startTime), end=\(clip.endTime), url=\(playbackInfo.url)")

                let fm = FileManager.default
                let cleanTitle = clip.title
                    .replacingOccurrences(of: "/", with: "-")
                    .replacingOccurrences(of: "\\", with: "-")
                    .replacingOccurrences(of: ":", with: " -")
                let fileName = "sloosh_\(cleanTitle)_\(clip.id).mp4"
                let outputUrl = fm.temporaryDirectory.appendingPathComponent(fileName)
                try? fm.removeItem(at: outputUrl)

                // Выбираем лучший URL: отдаём предпочтение 1080p -> 720p -> url
                let targetUrl = playbackInfo.qualityUrls["1080p"]
                    ?? playbackInfo.qualityUrls["720p"]
                    ?? playbackInfo.url

                try await downloadAndTrimClip(
                    targetUrl: targetUrl,
                    headers: playbackInfo.headers,
                    clip: clip,
                    outputUrl: outputUrl
                )

                let exactSize = ((try? fm.attributesOfItem(atPath: outputUrl.path))?[.size] as? Int64) ?? 0
                guard fm.fileExists(atPath: outputUrl.path) && exactSize > 5000 else {
                    throw NSError(domain: "sloosh.clip", code: -2, userInfo: [NSLocalizedDescriptionKey: "Не удалось экспортировать фрагмент"])
                }

                AppDiagnostics.shared.log("[ClipDownloader] Exported MP4 successfully, size=\(exactSize) bytes")

                // Сохранение в Фотоплёнку
                let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
                if status == .authorized || status == .limited {
                    try await PHPhotoLibrary.shared().performChanges {
                        PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: outputUrl)
                    }
                    ToastManager.shared.show(
                        title: "Момент сохранён в «Фото»",
                        subtitle: clip.title,
                        icon: "checkmark.circle.fill",
                        iconColor: .green
                    )
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } else {
                    // Фолбэк в системный Share Sheet
                    presentShareSheet(for: outputUrl)
                    ToastManager.shared.show(
                        title: "Момент готов",
                        subtitle: "Выберите «Сохранить в Файлы»",
                        icon: "square.and.arrow.up",
                        iconColor: .white
                    )
                }
            } catch {
                AppDiagnostics.shared.log("[ClipDownloader] Error: \(error.localizedDescription)")
                ToastManager.shared.show(
                    title: "Не удалось скачать момент",
                    subtitle: error.localizedDescription,
                    icon: "exclamationmark.triangle.fill",
                    iconColor: .orange
                )
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }

            self.isDownloading = false
            self.currentClipId = nil
        }
    }

    private func downloadAndTrimClip(
        targetUrl: URL,
        headers: [String: String],
        clip: MovieClip,
        outputUrl: URL
    ) async throws {
        let session = URLSession.shared
        var req = URLRequest(url: targetUrl)
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }

        let (data, response) = try await session.data(for: req)
        guard let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode) else {
            throw NSError(domain: "sloosh.clip", code: -4, userInfo: [NSLocalizedDescriptionKey: "Сервер вернул ошибку при запросе потока"])
        }

        let playlistText = String(data: data, encoding: .utf8) ?? ""

        if !playlistText.contains("#EXTM3U") {
            // Direct MP4 / media stream
            try await handleDirectVideoStream(data: data, clip: clip, outputUrl: outputUrl)
            return
        }

        // HLS Playlist
        let mediaPlaylistUrl: URL
        let mediaPlaylistText: String

        if playlistText.contains("#EXT-X-STREAM-INF") {
            // Master playlist: find highest bandwidth variant
            guard let variantUrl = parseBestVariantUrl(from: playlistText, baseUrl: targetUrl) else {
                throw NSError(domain: "sloosh.clip", code: -5, userInfo: [NSLocalizedDescriptionKey: "Не удалось выбрать дорожку качества"])
            }
            var variantReq = URLRequest(url: variantUrl)
            for (k, v) in headers { variantReq.setValue(v, forHTTPHeaderField: k) }
            let (variantData, variantResp) = try await session.data(for: variantReq)
            guard let vHttp = variantResp as? HTTPURLResponse, (200...299).contains(vHttp.statusCode) else {
                throw NSError(domain: "sloosh.clip", code: -6, userInfo: [NSLocalizedDescriptionKey: "Не удалось загрузить плейлист фрагментов"])
            }
            mediaPlaylistUrl = variantUrl
            mediaPlaylistText = String(data: variantData, encoding: .utf8) ?? ""
        } else {
            mediaPlaylistUrl = targetUrl
            mediaPlaylistText = playlistText
        }

        try await downloadHlsSegmentsAndTrim(
            mediaPlaylistText: mediaPlaylistText,
            baseUrl: mediaPlaylistUrl,
            headers: headers,
            clip: clip,
            outputUrl: outputUrl
        )
    }

    private struct HlsSegment {
        let url: URL
        let duration: Double
        let startTime: Double
        let sequenceNumber: Int
        let keyUrl: URL?
        let ivData: Data?
    }

    private func downloadHlsSegmentsAndTrim(
        mediaPlaylistText: String,
        baseUrl: URL,
        headers: [String: String],
        clip: MovieClip,
        outputUrl: URL
    ) async throws {
        var segments: [HlsSegment] = []
        var currentKeyUrl: URL? = nil
        var currentIvData: Data? = nil
        var currentTime: Double = 0.0
        var sequenceNumber: Int = 0
        var initSegmentUrl: URL? = nil
        var pendingDuration: Double? = nil

        let lines = mediaPlaylistText.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if trimmed.hasPrefix("#EXT-X-MEDIA-SEQUENCE:") {
                let seqStr = trimmed.replacingOccurrences(of: "#EXT-X-MEDIA-SEQUENCE:", with: "")
                if let s = Int(seqStr.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    sequenceNumber = s
                }
            } else if trimmed.hasPrefix("#EXT-X-MAP:") {
                if let uriRange = trimmed.range(of: "URI=\"") {
                    let after = trimmed[uriRange.upperBound...]
                    if let endQuote = after.firstIndex(of: "\"") {
                        let uriStr = String(after[..<endQuote])
                        initSegmentUrl = URL(string: uriStr, relativeTo: baseUrl)?.absoluteURL
                    }
                }
            } else if trimmed.hasPrefix("#EXT-X-KEY:") {
                if trimmed.contains("METHOD=NONE") {
                    currentKeyUrl = nil
                    currentIvData = nil
                } else {
                    if let uriRange = trimmed.range(of: "URI=\"") {
                        let after = trimmed[uriRange.upperBound...]
                        if let endQuote = after.firstIndex(of: "\"") {
                            let uriStr = String(after[..<endQuote])
                            currentKeyUrl = URL(string: uriStr, relativeTo: baseUrl)?.absoluteURL
                        }
                    }
                    if let ivRange = trimmed.range(of: "IV=0x") {
                        let after = trimmed[ivRange.upperBound...]
                        let hexStr = String(after.prefix(32))
                        currentIvData = Self.hexToData(hexStr)
                    }
                }
            } else if trimmed.hasPrefix("#EXTINF:") {
                let durStr = trimmed
                    .replacingOccurrences(of: "#EXTINF:", with: "")
                    .components(separatedBy: ",")[0]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                pendingDuration = Double(durStr)
            } else if !trimmed.hasPrefix("#") {
                if let pendingDur = pendingDuration,
                   let segUrl = URL(string: trimmed, relativeTo: baseUrl)?.absoluteURL {
                    let seg = HlsSegment(
                        url: segUrl,
                        duration: pendingDur,
                        startTime: currentTime,
                        sequenceNumber: sequenceNumber,
                        keyUrl: currentKeyUrl,
                        ivData: currentIvData
                    )
                    segments.append(seg)
                    currentTime += pendingDur
                    sequenceNumber += 1
                    pendingDuration = nil
                }
            }
        }

        guard !segments.isEmpty else {
            throw NSError(domain: "sloosh.clip", code: -7, userInfo: [NSLocalizedDescriptionKey: "Плейлист не содержит фрагментов"])
        }

        let clipStart = clip.startTime
        let clipEnd = clip.endTime
        let targetSegments = segments.filter { seg in
            let segEnd = seg.startTime + seg.duration
            return segEnd >= clipStart && seg.startTime <= clipEnd
        }

        let chosenSegments = targetSegments.isEmpty ? segments : targetSegments
        guard let firstSeg = chosenSegments.first else {
            throw NSError(domain: "sloosh.clip", code: -8, userInfo: [NSLocalizedDescriptionKey: "Не найдены фрагменты для момента"])
        }

        let firstSegmentStartTime = firstSeg.startTime
        let relativeStart = max(0.0, clipStart - firstSegmentStartTime)
        let clipDuration = max(1.0, clipEnd - clipStart)

        AppDiagnostics.shared.log("[ClipDownloader] Downloading \(chosenSegments.count) segments for clip \(clip.id), relativeStart=\(relativeStart), duration=\(clipDuration)")

        let session = URLSession.shared

        // 1. Fetch decryption keys if needed
        var keysCache: [URL: Data] = [:]
        for seg in chosenSegments {
            if let kUrl = seg.keyUrl, keysCache[kUrl] == nil {
                var kReq = URLRequest(url: kUrl)
                for (k, v) in headers { kReq.setValue(v, forHTTPHeaderField: k) }
                if let (kData, kResp) = try? await session.data(for: kReq),
                   (kResp as? HTTPURLResponse)?.statusCode == 200,
                   kData.count == 16 {
                    keysCache[kUrl] = kData
                }
            }
        }

        // 2. Fetch init segment data if fMP4
        var initData: Data? = nil
        if let initUrl = initSegmentUrl {
            var initReq = URLRequest(url: initUrl)
            for (k, v) in headers { initReq.setValue(v, forHTTPHeaderField: k) }
            if let (iData, iResp) = try? await session.data(for: initReq),
               (iResp as? HTTPURLResponse)?.statusCode == 200 {
                initData = iData
            }
        }

        // 3. Download and decrypt segments concurrently
        let downloadedChunks: [Data] = try await withThrowingTaskGroup(of: (Int, Data).self) { group in
            for (index, seg) in chosenSegments.enumerated() {
                group.addTask {
                    var sReq = URLRequest(url: seg.url)
                    for (k, v) in headers { sReq.setValue(v, forHTTPHeaderField: k) }
                    let (sData, sResp) = try await session.data(for: sReq)
                    guard (sResp as? HTTPURLResponse)?.statusCode == 200 else {
                        throw NSError(domain: "sloosh.clip", code: -9, userInfo: [NSLocalizedDescriptionKey: "Ошибка загрузки сегмента"])
                    }
                    if let kUrl = seg.keyUrl, let kData = keysCache[kUrl] {
                        let decrypted = Self.decryptHlsSegment(
                            data: sData,
                            key: kData,
                            sequence: seg.sequenceNumber,
                            customIv: seg.ivData
                        ) ?? sData
                        return (index, decrypted)
                    } else {
                        return (index, sData)
                    }
                }
            }
            var collected: [(Int, Data)] = []
            for try await item in group {
                collected.append(item)
            }
            return collected.sorted(by: { $0.0 < $1.0 }).map { $0.1 }
        }

        // 4. Stitch chunks into a local temp file
        let fm = FileManager.default
        let stitchedExt = (initData != nil) ? "mp4" : "ts"
        let stitchedUrl = fm.temporaryDirectory.appendingPathComponent("stitched_\(UUID().uuidString).\(stitchedExt)")
        fm.createFile(atPath: stitchedUrl.path, contents: nil)

        guard let handle = try? FileHandle(forWritingTo: stitchedUrl) else {
            throw NSError(domain: "sloosh.clip", code: -10, userInfo: [NSLocalizedDescriptionKey: "Ошибка записи временного файла"])
        }

        defer {
            try? handle.close()
            try? fm.removeItem(at: stitchedUrl)
        }

        if let initData {
            try handle.write(contentsOf: initData)
        }
        for chunk in downloadedChunks {
            try handle.write(contentsOf: chunk)
        }
        try handle.close()

        // 5. Trim stitched local file to exact clip bounds
        let trimRange = CMTimeRange(
            start: CMTime(seconds: relativeStart, preferredTimescale: 600),
            duration: CMTime(seconds: clipDuration, preferredTimescale: 600)
        )

        try await Self.remuxOrExport(inputUrl: stitchedUrl, outputUrl: outputUrl, timeRange: trimRange)
    }

    private func handleDirectVideoStream(data: Data, clip: MovieClip, outputUrl: URL) async throws {
        let fm = FileManager.default
        let tempUrl = fm.temporaryDirectory.appendingPathComponent("direct_\(UUID().uuidString).mp4")
        try data.write(to: tempUrl)
        defer { try? fm.removeItem(at: tempUrl) }

        let durationSec = max(1.0, clip.endTime - clip.startTime)
        let trimRange = CMTimeRange(
            start: CMTime(seconds: clip.startTime, preferredTimescale: 600),
            duration: CMTime(seconds: durationSec, preferredTimescale: 600)
        )

        try await Self.remuxOrExport(inputUrl: tempUrl, outputUrl: outputUrl, timeRange: trimRange)
    }

    private func parseBestVariantUrl(from masterText: String, baseUrl: URL) -> URL? {
        var variants: [(bandwidth: Int, url: URL)] = []
        var currentBandwidth = 0
        let lines = masterText.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("#EXT-X-STREAM-INF:") {
                if let bwRange = trimmed.range(of: "BANDWIDTH=") {
                    let afterBw = trimmed[bwRange.upperBound...]
                    let bwDigits = afterBw.components(separatedBy: CharacterSet.decimalDigits.inverted)[0]
                    currentBandwidth = Int(bwDigits) ?? 0
                }
            } else if !trimmed.hasPrefix("#") && !trimmed.isEmpty {
                if let u = URL(string: trimmed, relativeTo: baseUrl)?.absoluteURL {
                    variants.append((currentBandwidth, u))
                }
                currentBandwidth = 0
            }
        }
        return variants.sorted(by: { $0.bandwidth > $1.bandwidth }).first?.url
    }

    private static func remuxOrExport(inputUrl: URL, outputUrl: URL, timeRange: CMTimeRange) async throws {
        let fm = FileManager.default
        let asset = AVURLAsset(url: inputUrl)

        let presets = [
            AVAssetExportPresetHighestQuality,
            AVAssetExportPreset1920x1080,
            AVAssetExportPreset1280x720,
            AVAssetExportPresetPassthrough
        ]

        for preset in presets {
            try? fm.removeItem(at: outputUrl)
            if let session = AVAssetExportSession(asset: asset, presetName: preset) {
                session.outputURL = outputUrl
                session.outputFileType = .mp4
                session.shouldOptimizeForNetworkUse = true
                if timeRange.duration.isNumeric && timeRange.duration.seconds > 0 {
                    session.timeRange = timeRange
                }
                await session.export()

                let size = ((try? fm.attributesOfItem(atPath: outputUrl.path))?[.size] as? Int64) ?? 0
                if session.status == .completed && fm.fileExists(atPath: outputUrl.path) && size > 5000 {
                    return
                }
            }
        }

        throw NSError(domain: "sloosh.clip", code: -11, userInfo: [NSLocalizedDescriptionKey: "Не удалось перекодировать фрагмент видео"])
    }

    private static func hexToData(_ hex: String) -> Data? {
        var cleanHex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanHex.hasPrefix("0x") || cleanHex.hasPrefix("0X") {
            cleanHex = String(cleanHex.dropFirst(2))
        }
        guard cleanHex.count % 2 == 0 else { return nil }
        var data = Data(capacity: cleanHex.count / 2)
        var index = cleanHex.startIndex
        while index < cleanHex.endIndex {
            let nextIndex = cleanHex.index(index, offsetBy: 2)
            if let byte = UInt8(cleanHex[index..<nextIndex], radix: 16) {
                data.append(byte)
            } else {
                return nil
            }
            index = nextIndex
        }
        return data
    }

    private static func decryptHlsSegment(data: Data, key: Data, sequence: Int, customIv: Data? = nil) -> Data? {
        guard key.count == 16 else { return nil }

        var iv = [UInt8](repeating: 0, count: 16)
        if let customIv, customIv.count == 16 {
            customIv.copyBytes(to: &iv, count: 16)
        } else {
            var seqBig = UInt64(sequence).bigEndian
            withUnsafeBytes(of: &seqBig) { bytes in
                for i in 0..<min(8, bytes.count) {
                    iv[16 - bytes.count + i] = bytes[i]
                }
            }
        }

        let bufferSize = data.count + kCCBlockSizeAES128
        var decryptedData = Data(count: bufferSize)
        var numBytesDecrypted: size_t = 0

        let cryptStatus = key.withUnsafeBytes { keyBytes in
            data.withUnsafeBytes { dataBytes in
                decryptedData.withUnsafeMutableBytes { decBytes in
                    CCCrypt(
                        CCOperation(kCCDecrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionPKCS7Padding),
                        keyBytes.baseAddress, 16,
                        iv,
                        dataBytes.baseAddress, data.count,
                        decBytes.baseAddress, bufferSize,
                        &numBytesDecrypted
                    )
                }
            }
        }

        if cryptStatus == kCCSuccess {
            decryptedData.removeSubrange(numBytesDecrypted..<bufferSize)
            return decryptedData
        }
        return nil
    }

    private func presentShareSheet(for url: URL) {
        let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(av, animated: true)
        }
    }
}
