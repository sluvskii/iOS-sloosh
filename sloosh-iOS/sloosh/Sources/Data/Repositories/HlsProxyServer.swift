import Foundation
import Network
import Security
import os.log

import UIKit

class HlsProxyServer {
    static let shared = HlsProxyServer()
    private var listener: NWListener?
    private var isListenerAlive = false // надёжный флаг: false если .failed/.cancelled
    private let queue = DispatchQueue(label: "com.sloosh.ios.hlsproxy", attributes: .concurrent)
    private let stateLock = NSLock()
    private var headers: [String: String] = [:]
    private var voices: [String] = []
    private var subtitles: [PlaybackSubtitle] = []
    private var mediaId: String = ""
    private var preferredVoiceName: String? = nil
    private var isCollapsStream: Bool = false
    struct VideoTimelineEntry: Sendable {
        let name: String
        let startSeconds: Double
        let endSeconds: Double
        let url: URL
    }

    struct TimeWindowTarget: Sendable {
        let startSeconds: Double
        let endSeconds: Double
        let targetKey: String
        let host: String
        let directIp: String?
        let recordedAt: Date
    }

    struct BlackoutTimeWindow: Sendable {
        let startSeconds: Double
        let endSeconds: Double
        let recordedAt: Date
    }

    private final class VideoInspectionWaiter: @unchecked Sendable {
        let id = UUID()
        let startSeconds: Double
        let endSeconds: Double
        private let lock = NSLock()
        private var waiters: [DispatchSemaphore] = []
        private var finished = false

        init(startSeconds: Double, endSeconds: Double) {
            self.startSeconds = startSeconds
            self.endSeconds = endSeconds
        }

        func overlaps(_ otherStart: Double, _ otherEnd: Double) -> Bool {
            max(startSeconds, otherStart) < min(endSeconds, otherEnd)
        }

        func addWaiter(_ sem: DispatchSemaphore) -> Bool {
            lock.withLock {
                if finished { return false }
                waiters.append(sem)
                return true
            }
        }

        func finish() {
            let sems: [DispatchSemaphore] = lock.withLock {
                guard !finished else { return [] }
                finished = true
                let copy = waiters
                waiters.removeAll()
                return copy
            }
            for s in sems {
                s.signal()
            }
        }
    }

    private var currentMasterUrl: URL?
    private var failoverHosts: [String] = []
    private var streamDeclaredMaxFps: Double? = nil
    private var segmentBaselineSpsByTier: [String: Data] = [:]
    private var segmentBaselineAudioByTier: [String: HlsAudioStreamInfo] = [:]
    private var knownBannerAudioFingerprints: Set<UInt64> = []
    private var recentAudioFingerprints: [UInt64: (segmentName: String, seenAt: Date)] = [:]
    private var videoPtsOffsetByTier: [String: Int64] = [:]
    private var audioPtsOffsetByTier: [String: Int64] = [:]
    private var hostPoisonedUntil: [String: Date] = [:]
    private var preferredHealthyTarget: (targetKey: String, host: String, directIp: String?)? = nil
    private var segmentDurationsByName: [String: Double] = [:]
    private var segmentStartPtsByName: [String: UInt64] = [:]
    private var segmentTimeRangeByName: [String: (startSec: Double, endSec: Double)] = [:]
    private var videoTimelineEntries: [VideoTimelineEntry] = []
    private var edgeIpsByHost: [String: [String]] = [:]
    private var activeVideoInspections: [UUID: VideoInspectionWaiter] = [:]
    private var cleanTargetByTimeWindow: [TimeWindowTarget] = []
    private var blackoutTimeWindows: [BlackoutTimeWindow] = []
    private var lastBannerDetectedAt: Date? = nil

    // Фоновая задача iOS: не даёт системе заморозить процесс пока прокси активен в фоне
    private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid

    var port: NWEndpoint.Port = 8181
    var fixedMasterUrl: String { "http://127.0.0.1:\(port.rawValue)/master.m3u8" }

    /// Публичное свойство для проверки живости прокси из PlayerView
    var isAlive: Bool { stateLock.withLock { isListenerAlive && listener != nil } }

    private let sessionDelegate = ProxyTrustAllSessionDelegate()
    private var playlistCache: [String: (
        content: String,
        timestamp: Date,
        failoverHosts: [String],
        maxFps: Double?,
        durations: [String: Double],
        startPts: [String: UInt64],
        timeRanges: [String: (startSec: Double, endSec: Double)],
        videoEntries: [VideoTimelineEntry]
    )] = [:]
    private let playlistCacheLock = NSLock()

