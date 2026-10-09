import Foundation
import AVKit

public struct ResolvedClipPlayback: Sendable {
    public let url: URL
    public let headers: [String: String]

    public init(url: URL, headers: [String: String]) {
        self.url = url
        self.headers = headers
    }
}

@MainActor
public final class ClipStreamResolver {
    public static let shared = ClipStreamResolver()

    private var cache: [String: (playback: ResolvedClipPlayback, expiresAt: Date)] = [:]
    private let cacheTtl: TimeInterval = 600 // 10 minutes TTL
    private var activeTasks: [String: Task<ResolvedClipPlayback?, Never>] = [:]

    private init() {}

    /// Invalidate cache for a specific clip ID
    public func invalidate(clipId: String) {
        cache.removeValue(forKey: clipId)
    }

    /// Resolves fresh authorized playback stream for a MovieClip without proxy collision
    public func resolveClip(for clip: MovieClip) async -> ResolvedClipPlayback? {
        let now = Date()
        // 1. Check in-memory cache
        if let cached = cache[clip.id], cached.expiresAt > now {
            return cached.playback
        }

        // 2. Inflight task deduplication
        if let existing = activeTasks[clip.id] {
            return await existing.value
        }

        let task = Task<ResolvedClipPlayback?, Never> { @MainActor in
            defer { activeTasks.removeValue(forKey: clip.id) }
            return await doResolve(clip: clip)
        }
        activeTasks[clip.id] = task
        let result = await task.value
        if let result {
            cache[clip.id] = (playback: result, expiresAt: Date().addingTimeInterval(cacheTtl))
        }
        return result
    }

    /// Resolves direct stream URL (for backward compatibility)
    public func resolveStreamUrl(for clip: MovieClip) async -> URL? {
        let resolved = await resolveClip(for: clip)
        return resolved?.url
    }

    private func doResolve(clip: MovieClip) async -> ResolvedClipPlayback? {
        AppDiagnostics.shared.log("[ClipStreamResolver] Resolving clip=\(clip.id) kpId=\(clip.kpId ?? 0) tmdbId=\(clip.tmdbId ?? 0) title=\(clip.title)")
        _ = await AllohaRepository.shared.ensureTokensLoaded()
        var targetIframe: String? = nil

        // 1. Query Alloha dynamic catalog using kpId, tmdbId or title
        let kpId = clip.kpId ?? 0
        if kpId > 0 || (clip.tmdbId != nil && clip.tmdbId! > 0) || !clip.title.isEmpty {
            if let res = try? await AllohaRepository.shared.fetchByKpId(kpId: kpId, tmdbId: clip.tmdbId, title: clip.title) {
                if let season = clip.season, let episode = clip.episode {
                    if let sObj = res.seasons.first(where: { $0.season == season }),
                       let epObj = sObj.episodes.first(where: { $0.episode == episode }) {
                        if let trName = clip.translationName,
                           let tr = epObj.translations.first(where: { allohaTranslationNamesMatch($0.name, trName, exactOnly: true) })
                                ?? epObj.translations.first(where: { allohaTranslationNamesMatch($0.name, trName, exactOnly: false) }) {
                            targetIframe = tr.iframeUrl
                        } else {
                            targetIframe = epObj.translations.first?.iframeUrl
                        }
                    }
                } else if let movie = res.movie {
                    if let trName = clip.translationName,
                       let tr = movie.translations.first(where: { allohaTranslationNamesMatch($0.name, trName, exactOnly: true) })
                            ?? movie.translations.first(where: { allohaTranslationNamesMatch($0.name, trName, exactOnly: false) }) {
                        targetIframe = tr.iframeUrl
                    } else {
                        targetIframe = movie.translations.first?.iframeUrl ?? movie.iframeUrl
                    }
                }
            }
        }

        // 2. Fallback to saved clip.iframeUrl if dynamic query didn't yield an iframe
        if (targetIframe == nil || targetIframe?.isEmpty == true),
           let savedIframe = clip.iframeUrl, !savedIframe.isEmpty {
            targetIframe = savedIframe
        }

        // 3. Resolve stream via AllohaRuntimeResolver
        if let iframe = targetIframe, !iframe.isEmpty {
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

                if let resolvedUrl = URL(string: resolvedUrlString) {
                    var headers = (resolved["headers"] as? [String: String]) ?? [:]
                    if headers["Referer"] == nil && headers["referer"] == nil {
                        headers["Referer"] = "https://api.alloha.tv/"
                    }
                    AppDiagnostics.shared.log("[ClipStreamResolver] Successfully resolved clip=\(clip.id) host=\(resolvedUrl.host ?? "")")
                    return ResolvedClipPlayback(url: resolvedUrl, headers: headers)
                }
            } catch {
                AppDiagnostics.shared.log("[ClipStreamResolver] Stream resolution failed for clip \(clip.id): \(error)")
            }
        }

        // 4. Last resort fallback: direct streamUrl (if present and not localhost proxy)
        if let directStr = clip.streamUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
           !directStr.isEmpty,
           let directUrl = URL(string: directStr) {
            let realUrl = extractRealUrl(from: directUrl)
            if let host = realUrl.host?.lowercased(), host != "127.0.0.1" && host != "localhost" {
                AppDiagnostics.shared.log("[ClipStreamResolver] Using direct streamUrl for clip=\(clip.id)")
                return ResolvedClipPlayback(url: realUrl, headers: ["Referer": "https://api.alloha.tv/"])
            }
        }

        AppDiagnostics.shared.log("[ClipStreamResolver] Failed to resolve stream for clip=\(clip.id)")
        return nil
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
