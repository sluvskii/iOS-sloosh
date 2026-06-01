import Foundation
import Network

class HlsProxyServer {
    static let shared = HlsProxyServer()
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.sloosh.ios.hlsproxy", attributes: .concurrent)
    private var headers: [String: String] = [:]
    private var voices: [String] = []
    private var subtitles: [CollapsSubtitle] = []
    private var mediaId: String = ""
    private var currentMasterUrl: URL?
    
    // We use a custom delegate to bypass SSL issues like in Android's buildTrustingClient
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        let delegate = TrustAllSessionDelegate()
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }()
    
    var port: NWEndpoint.Port = 8181
    var fixedMasterUrl: String { "http://127.0.0.1:\(port.rawValue)/master.m3u8" }
    
    func start(headers: [String: String], voices: [String] = [], subtitles: [CollapsSubtitle] = [], mediaId: String = "") {
        self.headers = headers
        self.voices = voices
        self.subtitles = subtitles
        self.mediaId = mediaId
        if listener != nil { return }
        
        do {
            listener = try NWListener(using: .tcp, on: port)
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            listener?.start(queue: queue)
            print("HlsProxyServer started on port \(port)")
        } catch {
            print("Failed to start HlsProxyServer: \(error)")
        }
    }

    func updateHeaders(_ headers: [String: String]) {
        self.headers = headers
    }

    func updateMasterUrl(_ urlString: String) {
        currentMasterUrl = URL(string: urlString)
    }
    
    func stop() {
        listener?.cancel()
        listener = nil
        currentMasterUrl = nil
    }
    
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(on: connection, data: Data())
    }
    
    private func receiveRequest(on connection: NWConnection, data: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] newData, _, isComplete, error in
            guard let self = self else { return }
            if error != nil {
                connection.cancel()
                return
            }
            
            var currentData = data
            if let newData = newData {
                currentData.append(newData)
            }
            
            if let requestString = String(data: currentData, encoding: .utf8),
               requestString.contains("\r\n\r\n") {
                self.processRequest(requestString, on: connection)
            } else if !isComplete {
                self.receiveRequest(on: connection, data: currentData)
            } else {
                connection.cancel()
            }
        }
    }
    
    private func processRequest(_ requestString: String, on connection: NWConnection) {
        let lines = requestString.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else {
            connection.cancel()
            return
        }
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2 else {
            connection.cancel()
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
            send404(on: connection)
            return
        }
        
        if urlComponents.path == "/master.m3u8" {
            guard let currentMasterUrl else {
                send404(on: connection)
                return
            }

            fetchAndServe(realUrl: currentMasterUrl, isPlaylist: true, incomingHeaders: incomingHeaders, connection: connection)
        } else if urlComponents.path.hasPrefix("/proxy"),
           let urlQuery = urlComponents.queryItems?.first(where: { $0.name == "url" })?.value {
            
            // Re-pad base64 string if necessary
            var base64String = urlQuery
            let remainder = base64String.count % 4
            if remainder > 0 {
                base64String = base64String.padding(toLength: base64String.count + 4 - remainder, withPad: "=", startingAt: 0)
            }
            // Replace url safe characters if they were used
            base64String = base64String.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            
            if let decodedData = Data(base64Encoded: base64String),
               let decodedString = String(data: decodedData, encoding: .utf8),
               let realUrl = URL(string: decodedString) {
                
                fetchAndServe(realUrl: realUrl, isPlaylist: decodedString.contains(".m3u8"), incomingHeaders: incomingHeaders, connection: connection)
            } else {
                send404(on: connection)
            }
        } else {
            send404(on: connection)
        }
    }
    
    private func fetchAndServe(realUrl: URL, isPlaylist: Bool, incomingHeaders: [String: String], connection: NWConnection) {
        var request = URLRequest(url: realUrl)
        for (k, v) in headers {
            request.setValue(v, forHTTPHeaderField: k)
        }
        if let range = incomingHeaders["range"] {
            request.setValue(range, forHTTPHeaderField: "Range")
        }
        
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self, let data = data, let httpResponse = response as? HTTPURLResponse else {
                self?.send404(on: connection)
                return
            }
            
            let statusCode = httpResponse.statusCode
            let contentRange = httpResponse.value(forHTTPHeaderField: "Content-Range")
            
            if isPlaylist, let content = String(data: data, encoding: .utf8) {
                let rewritten: String
                if content.contains("#EXT-X-STREAM-INF") && (!self.voices.isEmpty || !self.subtitles.isEmpty) {
                    let collapsRewritten = CollapsHlsRewriter.rewrite(
                        master: content,
                        voices: self.voices,
                        subtitles: self.subtitles,
                        mediaId: self.mediaId
                    )
                    rewritten = self.rewriteM3u8(content: collapsRewritten, baseUrl: realUrl)
                } else {
                    rewritten = self.rewriteM3u8(content: content, baseUrl: realUrl)
                }
                
                let rewrittenData = rewritten.data(using: .utf8)!
                self.sendResponse(data: rewrittenData, statusCode: 200, contentType: "application/vnd.apple.mpegurl", contentRange: nil, connection: connection)
            } else {
                let contentType = httpResponse.mimeType ?? "video/MP2T"
                self.sendResponse(data: data, statusCode: statusCode, contentType: contentType, contentRange: contentRange, connection: connection)
            }
        }
        task.resume()
    }
    
    private func rewriteM3u8(content: String, baseUrl: URL) -> String {
        let lines = content.components(separatedBy: .newlines)
        var result = [String]()
        
        for line in lines {
            if line.isEmpty {
                result.append(line)
                continue
            }
            if line.hasPrefix("#") {
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
                result.append(proxyUrl(line, baseUrl: baseUrl))
            }
        }
        return result.joined(separator: "\n")
    }
    
    private func proxyUrl(_ urlString: String, baseUrl: URL) -> String {
        let absoluteUrlString: String
        if urlString.hasPrefix("http") {
            absoluteUrlString = urlString
        } else {
            guard let resolvedUrl = URL(string: urlString, relativeTo: baseUrl) else {
                return urlString
            }
            absoluteUrlString = resolvedUrl.absoluteString
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
        let reason = statusCode == 206 ? "Partial Content" : "OK"
        var header = "HTTP/1.1 \(statusCode) \(reason)\r\nContent-Type: \(contentType)\r\nContent-Length: \(data.count)\r\nConnection: close\r\n"
        if let cr = contentRange {
            header += "Content-Range: \(cr)\r\n"
        }
        header += "Accept-Ranges: bytes\r\n\r\n"
        let headerData = header.data(using: .utf8)!
        
        connection.send(content: headerData, completion: .contentProcessed({ _ in
            connection.send(content: data, completion: .contentProcessed({ _ in
                connection.cancel()
            }))
        }))
    }
    
    private func send404(on connection: NWConnection) {
        let response = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: response.data(using: .utf8)!, completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }
}