    // We use a custom delegate to bypass SSL issues like in Android's buildTrustingClient
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpMaximumConnectionsPerHost = 32
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 90
        config.waitsForConnectivity = true
        config.httpShouldUsePipelining = true
        config.urlCache = URLCache(memoryCapacity: 64 * 1024 * 1024, diskCapacity: 0, diskPath: nil)
        config.requestCachePolicy = .useProtocolCachePolicy
        return URLSession(configuration: config, delegate: sessionDelegate, delegateQueue: nil)
    }()

    /// Isolated uncached session for failover segment retries (avoids reusing a poisoned socket/worker).
    private lazy var failoverSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpMaximumConnectionsPerHost = 6
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 45
        config.waitsForConnectivity = true
        config.httpShouldUsePipelining = false
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config, delegate: sessionDelegate, delegateQueue: nil)
    }()

    private init() {
        NotificationCenter.default.addObserver(self, selector: #selector(appWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    // MARK: - Background task management

    @objc private func appDidEnterBackground() {
        // Запускаем фоновую задачу только если идёт активное воспроизведение
        let hasActiveSession = stateLock.withLock { !self.mediaId.isEmpty && self.isListenerAlive }
        guard hasActiveSession else { return }
        beginBackgroundTaskIfNeeded()
    }

    @objc func appWillEnterForeground() {
        // Завершаем фоновую задачу при возврате в активный режим
        endBackgroundTaskIfNeeded()

        let params: (headers: [String: String], voices: [String], subtitles: [PlaybackSubtitle], mediaId: String, preferredVoiceName: String?, isCollaps: Bool)? = stateLock.withLock {
            if !self.mediaId.isEmpty {
                return (self.headers, self.voices, self.subtitles, self.mediaId, self.preferredVoiceName, self.isCollapsStream)
            }
            return nil
        }

        if let p = params {
            let needsRestart = stateLock.withLock { !self.isListenerAlive || self.listener == nil }
            if needsRestart {
                print("HlsProxyServer: restarting listener on foreground (was dead)")
                let deadListener: NWListener? = stateLock.withLock {
                    let existing = self.listener
                    self.listener = nil
                    self.isListenerAlive = false
                    return existing
                }
                deadListener?.cancel()
                start(headers: p.headers, voices: p.voices, subtitles: p.subtitles, mediaId: p.mediaId, preferredVoiceName: p.preferredVoiceName, isCollaps: p.isCollaps)
            }
        }
    }

    private func beginBackgroundTaskIfNeeded() {
        guard backgroundTaskId == .invalid else { return }
        backgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: "HlsProxyServer") { [weak self] in
            // Истёк лимит фонового времени — завершаем задачу
            self?.endBackgroundTaskIfNeeded()
        }
    }

    private func endBackgroundTaskIfNeeded() {
        let taskId = backgroundTaskId
        guard taskId != .invalid else { return }
        backgroundTaskId = .invalid
        UIApplication.shared.endBackgroundTask(taskId)
    }

    // MARK: - Lifecycle

    func start(headers: [String: String] = [:], voices: [String] = [], subtitles: [PlaybackSubtitle] = [], mediaId: String = "", preferredVoiceName: String? = nil, isCollaps: Bool = false) {
        playlistCacheLock.withLock {
            self.playlistCache.removeAll()
        }
        let isAlreadyRunning = stateLock.withLock {
            self.headers = headers
            self.voices = voices
            self.subtitles = subtitles
            self.mediaId = mediaId
            self.isCollapsStream = isCollaps
            self.failoverHosts = []
            self.streamDeclaredMaxFps = nil
            self.segmentBaselineSpsByTier.removeAll()
            self.segmentBaselineAudioByTier.removeAll()
            self.knownBannerAudioFingerprints.removeAll()
            self.recentAudioFingerprints.removeAll()
            self.videoPtsOffsetByTier.removeAll()
            self.audioPtsOffsetByTier.removeAll()
            self.hostPoisonedUntil.removeAll()
            self.preferredHealthyTarget = nil
            self.segmentDurationsByName.removeAll()
            self.segmentStartPtsByName.removeAll()
            self.segmentTimeRangeByName.removeAll()
            self.videoTimelineEntries.removeAll()
            self.edgeIpsByHost.removeAll()
            self.activeVideoInspections.values.forEach { $0.finish() }
            self.activeVideoInspections.removeAll()
            self.cleanTargetByTimeWindow.removeAll()
            self.blackoutTimeWindows.removeAll()
            self.lastBannerDetectedAt = nil
            if let preferredVoiceName, !preferredVoiceName.isEmpty {
                self.preferredVoiceName = preferredVoiceName
            }
            // Блокируем повторный запуск ТОЛЬКО если listener уже создан И живой.
            // Это исправляет баг: упавший listener (isListenerAlive=false, listener=nil) больше не блокирует запуск.
            return self.isListenerAlive && self.listener != nil
        }

        if isAlreadyRunning { return }

        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            let newListener = try NWListener(using: parameters, on: port)
            newListener.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            newListener.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                // Игнорируем события от уже заменённого листенера: иначе запоздавший
                // .cancelled старого объекта обнулит только что поднятый новый.
                let isCurrent = self.stateLock.withLock { self.listener === newListener }
                guard isCurrent else { return }
                switch state {
                case .ready:
                    print("HlsProxyServer listener ready")
                    AppDiagnostics.shared.log("HlsProxyServer: listener ready on port \(self.port.rawValue)")
                    self.stateLock.withLock { self.isListenerAlive = true }
                case .waiting(let error):
                    print("HlsProxyServer listener waiting: \(error)")
                    AppDiagnostics.shared.log("HlsProxyServer: listener waiting (\(error))")
                    self.stateLock.withLock { self.isListenerAlive = false }
                case .failed(let error):
                    print("HlsProxyServer listener failed: \(error)")
                    AppDiagnostics.shared.log("HlsProxyServer: listener failed (\(error))")
                    self.stateLock.withLock {
                        self.listener = nil
                        self.isListenerAlive = false
                    }
                    // Самовосстановление: перезапускаем если есть активная сессия
                    self.scheduleListenerRestart()
                case .cancelled:
                    print("HlsProxyServer listener cancelled")
                    self.stateLock.withLock {
                        self.listener = nil
                        self.isListenerAlive = false
                    }
                default: break
                }
            }
            // Сохраняем listener ДО start(), чтобы stateUpdateHandler не увидел nil при немедленном сбое
            stateLock.withLock {
                self.listener = newListener
                self.isListenerAlive = false // станет true только когда state == .ready
            }
            newListener.start(queue: queue)

            print("HlsProxyServer started on port \(port)")
        } catch {
            print("Failed to start HlsProxyServer: \(error)")
            AppDiagnostics.shared.log("HlsProxyServer: failed to create listener (\(error))")
        }
    }

    /// Планирует автоматический перезапуск слушателя через 300 мс при обнаружении сбоя
    private func scheduleListenerRestart() {
        let hasActiveSession = stateLock.withLock { !self.mediaId.isEmpty }
        guard hasActiveSession else { return }
        print("HlsProxyServer: scheduling self-healing restart in 300ms")
        queue.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            let (headers, voices, subtitles, mediaId, preferred, collaps) = self.stateLock.withLock {
                (self.headers, self.voices, self.subtitles, self.mediaId, self.preferredVoiceName, self.isCollapsStream)
            }
            guard !mediaId.isEmpty else { return }
            self.start(headers: headers, voices: voices, subtitles: subtitles, mediaId: mediaId, preferredVoiceName: preferred, isCollaps: collaps)
        }
    }

    func updateHeaders(_ headers: [String: String]) {
        stateLock.withLock {
            self.headers.merge(headers) { _, new in new }
        }
    }

    func updateMasterUrl(_ urlString: String) {
        let parsed = URL(string: urlString)
        let shouldWarmEdges: [String]? = stateLock.withLock {
            let sameStreamPath = (currentMasterUrl?.path == parsed?.path) && (parsed?.path.isEmpty == false)
            if currentMasterUrl?.absoluteString != parsed?.absoluteString {
                if !sameStreamPath {
                    self.failoverHosts = []
                    self.streamDeclaredMaxFps = nil
                    self.segmentBaselineSpsByTier.removeAll()
                    self.segmentBaselineAudioByTier.removeAll()
                    self.knownBannerAudioFingerprints.removeAll()
                    self.recentAudioFingerprints.removeAll()
                    self.videoPtsOffsetByTier.removeAll()
                    self.audioPtsOffsetByTier.removeAll()
                    self.hostPoisonedUntil.removeAll()
                    self.preferredHealthyTarget = nil
                    self.segmentDurationsByName.removeAll()
                    self.segmentStartPtsByName.removeAll()
                    self.segmentTimeRangeByName.removeAll()
                    self.videoTimelineEntries.removeAll()
                    self.cleanTargetByTimeWindow.removeAll()
                    self.blackoutTimeWindows.removeAll()
                    self.lastBannerDetectedAt = nil
                }
                self.activeVideoInspections.values.forEach { $0.finish() }
                self.activeVideoInspections.removeAll()
            }
            currentMasterUrl = parsed
            if let host = parsed?.host, (self.isCollapsStream || host.lowercased().contains("interkh")) {
                return [host, "x-bc.interkh.com", "hye1eaipby4w.interkh.com", "fzgbzcajzbbb.interkh.com", "cdnr.interkh.com"]
            }
            return nil
        }
        if let hostsToWarm = shouldWarmEdges {
            warmEdgeIps(forHosts: hostsToWarm)
        }
    }

    func updatePreferredVoice(_ voiceName: String?) {
        stateLock.withLock {
            self.preferredVoiceName = voiceName
        }
    }
    
    func stop() {
        endBackgroundTaskIfNeeded()
        let listenerToCancel: NWListener? = stateLock.withLock {
            let existing = listener
            listener = nil
            isListenerAlive = false
            currentMasterUrl = nil
            self.failoverHosts = []
            self.streamDeclaredMaxFps = nil
            self.segmentBaselineSpsByTier.removeAll()
            self.segmentBaselineAudioByTier.removeAll()
            self.knownBannerAudioFingerprints.removeAll()
            self.recentAudioFingerprints.removeAll()
            self.videoPtsOffsetByTier.removeAll()
            self.audioPtsOffsetByTier.removeAll()
            self.hostPoisonedUntil.removeAll()
            self.preferredHealthyTarget = nil
            self.segmentDurationsByName.removeAll()
            self.segmentStartPtsByName.removeAll()
            self.segmentTimeRangeByName.removeAll()
            self.videoTimelineEntries.removeAll()
            self.edgeIpsByHost.removeAll()
            self.activeVideoInspections.values.forEach { $0.finish() }
            self.activeVideoInspections.removeAll()
            self.cleanTargetByTimeWindow.removeAll()
            self.blackoutTimeWindows.removeAll()
            self.lastBannerDetectedAt = nil
            self.voices = []
            self.subtitles = []
            self.mediaId = ""
            self.headers = [:]
            return existing
        }
        listenerToCancel?.cancel()
        playlistCacheLock.withLock {
            self.playlistCache.removeAll()
        }
    }
    
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(on: connection, data: Data())
    }
    
    private func receiveRequest(on connection: NWConnection, data: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] newData, _, isComplete, error in
            guard let self = self else { return }
            if error != nil {
                connection.cancel()
                return
            }
            
            var currentData = data
            if let newData = newData {
                currentData.append(newData)
            }
            
            // Защита от неограниченно большого запроса (макс 256 KB)
            if currentData.count > 262_144 {
                connection.cancel()
                return
            }
            
            // Проверяем конец заголовков на уровне Data, чтобы избежать зависания
            // при TCP-разбиении многобайтовых UTF-8 символов (например, кириллица в User-Agent)
            let separator: [UInt8] = [0x0D, 0x0A, 0x0D, 0x0A] // \r\n\r\n
            let hasHeaderEnd = currentData.withUnsafeBytes { buf -> Bool in
                guard buf.count >= 4 else { return false }
                return buf.indices.dropLast(3).contains(where: {
                    buf[$0] == separator[0] && buf[$0+1] == separator[1] &&
                    buf[$0+2] == separator[2] && buf[$0+3] == separator[3]
                })
            }
            
            if hasHeaderEnd, let requestString = String(data: currentData, encoding: .utf8) {
                Task {
                    await self.processRequest(requestString, on: connection)
                }
            } else if hasHeaderEnd, let requestString = String(data: currentData, encoding: .isoLatin1) {
                // Fallback для нестандартных символов в заголовках
                Task {
                    await self.processRequest(requestString, on: connection)
                }
            } else if !isComplete {
                self.receiveRequest(on: connection, data: currentData)
            } else {
                connection.cancel()
            }
        }
    }
    
    private func processRequest(_ requestString: String, on connection: NWConnection) async {
        let lines = requestString.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else {
            self.send404(on: connection)
            return
        }
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2 else {
            self.send404(on: connection)
            return
        }
        
        let method = parts[0].uppercased()
        if method == "HEAD" {
            let header = "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nAccept-Ranges: bytes\r\nConnection: close\r\n\r\n"
            if let data = header.data(using: .utf8) {
                connection.send(content: data, completion: .contentProcessed({ _ in connection.cancel() }))
            } else {
                connection.cancel()
            }
            return
        }
        
        var incomingHeaders: [String: String] = [:]
        for line in lines.dropFirst() {
            guard !line.isEmpty else { break }
            let split = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard split.count == 2 else { continue }
            incomingHeaders[split[0].lowercased()] = split[1].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        let path = parts[1]
        guard let urlComponents = URLComponents(string: path) else {
            self.send404(on: connection)
            return
        }
        
        if urlComponents.path == "/master.m3u8" {
            let masterUrl = stateLock.withLock {
                self.currentMasterUrl
            }
            
            guard let currentMasterUrl = masterUrl else {
                self.send404(on: connection)
                return
            }
            await fetchAndServe(realUrl: currentMasterUrl, isPlaylist: true, incomingHeaders: incomingHeaders, connection: connection)
        } else if urlComponents.path.hasPrefix("/proxy"),
           let urlQuery = urlComponents.queryItems?.first(where: { $0.name == "url" })?.value {
            
            var base64String = urlQuery
            let remainder = base64String.count % 4
            if remainder > 0 {
                base64String = base64String.padding(toLength: base64String.count + 4 - remainder, withPad: "=", startingAt: 0)
            }
            base64String = base64String.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            
            if let decodedData = Data(base64Encoded: base64String),
               let decodedString = String(data: decodedData, encoding: .utf8),
               let realUrl = URL(string: decodedString),
               ["http", "https"].contains(realUrl.scheme?.lowercased() ?? ""),
               realUrl.host != nil {
                // isPlaylist: true if decoded URL contains .m3u8 OR if the proxy path suffix
                // implies a playlist (e.g. proxied URL had no extension → assigned stream.m3u8).
                // This fixes signed CDN URLs (VKVideo, etc.) that return m3u8 without extension.
                let pathImpliesPlaylist = urlComponents.path.lowercased().hasSuffix(".m3u8")
                let isPlaylist = decodedString.contains(".m3u8") || pathImpliesPlaylist
                let targetQuality = urlComponents.queryItems?.first(where: { $0.name == "q" || $0.name == "quality" })?.value
                await fetchAndServe(realUrl: realUrl, isPlaylist: isPlaylist, targetQuality: targetQuality, incomingHeaders: incomingHeaders, connection: connection)
            } else {
                self.send404(on: connection)
            }
        } else if urlComponents.path.hasPrefix("/subtitles"),
                  let urlQuery = urlComponents.queryItems?.first(where: { $0.name == "url" })?.value {
            let vttProxyUrl = "http://127.0.0.1:\(self.port.rawValue)/proxy/stream.vtt?url=\(urlQuery)"
            let playlist = """
            #EXTM3U
            #EXT-X-VERSION:3
            #EXT-X-TARGETDURATION:14400
            #EXT-X-MEDIA-SEQUENCE:0
            #EXT-X-PLAYLIST-TYPE:VOD
            #EXTINF:14400.0,
            \(vttProxyUrl)
            #EXT-X-ENDLIST
            """
            if let data = playlist.data(using: .utf8) {
                self.sendResponse(data: data, statusCode: 200, contentType: "application/vnd.apple.mpegurl", contentRange: nil, connection: connection)
            } else {
                self.send404(on: connection)
            }
        } else if urlComponents.path.hasPrefix("/local/") {
            let relativePath = String(urlComponents.path.dropFirst(7)) // drop "/local/"
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            // Only downloaded media may be served, never preferences or other app data.
            // Resolve symlinks as well as '..' before checking the directory boundary.
            guard let fileUrl = LocalMediaPathPolicy.resolve(relativePath, documents: docs) else {
                self.send404(on: connection)
                return
            }
            
            if FileManager.default.fileExists(atPath: fileUrl.path) {
                do {
                    let fileData = try Data(contentsOf: fileUrl)
                    let ext = fileUrl.pathExtension.lowercased()
                    let contentType: String
                    if ext == "m3u8" {
                        contentType = "application/vnd.apple.mpegurl"
                    } else if ext == "ts" {
                        contentType = "video/MP2T"
                    } else if ext == "mp4" || ext == "m4s" {
                        contentType = "video/mp4"
                    } else if ext == "bin" || ext == "key" {
                        contentType = "application/octet-stream"
                    } else {
                        contentType = "application/octet-stream"
                    }
                    if let rangeHeader = incomingHeaders["range"], rangeHeader.hasPrefix("bytes=") {
                        let rangeSpec = String(rangeHeader.dropFirst(6))
                        let rangeComponents = rangeSpec.components(separatedBy: "-")
                        let totalLength = fileData.count
                        if let startStr = rangeComponents.first, let start = Int(startStr) {
                            let end: Int
                            if rangeComponents.count > 1, let endParsed = Int(rangeComponents[1]), endParsed < totalLength {
                                end = endParsed
                            } else {
                                end = totalLength - 1
                            }
                            if start >= 0 && start <= end && start < totalLength {
                                let subData = fileData.subdata(in: start..<(end + 1))
                                let contentRange = "bytes \(start)-\(end)/\(totalLength)"
                                self.sendResponse(data: subData, statusCode: 206, contentType: contentType, contentRange: contentRange, connection: connection)
                                return
                            }
                        }
                    }

                    self.sendResponse(data: fileData, statusCode: 200, contentType: contentType, contentRange: nil, connection: connection)
                } catch {
                    self.send404(on: connection)
                }
            } else {
                self.send404(on: connection)
            }
        } else {
            self.send404(on: connection)
        }
    }
    
    private func fetchAndServe(realUrl: URL, isPlaylist: Bool, targetQuality: String? = nil, incomingHeaders: [String: String], connection: NWConnection) async {
        let (currentHeaders, currentVoices, currentSubtitles, currentMediaId, currentPreferredVoice, currentIsCollaps, currentFailoverHosts, currentDeclaredMaxFps) = stateLock.withLock {
            (self.headers, self.voices, self.subtitles, self.mediaId, self.preferredVoiceName, self.isCollapsStream, self.failoverHosts, self.streamDeclaredMaxFps)
        }

        var request = URLRequest(url: realUrl)

        for (k, v) in currentHeaders {
            request.setValue(v, forHTTPHeaderField: k)
        }
        if let range = incomingHeaders["range"] {
            request.setValue(range, forHTTPHeaderField: "Range")
        }
        if request.value(forHTTPHeaderField: "User-Agent") == nil {
            request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64)", forHTTPHeaderField: "User-Agent")
        }
        if request.value(forHTTPHeaderField: "Accept") == nil {
            request.setValue("*/*", forHTTPHeaderField: "Accept")
        }

        do {
            if isPlaylist {
                let cacheKey = "\(realUrl.absoluteString)_\(targetQuality ?? "")_\(currentPreferredVoice ?? "")_\(currentIsCollaps)"
                if let cached = playlistCacheLock.withLock({ () -> (content: String, failoverHosts: [String], maxFps: Double?, durations: [String: Double], startPts: [String: UInt64], timeRanges: [String: (startSec: Double, endSec: Double)], videoEntries: [VideoTimelineEntry])? in
                    if let entry = self.playlistCache[cacheKey], Date().timeIntervalSince(entry.timestamp) < 30.0 {
                        return (entry.content, entry.failoverHosts, entry.maxFps, entry.durations, entry.startPts, entry.timeRanges, entry.videoEntries)
                    }
                    return nil
                }) {
                    if !cached.failoverHosts.isEmpty || cached.maxFps != nil || !cached.durations.isEmpty || !cached.videoEntries.isEmpty {
                        stateLock.withLock {
                            if !cached.failoverHosts.isEmpty && self.failoverHosts.isEmpty {
                                self.failoverHosts = cached.failoverHosts
                            }
                            if self.streamDeclaredMaxFps == nil, let maxFps = cached.maxFps {
                                self.streamDeclaredMaxFps = maxFps
                            }
                            if !cached.durations.isEmpty {
                                self.segmentDurationsByName.merge(cached.durations) { _, new in new }
                                self.segmentStartPtsByName.merge(cached.startPts) { _, new in new }
                                self.segmentTimeRangeByName.merge(cached.timeRanges) { _, new in new }
                            }
                            if !cached.videoEntries.isEmpty {
                                self.videoTimelineEntries = cached.videoEntries
                            }
                        }
                    }
                    let cachedData = cached.content.data(using: .utf8) ?? Data()
                    self.sendResponse(data: cachedData, statusCode: 200, contentType: "application/vnd.apple.mpegurl", contentRange: nil, connection: connection)
                    return
                }

                let (data, response): (Data, URLResponse) = try await {
                    do {
                        return try await self.session.data(for: request)
                    } catch {
                        guard !Task.isCancelled else { throw error }
                        AppDiagnostics.shared.log("HlsProxyServer playlist fetch failed: \(error), retrying once in 400ms...")
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        return try await self.session.data(for: request)
                    }
                }()
                guard !Task.isCancelled else { return }
                guard let httpResponse = response as? HTTPURLResponse else {
                    AppDiagnostics.shared.log("HlsProxyServer fetchAndServe: invalid response for \(realUrl.path)")
                    self.send503(on: connection)
                    return
                }

                let statusCode = httpResponse.statusCode
                AppDiagnostics.shared.log("HlsProxyServer fetchAndServe: \(realUrl.path) returned \(statusCode)")

                guard statusCode >= 200 && statusCode < 300 else {
                    AppDiagnostics.shared.log("HlsProxyServer fetchAndServe: HTTP error \(statusCode) for \(realUrl.path)")
                    self.sendResponse(data: data, statusCode: statusCode, contentType: httpResponse.mimeType ?? "text/plain", contentRange: nil, connection: connection)
                    return
                }

                if let content = String(data: data, encoding: .utf8), content.contains("#EXT") {
                    let finalUrl = httpResponse.url ?? realUrl
                    let rewritten: String
                    var masterFailoverHosts: [String] = []
                    var masterMaxFps: Double? = nil
                    var mediaDurations: [String: Double] = [:]
                    var mediaStartPts: [String: UInt64] = [:]
                    var mediaTimeRanges: [String: (startSec: Double, endSec: Double)] = [:]
                    var mediaVideoEntries: [VideoTimelineEntry] = []
                    if content.contains("#EXT-X-STREAM-INF") {
                        var extractedFailoverHosts = PlaybackHlsRewriter.extractFailoverHosts(from: content, primaryHost: finalUrl.host)
                        if (currentIsCollaps || (finalUrl.host?.lowercased().contains("interkh") == true)),
                           !extractedFailoverHosts.contains(where: { $0.caseInsensitiveCompare("x-bc.interkh.com") == .orderedSame }),
                           finalUrl.host?.caseInsensitiveCompare("x-bc.interkh.com") != .orderedSame {
                            extractedFailoverHosts.append("x-bc.interkh.com")
                        }
                        let extractedMaxFps = PlaybackHlsRewriter.extractMaxFrameRate(from: content)
                        masterFailoverHosts = extractedFailoverHosts
                        masterMaxFps = extractedMaxFps
                        let hostsToWarm: [String]? = stateLock.withLock {
                            self.failoverHosts = extractedFailoverHosts
                            if let extractedMaxFps {
                                self.streamDeclaredMaxFps = extractedMaxFps
                            }
                            if currentIsCollaps || (finalUrl.host?.lowercased().contains("interkh") == true) {
                                return [finalUrl.host ?? ""] + extractedFailoverHosts + ["x-bc.interkh.com", "hye1eaipby4w.interkh.com", "fzgbzcajzbbb.interkh.com", "cdnr.interkh.com"]
                            }
                            return nil
                        }
                        if let hostsToWarm {
                            self.warmEdgeIps(forHosts: hostsToWarm)
                        }

                        let playlistRewritten = PlaybackHlsRewriter.rewrite(
                            master: content,
                            voices: currentVoices,
                            subtitles: currentSubtitles,
                            mediaId: currentMediaId,
                            targetQuality: targetQuality,
                            preferredVoiceName: currentPreferredVoice,
                            port: Int(self.port.rawValue),
                            isCollaps: currentIsCollaps
                        )

                        AppDiagnostics.shared.log("HlsProxyServer: master playlist rewritten (\(playlistRewritten.count) bytes)")
                        rewritten = self.rewriteM3u8(content: playlistRewritten, baseUrl: finalUrl, isCollaps: currentIsCollaps)
                    } else {
                        let lowerFile = realUrl.lastPathComponent.lowercased()
                        let entries = PlaybackHlsRewriter.extractTimelineEntries(fromMediaPlaylist: content)
                        var cleanBaseComps = URLComponents(url: finalUrl, resolvingAgainstBaseURL: true)
                        cleanBaseComps?.query = nil
                        let cleanBaseUrl = cleanBaseComps?.url ?? finalUrl
                        let isVideoMediaPlaylist = !lowerFile.contains("-a") && !lowerFile.contains("sub")

                        for entry in entries {
                            mediaDurations[entry.name] = entry.duration
                            mediaStartPts[entry.name] = entry.startPts90k
                            mediaTimeRanges[entry.name] = (entry.startSeconds, entry.endSeconds)
                            if isVideoMediaPlaylist,
                               let resolved = URL(string: entry.uri, relativeTo: cleanBaseUrl)?.absoluteURL {
                                mediaVideoEntries.append(VideoTimelineEntry(
                                    name: entry.name,
                                    startSeconds: entry.startSeconds,
                                    endSeconds: entry.endSeconds,
                                    url: resolved
                                ))
                            }
                        }

                        if !mediaDurations.isEmpty || !mediaVideoEntries.isEmpty {
                            stateLock.withLock {
                                self.segmentDurationsByName.merge(mediaDurations) { _, new in new }
                                self.segmentStartPtsByName.merge(mediaStartPts) { _, new in new }
                                self.segmentTimeRangeByName.merge(mediaTimeRanges) { _, new in new }
                                if !mediaVideoEntries.isEmpty {
                                    self.videoTimelineEntries = mediaVideoEntries
                                }
                            }
                        }
                        AppDiagnostics.shared.log("HlsProxyServer: media playlist served for \(realUrl.lastPathComponent) (\(content.count) bytes)")
                        rewritten = self.rewriteM3u8(content: content, baseUrl: finalUrl, isCollaps: currentIsCollaps)
                    }

                    playlistCacheLock.withLock {
                        self.playlistCache[cacheKey] = (
                            content: rewritten,
                            timestamp: Date(),
                            failoverHosts: masterFailoverHosts,
                            maxFps: masterMaxFps,
                            durations: mediaDurations,
                            startPts: mediaStartPts,
                            timeRanges: mediaTimeRanges,
                            videoEntries: mediaVideoEntries
                        )
                    }

                    let rewrittenData = rewritten.data(using: .utf8) ?? Data()
                    guard !Task.isCancelled else { return }
                    self.sendResponse(data: rewrittenData, statusCode: 200, contentType: "application/vnd.apple.mpegurl", contentRange: nil, connection: connection)
                } else {
                    guard !Task.isCancelled else { return }
                    self.sendResponse(data: data, statusCode: statusCode, contentType: "application/vnd.apple.mpegurl", contentRange: nil, connection: connection)
                }
            } else {
                let isSub = realUrl.pathExtension.lowercased() == "vtt" || realUrl.pathExtension.lowercased() == "srt"
                if isSub {
                    let (data, response): (Data, URLResponse) = await {
                        do {
                            return try await self.session.data(for: request)
                        } catch {
                            guard !Task.isCancelled else { return (Data(), HTTPURLResponse()) }
                            try? await Task.sleep(nanoseconds: 400_000_000)
                            if let result = try? await self.session.data(for: request) {
                                return result
                            }
                            return (Data(), HTTPURLResponse())
                        }
                    }()
                    guard !Task.isCancelled else { return }
                    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode > 0 else {
                        self.send503(on: connection)
                        return
                    }

                    let statusCode = httpResponse.statusCode
                    let normalized = self.normalizeSubtitleData(data)
                    self.sendResponse(data: normalized, statusCode: statusCode, contentType: "text/vtt", contentRange: nil, connection: connection)
                } else {
                    // Direct chunk-by-chunk streaming for media segments (.ts, .m4s, .mp4, etc.)
                    // with lightweight video+audio prefix inspection, 9-IP edge failover, and zero-ad substitution.
                    await self.streamMediaSegment(
                        request: request,
                        realUrl: realUrl,
                        incomingRange: incomingHeaders["range"],
                        isCollaps: currentIsCollaps,
                        failoverHosts: currentFailoverHosts,
                        declaredMaxFps: currentDeclaredMaxFps,
                        connection: connection
                    )
                }
            }
        } catch {
            if Task.isCancelled { return }
            AppDiagnostics.shared.log("HlsProxyServer fetch failed: \(error)")
            self.send503(on: connection)
        }
    }

    private func warmEdgeIps(forHosts hosts: [String]) {
        let uniqueHosts = Array(Set(hosts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty }))
        guard !uniqueHosts.isEmpty else { return }
        queue.async { [weak self] in
            for host in uniqueHosts {
                let ips = Self.resolveIPv4Addresses(for: host)
                if !ips.isEmpty {
                    self?.stateLock.withLock {
                        self?.edgeIpsByHost[host] = ips
                    }
                }
            }
        }
    }

    private static func resolveIPv4Addresses(for host: String) -> [String] {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM
        var res: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &res) == 0, let first = res else {
            return []
        }
        defer { freeaddrinfo(first) }
        var ips: [String] = []
        var ptr: UnsafeMutablePointer<addrinfo>? = first
        while let cur = ptr {
            if let sa = cur.pointee.ai_addr {
                var hostBuf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(sa, cur.pointee.ai_addrlen, &hostBuf, socklen_t(hostBuf.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let ip = String(cString: hostBuf)
                    if !ip.isEmpty && !ips.contains(ip) {
                        ips.append(ip)
                    }
                }
            }
            ptr = cur.pointee.ai_next
        }
        return ips
    }

    private static func findOverlappingVideoUrl(in entries: [VideoTimelineEntry], startSec: Double, endSec: Double) -> URL? {
        guard !entries.isEmpty else { return nil }
        let mid = (startSec + endSec) * 0.5
        var lo = 0
        var hi = entries.count - 1
        while lo <= hi {
            let m = (lo + hi) / 2
            let e = entries[m]
            if mid < e.startSeconds {
                hi = m - 1
            } else if mid > e.endSeconds {
                lo = m + 1
            } else {
                return e.url
            }
        }
        return entries.min(by: { abs((($0.startSeconds + $0.endSeconds) * 0.5) - mid) < abs((($1.startSeconds + $1.endSeconds) * 0.5) - mid) })?.url
    }

    private func streamMediaSegment(
        request: URLRequest,
        realUrl: URL,
        incomingRange: String?,
        isCollaps: Bool,
        failoverHosts: [String],
        declaredMaxFps: Double?,
        connection: NWConnection
    ) async {
        let isVideoInspect = HlsSegmentShield.isInspectableVideoSegment(
            url: realUrl,
            isCollaps: isCollaps,
            rangeHeader: incomingRange
        )
        let isAudioInspect = !isVideoInspect && HlsSegmentShield.isInspectableAudioSegment(
            url: realUrl,
            isCollaps: isCollaps,
            rangeHeader: incomingRange
        )
        let inspectMode: ProxySegmentInspectionMode = isVideoInspect ? .video : (isAudioInspect ? .audio : .none)
        let tierKey = (inspectMode != .none) ? HlsSegmentShield.tierKey(for: realUrl) : ""
        let segName = realUrl.lastPathComponent
        let originalHostLower = realUrl.host?.lowercased() ?? ""

        let timeRange = stateLock.withLock { self.segmentTimeRangeByName[segName] }
        let segStartSec = timeRange?.startSec ?? 0
        let segEndSec = timeRange?.endSec ?? (segStartSec + 8.0)

        var videoTracker: VideoInspectionWaiter? = nil
        if inspectMode == .video {
            let tracker = VideoInspectionWaiter(startSeconds: segStartSec, endSeconds: segEndSec)
            videoTracker = tracker
            stateLock.withLock {
                self.activeVideoInspections[tracker.id] = tracker
            }
        } else if inspectMode == .audio {
            // If an overlapping video inspection is currently running, wait briefly so audio inherits its ban/failover verdict immediately.
            let overlappingSem: DispatchSemaphore? = stateLock.withLock {
                for tracker in self.activeVideoInspections.values where tracker.overlaps(segStartSec, segEndSec) {
                    let sem = DispatchSemaphore(value: 0)
                    if tracker.addWaiter(sem) {
                        return sem
                    }
                }
                return nil
            }
            if let sem = overlappingSem {
                await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                    DispatchQueue.global(qos: .userInitiated).async {
                        _ = sem.wait(timeout: .now() + .milliseconds(650))
                        cont.resume()
                    }
                }
            }
        }

        guard !Task.isCancelled else {
            if let tracker = videoTracker {
                stateLock.withLock { _ = self.activeVideoInspections.removeValue(forKey: tracker.id) }
                tracker.finish()
            }
            return
        }

        let (poisonedSnapshot, promotedTarget, edgeIpsSnapshot, segDuration, segStartPts, videoEntriesSnapshot, preferredWindowTarget) = stateLock.withLock {
            let now = Date()
            let windowPreferred = self.cleanTargetByTimeWindow.reversed().first {
                now.timeIntervalSince($0.recordedAt) < 45.0 && max($0.startSeconds, segStartSec) < min($0.endSeconds, segEndSec)
            }
            return (
                self.hostPoisonedUntil,
                self.preferredHealthyTarget,
                self.edgeIpsByHost,
                self.segmentDurationsByName[segName] ?? 8.0,
                self.segmentStartPtsByName[segName] ?? 0,
                self.videoTimelineEntries,
                windowPreferred
            )
        }

        let plan: (initial: ProxySegmentAttempt, fallbacks: [ProxySegmentAttempt])
        if inspectMode != .none {
            let effectivePromoted: (targetKey: String, host: String, directIp: String?)? = {
                if let win = preferredWindowTarget,
                   (poisonedSnapshot[win.targetKey] ?? .distantPast) <= Date() {
                    return (win.targetKey, win.host, win.directIp)
                }
                return promotedTarget
            }()
            plan = Self.buildAttemptPlan(
                from: request,
                realUrl: realUrl,
                failoverHosts: failoverHosts,
                isCollaps: isCollaps,
                edgeIpsByHost: edgeIpsSnapshot,
                hostPoisonedUntil: poisonedSnapshot,
                preferredHealthyTarget: effectivePromoted
            )
        } else {
            plan = (ProxySegmentAttempt(request: request, targetKey: originalHostLower, useFailoverSession: false, directIp: nil, delayMs: 0), [])
        }

        let overlappingVideoUrl = (inspectMode == .audio)
            ? Self.findOverlappingVideoUrl(in: videoEntriesSnapshot, startSec: segStartSec, endSec: segEndSec)
            : nil

        let trackerToFinish = videoTracker
        let finishVideoTracker: @Sendable () -> Void = { [weak self] in
            guard let tracker = trackerToFinish else { return }
            self?.stateLock.withLock {
                _ = self?.activeVideoInspections.removeValue(forKey: tracker.id)
            }
            tracker.finish()
        }

        let streamContext = ProxyStreamContext(
            connection: connection,
            realUrl: realUrl,
            primarySession: self.session,
            failoverSession: self.failoverSession,
            sessionDelegate: self.sessionDelegate,
            inspectionMode: inspectMode,
            initialAttempt: plan.initial,
            fallbackAttempts: plan.fallbacks,
            declaredMaxFps: declaredMaxFps,
            fallbackDurationSeconds: segDuration,
            fallbackStartPts90k: segStartPts,
            overlappingVideoUrl: overlappingVideoUrl,
            baselineSpsProvider: (inspectMode == .video) ? { [weak self] in
                self?.stateLock.withLock { self?.segmentBaselineSpsByTier[tierKey] }
            } : nil,
            onRecordBaseline: (inspectMode == .video) ? { [weak self] sps in
                self?.stateLock.withLock {
                    if self?.segmentBaselineSpsByTier[tierKey] == nil {
                        self?.segmentBaselineSpsByTier[tierKey] = sps
                    }
                }
            } : nil,
            baselineAudioProvider: (inspectMode == .audio) ? { [weak self] in
                self?.stateLock.withLock { self?.segmentBaselineAudioByTier[tierKey] }
            } : nil,
            onRecordAudioBaseline: (inspectMode == .audio) ? { [weak self] info in
                self?.stateLock.withLock {
                    if self?.segmentBaselineAudioByTier[tierKey] == nil {
                        self?.segmentBaselineAudioByTier[tierKey] = info
                    }
                    if let fpPts = info.firstPts90k, segStartPts > 0, self?.audioPtsOffsetByTier[tierKey] == nil {
                        self?.audioPtsOffsetByTier[tierKey] = Int64(fpPts) - Int64(segStartPts)
                    }
                }
            } : nil,
            ptsOffsetProvider: (inspectMode != .none) ? { [weak self] in
                self?.stateLock.withLock {
                    inspectMode == .video
                        ? (self?.videoPtsOffsetByTier[tierKey] ?? 0)
                        : (self?.audioPtsOffsetByTier[tierKey] ?? 0)
                } ?? 0
            } : nil,
            onRecordVideoPtsOffset: (inspectMode == .video) ? { [weak self] actualPts in
                guard segStartPts > 0 else { return }
                self?.stateLock.withLock {
                    if self?.videoPtsOffsetByTier[tierKey] == nil {
                        self?.videoPtsOffsetByTier[tierKey] = Int64(actualPts) - Int64(segStartPts)
                    }
                }
            } : nil,
            knownAudioAdFingerprintsProvider: (inspectMode == .audio) ? { [weak self] in
                self?.stateLock.withLock { self?.knownBannerAudioFingerprints ?? [] } ?? []
            } : nil,
            onLearnAudioAdFingerprint: (inspectMode == .audio) ? { [weak self] fp in
                self?.stateLock.withLock {
                    self?.knownBannerAudioFingerprints.insert(fp)
                }
            } : nil,
            onCheckAudioDuplicate: (inspectMode == .audio) ? { [weak self] fp in
                self?.stateLock.withLock { () -> Bool in
                    guard let self else { return false }
                    let now = Date()
                    if let prev = self.recentAudioFingerprints[fp] {
                        if prev.segmentName != segName && now.timeIntervalSince(prev.seenAt) < 600 {
                            self.knownBannerAudioFingerprints.insert(fp)
                            return true
                        }
                    } else {
                        self.recentAudioFingerprints[fp] = (segName, now)
                        if self.recentAudioFingerprints.count > 200 {
                            let cutoff = now.addingTimeInterval(-600)
                            self.recentAudioFingerprints = self.recentAudioFingerprints.filter { $0.value.seenAt > cutoff }
                        }
                    }
                    return false
                } ?? false
            } : nil,
            shadowProbeRequirementProvider: (inspectMode == .audio) ? { [weak self] attemptTargetKey in
                self?.stateLock.withLock { () -> (shouldProbe: Bool, inBlackout: Bool) in
                    guard let self else { return (false, false) }
                    let now = Date()
                    let inBlackout = self.blackoutTimeWindows.contains {
                        now.timeIntervalSince($0.recordedAt) < 45.0 && max($0.startSeconds, segStartSec) < min($0.endSeconds, segEndSec)
                    }
                    let verifiedCleanTarget = self.cleanTargetByTimeWindow.reversed().first {
                        now.timeIntervalSince($0.recordedAt) < 45.0 && max($0.startSeconds, segStartSec) < min($0.endSeconds, segEndSec)
                    }?.targetKey

                    if let verifiedCleanTarget, verifiedCleanTarget == attemptTargetKey && !inBlackout {
                        return (false, false)
                    }
                    let recentBanner = self.lastBannerDetectedAt.map { now.timeIntervalSince($0) < 90.0 } ?? false
                    let anyHostPoisoned = self.hostPoisonedUntil.values.contains { $0 > now }
                    let unverifiedAlternate = (verifiedCleanTarget != nil && verifiedCleanTarget != attemptTargetKey)
                    return (inBlackout || unverifiedAlternate || recentBanner || anyHostPoisoned, inBlackout)
                } ?? (false, false)
            } : nil,
            onAllHostsBlackout: (inspectMode == .video) ? { [weak self] in
                self?.stateLock.withLock {
                    let now = Date()
                    self?.blackoutTimeWindows.append(BlackoutTimeWindow(startSeconds: segStartSec, endSeconds: segEndSec, recordedAt: now))
                    if let count = self?.blackoutTimeWindows.count, count > 120 {
                        self?.blackoutTimeWindows.removeFirst(count - 120)
                    }
                }
                finishVideoTracker()
            } : nil,
            onHostPoisoned: (inspectMode != .none) ? { [weak self] poisonedKey in
                let lower = poisonedKey.lowercased()
                guard !lower.isEmpty else { return }
                self?.stateLock.withLock {
                    let now = Date()
                    self?.hostPoisonedUntil[lower] = now.addingTimeInterval(25.0)
                    self?.lastBannerDetectedAt = now
                    if self?.preferredHealthyTarget?.targetKey == lower {
                        self?.preferredHealthyTarget = nil
                    }
                }
            } : nil,
            onHostClean: (inspectMode != .none) ? { [weak self] cleanKey, cleanHost, cleanIp in
                let lowerKey = cleanKey.lowercased()
                let lowerHost = cleanHost.lowercased()
                guard !lowerKey.isEmpty else { return }
                self?.stateLock.withLock {
                    let now = Date()
                    self?.hostPoisonedUntil.removeValue(forKey: lowerKey)
                    if lowerKey != originalHostLower {
                        self?.preferredHealthyTarget = (lowerKey, lowerHost, cleanIp)
                    }
                    if inspectMode == .video {
                        self?.cleanTargetByTimeWindow.append(TimeWindowTarget(
                            startSeconds: segStartSec,
                            endSeconds: segEndSec,
                            targetKey: lowerKey,
                            host: lowerHost,
                            directIp: cleanIp,
                            recordedAt: now
                        ))
                        if let c = self?.cleanTargetByTimeWindow.count, c > 250 {
                            self?.cleanTargetByTimeWindow.removeFirst(c - 250)
                        }
                    }
                }
                finishVideoTracker()
            } : nil,
            onInspectionFinished: finishVideoTracker
        )

        streamContext.start()

        connection.stateUpdateHandler = { state in
            switch state {
            case .cancelled, .failed:
                streamContext.cancel()
            default:
                break
            }
        }
    }

    private static func buildAttemptPlan(
        from originalRequest: URLRequest,
        realUrl: URL,
        failoverHosts: [String],
        isCollaps: Bool,
        edgeIpsByHost: [String: [String]],
        hostPoisonedUntil: [String: Date],
        preferredHealthyTarget: (targetKey: String, host: String, directIp: String?)?
    ) -> (initial: ProxySegmentAttempt, fallbacks: [ProxySegmentAttempt]) {
        let now = Date()
        let originalHost = realUrl.host?.lowercased() ?? ""

        var domainPool: [String] = []
        func appendUniqueDomain(_ h: String?) {
            guard let h = h?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !h.isEmpty else { return }
            if !domainPool.contains(h) { domainPool.append(h) }
        }

        appendUniqueDomain(originalHost)
        for h in failoverHosts { appendUniqueDomain(h) }
        if isCollaps || originalHost.contains("interkh") {
            appendUniqueDomain("x-bc.interkh.com")
            appendUniqueDomain("hye1eaipby4w.interkh.com")
        }

        struct CandidateTarget {
            let targetKey: String
            let host: String
            let directIp: String?
            let useFailoverSession: Bool
        }

        var allCandidates: [CandidateTarget] = []
        var representedSingleIps = Set<String>()

        for h in domainPool {
            allCandidates.append(CandidateTarget(
                targetKey: h,
                host: h,
                directIp: nil,
                useFailoverSession: h != originalHost
            ))
            if let ips = edgeIpsByHost[h], ips.count == 1, let singleIp = ips.first {
                representedSingleIps.insert(singleIp)
            }
        }

        // Expand direct edge-node IP targets for hosts backed by multi-IP round-robin DNS (e.g., hye1eaipby4w, x-bc)
        if isCollaps || originalHost.contains("interkh") {
            let sniHost = domainPool.contains("hye1eaipby4w.interkh.com") ? "hye1eaipby4w.interkh.com" : (domainPool.first ?? originalHost)
            var extraEdgeIps: [(ip: String, host: String)] = []
            var seenIps = representedSingleIps
            for hostKey in ["hye1eaipby4w.interkh.com", "x-bc.interkh.com", "cdnr.interkh.com", originalHost] {
                for ip in edgeIpsByHost[hostKey] ?? [] {
                    if !seenIps.contains(ip) {
                        seenIps.insert(ip)
                        extraEdgeIps.append((ip, hostKey == originalHost ? sniHost : hostKey))
                    }
                }
            }
            for item in extraEdgeIps {
                let key = "\(item.host)@\(item.ip)"
                allCandidates.append(CandidateTarget(
                    targetKey: key,
                    host: item.host,
                    directIp: item.ip,
                    useFailoverSession: true
                ))
            }
        }

        var healthy: [CandidateTarget] = []
        var cooled: [CandidateTarget] = []
        for c in allCandidates {
            let until = hostPoisonedUntil[c.targetKey] ?? .distantPast
            if until > now {
                cooled.append(c)
            } else {
                healthy.append(c)
            }
        }

        if let preferred = preferredHealthyTarget {
            let prefKey = preferred.targetKey.lowercased()
            if let idx = healthy.firstIndex(where: { $0.targetKey == prefKey }) {
                if idx > 0 {
                    let chosen = healthy.remove(at: idx)
                    healthy.insert(chosen, at: 0)
                }
            } else if let directIp = preferred.directIp,
                      (hostPoisonedUntil[prefKey] ?? .distantPast) <= now {
                healthy.insert(CandidateTarget(
                    targetKey: prefKey,
                    host: preferred.host,
                    directIp: directIp,
                    useFailoverSession: true
                ), at: 0)
            }
        }

        let ordered = healthy + cooled
        func makeAttempt(_ target: CandidateTarget, delayMs: Int = 0, stripRefererOrigin: Bool = false) -> ProxySegmentAttempt? {
            if !target.useFailoverSession && target.directIp == nil && !stripRefererOrigin {
                return ProxySegmentAttempt(
                    request: originalRequest,
                    targetKey: target.targetKey,
                    useFailoverSession: false,
                    directIp: nil,
                    delayMs: delayMs
                )
            }
            let hostArg: String? = (target.host == originalHost && target.directIp == nil && stripRefererOrigin) ? nil : target.host
            guard let req = HlsSegmentShield.buildFailoverRequest(
                from: originalRequest,
                failoverHost: hostArg,
                stripRefererOrigin: stripRefererOrigin
            ) else {
                return nil
            }
            return ProxySegmentAttempt(
                request: req,
                targetKey: target.targetKey,
                useFailoverSession: true,
                directIp: target.directIp,
                delayMs: delayMs
            )
        }

        let initialAttempt = ordered.first.flatMap { makeAttempt($0) }
            ?? ProxySegmentAttempt(request: originalRequest, targetKey: originalHost, useFailoverSession: false, directIp: nil, delayMs: 0)

        var fallbacks: [ProxySegmentAttempt] = []
        for target in ordered.dropFirst() {
            if let attempt = makeAttempt(target) {
                fallbacks.append(attempt)
            }
        }
        if let retryTarget = healthy.first ?? ordered.dropFirst().first,
           let pacedAttempt = makeAttempt(retryTarget, delayMs: 250) {
            fallbacks.append(pacedAttempt)
        }
        if let strippedReq = HlsSegmentShield.buildFailoverRequest(from: originalRequest, failoverHost: nil, stripRefererOrigin: true) {
            fallbacks.append(ProxySegmentAttempt(
                request: strippedReq,
                targetKey: originalHost,
                useFailoverSession: true,
                directIp: nil,
                delayMs: 150
            ))
        }

        return (initialAttempt, Array(fallbacks.prefix(8)))
    }
    
    private func rewriteM3u8(content: String, baseUrl: URL, isCollaps: Bool = false) -> String {
        PlaybackHlsRewriter.rewriteMediaPlaylist(
            content: content,
            baseUrl: baseUrl,
            isCollaps: isCollaps
        ) { [weak self] uriString in
            self?.proxyUrl(uriString, baseUrl: baseUrl) ?? uriString
        }
    }
    
    private func proxyUrl(_ urlString: String, baseUrl: URL) -> String {
        let absoluteUrlString: String
        if urlString.hasPrefix("http://") || urlString.hasPrefix("https://") {
            absoluteUrlString = urlString
        } else {
            var components = URLComponents(url: baseUrl, resolvingAgainstBaseURL: true)
            components?.query = nil
            let cleanBaseUrl = components?.url ?? baseUrl
            
            if let resolvedUrl = URL(string: urlString, relativeTo: cleanBaseUrl)?.absoluteURL {
                absoluteUrlString = resolvedUrl.absoluteString
            } else {
                absoluteUrlString = urlString
            }
        }
        
        guard let encodedData = absoluteUrlString.data(using: .utf8) else {
            return urlString
        }
        
        // URL Safe Base64 without padding
        let encoded = encodedData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        
        let urlObj = URL(string: absoluteUrlString)
        let ext = urlObj?.pathExtension ?? ""
        let pathSuffix = ext.isEmpty ? "stream.m3u8" : "stream.\(ext)"
        
        return "http://127.0.0.1:\(port.rawValue)/proxy/\(pathSuffix)?url=\(encoded)"
    }
    
    private func sendResponse(data: Data, statusCode: Int, contentType: String, contentRange: String?, connection: NWConnection) {
        let reason = statusCode == 206 ? "Partial Content" : (statusCode == 200 ? "OK" : "Error")
        var header = "HTTP/1.1 \(statusCode) \(reason)\r\nContent-Type: \(contentType)\r\nContent-Length: \(data.count)\r\nConnection: close\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Headers: *\r\n"
        if let cr = contentRange {
            header += "Content-Range: \(cr)\r\n"
        }
        header += "Accept-Ranges: bytes\r\n\r\n"
        guard let headerData = header.data(using: .utf8) else { connection.cancel(); return }
        
        connection.send(content: headerData, completion: .contentProcessed({ _ in
            connection.send(content: data, completion: .contentProcessed({ _ in
                connection.cancel()
            }))
        }))
    }
    
    private func send404(on connection: NWConnection) {
        let response = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        guard let data = response.data(using: .utf8) else { connection.cancel(); return }
        connection.send(content: data, completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }

    /// Возвращает 503 Service Unavailable с Retry-After: 1.
    /// AVPlayer по стандарту HLS при получении 5xx повторяет запрос через указанное время,
    /// что позволяет сегменту загрузиться после восстановления прокси — без прерывания потока.
    static func send503(on connection: NWConnection) {
        let response = "HTTP/1.1 503 Service Unavailable\r\nContent-Length: 0\r\nRetry-After: 1\r\nConnection: close\r\n\r\n"
        guard let data = response.data(using: .utf8) else { connection.cancel(); return }
        connection.send(content: data, completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }

    func send503(on connection: NWConnection) {
        Self.send503(on: connection)
    }

    private func normalizeSubtitleData(_ rawData: Data) -> Data {
        guard var text = String(data: rawData, encoding: .utf8) ?? String(data: rawData, encoding: .windowsCP1251) else {
            return rawData
        }

        if text.hasPrefix("\u{FEFF}") {
            text.removeFirst()
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("WEBVTT") {
            if !text.contains("X-TIMESTAMP-MAP") {
                if let range = text.range(of: "WEBVTT") {
                    let insertIdx = range.upperBound
                    text.insert(contentsOf: "\nX-TIMESTAMP-MAP=LOCAL:00:00:00.000,MPEGTS:0", at: insertIdx)
                }
            }
        } else {
            let srtRegex = try? NSRegularExpression(pattern: #"(\d{2}:\d{2}:\d{2}),(\d{3})"#, options: [])
            if let regex = srtRegex {
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "$1.$2")
            }
            text = "WEBVTT\nX-TIMESTAMP-MAP=LOCAL:00:00:00.000,MPEGTS:0\n\n" + text
        }

        return text.data(using: .utf8) ?? rawData
    }

    static func resolveContentType(for url: URL, httpResponse: HTTPURLResponse?) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "mp4", "m4s", "m4v":
            return "video/mp4"
        case "m4a":
            return "audio/mp4"
        case "ts":
            return "video/MP2T"
        case "m3u8":
            return "application/vnd.apple.mpegurl"
        case "aac":
            return "audio/aac"
        case "vtt":
            return "text/vtt"
        case "srt":
            return "application/x-subrip"
        default:
            if let mime = httpResponse?.mimeType, !mime.isEmpty, mime != "application/octet-stream", mime != "binary/octet-stream" {
                return mime
            }
            return "video/mp4"
        }
    }

    func resolveContentType(for url: URL, httpResponse: HTTPURLResponse?) -> String {
        Self.resolveContentType(for: url, httpResponse: httpResponse)
    }
}

