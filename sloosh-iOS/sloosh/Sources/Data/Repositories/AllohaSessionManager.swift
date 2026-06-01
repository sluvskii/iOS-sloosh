import Foundation

@MainActor
final class AllohaSessionManager {
    private var resolver: AllohaRuntimeResolver?
    private var resolveTask: Task<Void, Never>?
    private var proactiveRestartTask: Task<Void, Never>?
    private var lastIframeUrl: String = ""
    private var currentSessionIsRestart = false

    private(set) var currentM3u8Url: String = ""
    private(set) var lastQualityMap: [String: String] = [:]
    private(set) var lastSelectedQuality: String = ""

    var onStreamReady: ((String, String) -> Void)?
    var onError: ((String) -> Void)?

    func startSession(iframeUrl: String, isRestart: Bool = false) {
        resolveTask?.cancel()
        resolver?.cancel()
        resolver = AllohaRuntimeResolver()

        lastIframeUrl = iframeUrl
        currentSessionIsRestart = isRestart
        currentM3u8Url = ""
        lastQualityMap = [:]
        lastSelectedQuality = ""

        HlsProxyServer.shared.start(headers: [:])
        guard let resolver else { return }

        resolveTask = Task { [weak self] in
            do {
                let resolved = try await resolver.resolve(iframeUrl: iframeUrl)
                guard let self, !Task.isCancelled else { return }
                self.applyResolvedStream(resolved)
            } catch is CancellationError {
                return
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.onError?(error.localizedDescription)
            }
        }
    }

    func release() {
        resolveTask?.cancel()
        resolveTask = nil
        proactiveRestartTask?.cancel()
        proactiveRestartTask = nil
        resolver?.cancel()
        resolver = nil
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

    private func applyResolvedStream(_ resolved: [String: Any]) {
        guard let resolvedUrl = (resolved["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !resolvedUrl.isEmpty else {
            onError?("Не удалось получить поток")
            return
        }

        let headers = (resolved["headers"] as? [String: String]) ?? [:]
        let qualities = parseQualities(from: resolved, fallbackUrl: resolvedUrl)

        currentM3u8Url = resolvedUrl
        lastQualityMap = qualities
        lastSelectedQuality = qualities.first(where: { $0.value == resolvedUrl })?.key ?? "Авто"

        HlsProxyServer.shared.updateHeaders(headers)
        HlsProxyServer.shared.updateMasterUrl(resolvedUrl)

        if let ttl = playbackTTL(from: headers) {
            scheduleProactiveRestart(ttlSeconds: ttl)
        }

        if !currentSessionIsRestart {
            onStreamReady?("", resolvedUrl)
        }
    }

    private func parseQualities(from resolved: [String: Any], fallbackUrl: String) -> [String: String] {
        var parsed: [String: String] = ["Авто": fallbackUrl]

        let qualityVariants = (resolved["qualityVariants"] as? [[String: Any]]) ?? []
        for variant in qualityVariants {
            guard let url = variant["url"] as? String,
                  !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            let label = normalizedQualityLabel(from: variant["label"] as? String)
            parsed[label] = url
        }

        if parsed.count == 1,
           let audioVariants = resolved["audioVariants"] as? [[String: Any]],
           let firstAudio = audioVariants.first,
           let nestedVariants = firstAudio["qualityVariants"] as? [[String: Any]] {
            for variant in nestedVariants {
                guard let url = variant["url"] as? String,
                      !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    continue
                }
                let label = normalizedQualityLabel(from: variant["label"] as? String)
                parsed[label] = url
            }
        }

        return parsed
    }

    private func normalizedQualityLabel(from rawLabel: String?) -> String {
        let label = (rawLabel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return "Поток" }
        if label.lowercased().hasSuffix("p") { return label }
        if Int(label) != nil { return "\(label)p" }
        return label
    }

    private func playbackTTL(from headers: [String: String]) -> Int? {
        let ttlValue = headers["x-neo-config-ttl"] ?? headers["X-Neo-Config-Ttl"]
        guard let ttlValue, let ttl = Int(ttlValue), ttl > 0 else { return nil }
        return ttl
    }
}
