import Foundation
import Combine

// MARK: - Errors

public enum MediaCommentError: LocalizedError {
    case notAuthenticated
    case emptyText
    case tooLong
    case cooldown(remaining: Int)
    case network

    public var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Войдите в аккаунт, чтобы комментировать"
        case .emptyText:
            return "Комментарий не может быть пустым"
        case .tooLong:
            return "Комментарий слишком длинный (максимум \(MediaCommentLimits.maxLength) символов)"
        case .cooldown(let remaining):
            return "Подождите \(remaining) сек. перед следующим комментарием"
        case .network:
            return "Не удалось отправить. Проверьте соединение"
        }
    }
}

// MARK: - Repository

/// Комментарии к фильмам и сериалам поверх Firebase RTDB.
///
/// Схема:
/// - `media_comments/{mediaKey}/{commentId}` — сам комментарий (+ карта `likedBy`)
/// - `media_comment_reports/{commentId}/{uid}` — жалобы (модерация)
///
/// Комментарии читаются последними `pageSize` штуками, сортируются по времени
/// на клиенте, кэшируются в памяти и на диске (мгновенное открытие листа).
@MainActor
public final class MediaCommentsRepository: ObservableObject {
    public static let shared = MediaCommentsRepository()

    @Published public private(set) var commentsByKey: [String: [MediaComment]] = [:]
    @Published public private(set) var loadingKeys: Set<String> = []
    @Published public private(set) var errorByKey: [String: String] = [:]

    private let databaseBaseURL = "https://sloosh-77434-default-rtdb.firebaseio.com"
    private let diskKeyPrefix = "sloosh_media_comments_v1_"
    private let lastSentPrefix = "sloosh_media_comment_last_sent_"
    private var inFlight: [String: Task<[MediaComment], Never>] = [:]
    private var lastFetchedAt: [String: Date] = [:]
    /// Свежесть кэша между открытиями: в пределах TTL сеть не дёргаем.
    private let cacheTTL: TimeInterval = 60
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    private init() {}

    // MARK: - Reads

    public func comments(for mediaKey: String) -> [MediaComment] {
        commentsByKey[mediaKey] ?? []
    }

    public func count(for mediaKey: String) -> Int {
        commentsByKey[mediaKey]?.count ?? 0
    }

    public func isLoading(_ mediaKey: String) -> Bool {
        loadingKeys.contains(mediaKey)
    }

    /// Мгновенно поднимает последний снимок с диска, чтобы лист открывался
    /// с контентом, пока летит сетевой запрос.
    public func primeFromDisk(mediaKey: String) {
        guard commentsByKey[mediaKey] == nil, !mediaKey.isEmpty else { return }
        guard let data = UserDefaults.standard.data(forKey: diskKeyPrefix + mediaKey),
              let list = try? decoder.decode([MediaComment].self, from: data) else { return }
        commentsByKey[mediaKey] = list
    }

    @discardableResult
    public func fetch(mediaKey: String, force: Bool = false) async -> [MediaComment] {
        guard !mediaKey.isEmpty else { return [] }

        if !force, let cached = commentsByKey[mediaKey], !cached.isEmpty,
           let fetchedAt = lastFetchedAt[mediaKey],
           Date().timeIntervalSince(fetchedAt) < cacheTTL {
            return cached
        }
        if let existing = inFlight[mediaKey] {
            return await existing.value
        }

        primeFromDisk(mediaKey: mediaKey)

        let task = Task { await self.performFetch(mediaKey: mediaKey) }
        inFlight[mediaKey] = task
        let result = await task.value
        inFlight[mediaKey] = nil
        return result
    }

    private func performFetch(mediaKey: String) async -> [MediaComment] {
        loadingKeys.insert(mediaKey)
        defer { loadingKeys.remove(mediaKey) }

        guard let url = await makeURL(
            path: "media_comments/\(mediaKey)",
            query: [
                URLQueryItem(name: "orderBy", value: "\"createdAtMs\""),
                URLQueryItem(name: "limitToLast", value: "\(MediaCommentLimits.pageSize)")
            ]
        ) else {
            errorByKey[mediaKey] = MediaCommentError.network.localizedDescription
            return commentsByKey[mediaKey] ?? []
        }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 10
            request.cachePolicy = .reloadIgnoringLocalCacheData

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                errorByKey[mediaKey] = MediaCommentError.network.localizedDescription
                return commentsByKey[mediaKey] ?? []
            }