// MARK: - Streaming Segment Context & Direct Edge TLS Transport

enum ProxySegmentInspectionMode: Equatable, Sendable {
    case none
    case video
    case audio
}

struct ProxySegmentAttempt: @unchecked Sendable {
    let request: URLRequest
    let targetKey: String
    let useFailoverSession: Bool
    let directIp: String?
    let delayMs: Int
}

final class DirectEdgeRequestTask: @unchecked Sendable {
    private static let idLock = NSLock()
    private static var nextId = 1_000_000_000

    static func allocateTaskId() -> Int {
        idLock.withLock {
            nextId += 1
            return nextId
        }
    }

    let taskId: Int
    private let request: URLRequest
    private let directIp: String
    private let sniHost: String
    private let callbackQueue: DispatchQueue
    private let onResponse: @Sendable (Int, URLResponse, @escaping @Sendable (URLSession.ResponseDisposition) -> Void) -> Void
    private let onData: @Sendable (Int, Data) -> Void
    private let onComplete: @Sendable (Int, Error?) -> Void

    private let lock = NSLock()
    private var connection: NWConnection?
    private var cancelled = false
    private var completed = false
    private var headersParsed = false
    private var rawBuffer = Data()
    private var expectedContentLength: Int64?
    private var isChunked = false
    private var chunkStateBuffer = Data()
    private var chunkRemainingBytes: Int? = nil
    private var readingChunkCrlf = false
    private var receivedBodyBytes: Int64 = 0
    private var timeoutWorkItem: DispatchWorkItem?

