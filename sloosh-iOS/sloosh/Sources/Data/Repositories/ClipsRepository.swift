import Foundation
import UIKit
import SwiftUI
import Combine

@MainActor
public final class ClipsRepository: ObservableObject {
    public static let shared = ClipsRepository()

    @Published public private(set) var clips: [MovieClip] = []
    @Published public private(set) var likedClipIds: Set<String> = []
    @Published public private(set) var isLoading: Bool = false
    @Published public var errorMessage: String? = nil

    private let databaseBaseURL = "https://sloosh-77434-default-rtdb.firebaseio.com"
    private let likedClipsStorageKey = "sloosh_liked_clips_v1"
    private let viewedClipsStorageKey = "sloosh_viewed_clips_v1"
    private let feedDiskCacheKey = "sloosh_cached_clips_v1"

    @Published public private(set) var viewedClipIds: Set<String> = []

    private init() {
        loadLikedClipsFromDisk()
        loadViewedClipsFromDisk()
        loadFeedFromDisk()
    }

    // MARK: - URLs & Auth

    private func makeURL(path: String) async -> URL? {
        let safePath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        var urlString = "\(databaseBaseURL)/\(safePath).json"
        if let token = await AuthRepository.shared.ensureFreshToken(), !token.isEmpty {
            urlString += "?auth=\(token)"
        }
        return URL(string: urlString)
    }

    // MARK: - Feed Management

    public func loadFeedFromDisk() {
        guard let data = UserDefaults.standard.data(forKey: feedDiskCacheKey),
              let list = try? JSONDecoder().decode([MovieClip].self, from: data), !list.isEmpty else {
            return
        }
        self.clips = rankClips(list)
    }

