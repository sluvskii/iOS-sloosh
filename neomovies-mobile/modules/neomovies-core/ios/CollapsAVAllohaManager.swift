import Foundation
import AVFoundation

/// Manages Alloha-specific functionality for AVPlayer
final class CollapsAVAllohaManager {
    
    // MARK: - Dependencies
    
    private weak var playbackProxy: AllohaHLSProxyServer?
    
    // MARK: - State
    
    private var allohaSessionRefreshTask: Task<Void, Never>?
    private var allohaRecoveryTask: Task<Void, Never>?
    
    // MARK: - Initialization
    
    init() {
        self.playbackProxy = nil
    }
    
    // MARK: - Public API
    
    /// Resolves an Alloha item if needed
    func resolveAllohaItemIfNeeded(_ item: CollapsAVPlaylistItem) async throws -> CollapsAVPlaylistItem {
        guard isAllohaPlaylistItem(item),
              let iframeUrl = item.headers["X-Neo-Alloha-Iframe"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !iframeUrl.isEmpty else {
            return item
        }

        let looksResolved = item.url.lowercased().contains(".m3u8") || item.url.lowercased().contains(".mp4") || item.url.lowercased().contains(".mpd")
        let hasSessionHeaders = !(item.headers["accepts-controls"] ?? item.headers["authorizations"] ?? "").isEmpty
        if looksResolved && hasSessionHeaders {
            return item
        }

        let resolved = try await awaitResolveAllohaStream(iframeUrl: iframeUrl)
        let resolvedUrl = resolved["url"] as? String ?? ""
        
        guard !resolvedUrl.isEmpty else {
            return item
        }
        
        let resolvedAudioVariants = ((resolved["audioVariants"] as? [[String: Any]]) ?? []).compactMap { variant -> CollapsAVAudioVariant? in
            guard let url = variant["url"] as? String, !url.isEmpty else { return nil }
            let title = (variant["title"] as? String) ?? ""
            let qualityVariants = ((variant["qualityVariants"] as? [[String: Any]]) ?? []).compactMap { qualityFromDictionary($0) }
            return CollapsAVAudioVariant(title: title, url: url, qualityVariants: qualityVariants)
        }
        let resolvedQualityVariants = ((resolved["qualityVariants"] as? [[String: Any]]) ?? []).compactMap { qualityFromDictionary($0) }

        let mergedHeaders = item.headers.merging((resolved["headers"] as? [String: String]) ?? [:]) { _, new in new }
        let subtitles = ((resolved["subtitles"] as? [[String: Any]]) ?? []).compactMap { subtitle -> CollapsSubtitle? in
            guard let url = subtitle["url"] as? String, !url.isEmpty else { return nil }
            let label = (subtitle["label"] as? String) ?? (subtitle["name"] as? String) ?? ""
            let language = (subtitle["language"] as? String) ?? ""
            return CollapsSubtitle(url: url, label: label, language: language)
        }

        let resolvedItem = CollapsAVPlaylistItem(
            mediaId: item.mediaId,
            title: item.title,
            url: resolvedUrl,
            headers: mergedHeaders,
            season: item.season,
            episode: item.episode,
            voiceovers: item.voiceovers,
            subtitles: subtitles.isEmpty ? item.subtitles : subtitles,
            audioVariants: resolvedAudioVariants.isEmpty ? item.audioVariants : resolvedAudioVariants,
            qualityVariants: resolvedQualityVariants.isEmpty ? item.qualityVariants : resolvedQualityVariants
        )
        return resolvedItem
    }
    
    /// Starts Alloha session refresh if needed
    func startAllohaSessionRefreshIfNeeded(itemMeta: CollapsAVPlaylistItem) {
        allohaSessionRefreshTask?.cancel()
        allohaSessionRefreshTask = nil

        guard let proxy = playbackProxy,
              let iframeUrl = itemMeta.headers["X-Neo-Alloha-Iframe"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !iframeUrl.isEmpty else {
            return
        }

        let ttlRaw = itemMeta.headers["x-neo-config-ttl"] ?? itemMeta.headers["X-Neo-Config-Ttl"] ?? ""
        let ttlSec = Int(ttlRaw) ?? 120
        let refreshDelaySec = max(30, ttlSec - 20)

        allohaSessionRefreshTask = Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: UInt64(refreshDelaySec) * 1_000_000_000)
                } catch {
                    return
                }
                if Task.isCancelled { return }
                do {
                    try await self.refreshAllohaProxySession(proxy: proxy, iframeUrl: iframeUrl)
                } catch {
                    continue
                }
            }
        }
    }
    
    /// Schedules immediate Alloha recovery
    func scheduleImmediateAllohaRecovery(for itemMeta: CollapsAVPlaylistItem, onRecovery: @escaping () -> Void) {
        guard let proxy = playbackProxy,
              let iframeUrl = itemMeta.headers["X-Neo-Alloha-Iframe"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !iframeUrl.isEmpty else {
            return
        }
        if let task = allohaRecoveryTask, !task.isCancelled {
            return
        }
        allohaRecoveryTask = Task.detached(priority: .high) { [weak self] in
            guard let self else { return }
            defer { self.allohaRecoveryTask = nil }
            do {
                try await self.refreshAllohaProxySession(proxy: proxy, iframeUrl: iframeUrl)
                await MainActor.run {
                    onRecovery()
                }
            } catch {}
        }
    }
    
    /// Cancels all Alloha tasks
    func cancelAllohaTasks() {
        allohaSessionRefreshTask?.cancel()
        allohaSessionRefreshTask = nil
        allohaRecoveryTask?.cancel()
        allohaRecoveryTask = nil
    }
    
    /// Checks if an item is an Alloha playlist item
    func isAllohaPlaylistItem(_ item: CollapsAVPlaylistItem) -> Bool {
        let iframe = item.headers["X-Neo-Alloha-Iframe"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !iframe.isEmpty
    }
    
    // MARK: - Private Helper Methods
    
    private func awaitResolveAllohaStream(iframeUrl: String) async throws -> [String: Any] {
        let resolver = await MainActor.run { AllohaRuntimeResolver() }
        let resolved = try await resolver.resolve(iframeUrl: iframeUrl)
        var resolvedUrl = resolved["url"] as? String ?? ""
        
        // Filter out AV1 and high qualities (>= 1440p) when selecting URL
        let resolvedQualityVariants = ((resolved["qualityVariants"] as? [[String: Any]]) ?? []).compactMap { qualityFromDictionary($0) }
        let resolvedAudioVariants = ((resolved["audioVariants"] as? [[String: Any]]) ?? []).compactMap { variant -> (url: String, qualities: [CollapsAVQualityOption])? in
            guard let url = variant["url"] as? String, !url.isEmpty else { return nil }
            let qualities = ((variant["qualityVariants"] as? [[String: Any]]) ?? []).compactMap { qualityFromDictionary($0) }
            return (url: url, qualities: qualities)
        }
        
        // Find a supported quality URL (not AV1, not >= 1440p)
        let supportedQuality = resolvedQualityVariants.first { option in
            let height = option.height ?? 0
            let label = option.label.lowercased()
            return !label.contains("av1") && !label.contains("av01") && height < 1440
        }
        if let supported = supportedQuality, let url = supported.url, !url.isEmpty {
            resolvedUrl = url
        } else if !resolvedAudioVariants.isEmpty {
            // Try audio variants
            for audioVariant in resolvedAudioVariants {
                let supported = audioVariant.qualities.first { option in
                    let height = option.height ?? 0
                    let label = option.label.lowercased()
                    return !label.contains("av1") && !label.contains("av01") && height < 1440
                }
                if let supported = supported, let url = supported.url, !url.isEmpty {
                    resolvedUrl = url
                    break
                }
            }
        }
        
        guard !resolvedUrl.isEmpty else {
            return resolved
        }
        
        var mutable = resolved
        mutable["url"] = resolvedUrl
        return mutable
    }
    
    private func qualityFromDictionary(_ quality: [String: Any]) -> CollapsAVQualityOption? {
        guard let qurl = quality["url"] as? String, !qurl.isEmpty else { return nil }
        let label = (quality["label"] as? String) ?? "Stream"
        let bitrate = quality["bitrate"] as? Double ?? quality["bandwidth"] as? Double ?? 0
        let height = quality["height"] as? Int ?? Self.heightFromQualityLabel(label)
        return CollapsAVQualityOption(index: 0, bitrate: bitrate, height: height, label: label, isAuto: false, url: qurl)
    }
    
    private static func heightFromQualityLabel(_ label: String) -> Int? {
        let lowercased = label.lowercased()
        if lowercased.contains("2160") || lowercased.contains("4k") { return 2160 }
        if lowercased.contains("1440") { return 1440 }
        if lowercased.contains("1080") { return 1080 }
        if lowercased.contains("720") { return 720 }
        if lowercased.contains("480") { return 480 }
        if lowercased.contains("360") { return 360 }
        if lowercased.contains("240") { return 240 }
        return nil
    }
    
    /// Refreshes Alloha proxy session with new credentials
    func refreshAllohaProxySession(proxy: AllohaHLSProxyServer, iframeUrl: String) async throws {
        let resolver = await MainActor.run { AllohaRuntimeResolver() }
        let resolved = try await resolver.resolve(iframeUrl: iframeUrl)
        guard let newUrlString = resolved["url"] as? String,
              let newURL = URL(string: newUrlString) else {
            return
        }
        let newHeaders = (resolved["headers"] as? [String: String]) ?? [:]
        proxy.updateHeaders(newHeaders)
        proxy.updateMasterURL(newURL)
    }
}