    init(
        taskId: Int = DirectEdgeRequestTask.allocateTaskId(),
        request: URLRequest,
        directIp: String,
        sniHost: String,
        queue: DispatchQueue,
        onResponse: @escaping @Sendable (Int, URLResponse, @escaping @Sendable (URLSession.ResponseDisposition) -> Void) -> Void,
        onData: @escaping @Sendable (Int, Data) -> Void,
        onComplete: @escaping @Sendable (Int, Error?) -> Void
    ) {
        self.taskId = taskId
        self.request = request
        self.directIp = directIp
        self.sniHost = sniHost
        self.callbackQueue = queue
        self.onResponse = onResponse
        self.onData = onData
        self.onComplete = onComplete
    }

    func resume() {
        guard let url = request.url else {
            finish(error: NSError(domain: NSURLErrorDomain, code: NSURLErrorBadURL))
            return
        }

        let tlsOptions = NWProtocolTLS.Options()
        sec_protocol_options_set_tls_server_name(tlsOptions.securityProtocolOptions, sniHost)
        sec_protocol_options_set_verify_block(tlsOptions.securityProtocolOptions, { _, _, completion in
            completion(true)
        }, callbackQueue)

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.connectionTimeout = 5
        let params = NWParameters(tls: tlsOptions, tcp: tcpOptions)
        let conn = NWConnection(host: NWEndpoint.Host(directIp), port: .https, using: params)

        let timer = DispatchWorkItem { [weak self] in
            self?.finish(error: NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut))
        }

