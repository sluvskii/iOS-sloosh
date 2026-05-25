import Foundation

@MainActor
final class AllohaSessionManager: NSObject, AllohaParserDelegate {
    private var parser: AllohaParser?
    private var proactiveRestartTask: Task<Void, Never>?
    private var lastIframeUrl: String = ""
    private var currentSessionIsRestart = false
    private var configUpdateReceived = false

    private(set) var currentM3u8Url: String = ""
    private(set) var lastQualityMap: [String: String] = [:]
    private(set) var lastSelectedQuality: String = ""

    var onStreamReady: ((String, String) -> Void)?
    var onError: ((String) -> Void)?

    func startSession(iframeUrl: String, isRestart: Bool = false) {
        ensureInitialized()

        lastIframeUrl = iframeUrl
        currentSessionIsRestart = isRestart
        configUpdateReceived = false
        currentM3u8Url = ""
        lastQualityMap = [:]
        lastSelectedQuality = ""

        HlsProxyServer.shared.start(headers: [:])

        parser?.parse(iframeUrl: iframeUrl)
    }

    func release() {
        proactiveRestartTask?.cancel()
        proactiveRestartTask = nil
        parser?.release()
        parser = nil
    }

    private func ensureInitialized() {
        if parser == nil {
            let parser = AllohaParser()
            parser.delegate = self
            self.parser = parser
        }
    }

    private func scheduleProactiveRestart(ttlSeconds: Int) {
        proactiveRestartTask?.cancel()
        proactiveRestartTask = Task { [weak self] in
            guard let self = self else { return }
            let ttlNanoseconds = UInt64(max(ttlSeconds, 1)) * 1_000_000_000
            let leadNanoseconds = min<UInt64>(20_000_000_000, ttlNanoseconds / 2)
            let delayNanoseconds = max<UInt64>(1_000_000_000, ttlNanoseconds - leadNanoseconds)

            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled, !self.lastIframeUrl.isEmpty else { return }
            self.startSession(iframeUrl: self.lastIframeUrl, isRestart: true)
        }
    }

    private func parseQualities(from json: String) throws -> [String: String] {
        guard let data = json.data(using: .utf8),
              let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hlsSource = dict["hlsSource"] as? [[String: Any]],
              let firstSource = hlsSource.first,
              let quality = firstSource["quality"] as? [String: String] else {
            throw NSError(domain: "AllohaSessionManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Не удалось получить поток"])
        }

        var parsed: [String: String] = [:]
        for (key, value) in quality {
            let link = value.components(separatedBy: " or ").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !link.isEmpty else { continue }
            parsed[key] = link.hasPrefix("//") ? "https:\(link)" : link
        }

        if parsed.isEmpty {
            throw NSError(domain: "AllohaSessionManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Не удалось получить качества потока"])
        }

        return parsed
    }

    private func pickBestQuality(from qualities: [String: String]) -> String {
        let ordered = ["1080", "720", "480", "360", "1440", "2160"]
        return ordered.first(where: { qualities[$0] != nil }) ?? qualities.keys.sorted().first ?? ""
    }

    func onHlsLinksReceived(json: String, extraHeaders: [String: String]) {
        do {
            let qualities = try parseQualities(from: json)
            let bestKey = pickBestQuality(from: qualities)
            guard let bestUrl = qualities[bestKey] ?? qualities.values.sorted().first else {
                throw NSError(domain: "AllohaSessionManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Не удалось выбрать поток"])
            }

            lastQualityMap = qualities
            lastSelectedQuality = bestKey
            currentM3u8Url = bestUrl

            HlsProxyServer.shared.updateHeaders(extraHeaders)

            if !currentSessionIsRestart {
                HlsProxyServer.shared.updateMasterUrl(bestUrl)
                onStreamReady?(json, bestUrl)
            }
        } catch {
            onError?(error.localizedDescription)
        }
    }

    func onConfigUpdate(edgeHash: String, ttlSeconds: Int, extraHeaders: [String: String]) {
        var mergedHeaders = extraHeaders
        mergedHeaders["accepts-controls"] = edgeHash
        HlsProxyServer.shared.updateHeaders(mergedHeaders)

        scheduleProactiveRestart(ttlSeconds: ttlSeconds)

        if !configUpdateReceived {
            configUpdateReceived = true
            if !currentM3u8Url.isEmpty {
                HlsProxyServer.shared.updateMasterUrl(currentM3u8Url)
            }
        }
    }

    func onM3u8Refreshed(url: String, extraHeaders: [String: String]) {
        currentM3u8Url = url
        HlsProxyServer.shared.updateHeaders(extraHeaders)

        if configUpdateReceived || currentSessionIsRestart {
            HlsProxyServer.shared.updateMasterUrl(url)
        }
    }

    func onStreamHeadersUpdated(extraHeaders: [String: String]) {
        HlsProxyServer.shared.updateHeaders(extraHeaders)
    }

    func onError(error: String) {
        onError?(error)
    }
}