            // Пустой узел приходит как `null`.
            if data.isEmpty || String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) == "null" {
                commentsByKey[mediaKey] = []
                lastFetchedAt[mediaKey] = Date()
                saveToDisk(mediaKey: mediaKey, comments: [])
                return []
            }

            let dict = try decoder.decode([String: MediaComment].self, from: data)
            var list = dict.map { key, value -> MediaComment in
                var comment = value
                comment.id = key
                return comment
            }
            list.sort { $0.createdAtMs > $1.createdAtMs }

            commentsByKey[mediaKey] = list
            errorByKey[mediaKey] = nil
            lastFetchedAt[mediaKey] = Date()
            saveToDisk(mediaKey: mediaKey, comments: list)
            return list
        } catch {
            errorByKey[mediaKey] = MediaCommentError.network.localizedDescription
            return commentsByKey[mediaKey] ?? []
        }
    }

    // MARK: - Writes

    @discardableResult
    public func addComment(mediaKey: String, text: String, isSpoiler: Bool) async throws -> MediaComment {
        guard let user = AuthRepository.shared.currentUser, AuthRepository.shared.isAuthenticated else {
            throw MediaCommentError.notAuthenticated
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MediaCommentError.emptyText }
        guard trimmed.count <= MediaCommentLimits.maxLength else { throw MediaCommentError.tooLong }

        let remaining = cooldownRemaining(mediaKey: mediaKey)
        guard remaining <= 0 else { throw MediaCommentError.cooldown(remaining: remaining) }

        let comment = MediaComment(
            authorId: user.id,
            authorName: displayName(for: user),
            authorTag: user.tag?.isEmpty == false ? user.tag : nil,
            authorAvatar: user.photoURL,
            text: trimmed,
            isSpoiler: isSpoiler
        )

        guard let url = await makeURL(path: "media_comments/\(mediaKey)/\(comment.id)") else {
            throw MediaCommentError.network
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // В узел не пишем `likedBy` и не дублируем путь — только полезные поля.
        let payload: [String: Any] = [
            "authorId": comment.authorId,
            "authorName": comment.authorName,
            "authorTag": comment.authorTag ?? NSNull(),
            "authorAvatar": comment.authorAvatar ?? NSNull(),
            "text": comment.text,
            "createdAtMs": comment.createdAtMs,
            "isSpoiler": comment.isSpoiler
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw MediaCommentError.network
        }

        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastSentPrefix + mediaKey)

        var updated = commentsByKey[mediaKey] ?? []
        updated.insert(comment, at: 0)
        commentsByKey[mediaKey] = updated
        saveToDisk(mediaKey: mediaKey, comments: updated)
        return comment
    }

    public func deleteComment(_ comment: MediaComment, mediaKey: String) async throws {
        guard let url = await makeURL(path: "media_comments/\(mediaKey)/\(comment.id)") else {
            throw MediaCommentError.network
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.timeoutInterval = 12

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw MediaCommentError.network
        }

        var updated = commentsByKey[mediaKey] ?? []
        updated.removeAll { $0.id == comment.id }
        commentsByKey[mediaKey] = updated
        saveToDisk(mediaKey: mediaKey, comments: updated)
    }

    /// Оптимистичный лайк: мгновенно меняем локальное состояние и карту `likedBy`,
    /// при ошибке откатываемся.
    public func toggleLike(_ comment: MediaComment, mediaKey: String) async {
        guard let uid = AuthRepository.shared.currentUser?.id, !uid.isEmpty else { return }
        guard let index = (commentsByKey[mediaKey] ?? []).firstIndex(where: { $0.id == comment.id }) else { return }

        let wasLiked = comment.isLiked(by: uid)
        applyLike(mediaKey: mediaKey, commentId: comment.id, uid: uid, liked: !wasLiked)

        guard let url = await makeURL(path: "media_comments/\(mediaKey)/\(comment.id)/likedBy/\(uid)") else {
            applyLike(mediaKey: mediaKey, commentId: comment.id, uid: uid, liked: wasLiked)
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        if wasLiked {
            request.httpMethod = "DELETE"
        } else {
            request.httpMethod = "PUT"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data("true".utf8)
        }

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                applyLike(mediaKey: mediaKey, commentId: comment.id, uid: uid, liked: wasLiked)
                return
            }
            if let updated = commentsByKey[mediaKey] {
                saveToDisk(mediaKey: mediaKey, comments: updated)
            }
        } catch {
            applyLike(mediaKey: mediaKey, commentId: comment.id, uid: uid, liked: wasLiked)
        }
    }

    public func report(_ comment: MediaComment, mediaKey: String, reason: String) async -> Bool {
        guard let uid = AuthRepository.shared.currentUser?.id, !uid.isEmpty else { return false }
        guard let url = await makeURL(path: "media_comment_reports/\(comment.id)/\(uid)") else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "reason": reason,
            "mediaKey": mediaKey,
            "commentAuthorId": comment.authorId,
            "createdAtMs": Int64(Date().timeIntervalSince1970 * 1000)
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return false }
            return true
        } catch {
            return false
        }
    }

    /// Время до конца кулдауна в секундах (0 — можно отправлять).
    public func cooldownRemaining(mediaKey: String) -> Int {
        let last = UserDefaults.standard.double(forKey: lastSentPrefix + mediaKey)
        guard last > 0 else { return 0 }
        let elapsed = Date().timeIntervalSince1970 - last
        let remaining = MediaCommentLimits.sendCooldown - elapsed
        return remaining > 0 ? Int(ceil(remaining)) : 0
    }

    // MARK: - Helpers

    private func applyLike(mediaKey: String, commentId: String, uid: String, liked: Bool) {
        guard var list = commentsByKey[mediaKey],
              let index = list.firstIndex(where: { $0.id == commentId }) else { return }
        var likedBy = list[index].likedBy ?? [:]
        if liked {
            likedBy[uid] = true
        } else {
            likedBy.removeValue(forKey: uid)
        }
        list[index].likedBy = likedBy.isEmpty ? nil : likedBy
        commentsByKey[mediaKey] = list
    }

    private func displayName(for user: UserProfile) -> String {
        if let name = user.displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        if let tag = user.tag?.trimmingCharacters(in: .whitespacesAndNewlines), !tag.isEmpty {
            return tag
        }
        return "Пользователь"
    }

    private func saveToDisk(mediaKey: String, comments: [MediaComment]) {
        guard !mediaKey.isEmpty else { return }
        let snapshot = Array(comments.prefix(100))
        guard let data = try? encoder.encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: diskKeyPrefix + mediaKey)
    }

    private func makeURL(path: String, query: [URLQueryItem] = []) async -> URL? {
        let safePath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        guard var components = URLComponents(string: "\(databaseBaseURL)/\(safePath).json") else { return nil }

        var items = query
        if let token = await AuthRepository.shared.ensureFreshToken(), !token.isEmpty {
            items.append(URLQueryItem(name: "auth", value: token))
        }
        if !items.isEmpty {
            components.queryItems = items
        }
        return components.url
    }
}