        let shouldStart = lock.withLock { () -> Bool in
            guard !cancelled && !completed else { return false }
            connection = conn
            timeoutWorkItem = timer
            return true
        }
        guard shouldStart else { return }

        callbackQueue.asyncAfter(deadline: .now() + 7.0, execute: timer)

        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.sendHttpRequest(on: conn, url: url)
                self.receiveNext(on: conn)
            case .failed(let err):
                self.finish(error: err)
            case .cancelled:
                self.finish(error: NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled))
            default:
                break
            }
        }
        conn.start(queue: callbackQueue)
    }

    func cancel() {
        let conn: NWConnection? = lock.withLock {
            guard !cancelled && !completed else { return nil }
            cancelled = true
            completed = true
            timeoutWorkItem?.cancel()
            timeoutWorkItem = nil
            let c = connection
            connection = nil
            return c
        }
        conn?.cancel()
    }

    private func sendHttpRequest(on conn: NWConnection, url: URL) {
        let pathOnly = url.path.isEmpty ? "/" : url.path
        let pathAndQuery = pathOnly + (url.query.map { "?\($0)" } ?? "")
        var reqLines = ["GET \(pathAndQuery) HTTP/1.1", "Host: \(sniHost)"]
        for (k, v) in (request.allHTTPHeaderFields ?? [:]) {
            let lower = k.lowercased()
            if lower == "host" || lower == "accept-encoding" || lower == "connection" {
                continue
            }
            reqLines.append("\(k): \(v)")
        }
        reqLines.append("Accept-Encoding: identity")
        reqLines.append("Connection: close")
        let raw = reqLines.joined(separator: "\r\n") + "\r\n\r\n"
        guard let reqData = raw.data(using: .utf8) else {
            finish(error: NSError(domain: NSURLErrorDomain, code: NSURLErrorBadURL))
            return
        }
        conn.send(content: reqData, completion: .contentProcessed { [weak self] error in
            if let error {
                self?.finish(error: error)
            }
        })
    }

    private func receiveNext(on conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.handleIncomingChunk(data, on: conn)
            }
            if let error {
                self.finish(error: error)
                return
            }
            if isComplete {
                self.finish(error: nil)
                return
            }
            let keepGoing = self.lock.withLock { !self.cancelled && !self.completed }
            if keepGoing {
                self.receiveNext(on: conn)
            }
        }
    }

    private func handleIncomingChunk(_ chunk: Data, on conn: NWConnection) {
        let alreadyParsedHeaders = lock.withLock { () -> Bool in
            if cancelled || completed { return true }
            if !headersParsed {
                rawBuffer.append(chunk)
                return false
            }
            return true
        }
        if alreadyParsedHeaders {
            let active = lock.withLock { !cancelled && !completed && headersParsed }
            if active {
                processBodyBytes(chunk)
            }
            return
        }

        let headerEndData = Data([0x0D, 0x0A, 0x0D, 0x0A])
        let headerRange: Range<Data.Index>? = lock.withLock {
            rawBuffer.range(of: headerEndData)
        }
        guard let headerRange else {
            let oversized = lock.withLock { rawBuffer.count > 65_536 }
            if oversized {
                finish(error: NSError(domain: NSURLErrorDomain, code: NSURLErrorBadServerResponse))
            }
            return
        }

        let (headerData, bodyRemainder): (Data, Data) = lock.withLock {
            let h = rawBuffer.subdata(in: rawBuffer.startIndex..<headerRange.lowerBound)
            let rem = rawBuffer.subdata(in: headerRange.upperBound..<rawBuffer.endIndex)
            rawBuffer.removeAll(keepingCapacity: false)
            headersParsed = true
            return (h, rem)
        }

        guard let headerString = String(data: headerData, encoding: .utf8) ?? String(data: headerData, encoding: .isoLatin1) else {
            finish(error: NSError(domain: NSURLErrorDomain, code: NSURLErrorBadServerResponse))
            return
        }

        let lines = headerString.components(separatedBy: "\r\n")
        guard let statusLine = lines.first else {
            finish(error: NSError(domain: NSURLErrorDomain, code: NSURLErrorBadServerResponse))
            return
        }
        let statusParts = statusLine.split(separator: " ", maxSplits: 2)
        guard statusParts.count >= 2, let statusCode = Int(statusParts[1]) else {
            finish(error: NSError(domain: NSURLErrorDomain, code: NSURLErrorBadServerResponse))
            return
        }

        var headerFields: [String: String] = [:]
        var cl: Int64? = nil
        var chunked = false
        for line in lines.dropFirst() {
            let kv = line.split(separator: ":", maxSplits: 1)
            guard kv.count == 2 else { continue }
            let key = String(kv[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            let val = String(kv[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            headerFields[key] = val
            if key.lowercased() == "content-length", let v = Int64(val) {
                cl = v
            } else if key.lowercased() == "transfer-encoding", val.lowercased().contains("chunked") {
                chunked = true
            }
        }

        lock.withLock {
            expectedContentLength = cl
            isChunked = chunked
        }

        let respUrl = request.url ?? URL(string: "https://\(sniHost)/")!
        guard let httpResp = HTTPURLResponse(url: respUrl, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: headerFields) else {
            finish(error: NSError(domain: NSURLErrorDomain, code: NSURLErrorBadServerResponse))
            return
        }

        onResponse(taskId, httpResp) { [weak self] disposition in
            guard let self else { return }
            if disposition == .cancel {
                self.cancel()
                return
            }
            if !bodyRemainder.isEmpty {
                self.processBodyBytes(bodyRemainder)
            }
        }
    }

    private func processBodyBytes(_ data: Data) {
        let isChunkedMode = lock.withLock { isChunked }
        if !isChunkedMode {
            onData(taskId, data)
            let reachedEnd: Bool = lock.withLock {
                receivedBodyBytes += Int64(data.count)
                if let cl = expectedContentLength {
                    return receivedBodyBytes >= cl
                }
                return false
            }
            if reachedEnd {
                finish(error: nil)
            }
            return
        }

        var decoded = Data()
        var reachedTerminator = false
        lock.withLock {
            chunkStateBuffer.append(data)
            let crlf = Data([0x0D, 0x0A])
            while !chunkStateBuffer.isEmpty && !cancelled && !completed {
                if readingChunkCrlf {
                    if chunkStateBuffer.count >= 2 {
                        chunkStateBuffer.removeFirst(2)
                        readingChunkCrlf = false
                    } else {
                        break
                    }
                }
                if let rem = chunkRemainingBytes {
                    if rem == 0 {
                        chunkRemainingBytes = nil
                        readingChunkCrlf = true
                        continue
                    }
                    let take = min(rem, chunkStateBuffer.count)
                    decoded.append(chunkStateBuffer.prefix(take))
                    chunkStateBuffer.removeFirst(take)
                    chunkRemainingBytes = rem - take
                    if rem - take == 0 {
                        chunkRemainingBytes = nil
                        readingChunkCrlf = true
                    }
                } else {
                    guard let lineEnd = chunkStateBuffer.range(of: crlf) else { break }
                    let sizeLine = String(data: chunkStateBuffer.subdata(in: chunkStateBuffer.startIndex..<lineEnd.lowerBound), encoding: .ascii) ?? ""
                    let hexPart = sizeLine.split(separator: ";").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
                    chunkStateBuffer.removeSubrange(chunkStateBuffer.startIndex..<lineEnd.upperBound)
                    guard let chunkSize = Int(hexPart, radix: 16) else {
                        reachedTerminator = true
                        break
                    }
                    if chunkSize == 0 {
                        reachedTerminator = true
                        break
                    }
                    chunkRemainingBytes = chunkSize
                }
            }
        }

        if !decoded.isEmpty {
            onData(taskId, decoded)
        }
        if reachedTerminator {
            finish(error: nil)
        }
    }

    private func finish(error: Error?) {
        let shouldNotify: (notify: Bool, conn: NWConnection?) = lock.withLock {
            if completed { return (false, nil) }
            completed = true
            timeoutWorkItem?.cancel()
            timeoutWorkItem = nil
            let c = connection
            connection = nil
            return (!cancelled, c)
        }
        shouldNotify.conn?.cancel()
        if shouldNotify.notify {
            onComplete(taskId, error)
        }
    }

    private final class PrefixProbeBox: @unchecked Sendable {
        let lock = NSLock()
        var buffer = Data()
        var capturedResp: HTTPURLResponse?
        var finished = false
        var taskRef: DirectEdgeRequestTask?
    }

    /// Lightweight one-shot Range prefix fetcher over a pinned edge IP (used by Shadow Video Probe).
    static func fetchPrefix(
        request: URLRequest,
        directIp: String,
        maxBytes: Int,
        completion: @escaping @Sendable (Data?, HTTPURLResponse?) -> Void
    ) {
        let host = request.url?.host ?? ""
        let q = DispatchQueue.global(qos: .userInitiated)
        let box = PrefixProbeBox()

        let deliverOnce: @Sendable (Data?, HTTPURLResponse?) -> Void = { data, resp in
            let outcome: (shouldDeliver: Bool, taskToCancel: DirectEdgeRequestTask?) = box.lock.withLock {
                if box.finished { return (false, nil) }
                box.finished = true
                return (true, box.taskRef)
            }
            guard outcome.shouldDeliver else { return }
            outcome.taskToCancel?.cancel()
            completion(data, resp)
        }

        let task = DirectEdgeRequestTask(
            request: request,
            directIp: directIp,
            sniHost: host,
            queue: q,
            onResponse: { _, resp, disposition in
                if let httpResp = resp as? HTTPURLResponse {
                    box.lock.withLock { box.capturedResp = httpResp }
                }
                disposition(.allow)
            },
            onData: { _, chunk in
                let ready: (Data?, HTTPURLResponse?)? = box.lock.withLock {
                    if box.finished { return nil }
                    box.buffer.append(chunk)
                    if box.buffer.count >= maxBytes {
                        return (box.buffer, box.capturedResp)
                    }
                    return nil
                }
                if let ready {
                    deliverOnce(ready.0, ready.1)
                }
            },
            onComplete: { _, _ in
                let snapshot = box.lock.withLock { (box.buffer, box.capturedResp) }
                deliverOnce(snapshot.0.isEmpty ? nil : snapshot.0, snapshot.1)
            }
        )
        box.lock.withLock { box.taskRef = task }
        task.resume()
    }
}

final class ProxyStreamContext: @unchecked Sendable {
    private enum ActiveHandle {
        case urlSession(URLSessionDataTask, targetKey: String, host: String, directIp: String?)
        case directEdge(DirectEdgeRequestTask, targetKey: String, host: String, directIp: String)

        var taskId: Int {
            switch self {
            case .urlSession(let t, _, _, _): return t.taskIdentifier
            case .directEdge(let t, _, _, _): return t.taskId
            }
        }
        var targetKey: String {
            switch self {
            case .urlSession(_, let k, _, _): return k
            case .directEdge(_, let k, _, _): return k
            }
        }
        var host: String {
            switch self {
            case .urlSession(_, _, let h, _): return h
            case .directEdge(_, _, let h, _): return h
            }
        }
        var directIp: String? {
            switch self {
            case .urlSession(_, _, _, let ip): return ip
            case .directEdge(_, _, _, let ip): return ip
            }
        }
        func resume() {
            switch self {
            case .urlSession(let t, _, _, _): t.resume()
            case .directEdge(let t, _, _, _): t.resume()
            }
        }
        func cancel() {
            switch self {
            case .urlSession(let t, _, _, _): t.cancel()
            case .directEdge(let t, _, _, _): t.cancel()
            }
        }
    }

    let connection: NWConnection
    let realUrl: URL
    private let primarySession: URLSession
    private let failoverSession: URLSession
    private weak var sessionDelegate: ProxyTrustAllSessionDelegate?
    private let inspectionMode: ProxySegmentInspectionMode
    private let initialAttempt: ProxySegmentAttempt
    private let fallbackAttempts: [ProxySegmentAttempt]
    private let declaredMaxFps: Double?
    private let fallbackDurationSeconds: Double
    private let fallbackStartPts90k: UInt64
    private let overlappingVideoUrl: URL?

    private let baselineSpsProvider: (() -> Data?)?
    private let onRecordBaseline: ((Data) -> Void)?
    private let baselineAudioProvider: (() -> HlsAudioStreamInfo?)?
    private let onRecordAudioBaseline: ((HlsAudioStreamInfo) -> Void)?
    private let ptsOffsetProvider: (() -> Int64)?
    private let onRecordVideoPtsOffset: ((UInt64) -> Void)?
    private let knownAudioAdFingerprintsProvider: (() -> Set<UInt64>)?
    private let onLearnAudioAdFingerprint: ((UInt64) -> Void)?
    private let onCheckAudioDuplicate: ((UInt64) -> Bool)?
    private let shadowProbeRequirementProvider: ((String) -> (shouldProbe: Bool, inBlackout: Bool))?
    private let onAllHostsBlackout: (() -> Void)?
    private let onHostPoisoned: ((String) -> Void)?
    private let onHostClean: ((String, String, String?) -> Void)?
    private let onInspectionFinished: (() -> Void)?

    private let edgeQueue = DispatchQueue(label: "com.sloosh.ios.hlsproxy.edge", attributes: .concurrent)
    private let lock = NSLock()
    private var isCancelled = false
    private var hasSentHeaders = false
    private var pendingDecisionCommitted = false
    private var activeTaskId: Int = -1
    private var activeHandle: ActiveHandle?
    private var fallbackIndex: Int = 0
    private var pendingHeaderData: Data?
    private var pendingExpectedContentLength: Int64?
    private var pendingETag: String?
    private var pendingBuffer = Data()
    private var lastSuspectPts90k: UInt64?
    private var lastObservedAudioFormat: (sampleRateIndex: Int, channelConfig: Int)? = nil
    private var finishedTracker = false

    init(
        connection: NWConnection,
        realUrl: URL,
        primarySession: URLSession,
        failoverSession: URLSession,
        sessionDelegate: ProxyTrustAllSessionDelegate,
        inspectionMode: ProxySegmentInspectionMode,
        initialAttempt: ProxySegmentAttempt,
        fallbackAttempts: [ProxySegmentAttempt],
        declaredMaxFps: Double?,
        fallbackDurationSeconds: Double,
        fallbackStartPts90k: UInt64,
        overlappingVideoUrl: URL?,
        baselineSpsProvider: (() -> Data?)?,
        onRecordBaseline: ((Data) -> Void)?,
        baselineAudioProvider: (() -> HlsAudioStreamInfo?)?,
        onRecordAudioBaseline: ((HlsAudioStreamInfo) -> Void)?,
        ptsOffsetProvider: (() -> Int64)?,
        onRecordVideoPtsOffset: ((UInt64) -> Void)?,
        knownAudioAdFingerprintsProvider: (() -> Set<UInt64>)?,
        onLearnAudioAdFingerprint: ((UInt64) -> Void)?,
        onCheckAudioDuplicate: ((UInt64) -> Bool)?,
        shadowProbeRequirementProvider: ((String) -> (shouldProbe: Bool, inBlackout: Bool))?,
        onAllHostsBlackout: (() -> Void)?,
        onHostPoisoned: ((String) -> Void)?,
        onHostClean: ((String, String, String?) -> Void)?,
        onInspectionFinished: (() -> Void)?
    ) {
        self.connection = connection
        self.realUrl = realUrl
        self.primarySession = primarySession
        self.failoverSession = failoverSession
        self.sessionDelegate = sessionDelegate
        self.inspectionMode = inspectionMode
        self.initialAttempt = initialAttempt
        self.fallbackAttempts = fallbackAttempts
        self.declaredMaxFps = declaredMaxFps
        self.fallbackDurationSeconds = fallbackDurationSeconds
        self.fallbackStartPts90k = fallbackStartPts90k
        self.overlappingVideoUrl = overlappingVideoUrl
        self.baselineSpsProvider = baselineSpsProvider
        self.onRecordBaseline = onRecordBaseline
        self.baselineAudioProvider = baselineAudioProvider
        self.onRecordAudioBaseline = onRecordAudioBaseline
        self.ptsOffsetProvider = ptsOffsetProvider
        self.onRecordVideoPtsOffset = onRecordVideoPtsOffset
        self.knownAudioAdFingerprintsProvider = knownAudioAdFingerprintsProvider
        self.onLearnAudioAdFingerprint = onLearnAudioAdFingerprint
        self.onCheckAudioDuplicate = onCheckAudioDuplicate
        self.shadowProbeRequirementProvider = shadowProbeRequirementProvider
        self.onAllHostsBlackout = onAllHostsBlackout
        self.onHostPoisoned = onHostPoisoned
        self.onHostClean = onHostClean
        self.onInspectionFinished = onInspectionFinished
    }

    private func buildHandle(for attempt: ProxySegmentAttempt) -> ActiveHandle {
        let host = attempt.request.url?.host ?? realUrl.host ?? ""
        if let directIp = attempt.directIp, !directIp.isEmpty {
            let edgeTask = DirectEdgeRequestTask(
                request: attempt.request,
                directIp: directIp,
                sniHost: host,
                queue: edgeQueue,
                onResponse: { [weak self] tid, resp, handler in
                    self?.didReceiveResponse(taskId: tid, response: resp, completionHandler: handler)
                },
                onData: { [weak self] tid, chunk in
                    self?.didReceiveData(taskId: tid, data: chunk)
                },
                onComplete: { [weak self] tid, err in
                    self?.didComplete(taskId: tid, error: err)
                }
            )
            return .directEdge(edgeTask, targetKey: attempt.targetKey, host: host, directIp: directIp)
        } else {
            let sess = attempt.useFailoverSession ? failoverSession : primarySession
            let task = sess.dataTask(with: attempt.request)
            return .urlSession(task, targetKey: attempt.targetKey, host: host, directIp: nil)
        }
    }

    private func finishVideoInspectionOnce() {
        let shouldFire = lock.withLock { () -> Bool in
            if finishedTracker { return false }
            finishedTracker = true
            return true
        }
        if shouldFire {
            onInspectionFinished?()
        }
    }

    func start() {
        let handle = buildHandle(for: initialAttempt)
        let canStart = lock.withLock { () -> Bool in
            guard !isCancelled else { return false }
            activeHandle = handle
            activeTaskId = handle.taskId
            return true
        }
        guard canStart else {
            finishVideoInspectionOnce()
            return
        }
        if case .urlSession(let task, _, _, _) = handle {
            sessionDelegate?.register(taskId: task.taskIdentifier, context: self)
        }
        handle.resume()
    }

    func cancel() {
        let (handleToCancel, oldId): (ActiveHandle?, Int) = lock.withLock {
            isCancelled = true
            let current = activeHandle
            let prevId = activeTaskId
            activeHandle = nil
            activeTaskId = -1
            pendingHeaderData = nil
            pendingBuffer.removeAll()
            return (current, prevId)
        }
        if oldId >= 0 {
            sessionDelegate?.unregister(taskId: oldId)
        }
        handleToCancel?.cancel()
        finishVideoInspectionOnce()
    }

    private enum FallbackSwitchResult {
        case launched(newHandle: ActiveHandle, oldHandle: ActiveHandle?, delayMs: Int)
        case unavailable
    }

    private func resumeIfStillActive(handle: ActiveHandle) {
        let shouldResume = lock.withLock {
            !isCancelled && activeTaskId == handle.taskId
        }
        if shouldResume {
            handle.resume()
        } else if case .urlSession(let task, _, _, _) = handle {
            sessionDelegate?.unregister(taskId: task.taskIdentifier)
        }
    }

    private func trySwitchToFallback(fromTaskId taskId: Int, cancelOldTask: Bool) -> Bool {
        let result: FallbackSwitchResult = lock.withLock {
            guard !isCancelled, taskId == activeTaskId, !pendingDecisionCommitted,
                  fallbackIndex < fallbackAttempts.count else {
                return .unavailable
            }
            let nextAttempt = fallbackAttempts[fallbackIndex]
            fallbackIndex += 1
            let newHandle = buildHandle(for: nextAttempt)
            let oldHandle = activeHandle
            activeHandle = newHandle
            activeTaskId = newHandle.taskId
            pendingHeaderData = nil
            pendingExpectedContentLength = nil
            pendingETag = nil
            pendingBuffer.removeAll(keepingCapacity: true)
            return .launched(newHandle: newHandle, oldHandle: oldHandle, delayMs: nextAttempt.delayMs)
        }

        switch result {
        case .launched(let newHandle, let oldHandle, let delayMs):
            if case .urlSession(let task, _, _, _) = newHandle {
                sessionDelegate?.register(taskId: task.taskIdentifier, context: self)
            }
            if cancelOldTask {
                oldHandle?.cancel()
            }
            if delayMs > 0 {
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + .milliseconds(delayMs)) { [weak self] in
                    self?.resumeIfStillActive(handle: newHandle)
                }
            } else {
                newHandle.resume()
            }
            return true
        case .unavailable:
            return false
        }
    }

    private func computeCalibratedPts90k(rawSuspectBuffer: Data? = nil) -> UInt64 {
        let offset = ptsOffsetProvider?() ?? 0
        if fallbackStartPts90k > 0 {
            let adjusted = Int64(fallbackStartPts90k) + offset
            return UInt64(max(0, adjusted))
        }
        if offset != 0 {
            return UInt64(max(0, offset))
        }
        let savedPts = lock.withLock { lastSuspectPts90k }
        if let savedPts { return savedPts }
        if let rawSuspectBuffer, let extracted = HlsSegmentShield.extractFirstVideoPts90k(from: rawSuspectBuffer) {
            return extracted
        }
        return 0
    }

    func didReceiveResponse(
        taskId: Int,
        response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        let stateCheck: (active: Bool, hasFallback: Bool, activeTargetKey: String) = lock.withLock {
            (!isCancelled && taskId == activeTaskId, fallbackIndex < fallbackAttempts.count, activeHandle?.targetKey ?? realUrl.host ?? "")
        }
        guard stateCheck.active else {
            completionHandler(.cancel)
            return
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            if stateCheck.hasFallback && trySwitchToFallback(fromTaskId: taskId, cancelOldTask: false) {
                completionHandler(.cancel)
                return
            }
            if sendExhaustedReplacementIfNeeded(taskId: taskId, buffer: Data()) {
                completionHandler(.cancel)
                return
            }
            lock.withLock { isCancelled = true }
            finishVideoInspectionOnce()
            HlsProxyServer.send503(on: connection)
            completionHandler(.cancel)
            return
        }

        let statusCode = httpResponse.statusCode
        guard statusCode >= 200 && statusCode < 400 else {
            if stateCheck.hasFallback && trySwitchToFallback(fromTaskId: taskId, cancelOldTask: false) {
                AppDiagnostics.shared.log("HlsProxyServer: upstream HTTP \(statusCode) on \(stateCheck.activeTargetKey) (\(realUrl.lastPathComponent)), switching to fallback")
                completionHandler(.cancel)
                return
            }
            if sendExhaustedReplacementIfNeeded(taskId: taskId, buffer: Data()) {
                completionHandler(.cancel)
                return
            }
            lock.withLock { isCancelled = true }
            finishVideoInspectionOnce()
            HlsProxyServer.send503(on: connection)
            completionHandler(.cancel)
            return
        }

        let rawContentLength = httpResponse.value(forHTTPHeaderField: "Content-Length").flatMap { Int64($0) }
        let eTag = httpResponse.value(forHTTPHeaderField: "ETag")

        if inspectionMode == .video,
           stateCheck.hasFallback,
           let rawContentLength,
           rawContentLength == HlsSegmentShield.knownBannerByteLength,
           eTag?.lowercased().hasSuffix(HlsSegmentShield.knownBannerETagSuffix) == true {
            onHostPoisoned?(stateCheck.activeTargetKey)
            if trySwitchToFallback(fromTaskId: taskId, cancelOldTask: false) {
                AppDiagnostics.shared.log("HlsProxyServer: blocked swapped segment (Content-Length 268088 + banner ETag) on \(stateCheck.activeTargetKey) (\(realUrl.lastPathComponent)), switching to fallback")
                completionHandler(.cancel)
                return
            }
        }

        let reason = statusCode == 206 ? "Partial Content" : (statusCode == 200 ? "OK" : "Error")
        let contentType = HlsProxyServer.resolveContentType(for: realUrl, httpResponse: httpResponse)

        var header = "HTTP/1.1 \(statusCode) \(reason)\r\nContent-Type: \(contentType)\r\n"
        if let cl = httpResponse.value(forHTTPHeaderField: "Content-Length") {
            header += "Content-Length: \(cl)\r\n"
        }
        if let cr = httpResponse.value(forHTTPHeaderField: "Content-Range") {
            header += "Content-Range: \(cr)\r\n"
        }
        header += "Accept-Ranges: bytes\r\nConnection: close\r\n\r\n"

        guard let headerData = header.data(using: .utf8) else {
            completionHandler(.cancel)
            return
        }

        enum ResponsePlan {
            case ignore
            case bufferPrefix
            case sendHeaders
        }

        let plan: ResponsePlan = lock.withLock {
            guard !isCancelled, taskId == activeTaskId else { return .ignore }
            if inspectionMode != .none {
                pendingHeaderData = headerData
                pendingExpectedContentLength = rawContentLength
                pendingETag = eTag
                pendingBuffer.removeAll(keepingCapacity: true)
                pendingDecisionCommitted = false
                return .bufferPrefix
            } else {
                pendingDecisionCommitted = true
                hasSentHeaders = true
                return .sendHeaders
            }
        }

        switch plan {
        case .ignore:
            completionHandler(.cancel)
            return
        case .bufferPrefix:
            completionHandler(.allow)
        case .sendHeaders:
            connection.send(content: headerData, contentContext: .defaultMessage, isComplete: false, completion: .contentProcessed { [weak self] error in
                if error != nil {
                    self?.cancel()
                }
            })
            completionHandler(.allow)
        }
    }

    func didReceiveData(taskId: Int, data: Data) {
        enum DataAction {
            case ignore
            case passthrough
            case inspect(buffer: Data, expectedCL: Int64?, eTag: String?, targetKey: String, host: String, directIp: String?)
        }

        let action: DataAction = lock.withLock {
            guard !isCancelled, taskId == activeTaskId else { return .ignore }
            if pendingDecisionCommitted {
                return .passthrough
            }
            pendingBuffer.append(data)
            let tKey = activeHandle?.targetKey ?? realUrl.host ?? ""
            let hName = activeHandle?.host ?? realUrl.host ?? ""
            let dIp = activeHandle?.directIp
            return .inspect(
                buffer: pendingBuffer,
                expectedCL: pendingExpectedContentLength,
                eTag: pendingETag,
                targetKey: tKey,
                host: hName,
                directIp: dIp
            )
        }

        switch action {
        case .ignore:
            return

        case .passthrough:
            connection.send(content: data, contentContext: .defaultMessage, isComplete: false, completion: .contentProcessed { [weak self] error in
                if error != nil {
                    self?.cancel()
                }
            })

        case .inspect(let buffer, let expectedCL, let eTag, let targetKey, let host, let directIp):
            if inspectionMode == .video {
                let baseline = baselineSpsProvider?()
                guard let verdict = HlsSegmentShield.evaluateSegment(
                    prefixData: buffer,
                    isComplete: false,
                    expectedContentLength: expectedCL,
                    eTag: eTag,
                    baselineSps: baseline,
                    declaredMaxFps: declaredMaxFps
                ) else {
                    return
                }

                switch verdict {
                case .clean(let baselineToRecord):
                    if let baselineToRecord {
                        onRecordBaseline?(baselineToRecord)
                    }
                    if let pts = HlsSegmentShield.extractFirstVideoPts90k(from: buffer) {
                        onRecordVideoPtsOffset?(pts)
                    }
                    onHostClean?(targetKey, host, directIp)
                    flushPendingPayload(taskId: taskId)

                case .suspectAdSwap(let reason):
                    onHostPoisoned?(targetKey)
                    if let ptsInPacket = HlsSegmentShield.extractFirstVideoPts90k(from: buffer) {
                        lock.withLock { self.lastSuspectPts90k = ptsInPacket }
                    }
                    if trySwitchToFallback(fromTaskId: taskId, cancelOldTask: true) {
                        AppDiagnostics.shared.log("HlsProxyServer: blocked swapped segment (\(reason)) on \(targetKey) (\(realUrl.lastPathComponent)), switching to fallback")
                        return
                    }
                    if sendExhaustedReplacementIfNeeded(taskId: taskId, buffer: buffer) {
                        return
                    }
                    lock.withLock { isCancelled = true }
                    finishVideoInspectionOnce()
                    HlsProxyServer.send503(on: connection)
                }
            } else if inspectionMode == .audio {
                let calibratedPts = (fallbackStartPts90k > 0 || (ptsOffsetProvider?() ?? 0) != 0)
                    ? computeCalibratedPts90k()
                    : nil
                let knownFps = knownAudioAdFingerprintsProvider?() ?? []
                guard let audioVerdict = HlsSegmentShield.evaluateAudioSegment(
                    data: buffer,
                    isComplete: false,
                    expectedDurationSeconds: fallbackDurationSeconds,
                    expectedStartPts90k: calibratedPts,
                    baseline: baselineAudioProvider?(),
                    knownBannerFingerprints: knownFps
                ) else {
                    return
                }

                switch audioVerdict {
                case .clean(let info):
                    if let info {
                        lock.withLock {
                            self.lastObservedAudioFormat = (info.sampleRateIndex, info.channelConfig)
                        }
                    }
                    // For safety, hold audio in buffer until didComplete (~132 KB) so duration & shadow video check finish before commit,
                    // unless an unexpectedly large (>1.5 MB) payload arrives.
                    if buffer.count > 1_500_000 {
                        if let info { onRecordAudioBaseline?(info) }
                        onHostClean?(targetKey, host, directIp)
                        flushPendingPayload(taskId: taskId)
                    }

                case .suspectAdSwap(let reason, let info):
                    if let info, !info.isDigitalSilence {
                        onLearnAudioAdFingerprint?(info.payloadFingerprint)
                    }
                    onHostPoisoned?(targetKey)
                    if trySwitchToFallback(fromTaskId: taskId, cancelOldTask: true) {
                        AppDiagnostics.shared.log("HlsProxyServer: blocked swapped audio (\(reason)) on \(targetKey) (\(realUrl.lastPathComponent)), switching to fallback")
                        return
                    }
                    if sendExhaustedReplacementIfNeeded(taskId: taskId, buffer: buffer) {
                        return
                    }
                    lock.withLock { isCancelled = true }
                    HlsProxyServer.send503(on: connection)
                }
            }
        }
    }

    private func sendExhaustedReplacementIfNeeded(taskId: Int, buffer: Data) -> Bool {
        if inspectionMode == .video {
            return sendBlackReplacementIfNeeded(taskId: taskId, buffer: buffer)
        } else if inspectionMode == .audio {
            return sendSilentAudioReplacementIfNeeded(taskId: taskId)
        }
        return false
    }

    private func sendBlackReplacementIfNeeded(taskId: Int, buffer: Data) -> Bool {
        onAllHostsBlackout?()
        let baseline = baselineSpsProvider?()
        let dims = HlsSegmentShield.resolveStreamDimensions(fromBaselineSps: baseline)
        let ptsStart90k = computeCalibratedPts90k(rawSuspectBuffer: buffer)

        guard let replacementTs = HlsSegmentShield.buildBlackReplacementTs(
            width: dims.width,
            height: dims.height,
            ptsStart90k: ptsStart90k,
            durationSeconds: fallbackDurationSeconds
        ) else {
            return false
        }

        let responseHeader = "HTTP/1.1 200 OK\r\nContent-Type: video/MP2T\r\nContent-Length: \(replacementTs.count)\r\nAccept-Ranges: bytes\r\nConnection: close\r\n\r\n"
        guard let headerData = responseHeader.data(using: .utf8) else { return false }

        let cancelledHandle: (oldHandle: ActiveHandle?, payload: Data)? = lock.withLock {
            guard !isCancelled, taskId == activeTaskId, !pendingDecisionCommitted else { return nil }
            pendingDecisionCommitted = true
            hasSentHeaders = true
            let current = activeHandle
            activeHandle = nil
            pendingHeaderData = nil
            pendingBuffer.removeAll(keepingCapacity: false)
            var full = headerData
            full.append(replacementTs)
            return (current, full)
        }
        guard let item = cancelledHandle else { return false }

        item.oldHandle?.cancel()
        AppDiagnostics.shared.log("HlsProxyServer: all nodes returned banner on \(realUrl.lastPathComponent), substituted clean black \(dims.width)x\(dims.height) TS (\(replacementTs.count)B, pts=\(ptsStart90k / 90_000)s)")
        connection.send(content: item.payload, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { [weak self] _ in
            self?.connection.cancel()
        })
        return true
    }

    private func sendSilentAudioReplacementIfNeeded(taskId: Int) -> Bool {
        let baseInfo = baselineAudioProvider?()
        let obs = lock.withLock { lastObservedAudioFormat }
        let srIdx = baseInfo?.sampleRateIndex ?? obs?.sampleRateIndex ?? 4
        let chCfg = baseInfo?.channelConfig ?? obs?.channelConfig ?? 2
        let ptsStart90k = computeCalibratedPts90k()

        let silentTs = HlsSegmentShield.buildSilentAudioReplacementTs(
            sampleRateIndex: srIdx,
            channelConfig: chCfg,
            ptsStart90k: ptsStart90k,
            durationSeconds: fallbackDurationSeconds
        )

        let responseHeader = "HTTP/1.1 200 OK\r\nContent-Type: video/MP2T\r\nContent-Length: \(silentTs.count)\r\nAccept-Ranges: bytes\r\nConnection: close\r\n\r\n"
        guard let headerData = responseHeader.data(using: .utf8) else { return false }

        let cancelledHandle: (oldHandle: ActiveHandle?, payload: Data)? = lock.withLock {
            guard !isCancelled, taskId == activeTaskId, !pendingDecisionCommitted else { return nil }
            pendingDecisionCommitted = true
            hasSentHeaders = true
            let current = activeHandle
            activeHandle = nil
            pendingHeaderData = nil
            pendingBuffer.removeAll(keepingCapacity: false)
            var full = headerData
            full.append(silentTs)
            return (current, full)
        }
        guard let item = cancelledHandle else { return false }

        item.oldHandle?.cancel()
        AppDiagnostics.shared.log("HlsProxyServer: blocked promo audio on \(realUrl.lastPathComponent), substituted silent AAC TS (\(silentTs.count)B, pts=\(ptsStart90k / 90_000)s)")
        connection.send(content: item.payload, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { [weak self] _ in
            self?.connection.cancel()
        })
        return true
    }

    private func commitBufferedResponse(taskId: Int, headerData: Data, buffer: Data) {
        let finalPayload: Data? = lock.withLock {
            guard !isCancelled, taskId == activeTaskId, !pendingDecisionCommitted else { return nil }
            pendingDecisionCommitted = true
            hasSentHeaders = true
            var combined = headerData
            combined.append(buffer)
            pendingHeaderData = nil
            pendingBuffer.removeAll(keepingCapacity: false)
            return combined
        }
        if let finalPayload {
            connection.send(content: finalPayload, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { [weak self] _ in
                self?.connection.cancel()
            })
        }
    }

    private func flushPendingPayload(taskId: Int) {
        let payload: Data? = lock.withLock {
            guard !isCancelled, taskId == activeTaskId, !pendingDecisionCommitted else { return nil }
            pendingDecisionCommitted = true
            hasSentHeaders = true
            var combined = pendingHeaderData ?? Data()
            combined.append(pendingBuffer)
            pendingHeaderData = nil
            pendingBuffer.removeAll(keepingCapacity: false)
            return combined
        }
        if let payload, !payload.isEmpty {
            connection.send(content: payload, contentContext: .defaultMessage, isComplete: false, completion: .contentProcessed { [weak self] error in
                if error != nil {
                    self?.cancel()
                }
            })
        }
    }

    private func runShadowVideoProbe(
        videoUrl: URL,
        host: String,
        directIp: String?,
        completion: @escaping @Sendable (HlsSegmentVerdict?) -> Void
    ) {
        var baseReq = URLRequest(url: videoUrl)
        for (k, v) in (initialAttempt.request.allHTTPHeaderFields ?? [:]) {
            baseReq.setValue(v, forHTTPHeaderField: k)
        }
        baseReq.setValue("bytes=0-8191", forHTTPHeaderField: "Range")
        guard var probeReq = HlsSegmentShield.buildFailoverRequest(from: baseReq, failoverHost: host, stripRefererOrigin: false) else {
            completion(nil)
            return
        }
        probeReq.setValue("bytes=0-8191", forHTTPHeaderField: "Range")

        let evaluateProbe: @Sendable (Data?, HTTPURLResponse?) -> Void = { [weak self] data, httpResp in
            guard let self, let data, !data.isEmpty else {
                completion(nil)
                return
            }
            let totalFromRange: Int64? = httpResp?
                .value(forHTTPHeaderField: "Content-Range")?
                .split(separator: "/")
                .last
                .flatMap { Int64($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            let cl = totalFromRange ?? httpResp?.value(forHTTPHeaderField: "Content-Length").flatMap { Int64($0) }
            let eTag = httpResp?.value(forHTTPHeaderField: "ETag")
            let verdict = HlsSegmentShield.evaluateSegment(
                prefixData: data,
                isComplete: true,
                expectedContentLength: cl,
                eTag: eTag,
                baselineSps: self.baselineSpsProvider?(),
                declaredMaxFps: self.declaredMaxFps
            )
            completion(verdict)
        }

        if let directIp, !directIp.isEmpty {
            DirectEdgeRequestTask.fetchPrefix(request: probeReq, directIp: directIp, maxBytes: 8192, completion: evaluateProbe)
        } else {
            let task = failoverSession.dataTask(with: probeReq) { data, resp, _ in
                evaluateProbe(data, resp as? HTTPURLResponse)
            }
            task.resume()
        }
    }

    func didComplete(taskId: Int, error: Error?) {
        enum CompletionState {
            case ignore
            case committed(error: Error?)
            case bufferedComplete(headerData: Data, buffer: Data, expectedCL: Int64?, eTag: String?, targetKey: String, host: String, directIp: String?)
            case failedBeforeCommit
        }

        let state: CompletionState = lock.withLock {
            guard !isCancelled, taskId == activeTaskId else { return .ignore }
            if pendingDecisionCommitted {
                return .committed(error: error)
            }
            if error == nil, let headerData = pendingHeaderData {
                let tKey = activeHandle?.targetKey ?? realUrl.host ?? ""
                let hName = activeHandle?.host ?? realUrl.host ?? ""
                let dIp = activeHandle?.directIp
                return .bufferedComplete(
                    headerData: headerData,
                    buffer: pendingBuffer,
                    expectedCL: pendingExpectedContentLength,
                    eTag: pendingETag,
                    targetKey: tKey,
                    host: hName,
                    directIp: dIp
                )
            }
            return .failedBeforeCommit
        }

        switch state {
        case .ignore:
            return

        case .committed(let err):
            if err != nil {
                connection.cancel()
            } else {
                connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { [weak self] _ in
                    self?.connection.cancel()
                })
            }

        case .bufferedComplete(let headerData, let buffer, let expectedCL, let eTag, let targetKey, let host, let directIp):
            if inspectionMode == .video {
                let baseline = baselineSpsProvider?()
                if !buffer.isEmpty,
                   let verdict = HlsSegmentShield.evaluateSegment(
                       prefixData: buffer,
                       isComplete: true,
                       expectedContentLength: expectedCL,
                       eTag: eTag,
                       baselineSps: baseline,
                       declaredMaxFps: declaredMaxFps
                   ) {
                    switch verdict {
                    case .suspectAdSwap(let reason):
                        onHostPoisoned?(targetKey)
                        if let ptsInPacket = HlsSegmentShield.extractFirstVideoPts90k(from: buffer) {
                            lock.withLock { self.lastSuspectPts90k = ptsInPacket }
                        }
                        if trySwitchToFallback(fromTaskId: taskId, cancelOldTask: false) {
                            AppDiagnostics.shared.log("HlsProxyServer: blocked swapped short segment (\(reason)) on \(targetKey) (\(realUrl.lastPathComponent)), switching to fallback")
                            return
                        }
                        if sendBlackReplacementIfNeeded(taskId: taskId, buffer: buffer) {
                            return
                        }
                        lock.withLock { isCancelled = true }
                        finishVideoInspectionOnce()
                        HlsProxyServer.send503(on: connection)
                        return

                    case .clean(let baselineToRecord):
                        if let baselineToRecord {
                            onRecordBaseline?(baselineToRecord)
                        }
                        if let pts = HlsSegmentShield.extractFirstVideoPts90k(from: buffer) {
                            onRecordVideoPtsOffset?(pts)
                        }
                        onHostClean?(targetKey, host, directIp)
                    }
                }
                commitBufferedResponse(taskId: taskId, headerData: headerData, buffer: buffer)
                return
            }

            if inspectionMode == .audio {
                let calibratedPts = (fallbackStartPts90k > 0 || (ptsOffsetProvider?() ?? 0) != 0)
                    ? computeCalibratedPts90k()
                    : nil
                let knownFps = knownAudioAdFingerprintsProvider?() ?? []
                let audioVerdict = buffer.isEmpty ? nil : HlsSegmentShield.evaluateAudioSegment(
                    data: buffer,
                    isComplete: true,
                    expectedDurationSeconds: fallbackDurationSeconds,
                    expectedStartPts90k: calibratedPts,
                    baseline: baselineAudioProvider?(),
                    knownBannerFingerprints: knownFps
                )

                var parsedInfo: HlsAudioStreamInfo? = nil
                if case .suspectAdSwap(let reason, let info) = audioVerdict {
                    if let info, !info.isDigitalSilence {
                        onLearnAudioAdFingerprint?(info.payloadFingerprint)
                    }
                    onHostPoisoned?(targetKey)
                    if trySwitchToFallback(fromTaskId: taskId, cancelOldTask: false) {
                        AppDiagnostics.shared.log("HlsProxyServer: blocked swapped audio (\(reason)) on \(targetKey) (\(realUrl.lastPathComponent)), switching to fallback")
                        return
                    }
                    if sendSilentAudioReplacementIfNeeded(taskId: taskId) {
                        return
                    }
                    lock.withLock { isCancelled = true }
                    HlsProxyServer.send503(on: connection)
                    return
                } else if case .clean(let info) = audioVerdict {
                    parsedInfo = info
                }

                if let info = parsedInfo, !info.isDigitalSilence, onCheckAudioDuplicate?(info.payloadFingerprint) == true {
                    onHostPoisoned?(targetKey)
                    if trySwitchToFallback(fromTaskId: taskId, cancelOldTask: false) {
                        AppDiagnostics.shared.log("HlsProxyServer: blocked repeated audio ad jingle on \(targetKey) (\(realUrl.lastPathComponent)), switching to fallback")
                        return
                    }
                    if sendSilentAudioReplacementIfNeeded(taskId: taskId) {
                        return
                    }
                    lock.withLock { isCancelled = true }
                    HlsProxyServer.send503(on: connection)
                    return
                }

                let probeDecision = shadowProbeRequirementProvider?(targetKey) ?? (false, false)
                if probeDecision.shouldProbe, let videoUrl = overlappingVideoUrl {
                    runShadowVideoProbe(videoUrl: videoUrl, host: host, directIp: directIp) { [weak self] probeVerdict in
                        guard let self else { return }
                        let stillValid = self.lock.withLock { !self.isCancelled && taskId == self.activeTaskId && !self.pendingDecisionCommitted }
                        guard stillValid else { return }

                        var isSwap = false
                        if case .suspectAdSwap = probeVerdict {
                            isSwap = true
                        } else if probeVerdict == nil && probeDecision.inBlackout {
                            isSwap = true
                        }

                        if isSwap {
                            if let info = parsedInfo, !info.isDigitalSilence {
                                self.onLearnAudioAdFingerprint?(info.payloadFingerprint)
                            }
                            self.onHostPoisoned?(targetKey)
                            if self.trySwitchToFallback(fromTaskId: taskId, cancelOldTask: false) {
                                AppDiagnostics.shared.log("HlsProxyServer: shadow video probe caught ad on \(targetKey) for \(self.realUrl.lastPathComponent), switching audio to fallback")
                                return
                            }
                            if self.sendSilentAudioReplacementIfNeeded(taskId: taskId) {
                                return
                            }
                            self.lock.withLock { self.isCancelled = true }
                            HlsProxyServer.send503(on: self.connection)
                            return
                        }

                        if let info = parsedInfo {
                            self.onRecordAudioBaseline?(info)
                        }
                        self.onHostClean?(targetKey, host, directIp)
                        self.commitBufferedResponse(taskId: taskId, headerData: headerData, buffer: buffer)
                    }
                    return
                } else if probeDecision.inBlackout {
                    // No overlapping video URL to probe during active blackout: never gamble on poisoned audio.
                    onHostPoisoned?(targetKey)
                    if trySwitchToFallback(fromTaskId: taskId, cancelOldTask: false) {
                        return
                    }
                    if sendSilentAudioReplacementIfNeeded(taskId: taskId) {
                        return
                    }
                    lock.withLock { isCancelled = true }
                    HlsProxyServer.send503(on: connection)
                    return
                }

                if let info = parsedInfo {
                    onRecordAudioBaseline?(info)
                }
                onHostClean?(targetKey, host, directIp)
                commitBufferedResponse(taskId: taskId, headerData: headerData, buffer: buffer)
                return
            }

            commitBufferedResponse(taskId: taskId, headerData: headerData, buffer: buffer)

        case .failedBeforeCommit:
            if trySwitchToFallback(fromTaskId: taskId, cancelOldTask: false) {
                AppDiagnostics.shared.log("HlsProxyServer: segment fetch error before commit on \(realUrl.lastPathComponent), trying fallback")
                return
            }
            if sendExhaustedReplacementIfNeeded(taskId: taskId, buffer: Data()) {
                return
            }
            lock.withLock { isCancelled = true }
            finishVideoInspectionOnce()
            HlsProxyServer.send503(on: connection)
        }
    }
}

// MARK: - Trust-All Session & Data Delegate

final class ProxyTrustAllSessionDelegate: NSObject, @preconcurrency URLSessionDelegate, URLSessionTaskDelegate, URLSessionDataDelegate, @unchecked Sendable {
    private let contextsLock = NSLock()
    private var streamContexts: [Int: ProxyStreamContext] = [:]

    func register(taskId: Int, context: ProxyStreamContext) {
        contextsLock.withLock {
            streamContexts[taskId] = context
        }
    }

    func unregister(taskId: Int) {
        contextsLock.withLock {
            _ = streamContexts.removeValue(forKey: taskId)
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        let context = contextsLock.withLock { streamContexts[dataTask.taskIdentifier] }
        if let context = context {
            context.didReceiveResponse(taskId: dataTask.taskIdentifier, response: response, completionHandler: completionHandler)
        } else {
            completionHandler(.allow)
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        let context = contextsLock.withLock { streamContexts[dataTask.taskIdentifier] }
        context?.didReceiveData(taskId: dataTask.taskIdentifier, data: data)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        let context = contextsLock.withLock { streamContexts.removeValue(forKey: task.taskIdentifier) }
        context?.didComplete(taskId: task.taskIdentifier, error: error)
    }

    nonisolated func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        // Accept server trust for media proxying (handles Russian CA and dynamic CDN intermediates)
        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        var redirectedRequest = request
        if let originalRequest = task.originalRequest {
            let headersToPreserve = ["Range", "Referer", "Origin", "Accept", "User-Agent", "Accepts-Controls", "Authorizations", "Authorization"]
            for header in headersToPreserve {
                if let value = originalRequest.value(forHTTPHeaderField: header) {
                    redirectedRequest.setValue(value, forHTTPHeaderField: header)
                }
            }
        }
        completionHandler(redirectedRequest)
    }
}
