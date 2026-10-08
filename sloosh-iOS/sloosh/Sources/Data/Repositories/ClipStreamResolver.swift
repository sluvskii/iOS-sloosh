import Foundation
import AVKit

public struct ResolvedClipStream {
    public let url: URL
    public let headers: [String: String]
}

@MainActor
public final class ClipStreamResolver {
    public static let shared = ClipStreamResolver()

    private struct CachedStream {
        let stream: ResolvedClipStream
        let expiresAt: Date
    }

    private var cache: [String: CachedStream] = [:]
    private let cacheTtl: TimeInterval = 600 // 10 minutes TTL
    private var activeTasks: [String: Task<ResolvedClipStream?, Never>] = [:]

    private init() {}

    /// Resolves fresh direct playback stream and headers for a MovieClip
    public func resolveStream(for clip: MovieClip) async -> ResolvedClipStream? {
        // 1. Check in-memory cache
        if let cached = cache[clip.id], cached.expiresAt > Date() {
            return cached.stream
        }

        // 2. Inflight task deduplication
        if let existing = activeTasks[clip.id] {
            return await existing.value
        }

        let task = Task<ResolvedClipStream?, Never> { @MainActor in
            defer { activeTasks.removeValue(forKey: clip.id) }
            return await doResolve(clip: clip)
        }
        activeTasks[clip.id] = task
        return await task.value
    }

    private func doResolve(clip: MovieClip) async -> ResolvedClipStream? {
        // 1. Direct stream URL: instant resolution (< 5ms) directly to CDN
        if let directStr = clip.streamUrl, !directStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let directUrl = URL(string: directStr.trimmingCharacters(in: .whitespacesAndNewlines)) {
            let realUrl = extractRealUrl(from: directUrl)
            let res = ResolvedClipStream(url: realUrl, headers: [:])
            cache[clip.id] = CachedStream(
                stream: res,
                expiresAt: Date().addingTimeInterval(cacheTtl)
            )
            return res
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
            let res = ResolvedClipStream(url: resolvedUrl, headers: headers)

            // Cache positive result
            cache[clip.id] = CachedStream(
                stream: res,
                expiresAt: Date().addingTimeInterval(cacheTtl)
            )

            return res
        } catch {
            #if DEBUG
            print("[ClipStreamResolver] Stream resolution failed for clip \(clip.id): \(error)")
            #endif
            if let directStr = clip.streamUrl, let directUrl = URL(string: directStr) {
                let realUrl = extractRealUrl(from: directUrl)
                return ResolvedClipStream(url: realUrl, headers: [:])
            }
            return nil
        }
    }

    private func extractRealUrl(from url: URL) -> URL {
        guard let host = url.host?.lowercased(), (host == "127.0.0.1" || host == "localhost"),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItem = components.queryItems?.first(where: { $0.name == "url" }),
              let base64String = queryItem.value else {
            return url
        }
        var base64 = base64String
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64.append("=")
        }
        guard let data = Data(base64Encoded: base64),
              let urlString = String(data: data, encoding: .utf8),
              let realUrl = URL(string: urlString) else {
            return url
        }
        return realUrl
    }
}
