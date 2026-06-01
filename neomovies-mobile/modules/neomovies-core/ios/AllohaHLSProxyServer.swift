import Foundation
import Network
import os.log

final class AllohaHLSProxyServer {
    private static let logger = OSLog(subsystem: "com.neo.neomovies", category: "AllohaHLSProxy")
    var onRecoverableUpstreamFailure: (() -> Void)?
    private var masterURL: URL
    private var headers: [String: String]
    private let routeBase: String
    private let masterPath: String
    private let proxyPathPrefix: String
    private let queue = DispatchQueue(label: "ru.neomovies.hls-proxy")
    private let stateLock = NSLock()
    private var listener: NWListener?
    private var recoveryNotifiedAt: Date?

    init(masterURL: URL, headers: [String: String], routeBase: String) {
        self.masterURL = masterURL
        self.headers = headers
        let sanitized = routeBase
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .replacingOccurrences(of: "//+", with: "/", options: .regularExpression)
        self.routeBase = sanitized.isEmpty ? "stream" : sanitized
        self.masterPath = "/\(self.routeBase)/master.m3u8"
        self.proxyPathPrefix = "/\(self.routeBase)/proxy"
    }

    func start() throws -> URL {
        let listener = try NWListener(using: .tcp, on: .any)
        self.listener = listener

        let startSemaphore = DispatchSemaphore(value: 0)
        var startError: Error?

        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                startSemaphore.signal()
            case .failed(let error):
                startError = error
                startSemaphore.signal()
            default:
                break
            }
        }
        listener.start(queue: queue)

        if startSemaphore.wait(timeout: .now() + 3) == .timedOut {
            throw AllohaHLSProxyError.startTimedOut
        }
        if let startError {
            throw startError
        }
        guard let port = listener.port?.rawValue,
              let url = URL(string: "http://127.0.0.1:\(port)\(masterPath)") else {
            throw AllohaHLSProxyError.invalidLocalURL
        }
        os_log("start port=%{public}d routeBase=%{public}s master=%{public}s", log: Self.logger, type: .info, port, routeBase, masterURL.absoluteString)

        return url
    }

    func stop() {
        os_log("stop", log: Self.logger, type: .info)
        listener?.cancel()
        listener = nil
    }

    func updateMasterURL(_ url: URL) {
        stateLock.lock()
        masterURL = url
        stateLock.unlock()
        os_log("update master=%{public}s", log: Self.logger, type: .info, url.absoluteString)
    }

    func updateHeaders(_ newHeaders: [String: String]) {
        stateLock.lock()
        headers.merge(newHeaders) { _, new in new }
        let count = headers.count
        stateLock.unlock()
        os_log("update headers count=%{public}d", log: Self.logger, type: .debug, count)
    }

    private func currentMasterURL() -> URL {
        stateLock.lock()
        let value = masterURL
        stateLock.unlock()
        return value
    }

    private func currentHeaders() -> [String: String] {
        stateLock.lock()
        let value = headers
        stateLock.unlock()
        return value
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, _, _ in
            guard let self else {
                connection.cancel()
                return
            }

            guard let data,
                  let rawRequest = String(data: data, encoding: .utf8),
                  let request = self.request(from: rawRequest) else {
                self.send(status: 400, contentType: "text/plain", body: Data("Bad Request".utf8), on: connection)
                return
            }

            Task {
                let response = await self.response(for: request)
                self.send(status: response.status, contentType: response.contentType, headers: response.headers, body: response.body, on: connection)
            }
        }
    }

    private func response(for request: AllohaHLSProxyRequest) async -> AllohaHLSProxyResponse {
        os_log("request method=%{public}s path=%{public}s", log: Self.logger, type: .debug, request.method, request.path)
        if request.method == "HEAD" {
            return AllohaHLSProxyResponse(status: 200, contentType: "application/octet-stream", headers: ["Accept-Ranges": "bytes"], body: Data())
        }

        if request.path == masterPath {
            return await playlistResponse(for: currentMasterURL(), request: request)
        }

        guard request.path.hasPrefix(proxyPathPrefix),
              let originalURL = originalURL(from: request.path) else {
            return AllohaHLSProxyResponse(status: 404, contentType: "text/plain", body: Data("Not Found".utf8))
        }

        if originalURL.path.lowercased().contains(".m3u8") {
            return await playlistResponse(for: originalURL, request: request)
        }

        return await dataResponse(for: originalURL, request: request)
    }

    private func playlistResponse(for url: URL, request: AllohaHLSProxyRequest) async -> AllohaHLSProxyResponse {
        do {
            let fetched = try await fetch(url, request: request)
            guard let playlist = String(data: fetched.data, encoding: .utf8) else {
                return AllohaHLSProxyResponse(status: 502, contentType: "text/plain", body: Data("Invalid playlist".utf8))
            }

            let rewritten = rewritePlaylist(playlist, baseURL: url)
            return AllohaHLSProxyResponse(
                status: 200,
                contentType: "application/vnd.apple.mpegurl",
                headers: ["Accept-Ranges": "bytes"],
                body: Data(rewritten.utf8)
            )
        } catch {
            os_log("playlist error url=%{public}s err=%{public}s", log: Self.logger, type: .error, url.absoluteString, String(describing: error))
            return AllohaHLSProxyResponse(status: 502, contentType: "text/plain", body: Data("Playlist fetch failed".utf8))
        }
    }

    private func dataResponse(for url: URL, request: AllohaHLSProxyRequest) async -> AllohaHLSProxyResponse {
        do {
            let fetched = try await fetch(url, request: request)
            return AllohaHLSProxyResponse(
                status: fetched.status,
                contentType: fetched.contentType ?? contentType(for: url),
                headers: fetched.headers.merging(["Accept-Ranges": "bytes"]) { current, _ in current },
                body: fetched.data
            )
        } catch {
            os_log("segment error url=%{public}s err=%{public}s", log: Self.logger, type: .error, url.absoluteString, String(describing: error))
            return AllohaHLSProxyResponse(status: 502, contentType: "text/plain", body: Data("Segment fetch failed".utf8))
        }
    }

    private func fetch(_ url: URL, request incomingRequest: AllohaHLSProxyRequest) async throws -> AllohaHLSFetchResponse {
        var request = URLRequest(url: url)
        currentHeaders().forEach { key, value in request.setValue(value, forHTTPHeaderField: key) }
        if request.value(forHTTPHeaderField: "User-Agent") == nil {
            request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64)", forHTTPHeaderField: "User-Agent")
        }
        if let range = incomingRequest.headers["range"] {
            request.setValue(range, forHTTPHeaderField: "Range")
        }
        if request.value(forHTTPHeaderField: "Accept") == nil {
            request.setValue("*/*", forHTTPHeaderField: "Accept")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let preview = String(data: data.prefix(200), encoding: .utf8) ?? "<non-utf8>"
            os_log("upstream fail status=%{public}d url=%{public}s body=%{public}s", log: Self.logger, type: .error, status, url.absoluteString, preview)
            notifyRecoverableFailureIfNeeded(status: status)
            throw AllohaHLSProxyError.fetchFailed
        }
        os_log("upstream ok status=%{public}d url=%{public}s size=%{public}d", log: Self.logger, type: .debug, httpResponse.statusCode, url.absoluteString, data.count)
        return AllohaHLSFetchResponse(
            status: httpResponse.statusCode,
            contentType: httpResponse.value(forHTTPHeaderField: "Content-Type"),
            headers: forwardedResponseHeaders(from: httpResponse),
            data: data
        )
    }

    private func notifyRecoverableFailureIfNeeded(status: Int) {
        guard [403, 404, 500, 502, 503].contains(status) else { return }
        stateLock.lock()
        let now = Date()
        let shouldNotify: Bool
        if let last = recoveryNotifiedAt, now.timeIntervalSince(last) < 5 {
            shouldNotify = false
        } else {
            recoveryNotifiedAt = now
            shouldNotify = true
        }
        let handler = onRecoverableUpstreamFailure
        stateLock.unlock()
        guard shouldNotify else { return }
        os_log("trigger recoverable refresh status=%{public}d", log: Self.logger, type: .info, status)
        handler?()
    }

    private func rewritePlaylist(_ playlist: String, baseURL: URL) -> String {
        playlist
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { rewritePlaylistLine($0, baseURL: baseURL) }
            .joined(separator: "\n")
    }

    private func rewritePlaylistLine(_ line: String, baseURL: URL) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return line }
        if trimmed.hasPrefix("#") {
            return rewriteAttributeURIs(in: line, baseURL: baseURL)
        }
        guard let absoluteURL = URL(string: trimmed, relativeTo: baseURL)?.absoluteURL else { return line }
        return proxyURL(for: absoluteURL).absoluteString
    }

    private func rewriteAttributeURIs(in line: String, baseURL: URL) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"URI=\"([^\"]+)\""#) else { return line }
        let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
        var rewritten = line
        for match in regex.matches(in: line, range: nsRange).reversed() {
            guard let uriRange = Range(match.range(at: 1), in: line) else { continue }
            let rawURI = String(line[uriRange])
            guard rawURI != "none",
                  let absoluteURL = URL(string: rawURI, relativeTo: baseURL)?.absoluteURL else {
                continue
            }
            rewritten.replaceSubrange(uriRange, with: proxyURL(for: absoluteURL).absoluteString)
        }
        return rewritten
    }

    private func proxyURL(for url: URL) -> URL {
        let encoded = Data(url.absoluteString.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let port = listener?.port?.rawValue ?? 0
        return URL(string: "http://127.0.0.1:\(port)\(proxyPathPrefix)?url=\(encoded)")!
    }

    private func originalURL(from path: String) -> URL? {
        guard let components = URLComponents(string: "http://127.0.0.1\(path)"),
              let value = components.queryItems?.first(where: { $0.name == "url" })?.value else {
            return nil
        }
        var base64 = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        guard let data = Data(base64Encoded: base64),
              let urlString = String(data: data, encoding: .utf8) else {
            return nil
        }
        return URL(string: urlString)
    }

    private func request(from rawRequest: String) -> AllohaHLSProxyRequest? {
        let lines = rawRequest.components(separatedBy: "\r\n")
        let firstLine = lines.first ?? ""
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard !line.isEmpty else { break }
            let split = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard split.count == 2 else { continue }
            headers[split[0].lowercased()] = split[1].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return AllohaHLSProxyRequest(method: String(parts[0]).uppercased(), path: String(parts[1]), headers: headers)
    }

    private func forwardedResponseHeaders(from response: HTTPURLResponse) -> [String: String] {
        var headers: [String: String] = [:]
        for key in ["Content-Range", "Accept-Ranges", "Cache-Control", "ETag", "Last-Modified"] {
            if let value = response.value(forHTTPHeaderField: key) {
                headers[key] = value
            }
        }
        return headers
    }

    private func send(status: Int, contentType: String, headers: [String: String] = [:], body: Data, on connection: NWConnection) {
        let reason = statusReason(for: status)
        var headerLines = [
            "HTTP/1.1 \(status) \(reason)",
            "Content-Type: \(contentType)",
            "Content-Length: \(body.count)"
        ]
        headerLines.append(contentsOf: headers.map { "\($0.key): \($0.value)" })
        headerLines.append("Access-Control-Allow-Origin: *")
        headerLines.append("Connection: close")
        let header = headerLines.joined(separator: "\r\n") + "\r\n\r\n"
        var response = Data(header.utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }

    private func contentType(for url: URL) -> String {
        let path = url.path.lowercased()
        if path.contains(".vtt") || path.contains(".webvtt") { return "text/vtt" }
        if path.contains(".m4s") || path.contains(".mp4") { return "video/mp4" }
        if path.contains(".aac") { return "audio/aac" }
        return "video/mp2t"
    }

    private func statusReason(for status: Int) -> String {
        switch status {
        case 206: return "Partial Content"
        case 200: return "OK"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        default: return "Bad Gateway"
        }
    }
}

private struct AllohaHLSProxyResponse {
    let status: Int
    let contentType: String
    var headers: [String: String] = [:]
    let body: Data
}

private struct AllohaHLSProxyRequest {
    let method: String
    let path: String
    let headers: [String: String]
}

private struct AllohaHLSFetchResponse {
    let status: Int
    let contentType: String?
    let headers: [String: String]
    let data: Data
}

private enum AllohaHLSProxyError: Error {
    case startTimedOut
    case invalidLocalURL
    case fetchFailed
}
