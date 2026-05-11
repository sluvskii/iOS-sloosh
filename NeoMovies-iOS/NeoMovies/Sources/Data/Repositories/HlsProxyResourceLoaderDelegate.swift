import Foundation
import AVFoundation

class HlsProxyResourceLoaderDelegate: NSObject, AVAssetResourceLoaderDelegate, URLSessionDataDelegate, URLSessionDelegate {
    private let headers: [String: String]
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    
    private class TaskState {
        let loadingRequest: AVAssetResourceLoadingRequest
        var data = Data()
        var isPlaylist: Bool = false
        var response: HTTPURLResponse?
        
        init(loadingRequest: AVAssetResourceLoadingRequest) {
            self.loadingRequest = loadingRequest
        }
    }
    
    private var taskStates = [URLSessionTask: TaskState]()
    private let queue = DispatchQueue(label: "com.neomovies.hlsproxy")
    
    init(headers: [String: String]) {
        self.headers = headers
        super.init()
    }
    
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        guard let url = loadingRequest.request.url,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }
        
        let originalUrlString = components.string ?? ""
        var isPlaylist = originalUrlString.contains(".m3u8")
        
        // Decode proxied absolute URLs
        var realUrl: URL
        if components.path.hasPrefix("/proxy") {
            guard let urlQuery = components.queryItems?.first(where: { $0.name == "url" })?.value,
                  let decodedData = Data(base64Encoded: urlQuery),
                  let decodedString = String(data: decodedData, encoding: .utf8),
                  let decodedUrl = URL(string: decodedString) else {
                return false
            }
            realUrl = decodedUrl
            isPlaylist = decodedString.contains(".m3u8")
        } else {
            if components.scheme == "neoproxy" {
                components.scheme = "https"
            } else if components.scheme == "neoproxy-http" {
                components.scheme = "http"
            }
            guard let resolvedUrl = components.url else { return false }
            realUrl = resolvedUrl
        }
        
        var request = URLRequest(url: realUrl)
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        if let dataRequest = loadingRequest.dataRequest {
            let lower = dataRequest.requestedOffset
            if lower > 0 || !dataRequest.requestsAllDataToEndOfResource {
                if dataRequest.requestsAllDataToEndOfResource {
                    request.setValue("bytes=\(lower)-", forHTTPHeaderField: "Range")
                } else {
                    let upper = lower + Int64(dataRequest.requestedLength) - 1
                    request.setValue("bytes=\(lower)-\(upper)", forHTTPHeaderField: "Range")
                }
            }
        }
        
        let task = session.dataTask(with: request)
        let state = TaskState(loadingRequest: loadingRequest)
        state.isPlaylist = isPlaylist
        queue.sync {
            taskStates[task] = state
        }
        task.resume()
        
        return true
    }
    
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        queue.sync {
            if let task = taskStates.first(where: { $0.value.loadingRequest == loadingRequest })?.key {
                task.cancel()
                taskStates.removeValue(forKey: task)
            }
        }
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        queue.sync {
            if let state = taskStates[dataTask], let httpResponse = response as? HTTPURLResponse {
                state.response = httpResponse
                
                if !state.isPlaylist {
                    let loadingRequest = state.loadingRequest
                    loadingRequest.contentInformationRequest?.contentType = httpResponse.mimeType
                    loadingRequest.contentInformationRequest?.contentLength = httpResponse.expectedContentLength
                    if let rangeString = httpResponse.allHeaderFields["Content-Range"] as? String,
                       let totalString = rangeString.components(separatedBy: "/").last,
                       let total = Int64(totalString) {
                        loadingRequest.contentInformationRequest?.contentLength = total
                    }
                    loadingRequest.contentInformationRequest?.isByteRangeAccessSupported = true
                    
                    // Respond with response to avoid playback stuck
                    loadingRequest.response = httpResponse
                }
            }
        }
        completionHandler(.allow)
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        queue.sync {
            if let state = taskStates[dataTask] {
                if state.isPlaylist {
                    state.data.append(data)
                } else {
                    state.loadingRequest.dataRequest?.respond(with: data)
                }
            }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        var stateToProcess: TaskState?
        queue.sync {
            stateToProcess = taskStates[task]
            taskStates.removeValue(forKey: task)
        }
        
        if let state = stateToProcess {
            let loadingRequest = state.loadingRequest
            
            if let error = error as NSError? {
                if error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled {
                    // Cancelled
                } else {
                    loadingRequest.finishLoading(with: error)
                }
            } else {
                if state.isPlaylist {
                    if let content = String(data: state.data, encoding: .utf8),
                       let url = task.currentRequest?.url ?? task.originalRequest?.url {
                        let rewritten = rewriteM3u8(content: content, baseUrl: url)
                        let rewrittenData = rewritten.data(using: .utf8)!
                        
                        loadingRequest.contentInformationRequest?.contentType = state.response?.mimeType ?? "application/vnd.apple.mpegurl"
                        loadingRequest.contentInformationRequest?.contentLength = Int64(rewrittenData.count)
                        loadingRequest.contentInformationRequest?.isByteRangeAccessSupported = false
                        
                        if let response = state.response {
                            loadingRequest.response = response
                        }
                        
                        loadingRequest.dataRequest?.respond(with: rewrittenData)
                    } else {
                        if let response = state.response {
                            loadingRequest.response = response
                        }
                        loadingRequest.dataRequest?.respond(with: state.data)
                    }
                }
                loadingRequest.finishLoading()
            }
        }
    }
    
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let serverTrust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
            return
        }
        completionHandler(.performDefaultHandling, nil)
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
        
        guard let encoded = absoluteUrlString.data(using: .utf8)?.base64EncodedString() else {
            return urlString
        }
        
        let isM3u8 = absoluteUrlString.contains(".m3u8")
        let ext = isM3u8 ? ".m3u8" : ".ts"
        
        var comp = URLComponents(string: "neoproxy://127.0.0.1/proxy\(ext)")!
        comp.queryItems = [URLQueryItem(name: "url", value: encoded)]
        return comp.string ?? urlString
    }
}