    public func saveFeedToDisk(_ list: [MovieClip]) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: feedDiskCacheKey)
        }
    }

    public func fetchFeed(forceRefresh: Bool = false) async {
        if clips.isEmpty || forceRefresh {
            isLoading = true
        }
        defer { isLoading = false }

        guard let url = await makeURL(path: "media_stats/clips") else { return }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 10.0
            request.cachePolicy = .reloadIgnoringLocalCacheData

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                AppDiagnostics.shared.log("[ClipsRepository] fetchFeed non-2xx status: \(status)")
                return
            }

            // RTDB возвращает словарь [id: узел] или null.
            // Декодируем каждый клип ПО ОТДЕЛЬНОСТИ: один битый/осколочный узел
            // (например, «воскрешённый» лайком после удаления — узел из одного
            // likesCount) больше не роняет декодирование всего фида.
            var valid: [MovieClip] = []
            var shardIds: [String] = []

            if let raw = try? JSONSerialization.jsonObject(with: data),
               let dict = raw as? [String: Any] {
                for (key, value) in dict {
                    guard let node = value as? [String: Any] else { continue }
                    guard node["title"] != nil else {
                        // Осколок без данных клипа — подлежит очистке из базы
                        shardIds.append(key)
                        continue
                    }
                    guard let nodeData = try? JSONSerialization.data(withJSONObject: node),
                          let clip = try? JSONDecoder().decode(MovieClip.self, from: nodeData) else {
                        continue // битый, но не осколок — не показываем и не трогаем
                    }
                    valid.append(clip)
                }
            } else if let array = try? JSONDecoder().decode([MovieClip].self, from: data) {
                valid = array
            }

            // Мусорщик: убираем осколки из базы, чтобы они не попадали никому в фид
            if !shardIds.isEmpty {
                Task { [weak self] in
                    await self?.deleteShardNodes(shardIds)
                }
            }

            let fetched = rankClips(valid)
            self.clips = fetched
            saveFeedToDisk(fetched)
        } catch {
            AppDiagnostics.shared.log("[ClipsRepository] fetchFeed error: \(error.localizedDescription)")
        }
    }

    // MARK: - Smart Recommendations Algorithm (TikTok/Reels-style Cinema Discovery)

    public func rankClips(_ list: [MovieClip]) -> [MovieClip] {
        let favoriteIds = Set(FavoritesRepository.shared.favorites.compactMap { $0.mediaId ?? $0.id })
        let progressIds = Set(PlaybackProgressStore.shared.listAllMetadata().map { String($0.kpId) })
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)

        return list.sorted { c1, c2 in
            let score1 = recommendationScore(for: c1, favoriteIds: favoriteIds, progressIds: progressIds, nowMs: nowMs)
            let score2 = recommendationScore(for: c2, favoriteIds: favoriteIds, progressIds: progressIds, nowMs: nowMs)
            if abs(score1 - score2) > 0.001 {
                return score1 > score2
            }
            if c1.createdAtMs != c2.createdAtMs {
                return c1.createdAtMs > c2.createdAtMs
            }
            return c1.id > c2.id
        }
    }

    private func recommendationScore(for clip: MovieClip, favoriteIds: Set<String>, progressIds: Set<String>, nowMs: Int64) -> Double {
        // 1. Social engagement score (likes, comments, views)
        let engagementScore = Double(clip.likesCount * 2) + Double(clip.commentsCount * 3) + Double(clip.viewsCount) * 0.2

        // 2. Personal affinity boosts
        var affinityBoost: Double = 0.0
        let mediaIdStr = String(clip.mediaId)
        let kpIdStr = clip.kpId != nil ? String(clip.kpId!) : nil

        if favoriteIds.contains(mediaIdStr) || (kpIdStr != nil && favoriteIds.contains(kpIdStr!)) {
            affinityBoost += 80.0 // User bookmarked this movie
        }
        if progressIds.contains(mediaIdStr) || (kpIdStr != nil && progressIds.contains(kpIdStr!)) {
            affinityBoost += 50.0 // User is actively watching this movie
        }
        if likedClipIds.contains(clip.id) {
            affinityBoost += 25.0 // User previously liked this clip
        }

        // 3. Recency decay (fresh clips get boost to discover new moments)
        let ageHours = max(0.5, Double(nowMs - clip.createdAtMs) / (1000.0 * 3600.0))
        let freshnessBoost = max(0.0, 100.0 - (ageHours * 1.2))

        return engagementScore + affinityBoost + freshnessBoost
    }

    // MARK: - Publish Clip

    public func publishClip(_ clip: MovieClip) async throws {
        guard let url = await makeURL(path: "media_stats/clips/\(clip.id)") else {
            throw URLError(.badURL)
        }

        let encoder = JSONEncoder()
        let body = try encoder.encode(clip)

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        // Insert at the beginning of the feed
        self.clips.insert(clip, at: 0)
        saveFeedToDisk(self.clips)
    }

    // MARK: - Integrity (осколки и существование клипов)

    /// Удаление осколочных узлов (воскрешённых счётчиками лайков/просмотров после удаления клипа).
    private func deleteShardNodes(_ ids: [String]) async {
        for id in ids {
            guard let url = await makeURL(path: "media_stats/clips/\(id)") else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            request.timeoutInterval = 10.0
            if let (_, response) = try? await URLSession.shared.data(for: request),
               let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                AppDiagnostics.shared.log("[ClipsRepository] Removed shard node \(id)")
            }
        }
    }

    /// Проверка, что полноценный клип ещё существует в базе (по наличию title).
    private func clipExists(_ clipId: String) async -> Bool {
        guard let url = await makeURL(path: "media_stats/clips/\(clipId)/title") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10.0
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let text = String(data: data, encoding: .utf8) else {
            return false
        }
        // RTDB отвечает "null" на отсутствующее значение
        return text != "null"
    }

    // MARK: - Likes

    private func loadLikedClipsFromDisk() {
        if let array = UserDefaults.standard.stringArray(forKey: likedClipsStorageKey) {
            self.likedClipIds = Set(array)
        }
    }

    private func saveLikedClipsToDisk() {
        UserDefaults.standard.set(Array(likedClipIds), forKey: likedClipsStorageKey)
    }

    public func isLiked(clipId: String) -> Bool {
        likedClipIds.contains(clipId)
    }

    public func toggleLike(for clipId: String) async -> (isLiked: Bool, newCount: Int) {
        let currentlyLiked = isLiked(clipId: clipId)
        let newIsLiked = !currentlyLiked
        let userId = AuthRepository.shared.currentUser?.id ?? "guest_\(UIDevice.current.identifierForVendor?.uuidString ?? "user")"

        // Optimistic UI update
        if newIsLiked {
            likedClipIds.insert(clipId)
        } else {
            likedClipIds.remove(clipId)
        }
        saveLikedClipsToDisk()

        var currentCount = 0
        if let idx = clips.firstIndex(where: { $0.id == clipId }) {
            currentCount = clips[idx].likesCount
            currentCount = max(0, currentCount + (newIsLiked ? 1 : -1))
            clips[idx].likesCount = currentCount
            saveFeedToDisk(clips)
        }

        // Network sync
        Task {
            if let likeUrl = await makeURL(path: "media_stats/clips_likes/\(clipId)/\(userId)") {
                var likeReq = URLRequest(url: likeUrl)
                likeReq.httpMethod = newIsLiked ? "PUT" : "DELETE"
                if newIsLiked {
                    likeReq.httpBody = try? JSONEncoder().encode(true)
                    likeReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
                }
                _ = try? await URLSession.shared.data(for: likeReq)
            }

            // Счётчик пишем только если клип ещё существует: запись по пути
            // clips/{id}/likesCount иначе «воскресит» удалённый клип одним полем
            // и сломает всем декодирование фида.
            if await clipExists(clipId),
               let countUrl = await makeURL(path: "media_stats/clips/\(clipId)/likesCount") {
                var countReq = URLRequest(url: countUrl)
                countReq.httpMethod = "PUT"
                countReq.httpBody = try? JSONEncoder().encode(currentCount)
                countReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
                _ = try? await URLSession.shared.data(for: countReq)
            }
        }

        return (newIsLiked, currentCount)
    }

    // MARK: - Views Tracking (Single view per user/device deduplicated)

    private func loadViewedClipsFromDisk() {
        if let array = UserDefaults.standard.stringArray(forKey: viewedClipsStorageKey) {
            self.viewedClipIds = Set(array)
        }
    }

    private func saveViewedClipsToDisk() {
        UserDefaults.standard.set(Array(viewedClipIds), forKey: viewedClipsStorageKey)
    }

    public func isViewed(clipId: String) -> Bool {
        viewedClipIds.contains(clipId)
    }

    public func registerView(for clipId: String) async {
        guard !clipId.isEmpty else { return }

        // Deduplication: count only once per clip per user/device
        if isViewed(clipId: clipId) {
            return
        }

        viewedClipIds.insert(clipId)
        saveViewedClipsToDisk()

        var currentViews = 1
        if let idx = clips.firstIndex(where: { $0.id == clipId }) {
            clips[idx].viewsCount += 1
            currentViews = clips[idx].viewsCount
            saveFeedToDisk(clips)
        }

        let userId = AuthRepository.shared.currentUser?.id ?? "guest_\(UIDevice.current.identifierForVendor?.uuidString ?? "user")"

        // Network sync in background (RTDB)
        Task {
            // 1. Record per-user view marker
            if let userViewUrl = await makeURL(path: "media_stats/clips_views/\(clipId)/\(userId)") {
                var req = URLRequest(url: userViewUrl)
                req.httpMethod = "PUT"
                req.httpBody = try? JSONEncoder().encode(Int64(Date().timeIntervalSince1970 * 1000))
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                _ = try? await URLSession.shared.data(for: req)
            }

            // 2. Update clips/\(clipId)/viewsCount (только если клип ещё существует)
            if await clipExists(clipId),
               let countUrl = await makeURL(path: "media_stats/clips/\(clipId)/viewsCount") {
                var countReq = URLRequest(url: countUrl)
                countReq.httpMethod = "PUT"
                countReq.httpBody = try? JSONEncoder().encode(currentViews)
                countReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
                _ = try? await URLSession.shared.data(for: countReq)
            }
        }
    }

    // MARK: - Comments

    public func fetchComments(for clipId: String) async -> [ClipComment] {
        guard let url = await makeURL(path: "media_stats/clips_comments/\(clipId)") else { return [] }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 8.0

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return []
            }

            if let dict = try? JSONDecoder().decode([String: ClipComment].self, from: data) {
                return Array(dict.values).sorted { $0.createdAtMs < $1.createdAtMs }
            } else if let array = try? JSONDecoder().decode([ClipComment].self, from: data) {
                return array.sorted { $0.createdAtMs < $1.createdAtMs }
            }
        } catch {
            print("[ClipsRepository] fetchComments error: \(error.localizedDescription)")
        }
        return []
    }

    public func addComment(clipId: String, text: String) async throws -> ClipComment {
        let user = AuthRepository.shared.currentUser
        let authorId = user?.id ?? "guest_\(UIDevice.current.identifierForVendor?.uuidString ?? "user")"
        let authorName = (user?.displayName?.isEmpty == false ? user?.displayName : nil) ?? user?.displayTitle ?? "Гость"
        let authorAvatar = user?.photoURL

        let comment = ClipComment(
            clipId: clipId,
            authorId: authorId,
            authorName: authorName,
            authorAvatar: authorAvatar,
            text: text
        )

        guard let url = await makeURL(path: "media_stats/clips_comments/\(clipId)/\(comment.id)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody = try JSONEncoder().encode(comment)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        // Update local and remote commentsCount
        if let idx = clips.firstIndex(where: { $0.id == clipId }) {
            clips[idx].commentsCount += 1
            let newCount = clips[idx].commentsCount
            saveFeedToDisk(clips)

            if let countUrl = await makeURL(path: "media_stats/clips/\(clipId)/commentsCount") {
                var countReq = URLRequest(url: countUrl)
                countReq.httpMethod = "PUT"
                countReq.httpBody = try? JSONEncoder().encode(newCount)
                countReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
                _ = try? await URLSession.shared.data(for: countReq)
            }
        }

        return comment
    }

    // MARK: - Delete Clip

    public func deleteClip(clipId: String) async throws {
        guard let url = await makeURL(path: "media_stats/clips/\(clipId)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        clips.removeAll { $0.id == clipId }
        saveFeedToDisk(clips)

        // Гигиена: чистим лайки/просмотры/комментарии удалённого клипа, чтобы
        // последующие записи счётчиков не «воскресили» его осколком
        for path in ["media_stats/clips_likes/\(clipId)", "media_stats/clips_views/\(clipId)", "media_stats/clips_comments/\(clipId)"] {
            if let cleanupUrl = await makeURL(path: path) {
                var cleanupReq = URLRequest(url: cleanupUrl)
                cleanupReq.httpMethod = "DELETE"
                _ = try? await URLSession.shared.data(for: cleanupReq)
            }
        }
    }

    // MARK: - Author Clips

    public func fetchClips(forAuthorId authorId: String, forceRefresh: Bool = true) async -> [MovieClip] {
        if forceRefresh || clips.isEmpty {
            await fetchFeed(forceRefresh: forceRefresh)
        }
        return clips.filter { $0.authorId == authorId }.sorted { $0.createdAtMs > $1.createdAtMs }
    }
}

