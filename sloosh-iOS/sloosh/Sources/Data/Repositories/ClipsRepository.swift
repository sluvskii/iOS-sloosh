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
    private let feedDiskCacheKey = "sloosh_cached_clips_v1"

    private init() {
        loadLikedClipsFromDisk()
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
        self.clips = list
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

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return
            }

            // RTDB returns either a dictionary [String: MovieClip] or null
            if let dict = try? JSONDecoder().decode([String: MovieClip].self, from: data) {
                let fetched = Array(dict.values).sorted { $0.createdAtMs > $1.createdAtMs }
                self.clips = fetched
                saveFeedToDisk(fetched)
            } else if let array = try? JSONDecoder().decode([MovieClip].self, from: data) {
                let valid = array.sorted { $0.createdAtMs > $1.createdAtMs }
                self.clips = valid
                saveFeedToDisk(valid)
            }
        } catch {
            print("[ClipsRepository] fetchFeed error: \(error.localizedDescription)")
        }
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

            if let countUrl = await makeURL(path: "media_stats/clips/\(clipId)/likesCount") {
                var countReq = URLRequest(url: countUrl)
                countReq.httpMethod = "PUT"
                countReq.httpBody = try? JSONEncoder().encode(currentCount)
                countReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
                _ = try? await URLSession.shared.data(for: countReq)
            }
        }

        return (newIsLiked, currentCount)
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
    }
}
