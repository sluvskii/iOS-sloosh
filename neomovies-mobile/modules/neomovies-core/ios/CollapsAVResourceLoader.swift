import AVFoundation
import Foundation

final class CollapsAVAssetBridge: NSObject {
    let asset: AVURLAsset
    private let delegate: CollapsResourceLoaderDelegate

    init(sourceURL: URL, headers: [String: String], rewrittenMaster: String? = nil) {
        let originalScheme = sourceURL.scheme ?? "https"
        var proxyComponents = URLComponents(url: sourceURL, resolvingAgainstBaseURL: false)
        proxyComponents?.scheme = "nmproxy-\(originalScheme)"
        let rewritten = proxyComponents?.url ?? sourceURL

        delegate = CollapsResourceLoaderDelegate(
            sourceURL: sourceURL,
            headers: headers,
            originalScheme: originalScheme,
            rewrittenMaster: rewrittenMaster
        )
        asset = AVURLAsset(url: rewritten)
        super.init()
        asset.resourceLoader.setDelegate(delegate, queue: DispatchQueue(label: "CollapsResourceLoader"))
    }
}

final class CollapsResourceLoaderDelegate: NSObject, AVAssetResourceLoaderDelegate {
    private let sourceURL: URL
    private let headers: [String: String]
    private let originalScheme: String
    private let rewrittenMaster: String?
    private let session: URLSession
    private var activeTasks: [ObjectIdentifier: URLSessionDataTask] = [:]

    init(sourceURL: URL, headers: [String: String], originalScheme: String, rewrittenMaster: String?) {
        self.sourceURL = sourceURL
        self.headers = headers
        self.originalScheme = originalScheme
        self.rewrittenMaster = rewrittenMaster
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        session = URLSession(configuration: config)
        super.init()
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        guard let requestURL = loadingRequest.request.url else {
            loadingRequest.finishLoading(with: URLError(.badURL))
            return false
        }

        if let rewrittenMaster, isMasterRequest(proxyURL: requestURL) {
            if let data = rewrittenMaster.data(using: .utf8) {
                if let infoRequest = loadingRequest.contentInformationRequest {
                    infoRequest.contentType = "application/vnd.apple.mpegurl"
                    infoRequest.contentLength = Int64(data.count)
                    infoRequest.isByteRangeAccessSupported = false
                }
                loadingRequest.dataRequest?.respond(with: data)
                loadingRequest.finishLoading()
                return true
            }
        }

        let resolvedURL = resolveURL(proxyURL: requestURL)
        var request = URLRequest(url: resolvedURL)
        request.httpMethod = "GET"
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            defer {
                if let self {
                    self.activeTasks.removeValue(forKey: ObjectIdentifier(loadingRequest))
                }
            }

            if let error {
                loadingRequest.finishLoading(with: error)
                return
            }

            guard let response = response as? HTTPURLResponse else {
                loadingRequest.finishLoading(with: URLError(.badServerResponse))
                return
            }

            if let infoRequest = loadingRequest.contentInformationRequest {
                infoRequest.contentType = response.mimeType
                infoRequest.contentLength = response.expectedContentLength
                infoRequest.isByteRangeAccessSupported = response.value(forHTTPHeaderField: "Accept-Ranges")?.contains("bytes") == true
            }

            if let data {
                loadingRequest.dataRequest?.respond(with: data)
            }
            loadingRequest.finishLoading()
        }

        activeTasks[ObjectIdentifier(loadingRequest)] = task
        task.resume()
        return true
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        let key = ObjectIdentifier(loadingRequest)
        activeTasks[key]?.cancel()
        activeTasks.removeValue(forKey: key)
    }

    private func resolveURL(proxyURL: URL) -> URL {
        var components = URLComponents(url: sourceURL, resolvingAgainstBaseURL: false)
        components?.scheme = originalScheme
        if proxyURL.path != "/" {
            components?.path = proxyURL.path
        }
        components?.query = proxyURL.query
        return components?.url ?? sourceURL
    }

    private func isMasterRequest(proxyURL: URL) -> Bool {
        proxyURL.path == sourceURL.path
    }
}
