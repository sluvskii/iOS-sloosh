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

    // Модерация (админ-панель)
    @Published public private(set) var reports: [CommentReportGroup] = []
    @Published public private(set) var isLoadingReports: Bool = false
    @Published public private(set) var reportsError: String?
    /// `nil` — ещё не проверяли; `false` — UID отсутствует в `/admins`.
    @Published public private(set) var hasServerAdminAccess: Bool?
    @Published public private(set) var lastModerationError: String?
    /// Названия тайтлов по mediaKey (чтобы админка показывала фильм, а не `kp_…`).
    private var mediaMetaCache: [String: (title: String, poster: String?)] = [:]

    private let databaseBaseURL = "https://sloosh-77434-default-rtdb.firebaseio.com"
    private let diskKeyPrefix = "sloosh_media_comments_v1_"
    private let lastSentPrefix = "sloosh_media_comment_last_sent_"
    private var inFlight: [String: Task<[MediaComment], Never>] = [:]
    private var lastFetchedAt: [String: Date] = [:]
    /// Свежесть кэша между открытиями: в пределах TTL сеть не дёргаем.
    private let cacheTTL: TimeInterval = 600
    /// Насколько «свежий» локальный комментарий доживает при обновлении,
    /// чтобы только что отправленный ничего не потерял.
    private let localMergeWindow: Int64 = 90_000
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

            // Сохраняем свежие локальные комментарии (например, только что
            // отправленный), если сервер их ещё не отдал.
            let remoteIds = Set(list.map { $0.id })
            let localOnly = (commentsByKey[mediaKey] ?? []).filter { local in
                !remoteIds.contains(local.id)
                    && (Int64(Date().timeIntervalSince1970 * 1000) - local.createdAtMs) < localMergeWindow
            }
            list.append(contentsOf: localOnly)
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

    // MARK: - Moderation (admin)

    /// Подтягивает все жалобы и джойнит их с комментариями.
    /// Доступно только админу (серверная проверка через `admins/{uid}`).
    public func fetchReports() async {
        isLoadingReports = true
        defer { isLoadingReports = false }

        await checkServerAdminAccess()

        guard let url = await makeURL(path: "media_comment_reports") else {
            reportsError = MediaCommentError.network.localizedDescription
            return
        }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 12
            request.cachePolicy = .reloadIgnoringLocalCacheData

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                reportsError = MediaCommentError.network.localizedDescription
                return
            }

            guard (200...299).contains(http.statusCode) else {
                reportsError = (http.statusCode == 401 || http.statusCode == 403)
                    ? "Нет серверных прав. Опубликуйте rules и добавьте свой UID в узел admins."
                    : "Не удалось загрузить жалобы (HTTP \(http.statusCode))."
                return
            }

            if data.isEmpty || String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) == "null" {
                reports = []
                reportsError = nil
                return
            }

            let dict = try decoder.decode([String: [String: MediaCommentReport]].self, from: data)

            var groups: [CommentReportGroup] = []
            for (commentId, byUid) in dict {
                let reportList = Array(byUid.values)
                guard let mediaKey = reportList.compactMap({ $0.mediaKey }).first(where: { !$0.isEmpty }) else { continue }

                var group = CommentReportGroup(
                    id: commentId,
                    mediaKey: mediaKey,
                    reports: reportList,
                    comment: nil
                )

                switch await lookupComment(mediaKey: mediaKey, commentId: commentId) {
                case .found(let comment):
                    group.comment = comment
                case .failed:
                    group.commentLoadFailed = true
                case .deleted:
                    break
                }

                let meta = await mediaMeta(for: mediaKey)
                group.mediaTitle = meta.title
                group.posterUrl = meta.poster

                groups.append(group)
            }

            groups.sort { $0.createdAtMs > $1.createdAtMs }
            reports = groups
            reportsError = nil
        } catch {
            reportsError = MediaCommentError.network.localizedDescription
        }
    }

    /// Первичная активация прав: пока список `admins` пуст, владелец может
    /// добавить себя сам (дальше правило закрывается — numChildren() != 0).
    public func claimAdminAccess() async -> Bool {
        guard let uid = AuthRepository.shared.currentUser?.id, !uid.isEmpty else {
            lastModerationError = "Войдите в аккаунт"
            return false
        }
        guard let url = await makeURL(path: "admins/\(uid)") else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("true".utf8)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                lastModerationError = moderationFailureMessage(status: (response as? HTTPURLResponse)?.statusCode)
                return false
            }

            hasServerAdminAccess = true
            lastModerationError = nil
            await fetchReports()
            return true
        } catch {
            lastModerationError = MediaCommentError.network.localizedDescription
            return false
        }
    }

    /// Проверяет, что UID пользователя действительно есть в `admins` на сервере.
    public func checkServerAdminAccess() async {
        guard let uid = AuthRepository.shared.currentUser?.id, !uid.isEmpty else {
            hasServerAdminAccess = false
            return
        }
        guard let url = await makeURL(path: "admins/\(uid)") else {
            hasServerAdminAccess = nil
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else {
            hasServerAdminAccess = nil
            return
        }

        if (200...299).contains(http.statusCode) {
            hasServerAdminAccess = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) == "true"
        } else {
            hasServerAdminAccess = false
        }
    }

    /// Удаление любого комментария админом (правила разрешают автору или админу).
    public func deleteCommentAsAdmin(_ group: CommentReportGroup) async -> Bool {
        guard let url = await makeURL(path: "media_comments/\(group.mediaKey)/\(group.id)") else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.timeoutInterval = 12

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                lastModerationError = moderationFailureMessage(status: (response as? HTTPURLResponse)?.statusCode)
                return false
            }

            var cached = commentsByKey[group.mediaKey] ?? []
            cached.removeAll { $0.id == group.id }
            commentsByKey[group.mediaKey] = cached
            saveToDisk(mediaKey: group.mediaKey, comments: cached)

            _ = await dismissReports(group)
            lastModerationError = nil
            return true
        } catch {
            return false
        }
    }

    /// Пометить/снять пометку спойлера у комментария (админ-право в правилах).
    public func setSpoiler(_ group: CommentReportGroup, isSpoiler: Bool) async -> Bool {
        guard let url = await makeURL(path: "media_comments/\(group.mediaKey)/\(group.id)/isSpoiler") else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data((isSpoiler ? "true" : "false").utf8)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                lastModerationError = moderationFailureMessage(status: (response as? HTTPURLResponse)?.statusCode)
                return false
            }

            if var cached = commentsByKey[group.mediaKey],
               let index = cached.firstIndex(where: { $0.id == group.id }) {
                cached[index].isSpoiler = isSpoiler
                commentsByKey[group.mediaKey] = cached
                saveToDisk(mediaKey: group.mediaKey, comments: cached)
            }
            if let index = reports.firstIndex(where: { $0.id == group.id }) {
                reports[index].comment?.isSpoiler = isSpoiler
            }
            lastModerationError = nil
            return true
        } catch {
            return false
        }
    }

    /// «Игнорировать»: удаляем жалобы по комментарию, сам комментарий остаётся.
    public func dismissReports(_ group: CommentReportGroup) async -> Bool {
        guard let url = await makeURL(path: "media_comment_reports/\(group.id)") else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.timeoutInterval = 12

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                lastModerationError = moderationFailureMessage(status: (response as? HTTPURLResponse)?.statusCode)
                return false
            }
            reports.removeAll { $0.id == group.id }
            lastModerationError = nil
            return true
        } catch {
            return false
        }
    }

    private enum CommentLookup {
        case found(MediaComment)
        case deleted
        case failed
    }

    private func lookupComment(mediaKey: String, commentId: String) async -> CommentLookup {
        switch await fetchCommentNode(mediaKey: mediaKey, commentId: commentId) {
        case .found(let comment):
            return .found(comment)
        case .failed:
            return .failed
        case .deleted:
            // Ключ в жалобе мог не совпасть с ключом, под которым лежит комментарий.
            if let found = await searchCommentAcrossMedia(commentId: commentId) {
                return .found(found)
            }
            return .deleted
        }
    }

    private func fetchCommentNode(mediaKey: String, commentId: String) async -> CommentLookup {
        guard let url = await makeURL(path: "media_comments/\(mediaKey)/\(commentId)") else { return .failed }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else {
            return .failed
        }

        guard (200...299).contains(http.statusCode) else { return .failed }

        let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if raw.isEmpty || raw == "null" { return .deleted }

        guard var comment = try? decoder.decode(MediaComment.self, from: data) else { return .failed }
        comment.id = commentId
        return .found(comment)
    }

    /// Поиск комментария по всем тайтлам — на случай, если в жалобе другой ключ.
    private func searchCommentAcrossMedia(commentId: String) async -> MediaComment? {
        guard let listURL = await makeURL(path: "media_comments", query: [URLQueryItem(name: "shallow", value: "true")]),
              let (listData, listResponse) = try? await URLSession.shared.data(for: URLRequest(url: listURL)),
              let listHTTP = listResponse as? HTTPURLResponse,
              (200...299).contains(listHTTP.statusCode),
              let keys = try? decoder.decode([String: Bool].self, from: listData) else {
            return nil
        }

        for key in keys.keys.prefix(30) {
            guard let idsURL = await makeURL(
                path: "media_comments/\(key)",
                query: [URLQueryItem(name: "shallow", value: "true")]
            ) else { continue }

            guard let (idsData, idsResponse) = try? await URLSession.shared.data(for: URLRequest(url: idsURL)),
                  let idsHTTP = idsResponse as? HTTPURLResponse,
                  (200...299).contains(idsHTTP.statusCode),
                  let ids = try? decoder.decode([String: Bool].self, from: idsData),
                  ids[commentId] == true else {
                continue
            }

            if case .found(let comment) = await fetchCommentNode(mediaKey: key, commentId: commentId) {
                return comment
            }
        }

        return nil
    }

    /// Название и постер тайтла по `mediaKey` (`kp_…` / `tmdb_…`).
    private func mediaMeta(for mediaKey: String) async -> (title: String?, poster: String?) {
        if let cached = mediaMetaCache[mediaKey] {
            return (cached.title, cached.poster)
        }

        // 1. Аналитика уже знает человеческие названия по mediaKey.
        if let hit = AdminRepository.shared.mediaAnalytics.first(where: { $0.mediaKey == mediaKey }),
           !hit.title.isEmpty {
            mediaMetaCache[mediaKey] = (hit.title, hit.posterUrl)
            return (hit.title, hit.posterUrl)
        }

        // 2. Пробуем детали по ключу как есть.
        if let details = try? await MoviesRepository.shared.getDetails(id: mediaKey),
           let title = details.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            mediaMetaCache[mediaKey] = (title, details.displayPosterUrl)
            return (title, details.displayPosterUrl)
        }

        // 3. Числовой id — только если API подтверждает, что это тот же Кинопоиск.
        if mediaKey.hasPrefix("kp_") {
            let numeric = String(mediaKey.dropFirst(3))
            if let details = try? await MoviesRepository.shared.getDetails(id: numeric),
               let title = details.title?.trimmingCharacters(in: .whitespacesAndNewlines),
               !title.isEmpty,
               String(details.externalIds?.kp ?? details.ids?.kp ?? 0) == numeric {
                mediaMetaCache[mediaKey] = (title, details.displayPosterUrl)
                return (title, details.displayPosterUrl)
            }
        }

        return (nil, nil)
    }

    private func moderationFailureMessage(status: Int?) -> String {
        switch status ?? 0 {
        case 401, 403:
            return "Нет прав администратора на сервере. Проверьте rules и узел admins."
        default:
            return "Не удалось выполнить действие. Проверьте соединение."
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
