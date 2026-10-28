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
    private var currentMasterUrl: URL?

    // Фоновая задача iOS: не даёт системе заморозить процесс пока прокси активен в фоне
    private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid

    var port: NWEndpoint.Port = 8181
    var fixedMasterUrl: String { "http://127.0.0.1:\(port.rawValue)/master.m3u8" }

    /// Публичное свойство для проверки живости прокси из PlayerView
    var isAlive: Bool { stateLock.withLock { isListenerAlive && listener != nil } }

    private let sessionDelegate = ProxyTrustAllSessionDelegate()
    private var playlistCache: [String: (content: String, timestamp: Date)] = [:]
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

        let params: (headers: [String: String], voices: [String], subtitles: [PlaybackSubtitle], mediaId: String, preferredVoiceName: String?)? = stateLock.withLock {
            if !self.mediaId.isEmpty {
                return (self.headers, self.voices, self.subtitles, self.mediaId, self.preferredVoiceName)
            }
            return nil
        }

        if let p = params {
            let needsRestart = stateLock.withLock { !self.isListenerAlive || self.listener == nil }
            if needsRestart {
                print("HlsProxyServer: restarting listener on foreground (was dead)")
                stateLock.withLock {
                    self.listener?.cancel()
                    self.listener = nil
                    self.isListenerAlive = false
                }
                start(headers: p.headers, voices: p.voices, subtitles: p.subtitles, mediaId: p.mediaId, preferredVoiceName: p.preferredVoiceName)
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

    func start(headers: [String: String] = [:], voices: [String] = [], subtitles: [PlaybackSubtitle] = [], mediaId: String = "", preferredVoiceName: String? = nil) {
        playlistCacheLock.withLock {
            self.playlistCache.removeAll()
        }
        let isAlreadyRunning = stateLock.withLock {
            self.headers = headers
            self.voices = voices
            self.subtitles = subtitles
            self.mediaId = mediaId
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
                switch state {
                case .ready:
                    print("HlsProxyServer listener ready")
                    self.stateLock.withLock { self.isListenerAlive = true }
                case .failed(let error):
                    print("HlsProxyServer listener failed: \(error)")
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
        }
    }

    /// Планирует автоматический перезапуск слушателя через 300 мс при обнаружении сбоя
    private func scheduleListenerRestart() {
        let hasActiveSession = stateLock.withLock { !self.mediaId.isEmpty }
        guard hasActiveSession else { return }
        print("HlsProxyServer: scheduling self-healing restart in 300ms")
        queue.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            let (headers, voices, subtitles, mediaId) = self.stateLock.withLock {
                (self.headers, self.voices, self.subtitles, self.mediaId)
            }
            guard !mediaId.isEmpty else { return }
            self.start(headers: headers, voices: voices, subtitles: subtitles, mediaId: mediaId)
        }
    }

    func updateHeaders(_ headers: [String: String]) {
        stateLock.withLock {
            self.headers.merge(headers) { _, new in new }
        }
    }

    func updateMasterUrl(_ urlString: String) {
        stateLock.withLock {
            currentMasterUrl = URL(string: urlString)
        }
    }

    func updatePreferredVoice(_ voiceName: String?) {
        stateLock.withLock {
            self.preferredVoiceName = voiceName
        }
    }
    
    func stop() {
        endBackgroundTaskIfNeeded()
        stateLock.withLock {
            listener?.cancel()
            listener = nil
            isListenerAlive = false
            currentMasterUrl = nil
            self.voices = []
            self.subtitles = []
            self.mediaId = ""
            self.headers = [:]
        }
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
               let realUrl = URL(string: decodedString) {
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
            let fileUrl = docs.appendingPathComponent(relativePath)
            
            if FileManager.default.fileExists(atPath: fileUrl.path) {
                do {
                    let fileData = try Data(contentsOf: fileUrl)
                    let contentType: String
                    if fileUrl.pathExtension == "m3u8" {
                        contentType = "application/vnd.apple.mpegurl"
                    } else if fileUrl.pathExtension == "ts" {
                        contentType = "video/MP2T"
                    } else if fileUrl.pathExtension == "bin" {
                        contentType = "application/octet-stream"
                    } else {
                        contentType = "application/octet-stream"
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
        let (currentHeaders, currentVoices, currentSubtitles, currentMediaId, currentPreferredVoice) = stateLock.withLock {
            (self.headers, self.voices, self.subtitles, self.mediaId, self.preferredVoiceName)
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
                let cacheKey = "\(realUrl.absoluteString)_\(targetQuality ?? "")_\(currentPreferredVoice ?? "")"
                if let cached = playlistCacheLock.withLock({ () -> String? in
                    if let entry = self.playlistCache[cacheKey], Date().timeIntervalSince(entry.timestamp) < 30.0 {
                        return entry.content
                    }
                    return nil
                }) {
                    let cachedData = cached.data(using: .utf8) ?? Data()
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
                    if content.contains("#EXT-X-STREAM-INF") {
                        let playlistRewritten = PlaybackHlsRewriter.rewrite(
                            master: content,
                            voices: currentVoices,
                            subtitles: currentSubtitles,
                            mediaId: currentMediaId,
                            targetQuality: targetQuality,
                            preferredVoiceName: currentPreferredVoice,
                            port: Int(self.port.rawValue)
                        )

                        AppDiagnostics.shared.log("HlsProxyServer: master playlist rewritten (\(playlistRewritten.count) bytes)")
                        rewritten = self.rewriteM3u8(content: playlistRewritten, baseUrl: finalUrl)
                    } else {
                        AppDiagnostics.shared.log("HlsProxyServer: media playlist served for \(realUrl.lastPathComponent) (\(content.count) bytes)")
                        rewritten = self.rewriteM3u8(content: content, baseUrl: finalUrl)
                    }

                    playlistCacheLock.withLock {
                        self.playlistCache[cacheKey] = (content: rewritten, timestamp: Date())
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
                    self.streamMediaSegment(request: request, realUrl: realUrl, connection: connection)
                }
            }
        } catch {
            if Task.isCancelled { return }
            AppDiagnostics.shared.log("HlsProxyServer fetch failed: \(error)")
            self.send503(on: connection)
        }
    }

    private func streamMediaSegment(request: URLRequest, realUrl: URL, connection: NWConnection) {
        let streamContext = ProxyStreamContext(connection: connection, realUrl: realUrl) { [weak self] taskId in
            self?.sessionDelegate.unregister(taskId: taskId)
        }

        let task = self.session.dataTask(with: request)
        sessionDelegate.register(taskId: task.taskIdentifier, context: streamContext)

        connection.stateUpdateHandler = { state in
            switch state {
            case .cancelled, .failed:
                streamContext.cancel()
                task.cancel()
            default:
                break
            }
        }

        task.resume()
    }
    
    private func rewriteM3u8(content: String, baseUrl: URL) -> String {
        let lines = content.components(separatedBy: .newlines)
        var result = [String]()
        var skipNextUri = false
        var hasEmittedStartOffset = false
        let isCollaps = baseUrl.host?.contains("interkh.com") == true || baseUrl.absoluteString.contains("interkh")
        
        for line in lines {
            if line.isEmpty {
                if !skipNextUri { result.append(line) }
                continue
            }
            if line.hasPrefix("#") {
                // If this is a Collaps media playlist without EXT-X-START, inject start offset
                if isCollaps && !hasEmittedStartOffset && line.hasPrefix("#EXTINF:") {
                    if !result.contains(where: { $0.hasPrefix("#EXT-X-START") }) {
                        result.append("#EXT-X-START:TIME-OFFSET=3.5,PRECISE=YES")
                    }
                    hasEmittedStartOffset = true
                }

                // Filter AV1 streams from master playlist — not supported on iOS AVPlayer.
                // Skip the #EXT-X-STREAM-INF header and its following URI line.
                if line.hasPrefix("#EXT-X-STREAM-INF") {
                    if hlsLineHasAV1Codecs(line) {
                        skipNextUri = true
                        continue
                    }
                    skipNextUri = false
                    // Normalize VIDEO-RANGE: iOS doesn't support H.264 + PQ/HLG → causes -11848.
                    // Strip HDR VIDEO-RANGE attribute from non-HEVC/DV streams.
                    let normalizedLine = normalizeStreamInfVideoRange(line)
                    result.append(normalizedLine)
                    continue
                }
                if line.contains("URI=") {
                    var modifiedLine = line
                    if let range = modifiedLine.range(of: "URI=\"([^\"]+)\"", options: .regularExpression) {
                        let match = String(modifiedLine[range])
                        let uriString = match.replacingOccurrences(of: "URI=\"", with: "").replacingOccurrences(of: "\"", with: "")
                        if !uriString.isEmpty && uriString != "none" {
                            if uriString.hasPrefix("http://127.0.0.1:") {
                                // Already a local proxy URL, keep as is
                            } else {
                                let proxied = proxyUrl(uriString, baseUrl: baseUrl)
                                modifiedLine.replaceSubrange(range, with: "URI=\"\(proxied)\"")
                            }
                        }
                    }
                    result.append(modifiedLine)
                } else {
                    result.append(line)
                }
            } else {
                // URI line following #EXT-X-STREAM-INF — skip if AV1 was detected
                if skipNextUri {
                    skipNextUri = false
                    continue
                }
                result.append(proxyUrl(line, baseUrl: baseUrl))
            }
        }
        return result.joined(separator: "\n")
    }
    
    /// Strips VIDEO-RANGE=PQ and VIDEO-RANGE=HLG from non-HEVC/Dolby-Vision STREAM-INF lines.
    /// iOS AVPlayer does not support H.264 with HDR transfer functions — this causes -11848.
    /// HEVC (hvc1/hev1) and Dolby Vision (dvh1/dvhe) streams are left unchanged.
    private func normalizeStreamInfVideoRange(_ line: String) -> String {
        let lower = line.lowercased()
        // HEVC and Dolby Vision support HDR on iOS — leave those untouched
        let isHdrCapable = lower.contains("hvc1") || lower.contains("hev1") ||
                           lower.contains("dvh1") || lower.contains("dvhe")
        guard !isHdrCapable else { return line }
        
        var normalized = line
        if let regex = try? NSRegularExpression(pattern: ",?\\s*VIDEO-RANGE=[^,\\s]+", options: .caseInsensitive) {
            let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
            normalized = regex.stringByReplacingMatches(in: normalized, options: [], range: range, withTemplate: "")
        }
        return normalized
    }
    
    /// Returns true if a #EXT-X-STREAM-INF line declares an AV1 codec (av01.*)
    private func hlsLineHasAV1Codecs(_ line: String) -> Bool {
        let lower = line.lowercased()
        guard lower.contains("codecs=") else {
            // No CODECS attr — also check raw "av01" in the line as a safety net
            return lower.contains("av01")
        }
        // Extract value from CODECS="..."
        guard let afterPrefix = lower.range(of: "codecs=\"") else {
            return lower.contains("av01")
        }
        let rest = lower[afterPrefix.upperBound...]
        let codecValue: String
        if let endQuote = rest.firstIndex(of: "\"") {
            codecValue = String(rest[rest.startIndex..<endQuote])
        } else {
            codecValue = String(rest)
        }
        // Each codec is comma-separated, e.g. "hvc1.2.4.L120.B0,mp4a.40.2"
        return codecValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.contains { codec in
            codec.hasPrefix("av01") || codec == "av1"
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
        var header = "HTTP/1.1 \(statusCode) \(reason)\r\nContent-Type: \(contentType)\r\nContent-Length: \(data.count)\r\nConnection: close\r\n"
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

final class ProxyStreamContext: @unchecked Sendable {
    let connection: NWConnection
    let realUrl: URL
    let onComplete: (Int) -> Void
    private var hasSentHeaders = false
    private let lock = NSLock()
    private var isCancelled = false

    init(connection: NWConnection, realUrl: URL, onComplete: @escaping (Int) -> Void) {
        self.connection = connection
        self.realUrl = realUrl
        self.onComplete = onComplete
    }

    func cancel() {
        lock.withLock {
            isCancelled = true
        }
    }

    func didReceiveResponse(_ response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let isAlreadyCancelled = lock.withLock { isCancelled }
        guard !isAlreadyCancelled else {
            completionHandler(.cancel)
            return
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            return
        }

        let statusCode = httpResponse.statusCode
        guard statusCode >= 200 && statusCode < 400 else {
            lock.withLock { isCancelled = true }
            HlsProxyServer.send503(on: connection)
            completionHandler(.cancel)
            return
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

        lock.withLock { hasSentHeaders = true }

        connection.send(content: headerData, contentContext: .defaultMessage, isComplete: false, completion: .contentProcessed { [weak self] error in
            if error != nil {
                self?.cancel()
            }
        })

        completionHandler(.allow)
    }

    func didReceiveData(_ data: Data) {
        let isAlreadyCancelled = lock.withLock { isCancelled }
        guard !isAlreadyCancelled else { return }

        connection.send(content: data, contentContext: .defaultMessage, isComplete: false, completion: .contentProcessed { [weak self] error in
            if error != nil {
                self?.cancel()
            }
        })
    }

    func didComplete(taskId: Int, error: Error?) {
        defer { onComplete(taskId) }

        let headersSent = lock.withLock { hasSentHeaders }
        if let error = error {
            if !headersSent {
                HlsProxyServer.send503(on: connection)
            } else {
                connection.cancel()
            }
        } else {
            connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { [weak self] _ in
                self?.connection.cancel()
            })
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
            context.didReceiveResponse(response, completionHandler: completionHandler)
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
        context?.didReceiveData(data)
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
