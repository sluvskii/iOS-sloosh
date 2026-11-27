import Foundation
import Network
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
    private var currentMasterUrl: URL?
    private var failoverHosts: [String] = []
    private var streamDeclaredMaxFps: Double? = nil
    private var segmentBaselineSpsByTier: [String: Data] = [:]
    private var hostPoisonedUntil: [String: Date] = [:]
    private var preferredHealthyHost: String? = nil
    private var segmentDurationsByName: [String: Double] = [:]
    private var segmentStartPtsByName: [String: UInt64] = [:]

    // Фоновая задача iOS: не даёт системе заморозить процесс пока прокси активен в фоне
    private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid

    var port: NWEndpoint.Port = 8181
    var fixedMasterUrl: String { "http://127.0.0.1:\(port.rawValue)/master.m3u8" }

    /// Публичное свойство для проверки живости прокси из PlayerView
    var isAlive: Bool { stateLock.withLock { isListenerAlive && listener != nil } }

    private let sessionDelegate = ProxyTrustAllSessionDelegate()
    private var playlistCache: [String: (content: String, timestamp: Date, failoverHosts: [String], maxFps: Double?, durations: [String: Double], startPts: [String: UInt64])] = [:]
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
            self.hostPoisonedUntil.removeAll()
            self.preferredHealthyHost = nil
            self.segmentDurationsByName.removeAll()
            self.segmentStartPtsByName.removeAll()
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
        stateLock.withLock {
            if currentMasterUrl?.absoluteString != parsed?.absoluteString {
                self.failoverHosts = []
                self.streamDeclaredMaxFps = nil
                self.segmentBaselineSpsByTier.removeAll()
                self.hostPoisonedUntil.removeAll()
                self.preferredHealthyHost = nil
                self.segmentDurationsByName.removeAll()
                self.segmentStartPtsByName.removeAll()
            }
            currentMasterUrl = parsed
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
            self.hostPoisonedUntil.removeAll()
            self.preferredHealthyHost = nil
            self.segmentDurationsByName.removeAll()
            self.segmentStartPtsByName.removeAll()
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
                if let cached = playlistCacheLock.withLock({ () -> (content: String, failoverHosts: [String], maxFps: Double?, durations: [String: Double], startPts: [String: UInt64])? in
                    if let entry = self.playlistCache[cacheKey], Date().timeIntervalSince(entry.timestamp) < 30.0 {
                        return (entry.content, entry.failoverHosts, entry.maxFps, entry.durations, entry.startPts)
                    }
                    return nil
                }) {
                    if !cached.failoverHosts.isEmpty || cached.maxFps != nil || !cached.durations.isEmpty {
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
                        stateLock.withLock {
                            self.failoverHosts = extractedFailoverHosts
                            if let extractedMaxFps {
                                self.streamDeclaredMaxFps = extractedMaxFps
                            }
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
                        if !lowerFile.contains("-a") {
                            let timeline = PlaybackHlsRewriter.extractSegmentTimeline(fromMediaPlaylist: content)
                            mediaDurations = timeline.durations
                            mediaStartPts = timeline.startPts90k
                            if !mediaDurations.isEmpty {
                                stateLock.withLock {
                                    self.segmentDurationsByName.merge(mediaDurations) { _, new in new }
                                    self.segmentStartPtsByName.merge(mediaStartPts) { _, new in new }
                                }
                            }
                        }
                        AppDiagnostics.shared.log("HlsProxyServer: media playlist served for \(realUrl.lastPathComponent) (\(content.count) bytes)")
                        rewritten = self.rewriteM3u8(content: content, baseUrl: finalUrl, isCollaps: currentIsCollaps)
                    }

                    playlistCacheLock.withLock {
                        self.playlistCache[cacheKey] = (content: rewritten, timestamp: Date(), failoverHosts: masterFailoverHosts, maxFps: masterMaxFps, durations: mediaDurations, startPts: mediaStartPts)
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
                    // with lightweight prefix inspection, adaptive host cooldown, and zero-ad fallback.
                    self.streamMediaSegment(
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

    private func streamMediaSegment(
        request: URLRequest,
        realUrl: URL,
        incomingRange: String?,
        isCollaps: Bool,
        failoverHosts: [String],
        declaredMaxFps: Double?,
        connection: NWConnection
    ) {
        let inspectEnabled = HlsSegmentShield.isInspectableVideoSegment(
            url: realUrl,
            isCollaps: isCollaps,
            rangeHeader: incomingRange
        )
        let tierKey = inspectEnabled ? HlsSegmentShield.tierKey(for: realUrl) : ""
        let segName = realUrl.lastPathComponent
        let originalHostLower = realUrl.host?.lowercased() ?? ""

        let (poisonedSnapshot, promotedHost, segDuration, segStartPts) = stateLock.withLock {
            (
                self.hostPoisonedUntil,
                self.preferredHealthyHost,
                self.segmentDurationsByName[segName] ?? 8.0,
                self.segmentStartPtsByName[segName] ?? 0
            )
        }

        let plan: (initial: ProxySegmentAttempt, fallbacks: [ProxySegmentAttempt])
        if inspectEnabled {
            plan = Self.buildAttemptPlan(
                from: request,
                realUrl: realUrl,
                failoverHosts: failoverHosts,
                isCollaps: isCollaps,
                hostPoisonedUntil: poisonedSnapshot,
                preferredHealthyHost: promotedHost
            )
        } else {
            plan = (ProxySegmentAttempt(request: request, useFailoverSession: false, delayMs: 0), [])
        }

        let streamContext = ProxyStreamContext(
            connection: connection,
            realUrl: realUrl,
            primarySession: self.session,
            failoverSession: self.failoverSession,
            sessionDelegate: self.sessionDelegate,
            inspectEnabled: inspectEnabled,
            fallbackAttempts: plan.fallbacks,
            declaredMaxFps: declaredMaxFps,
            fallbackDurationSeconds: segDuration,
            fallbackStartPts90k: segStartPts,
            baselineSpsProvider: inspectEnabled ? { [weak self] in
                self?.stateLock.withLock { self?.segmentBaselineSpsByTier[tierKey] }
            } : nil,
            onRecordBaseline: inspectEnabled ? { [weak self] sps in
                self?.stateLock.withLock {
                    if self?.segmentBaselineSpsByTier[tierKey] == nil {
                        self?.segmentBaselineSpsByTier[tierKey] = sps
                    }
                }
            } : nil,
            onHostPoisoned: inspectEnabled ? { [weak self] poisonedHost in
                let lower = poisonedHost.lowercased()
                guard !lower.isEmpty else { return }
                self?.stateLock.withLock {
                    self?.hostPoisonedUntil[lower] = Date().addingTimeInterval(25.0)
                    if self?.preferredHealthyHost == lower {
                        self?.preferredHealthyHost = nil
                    }
                }
            } : nil,
            onHostClean: inspectEnabled ? { [weak self] cleanHost in
                let lower = cleanHost.lowercased()
                guard !lower.isEmpty else { return }
                self?.stateLock.withLock {
                    self?.hostPoisonedUntil.removeValue(forKey: lower)
                    if lower != originalHostLower {
                        self?.preferredHealthyHost = lower
                    }
                }
            } : nil
        )

        let startSession = plan.initial.useFailoverSession ? self.failoverSession : self.session
        let task = startSession.dataTask(with: plan.initial.request)
        streamContext.start(initialTask: task)

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
        hostPoisonedUntil: [String: Date],
        preferredHealthyHost: String?
    ) -> (initial: ProxySegmentAttempt, fallbacks: [ProxySegmentAttempt]) {
        let now = Date()
        let originalHost = realUrl.host?.lowercased() ?? ""

        var pool: [String] = []
        func appendUnique(_ h: String?) {
            guard let h = h?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !h.isEmpty else { return }
            if !pool.contains(h) { pool.append(h) }
        }

        appendUnique(originalHost)
        for h in failoverHosts { appendUnique(h) }
        if isCollaps || originalHost.contains("interkh") {
            appendUnique("x-bc.interkh.com")
            appendUnique("hye1eaipby4w.interkh.com")
        }

        var healthy: [String] = []
        var cooled: [String] = []
        for h in pool {
            if let until = hostPoisonedUntil[h], until > now {
                cooled.append(h)
            } else {
                healthy.append(h)
            }
        }
        if let preferred = preferredHealthyHost?.lowercased(),
           let idx = healthy.firstIndex(of: preferred), idx > 0 {
            healthy.remove(at: idx)
            healthy.insert(preferred, at: 0)
        }

        let orderedHosts = healthy + cooled
        let initialHost = orderedHosts.first ?? originalHost
        let initialAttempt: ProxySegmentAttempt
        if initialHost.isEmpty || initialHost == originalHost {
            initialAttempt = ProxySegmentAttempt(request: originalRequest, useFailoverSession: false, delayMs: 0)
        } else if let promotedReq = HlsSegmentShield.buildFailoverRequest(from: originalRequest, failoverHost: initialHost, stripRefererOrigin: false) {
            initialAttempt = ProxySegmentAttempt(request: promotedReq, useFailoverSession: true, delayMs: 0)
        } else {
            initialAttempt = ProxySegmentAttempt(request: originalRequest, useFailoverSession: false, delayMs: 0)
        }

        var fallbacks: [ProxySegmentAttempt] = []
        for host in orderedHosts.dropFirst() {
            if let req = HlsSegmentShield.buildFailoverRequest(from: originalRequest, failoverHost: host, stripRefererOrigin: false) {
                fallbacks.append(ProxySegmentAttempt(request: req, useFailoverSession: true, delayMs: 0))
            }
        }
        if let retryHost = healthy.first ?? failoverHosts.first ?? (isCollaps || originalHost.contains("interkh") ? "x-bc.interkh.com" : nil),
           let pacedReq = HlsSegmentShield.buildFailoverRequest(from: originalRequest, failoverHost: retryHost, stripRefererOrigin: false) {
            fallbacks.append(ProxySegmentAttempt(request: pacedReq, useFailoverSession: true, delayMs: 250))
        }
        if let stripped = HlsSegmentShield.buildFailoverRequest(from: originalRequest, failoverHost: nil, stripRefererOrigin: true) {
            fallbacks.append(ProxySegmentAttempt(request: stripped, useFailoverSession: true, delayMs: 150))
        }

        return (initialAttempt, Array(fallbacks.prefix(4)))
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

// MARK: - Streaming Segment Context

struct ProxySegmentAttempt {
    let request: URLRequest
    let useFailoverSession: Bool
    let delayMs: Int
}

final class ProxyStreamContext: @unchecked Sendable {
    let connection: NWConnection
    let realUrl: URL
    private let primarySession: URLSession
    private let failoverSession: URLSession
    private weak var sessionDelegate: ProxyTrustAllSessionDelegate?
    private let inspectEnabled: Bool
    private let fallbackAttempts: [ProxySegmentAttempt]
    private let declaredMaxFps: Double?
    private let fallbackDurationSeconds: Double
    private let fallbackStartPts90k: UInt64
    private let baselineSpsProvider: (() -> Data?)?
    private let onRecordBaseline: ((Data) -> Void)?
    private let onHostPoisoned: ((String) -> Void)?
    private let onHostClean: ((String) -> Void)?

    private let lock = NSLock()
    private var isCancelled = false
    private var hasSentHeaders = false
    private var pendingDecisionCommitted = false
    private var activeTaskId: Int = -1
    private weak var activeTask: URLSessionDataTask?
    private var fallbackIndex: Int = 0
    private var pendingHeaderData: Data?
    private var pendingExpectedContentLength: Int64?
    private var pendingETag: String?
    private var pendingBuffer = Data()
    private var lastSuspectPts90k: UInt64?

    init(
        connection: NWConnection,
        realUrl: URL,
        primarySession: URLSession,
        failoverSession: URLSession,
        sessionDelegate: ProxyTrustAllSessionDelegate,
        inspectEnabled: Bool,
        fallbackAttempts: [ProxySegmentAttempt],
        declaredMaxFps: Double?,
        fallbackDurationSeconds: Double,
        fallbackStartPts90k: UInt64,
        baselineSpsProvider: (() -> Data?)?,
        onRecordBaseline: ((Data) -> Void)?,
        onHostPoisoned: ((String) -> Void)?,
        onHostClean: ((String) -> Void)?
    ) {
        self.connection = connection
        self.realUrl = realUrl
        self.primarySession = primarySession
        self.failoverSession = failoverSession
        self.sessionDelegate = sessionDelegate
        self.inspectEnabled = inspectEnabled
        self.fallbackAttempts = fallbackAttempts
        self.declaredMaxFps = declaredMaxFps
        self.fallbackDurationSeconds = fallbackDurationSeconds
        self.fallbackStartPts90k = fallbackStartPts90k
        self.baselineSpsProvider = baselineSpsProvider
        self.onRecordBaseline = onRecordBaseline
        self.onHostPoisoned = onHostPoisoned
        self.onHostClean = onHostClean
    }

    func start(initialTask: URLSessionDataTask) {
        let canStart = lock.withLock { () -> Bool in
            guard !isCancelled else { return false }
            activeTask = initialTask
            activeTaskId = initialTask.taskIdentifier
            return true
        }
        guard canStart else { return }
        sessionDelegate?.register(taskId: initialTask.taskIdentifier, context: self)
        initialTask.resume()
    }

    func cancel() {
        let (taskToCancel, oldId): (URLSessionDataTask?, Int) = lock.withLock {
            isCancelled = true
            let current = activeTask
            let prevId = activeTaskId
            activeTask = nil
            activeTaskId = -1
            pendingHeaderData = nil
            pendingBuffer.removeAll()
            return (current, prevId)
        }
        if oldId >= 0 {
            sessionDelegate?.unregister(taskId: oldId)
        }
        taskToCancel?.cancel()
    }

    private enum FallbackSwitchResult {
        case launched(newTask: URLSessionDataTask, oldTask: URLSessionDataTask?, delayMs: Int)
        case unavailable
    }

    private func resumeIfStillActive(task: URLSessionDataTask) {
        let shouldResume = lock.withLock {
            !isCancelled && activeTaskId == task.taskIdentifier
        }
        if shouldResume {
            task.resume()
        } else {
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
            let targetSession = nextAttempt.useFailoverSession ? failoverSession : primarySession
            let newTask = targetSession.dataTask(with: nextAttempt.request)
            let oldTask = activeTask
            activeTask = newTask
            activeTaskId = newTask.taskIdentifier
            pendingHeaderData = nil
            pendingExpectedContentLength = nil
            pendingETag = nil
            pendingBuffer.removeAll(keepingCapacity: true)
            return .launched(newTask: newTask, oldTask: oldTask, delayMs: nextAttempt.delayMs)
        }

        switch result {
        case .launched(let newTask, let oldTask, let delayMs):
            sessionDelegate?.register(taskId: newTask.taskIdentifier, context: self)
            if cancelOldTask {
                oldTask?.cancel()
            }
            if delayMs > 0 {
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + .milliseconds(delayMs)) { [weak self] in
                    self?.resumeIfStillActive(task: newTask)
                }
            } else {
                newTask.resume()
            }
            return true
        case .unavailable:
            return false
        }
    }

    func didReceiveResponse(
        taskId: Int,
        response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        let stateCheck: (active: Bool, hasFallback: Bool, savedSuspectPts: UInt64?) = lock.withLock {
            (!isCancelled && taskId == activeTaskId, fallbackIndex < fallbackAttempts.count, lastSuspectPts90k)
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
            if let savedSuspectPts = stateCheck.savedSuspectPts,
               sendBlackReplacementIfNeeded(taskId: taskId, buffer: Data(), overridePts90k: savedSuspectPts) {
                completionHandler(.cancel)
                return
            }
            lock.withLock { isCancelled = true }
            HlsProxyServer.send503(on: connection)
            completionHandler(.cancel)
            return
        }

        let statusCode = httpResponse.statusCode
        guard statusCode >= 200 && statusCode < 400 else {
            if stateCheck.hasFallback && trySwitchToFallback(fromTaskId: taskId, cancelOldTask: false) {
                AppDiagnostics.shared.log("HlsProxyServer: upstream HTTP \(statusCode) on \(httpResponse.url?.host ?? realUrl.host ?? "") (\(realUrl.lastPathComponent)), switching to fallback")
                completionHandler(.cancel)
                return
            }
            if let savedSuspectPts = stateCheck.savedSuspectPts,
               sendBlackReplacementIfNeeded(taskId: taskId, buffer: Data(), overridePts90k: savedSuspectPts) {
                completionHandler(.cancel)
                return
            }
            lock.withLock { isCancelled = true }
            HlsProxyServer.send503(on: connection)
            completionHandler(.cancel)
            return
        }

        let rawContentLength = httpResponse.value(forHTTPHeaderField: "Content-Length").flatMap { Int64($0) }
        let eTag = httpResponse.value(forHTTPHeaderField: "ETag")
        let respHost = httpResponse.url?.host ?? realUrl.host ?? ""

        // When fallbacks remain, short-circuit unambiguous 268088B banner headers immediately.
        // On the final attempt, allow receiving the first ~564B so we can extract exact PTS before black substitution.
        if inspectEnabled,
           stateCheck.hasFallback,
           let rawContentLength,
           rawContentLength == HlsSegmentShield.knownBannerByteLength,
           eTag?.lowercased().hasSuffix(HlsSegmentShield.knownBannerETagSuffix) == true {
            onHostPoisoned?(respHost)
            if trySwitchToFallback(fromTaskId: taskId, cancelOldTask: false) {
                AppDiagnostics.shared.log("HlsProxyServer: blocked swapped segment (Content-Length 268088 + banner ETag) on \(respHost) (\(realUrl.lastPathComponent)), switching to fallback")
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
            if inspectEnabled {
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
            case inspect(buffer: Data, expectedCL: Int64?, eTag: String?, activeHost: String)
        }

        let action: DataAction = lock.withLock {
            guard !isCancelled, taskId == activeTaskId else { return .ignore }
            if pendingDecisionCommitted {
                return .passthrough
            }
            pendingBuffer.append(data)
            let activeHost = activeTask?.currentRequest?.url?.host ?? realUrl.host ?? ""
            return .inspect(
                buffer: pendingBuffer,
                expectedCL: pendingExpectedContentLength,
                eTag: pendingETag,
                activeHost: activeHost
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

        case .inspect(let buffer, let expectedCL, let eTag, let activeHost):
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
                onHostClean?(activeHost)
                flushPendingPayload(taskId: taskId)

            case .suspectAdSwap(let reason):
                onHostPoisoned?(activeHost)
                let ptsInPacket = HlsSegmentShield.extractFirstVideoPts90k(from: buffer)
                if let ptsInPacket {
                    lock.withLock { self.lastSuspectPts90k = ptsInPacket }
                }
                if trySwitchToFallback(fromTaskId: taskId, cancelOldTask: true) {
                    AppDiagnostics.shared.log("HlsProxyServer: blocked swapped segment (\(reason)) on \(activeHost) (\(realUrl.lastPathComponent)), switching to fallback")
                    return
                }
                if sendBlackReplacementIfNeeded(taskId: taskId, buffer: buffer, overridePts90k: ptsInPacket) {
                    return
                }
                lock.withLock { isCancelled = true }
                HlsProxyServer.send503(on: connection)
            }
        }
    }

    private func sendBlackReplacementIfNeeded(taskId: Int, buffer: Data, overridePts90k: UInt64? = nil) -> Bool {
        let baseline = baselineSpsProvider?()
        let dims = HlsSegmentShield.resolveStreamDimensions(fromBaselineSps: baseline)
        let savedPts = lock.withLock { lastSuspectPts90k }
        let ptsStart90k = overridePts90k
            ?? HlsSegmentShield.extractFirstVideoPts90k(from: buffer)
            ?? savedPts
            ?? fallbackStartPts90k

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

        let cancelledTask: (oldTask: URLSessionDataTask?, payload: Data)? = lock.withLock {
            guard !isCancelled, taskId == activeTaskId, !pendingDecisionCommitted else { return nil }
            pendingDecisionCommitted = true
            hasSentHeaders = true
            let current = activeTask
            activeTask = nil
            pendingHeaderData = nil
            pendingBuffer.removeAll(keepingCapacity: false)
            var full = headerData
            full.append(replacementTs)
            return (current, full)
        }
        guard let item = cancelledTask else { return false }

        item.oldTask?.cancel()
        AppDiagnostics.shared.log("HlsProxyServer: all hosts returned banner on \(realUrl.lastPathComponent), substituted clean black \(dims.width)x\(dims.height) TS (\(replacementTs.count)B, pts=\(ptsStart90k / 90_000)s)")
        connection.send(content: item.payload, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { [weak self] _ in
            self?.connection.cancel()
        })
        return true
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

    func didComplete(taskId: Int, error: Error?) {
        enum CompletionState {
            case ignore
            case committed(error: Error?)
            case bufferedComplete(headerData: Data, buffer: Data, expectedCL: Int64?, eTag: String?, activeHost: String)
            case failedBeforeCommit(savedSuspectPts: UInt64?)
        }

        let state: CompletionState = lock.withLock {
            guard !isCancelled, taskId == activeTaskId else { return .ignore }
            if pendingDecisionCommitted {
                return .committed(error: error)
            }
            if error == nil, let headerData = pendingHeaderData {
                let activeHost = activeTask?.currentRequest?.url?.host ?? realUrl.host ?? ""
                return .bufferedComplete(
                    headerData: headerData,
                    buffer: pendingBuffer,
                    expectedCL: pendingExpectedContentLength,
                    eTag: pendingETag,
                    activeHost: activeHost
                )
            }
            return .failedBeforeCommit(savedSuspectPts: lastSuspectPts90k)
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

        case .bufferedComplete(let headerData, let buffer, let expectedCL, let eTag, let activeHost):
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
                    onHostPoisoned?(activeHost)
                    let ptsInPacket = HlsSegmentShield.extractFirstVideoPts90k(from: buffer)
                    if let ptsInPacket {
                        lock.withLock { self.lastSuspectPts90k = ptsInPacket }
                    }
                    if trySwitchToFallback(fromTaskId: taskId, cancelOldTask: false) {
                        AppDiagnostics.shared.log("HlsProxyServer: blocked swapped short segment (\(reason)) on \(activeHost) (\(realUrl.lastPathComponent)), switching to fallback")
                        return
                    }
                    if sendBlackReplacementIfNeeded(taskId: taskId, buffer: buffer, overridePts90k: ptsInPacket) {
                        return
                    }
                    lock.withLock { isCancelled = true }
                    HlsProxyServer.send503(on: connection)
                    return

                case .clean(let baselineToRecord):
                    if let baselineToRecord {
                        onRecordBaseline?(baselineToRecord)
                    }
                    onHostClean?(activeHost)
                }
            }

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

        case .failedBeforeCommit(let savedSuspectPts):
            if trySwitchToFallback(fromTaskId: taskId, cancelOldTask: false) {
                AppDiagnostics.shared.log("HlsProxyServer: segment fetch error before commit on \(realUrl.lastPathComponent), trying fallback")
                return
            }
            if let savedSuspectPts,
               sendBlackReplacementIfNeeded(taskId: taskId, buffer: Data(), overridePts90k: savedSuspectPts) {
                return
            }
            lock.withLock { isCancelled = true }
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
