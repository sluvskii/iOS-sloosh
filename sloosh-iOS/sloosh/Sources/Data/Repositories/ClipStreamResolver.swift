import Foundation
import AVKit

public struct ResolvedClipPlayback: Sendable {
    public let url: URL
    public let headers: [String: String]
    public let qualityUrls: [String: URL]

    public init(url: URL, headers: [String: String], qualityUrls: [String: URL] = [:]) {
        self.url = url
        self.headers = headers
        self.qualityUrls = qualityUrls
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
                let allQualityVariants = (resolved["qualityVariants"] as? [[String: Any]]) ?? []
                var activeQualityVariants = allQualityVariants

                if let targetVoice = clip.translationName, !targetVoice.isEmpty {
                    let matchedVariant = findMatchingAudioVariant(in: audioVariants, for: targetVoice, isDedicatedIframe: true)
                    if let matchedVariant {
                        if let variantUrl = (matchedVariant["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                           !variantUrl.isEmpty {
                            resolvedUrlString = variantUrl
                        }
                        if let nestedQualities = matchedVariant["qualityVariants"] as? [[String: Any]], !nestedQualities.isEmpty {
                            activeQualityVariants = nestedQualities
                        }
                    }
                }

                // Строим карту доступных качеств, исключая AV1 кодеки
                var qualityMap: [String: URL] = [:]
                for variant in activeQualityVariants {
                    guard let rawLabel = variant["label"] as? String,
                          let rawUrl = variant["url"] as? String else { continue }
                    let label = normalizedQualityLabel(from: rawLabel)
                    let lowerLabel = label.lowercased()
                    let lowerUrl = rawUrl.lowercased()
                    if lowerLabel.contains("av1") || lowerLabel.contains("av01") || lowerUrl.contains("av1") || lowerUrl.contains("av01") {
                        continue
                    }
                    if let url = URL(string: rawUrl.trimmingCharacters(in: .whitespacesAndNewlines)) {
                        qualityMap[label] = url
                    }
                }

                // Выбираем лучший URL: учитываем предпочтение пользователя, иначе 1080p / максимальное
                let savedQuality = UserDefaults.standard.string(forKey: "sloosh_moments_quality") ?? "Авто"
                var chosenUrl: URL? = nil

                if savedQuality != "Авто", let preferredUrl = qualityMap[savedQuality] {
                    chosenUrl = preferredUrl
                }

                if chosenUrl == nil {
                    let sortedKeys = qualityMap.keys.sorted { qualityHeight($0) > qualityHeight($1) }
                    if let best = sortedKeys.first(where: { qualityHeight($0) <= 1080 }),
                       let bestUrl = qualityMap[best] {
                        chosenUrl = bestUrl
                    }
                }

                if chosenUrl == nil, let fallback = URL(string: resolvedUrlString) {
                    let lowerFallback = fallback.absoluteString.lowercased()
                    if !lowerFallback.contains("av1") && !lowerFallback.contains("av01") {
                        chosenUrl = fallback
                    } else if let nonAv1 = qualityMap.values.first {
                        chosenUrl = nonAv1
                    }
                }

                if let chosenUrl {
                    var headers = (resolved["headers"] as? [String: String]) ?? [:]
                    if headers["Referer"] == nil && headers["referer"] == nil {
                        headers["Referer"] = "https://api.alloha.tv/"
                    }
                    AppDiagnostics.shared.log("[ClipStreamResolver] Successfully resolved clip=\(clip.id) quality=\(chosenUrl.lastPathComponent) host=\(chosenUrl.host ?? "") variants=\(qualityMap.keys)")
                    return ResolvedClipPlayback(url: chosenUrl, headers: headers, qualityUrls: qualityMap)
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

    private func normalizedQualityLabel(from rawLabel: String?) -> String {
        let label = (rawLabel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return "Поток" }
        if label.lowercased().hasSuffix("p") { return label }
        if Int(label) != nil { return "\(label)p" }
        return label
    }

    private func qualityHeight(_ label: String) -> Int {
        let clean = label.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if clean == "4k" || clean == "2160p" || clean == "2160" { return 2160 }
        if clean == "2k" || clean == "1440p" || clean == "1440" { return 1440 }
        return Int(clean.replacingOccurrences(of: "p", with: "")) ?? 0
    }
}
