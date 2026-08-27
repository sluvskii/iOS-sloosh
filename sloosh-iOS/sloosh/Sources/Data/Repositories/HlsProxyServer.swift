import Foundation
import Network
import os.log

import UIKit

class HlsProxyServer {
    static let shared = HlsProxyServer()
    private var listener: NWListener?
    private var _isListenerAlive = false // надёжный флаг: false если .failed/.cancelled
    
    var isListenerAlive: Bool {
        stateLock.withLock { _isListenerAlive }
    }

    private let queue = DispatchQueue(label: "com.sloosh.ios.hlsproxy", attributes: .concurrent)
    private let stateLock = NSLock()
    private var headers: [String: String] = [:]
    private var voices: [String] = []
    private var subtitles: [PlaybackSubtitle] = []
    private var mediaId: String = ""
    private var preferredVoiceName: String? = nil
    private var currentMasterUrl: URL?
    
    var port: NWEndpoint.Port = 8181
    var fixedMasterUrl: String { "http://127.0.0.1:\(port.rawValue)/master.m3u8" }
    
    // We use a custom delegate to bypass SSL issues like in Android's buildTrustingClient
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpMaximumConnectionsPerHost = 20
        config.timeoutIntervalForRequest = 15
        let delegate = TrustAllSessionDelegate()
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }()
    
    private init() {
        NotificationCenter.default.addObserver(self, selector: #selector(appWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
    }
    
    @objc func appWillEnterForeground() {
        let params: (headers: [String: String], voices: [String], subtitles: [PlaybackSubtitle], mediaId: String)? = stateLock.withLock {
            // Перезапускаем если mediaId есть, но слушатель мёртв (nil или упавший)
            if !self.mediaId.isEmpty && !self._isListenerAlive {
                return (self.headers, self.voices, self.subtitles, self.mediaId)
            }
            return nil
        }
        
        if let p = params {
            print("HlsProxyServer: restarting listener on foreground (was dead)")
            // Очищаем мёртвый listener перед перезапуском
            stateLock.withLock {
                self.listener?.cancel()
                self.listener = nil
                self._isListenerAlive = false
            }
            start(headers: p.headers, voices: p.voices, subtitles: p.subtitles, mediaId: p.mediaId)
        }
    }
    
    func start(headers: [String: String], voices: [String] = [], subtitles: [PlaybackSubtitle] = [], mediaId: String = "", preferredVoiceName: String? = nil) {
        let isAlreadyRunning = stateLock.withLock {
            if !headers.isEmpty {
                self.headers = headers
            }
            if !voices.isEmpty {
                self.voices = voices
            }
            if !subtitles.isEmpty {
                self.subtitles = subtitles
            }
            if !mediaId.isEmpty {
                self.mediaId = mediaId
            }
            if let preferredVoiceName, !preferredVoiceName.isEmpty {
                self.preferredVoiceName = preferredVoiceName
            }
            // Блокируем повторный запуск если listener уже есть (пусть даже ещё не .ready)
            // или уже .ready. Это предотвращает двойное создание на одном порту.
            return self._isListenerAlive || self.listener != nil
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
                    self.stateLock.withLock { self._isListenerAlive = true }
                case .failed(let error):
                    print("HlsProxyServer listener failed: \(error)")
                    self.stateLock.withLock {
                        self.listener = nil
                        self._isListenerAlive = false
                    }
                case .cancelled:
                    print("HlsProxyServer listener cancelled")
                    self.stateLock.withLock {
                        self.listener = nil
                        self._isListenerAlive = false
                    }
                default: break
                }
            }
            // Сохраняем listener ДО start(), чтобы stateUpdateHandler не увидел nil при немедленном сбое
            stateLock.withLock {
                self.listener = newListener
                self._isListenerAlive = false // станет true только когда state == .ready
            }
            newListener.start(queue: queue)
            
            print("HlsProxyServer started on port \(port)")
        } catch {
            print("Failed to start HlsProxyServer: \(error)")
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
    
    func stop() {
        stateLock.withLock {
            listener?.cancel()
            listener = nil
            _isListenerAlive = false
            currentMasterUrl = nil
            self.voices = []
            self.subtitles = []
            self.mediaId = ""
            self.headers = [:]
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
                await fetchAndServe(realUrl: realUrl, isPlaylist: isPlaylist, incomingHeaders: incomingHeaders, connection: connection)
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
    
    private func fetchAndServe(realUrl: URL, isPlaylist: Bool, incomingHeaders: [String: String], connection: NWConnection) async {
        let (currentHeaders, currentVoices, currentSubtitles, currentMediaId) = stateLock.withLock {
            (self.headers, self.voices, self.subtitles, self.mediaId)
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
                var responseData: Data?
                var httpResponse: HTTPURLResponse?

                // Попробуем с ретраем до 3 раз при статусах 403 / 503 (кратковременный CDN handshake)
                for attempt in 0..<3 {
                    do {
                        let (data, response) = try await session.data(for: request)
                        if let resp = response as? HTTPURLResponse {
                            httpResponse = resp
                            responseData = data
                            if resp.statusCode == 200 {
                                break
                            }
                        }
                    } catch {
                        if attempt == 2 { throw error }
                    }
                    if attempt < 2 {
                        try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
                    }
                }

                guard let httpResp = httpResponse, let data = responseData else {
                    AppDiagnostics.shared.log("HlsProxyServer fetchAndServe: invalid response for \(realUrl)")
                    self.send404(on: connection)
                    return
                }

                let statusCode = httpResp.statusCode
                AppDiagnostics.shared.log("HlsProxyServer fetchAndServe: \(realUrl) returned \(statusCode)")

                guard statusCode == 200 else {
                    guard !Task.isCancelled else { return }
                    self.sendResponse(data: data, statusCode: statusCode, contentType: httpResp.mimeType ?? "text/plain", contentRange: nil, connection: connection)
                    return
                }

                if let content = String(data: data, encoding: .utf8), content.contains("#EXT") {
                    let finalUrl = httpResp.url ?? realUrl
                    let rewritten: String
                    if content.contains("#EXT-X-STREAM-INF") {
                        let playlistRewritten = PlaybackHlsRewriter.rewrite(
                            master: content,
                            voices: currentVoices,
                            subtitles: currentSubtitles,
                            mediaId: currentMediaId
                        )

                        AppDiagnostics.shared.log("HlsProxyServer: rewritten master playlist:\n\(playlistRewritten)")
                        rewritten = self.rewriteM3u8(content: playlistRewritten, baseUrl: finalUrl)
                    } else {
                        AppDiagnostics.shared.log("HlsProxyServer: playlist fallback:\n\(content)")
                        rewritten = self.rewriteM3u8(content: content, baseUrl: finalUrl)
                    }

                    let rewrittenData = rewritten.data(using: .utf8) ?? Data()
                    guard !Task.isCancelled else { return }
                    self.sendResponse(data: rewrittenData, statusCode: 200, contentType: "application/vnd.apple.mpegurl", contentRange: nil, connection: connection)
                } else {
                    guard !Task.isCancelled else { return }
                    self.sendResponse(data: data, statusCode: statusCode, contentType: "application/vnd.apple.mpegurl", contentRange: nil, connection: connection)
                }
            } else {
                let (data, response) = try await session.data(for: request)
                guard !Task.isCancelled else { return }
                guard let httpResponse = response as? HTTPURLResponse else {
                    self.send404(on: connection)
                    return
                }
                
                let statusCode = httpResponse.statusCode
                let contentType = resolveContentType(for: realUrl, httpResponse: httpResponse)
                let contentRange = httpResponse.value(forHTTPHeaderField: "Content-Range")
                
                self.sendResponse(data: data, statusCode: statusCode, contentType: contentType, contentRange: contentRange, connection: connection)
            }
        } catch {
            if Task.isCancelled { return }
            AppDiagnostics.shared.log("HlsProxyServer fetch failed: \(error)")
            self.send404(on: connection)
        }
    }
    
    private func rewriteM3u8(content: String, baseUrl: URL) -> String {
        let lines = content.components(separatedBy: .newlines)
        var result = [String]()
        var skipNextUri = false
        
        for line in lines {
            if line.isEmpty {
                if !skipNextUri { result.append(line) }
                continue
            }
            if line.hasPrefix("#") {
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
                            let proxied = proxyUrl(uriString, baseUrl: baseUrl)
                            modifiedLine.replaceSubrange(range, with: "URI=\"\(proxied)\"")
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
            
            let baseDir: URL
            if !cleanBaseUrl.pathExtension.isEmpty {
                baseDir = cleanBaseUrl.deletingLastPathComponent()
            } else {
                baseDir = cleanBaseUrl
            }
            
            if let resolvedUrl = URL(string: urlString, relativeTo: baseDir) {
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

    private func resolveContentType(for url: URL, httpResponse: HTTPURLResponse?) -> String {
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
}
