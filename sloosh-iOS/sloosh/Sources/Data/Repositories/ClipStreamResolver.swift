import Foundation
import AVKit

@MainActor
public final class ClipStreamResolver {
    public static let shared = ClipStreamResolver()

    private struct CachedStream {
        let streamUrl: URL
        let headers: [String: String]
        let expiresAt: Date
    }

    private var cache: [String: CachedStream] = [:]
    private let cacheTtl: TimeInterval = 600 // 10 minutes TTL
    private var activeTasks: [String: Task<URL?, Never>] = [:]

    private init() {}

    /// Resolves fresh authorized playback URL for a MovieClip through local HlsProxyServer
    public func resolveStreamUrl(for clip: MovieClip) async -> URL? {
        // 1. Check in-memory cache
        if let cached = cache[clip.id], cached.expiresAt > Date() {
            HlsProxyServer.shared.start(
                headers: cached.headers,
                mediaId: "clip_\(clip.id)",
                preferredVoiceName: clip.translationName
            )
            return proxiedPlaybackURL(for: cached.streamUrl) ?? cached.streamUrl
        }

        // 2. Inflight task deduplication
        if let existing = activeTasks[clip.id] {
            return await existing.value
        }

        let task = Task<URL?, Never> { @MainActor in
            defer { activeTasks.removeValue(forKey: clip.id) }
            return await doResolve(clip: clip)
        }
        activeTasks[clip.id] = task
        return await task.value
    }

    private func doResolve(clip: MovieClip) async -> URL? {
        // 1. Direct stream URL: instant resolution (< 10ms) without spinning up a headless WKWebView
        if let directStr = clip.streamUrl, !directStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let directUrl = URL(string: directStr.trimmingCharacters(in: .whitespacesAndNewlines)) {
            HlsProxyServer.shared.start(
                headers: [:],
                mediaId: "clip_\(clip.id)",
                preferredVoiceName: clip.translationName
            )
            let finalUrl = proxiedPlaybackURL(for: directUrl) ?? directUrl
            cache[clip.id] = CachedStream(
                streamUrl: finalUrl,
                headers: [:],
                expiresAt: Date().addingTimeInterval(cacheTtl)
            )
            return finalUrl
        }

        var targetIframe = clip.iframeUrl

        // 2. If iframeUrl is not directly present, query Alloha catalog
        if targetIframe == nil || targetIframe?.isEmpty == true {
            if let kpId = clip.kpId, kpId > 0 {
                if let res = try? await AllohaRepository.shared.fetchByKpId(kpId: kpId, tmdbId: clip.tmdbId, title: clip.title) {
                    if let season = clip.season, let episode = clip.episode {
                        if let sObj = res.seasons.first(where: { $0.season == season }),
                           let epObj = sObj.episodes.first(where: { $0.episode == episode }) {
                            if let trName = clip.translationName, let tr = epObj.translations.first(where: { allohaTranslationNamesMatch($0.name, trName) }) {
                                targetIframe = tr.iframeUrl
                            } else {
                                targetIframe = epObj.translations.first?.iframeUrl
                            }
                        }
                    } else if let movie = res.movie {
                        if let trName = clip.translationName, let tr = movie.translations.first(where: { allohaTranslationNamesMatch($0.name, trName) }) {
                            targetIframe = tr.iframeUrl
                        } else {
                            targetIframe = movie.translations.first?.iframeUrl ?? movie.iframeUrl
                        }
                    }
                }
            }
        }

        guard let iframe = targetIframe, !iframe.isEmpty else {
            return nil
        }

        do {
            let resolver = AllohaRuntimeResolver()
            let resolved = try await resolver.resolve(iframeUrl: iframe)

            var resolvedUrlString = (resolved["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let audioVariants = (resolved["audioVariants"] as? [[String: Any]]) ?? []

            if let targetVoice = clip.translationName, !targetVoice.isEmpty {
                let matchedVariant = findMatchingAudioVariant(in: audioVariants, for: targetVoice, isDedicatedIframe: true)
                if let matchedVariant,
                   let variantUrl = (matchedVariant["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !variantUrl.isEmpty {
                    resolvedUrlString = variantUrl
                }
            }

            guard let resolvedUrl = URL(string: resolvedUrlString) else {
                return nil
            }

            let headers = (resolved["headers"] as? [String: String]) ?? [:]

            // Cache positive result
            cache[clip.id] = CachedStream(
                streamUrl: resolvedUrl,
                headers: headers,
                expiresAt: Date().addingTimeInterval(cacheTtl)
            )

            // Start proxy server
            HlsProxyServer.shared.start(
                headers: headers,
                mediaId: "clip_\(clip.id)",
                preferredVoiceName: clip.translationName
            )

            let finalUrl = proxiedPlaybackURL(for: resolvedUrl) ?? resolvedUrl
            return finalUrl
        } catch {
            #if DEBUG
            print("[ClipStreamResolver] Stream resolution failed for clip \(clip.id): \(error)")
            #endif
            // Fallback to direct streamUrl if present
            if let directStr = clip.streamUrl, let directUrl = URL(string: directStr) {
                HlsProxyServer.shared.start(headers: [:], mediaId: "clip_\(clip.id)")
                return proxiedPlaybackURL(for: directUrl) ?? directUrl
            }
            return nil
        }
    }

    private func proxiedPlaybackURL(for sourceURL: URL) -> URL? {
        let absoluteUrlString = sourceURL.absoluteURL.absoluteString
        guard let encodedData = absoluteUrlString.data(using: .utf8) else { return nil }
        let encoded = encodedData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        let ext = sourceURL.pathExtension
        let pathSuffix = ext.isEmpty ? "stream.m3u8" : "stream.\(ext)"

        let baseString = "http://127.0.0.1:\(HlsProxyServer.shared.port.rawValue)/proxy/\(pathSuffix)?url=\(encoded)"
        return URL(string: baseString)
    }
}
