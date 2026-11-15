import Foundation
import SwiftUI

/// Соц-слой тир-листов. Паттерны взяты у MediaCommentsRepository (REST-обёртка RTDB,
/// in-flight дедуп, disk-prime, оптимистичные лайки) и ClipsRepository
/// (guard-счётчики против «воскрешения» удалённых узлов, дедуп просмотров, ранжинг).
@MainActor
final class TierListsRepository: ObservableObject {
    static let shared = TierListsRepository()

    /// Недавно опубликованные публичные списки (последние 100 по createdAtMs).
    @Published private(set) var publicLists: [TierList] = []
    /// Редакторские шаблоны из tier_templates.
    @Published private(set) var templates: [TierTemplate] = []

    private let session: URLSession
    private let defaults: UserDefaults
    private let databaseBaseURL = "https://sloosh-77434-default-rtdb.firebaseio.com"
    private var accountId: String? { AuthRepository.shared.currentUser?.id }
    private var likedDefaultsKey: String { "sloosh_liked_tier_lists_v2_\(accountId ?? "guest")" }
    private var viewedDefaultsKey: String { "sloosh_viewed_tier_lists_v2_\(accountId ?? "guest")" }
    private let feedCacheKey = "sloosh_tier_lists_cache_v1"
    @Published private(set) var lastError: String?

    private var inFlightLists: Task<[TierList], Never>?
    private var inFlightTemplates: Task<[TierTemplate], Never>?
    private var lastFetchDate: Date?
    private var likedIds: Set<String> {
        get { Set(defaults.stringArray(forKey: likedDefaultsKey) ?? []) }
        set { defaults.set(Array(newValue), forKey: likedDefaultsKey) }
    }
    private var viewedIds: Set<String> {
        get { Set(defaults.stringArray(forKey: viewedDefaultsKey) ?? []) }
        set { defaults.set(Array(newValue), forKey: viewedDefaultsKey) }
    }
    private var socialWrites: Set<String> = []

    private let encoder = JSONEncoder()

    init(session: URLSession = .shared, defaults: UserDefaults = .standard) {
        self.session = session
        self.defaults = defaults
        if let data = defaults.data(forKey: feedCacheKey),
           let cached = try? JSONDecoder().decode([TierList].self, from: data),
           !cached.isEmpty {
            publicLists = cached
        }
    }

    // MARK: - Транспорт

    private func makeURL(path: String, query: [URLQueryItem] = []) async -> URL? {
        let safePath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        guard var components = URLComponents(string: "\(databaseBaseURL)/\(safePath).json") else { return nil }
        var items = query
        if let token = await AuthRepository.shared.ensureFreshToken(), !token.isEmpty {
            items.append(URLQueryItem(name: "auth", value: token))
        }
        if !items.isEmpty { components.queryItems = items }
        return components.url
    }

    private func dataRequest(path: String, method: String, body: Data?, query: [URLQueryItem] = []) async throws {
        guard let url = await makeURL(path: path, query: query) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let body = body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.timeoutInterval = 12
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200...299).contains(http.statusCode) else {
            throw NSError(domain: "sloosh.tiers", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Не удалось сохранить изменения. Проверьте подключение и права доступа."])
        }
        _ = data
    }

    // MARK: - Публичные списки

    /// Последние 100 публичных списков (orderBy createdAtMs). Дедуп параллельных вызовов,
    /// короткий TTL и дисковый снапшот для мгновенного холодного старта.
    func fetchPublicLists(force: Bool = false) async -> [TierList] {
        lastError = nil
        if let inFlight = inFlightLists {
            return await inFlight.value
        }
        if !force, let last = lastFetchDate, Date().timeIntervalSince(last) < 60, !publicLists.isEmpty {
            return publicLists
        }

        let task = Task<[TierList], Never> { [weak self] in
            guard let self else { return [] }
            guard let url = await self.makeURL(
                path: "tier_lists",
                query: [
                    URLQueryItem(name: "orderBy", value: "\"createdAtMs\""),
                    URLQueryItem(name: "limitToLast", value: "100")
                ]
            ) else { return self.publicLists }
            var request = URLRequest(url: url)
            request.timeoutInterval = 12
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    self.lastError = "Не удалось обновить тир-листы. Потяните вниз, чтобы повторить."
                    return self.publicLists
                }
                let value = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
                guard value is NSNull || value is [String: Any] else { throw URLError(.cannotParseResponse) }
                let raw = value as? [String: Any] ?? [:]
                let decoded = raw.compactMap { key, value -> TierList? in
                    guard let document = value as? [String: Any] else { return nil }
                    return TierList.decode(id: key, document: document)
                }.sorted { $0.createdAtMs > $1.createdAtMs }
                await MainActor.run {
                    self.publicLists = decoded
                    self.lastFetchDate = Date()
                }
                if let snapshot = try? self.encoder.encode(decoded) {
                    defaults.set(snapshot, forKey: self.feedCacheKey)
                }
                return decoded
            } catch {
                self.lastError = "Нет подключения. Показаны сохранённые тир-листы."
                return self.publicLists
            }
        }
        inFlightLists = task
        let result = await task.value
        inFlightLists = nil
        return result
    }

    /// Один список по id (deep link / просмотрщик).
    func fetchList(id: String, force: Bool = false) async -> TierList? {
        if !force, let cached = publicLists.first(where: { $0.id == id }) { return cached }
        guard let url = await makeURL(path: "tier_lists/\(id)") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              !raw.isEmpty,
              let list = TierList.decode(id: id, document: raw) else {
            return nil
        }
        return list
    }

    /// Списки конкретного автора (паттерн fetchClips(forAuthorId:)): берём свежие 100 и фильтруем.
    func fetchLists(forAuthorId authorId: String) async -> [TierList] {
        guard !authorId.isEmpty else { return [] }
        // $key is indexed by RTDB itself. Scan bounded pages, not just the last
        // 100 global publications; no new production index/rules are required.
        var cursor: String?
        var result: [TierList] = []
        do {
            while !Task.isCancelled {
                var query = [URLQueryItem(name: "orderBy", value: "\"$key\""), URLQueryItem(name: "limitToFirst", value: "201")]
                if let cursor {
                    query.append(URLQueryItem(name: "startAt", value: String(data: try JSONEncoder().encode(cursor), encoding: .utf8)!))
                }
                guard let url = await makeURL(path: "tier_lists", query: query) else { throw URLError(.badURL) }
                let (data, response) = try await session.data(for: URLRequest(url: url, timeoutInterval: 12))
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
                let value = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
                guard value is NSNull || value is [String: Any] else { throw URLError(.cannotParseResponse) }
                let raw = value as? [String: Any] ?? [:]
                let keys = raw.keys.sorted()
                for key in keys where cursor == nil || key > cursor! {
                    if let doc = raw[key] as? [String: Any], let list = TierList.decode(id: key, document: doc), list.authorId == authorId { result.append(list) }
                }
                guard raw.count == 201, let last = keys.last, last != cursor else { break }
                cursor = last
            }
            try Task.checkCancellation()
            return result.sorted { $0.updatedAtMs > $1.updatedAtMs }
        } catch {
            lastError = "Не удалось загрузить все списки автора. Повторите попытку."
            return publicLists.filter { $0.authorId == authorId }
        }
    }

    /// Ранжинг для вкладки «Популярные»: вовлечённость + свежесть (формула клипов).
    func rankLists(_ lists: [TierList]) -> [TierList] {
        TierListRanking.rank(lists, nowMs: Int64(Date().timeIntervalSince1970 * 1000))
    }

    // MARK: - Публикация

    private func authorPayload() -> (id: String, name: String, tag: String?, avatar: String?)? {
        guard let user = AuthRepository.shared.currentUser, !user.isAnonymous else { return nil }
        let trimmedName = (user.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let name: String
        if trimmedName.isEmpty {
            name = user.email?.split(separator: "@").first.map(String.init) ?? "Пользователь"
        } else {
            name = trimmedName
        }
        return (user.id, name, user.tag, user.photoURL)
    }

    /// Публикация нового списка или обновление своего опубликованного.
    /// Возвращает опубликованный список (с реальным id вместо draft_) либо nil.
    func publish(_ draft: TierList) async throws -> TierList? {
        guard let author = authorPayload() else { return nil }
        if let message = TierBoardPolicy.validationMessage(title: draft.title, subtitle: draft.subtitle, rows: draft.rows, items: draft.allItems) {
            throw NSError(domain: "sloosh.tiers", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        var list = draft
        let wasDraft = list.id.hasPrefix("draft_")
        let listId = wasDraft ? UUID().uuidString : list.id
        list.id = listId
        list.isDraft = nil
        list.authorId = author.id
        list.authorName = author.name
        list.authorTag = author.tag
        list.authorAvatar = author.avatar
        if wasDraft || list.createdAtMs == 0 { list.createdAtMs = Int64(Date().timeIntervalSince1970 * 1000) }
        list.updatedAtMs = Int64(Date().timeIntervalSince1970 * 1000)

        var document = list.publishDocument
        // Never overwrite social counters with the editor's stale snapshot.
        if !wasDraft { document.removeValue(forKey: "likesCount"); document.removeValue(forKey: "viewsCount") }
        let body = try JSONSerialization.data(withJSONObject: document)
        try await dataRequest(path: "tier_lists/\(listId)", method: wasDraft ? "PUT" : "PATCH", body: body)

        // Публикация черновика: локальный черновик больше не нужен
        deleteDraft(id: draft.id)

        if let index = publicLists.firstIndex(where: { $0.id == listId }) {
            publicLists[index] = list
        } else {
            publicLists.insert(list, at: 0)
        }
        persistFeed()
        return list
    }

    private func persistFeed() {
        if let data = try? encoder.encode(publicLists) { defaults.set(data, forKey: feedCacheKey) }
    }

    /// Удаление своего списка + каскадная чистка лайков/просмотров (паттерн deleteClip).
    func deleteList(id: String) async throws {
        try await dataRequest(path: "tier_lists/\(id)", method: "DELETE", body: nil)
        try? await dataRequest(path: "tier_lists_likes/\(id)", method: "DELETE", body: nil)
        try? await dataRequest(path: "tier_lists_views/\(id)", method: "DELETE", body: nil)
        publicLists.removeAll { $0.id == id }
        if let snapshot = try? encoder.encode(publicLists) {
            defaults.set(snapshot, forKey: feedCacheKey)
        }
    }

    // MARK: - Лайки (оптимистичные, счётчик с guard-ом)

    func isLiked(_ listId: String) -> Bool { likedIds.contains(listId) }

    /// Синхронизация счётчика лайков в кэше фида (publicLists — private(set)).
    func applyLikeCount(listId: String, count: Int) {
        if let index = publicLists.firstIndex(where: { $0.id == listId }) {
            publicLists[index].likesCount = count
        }
    }

    /// ETag compare-and-set retries contention without losing concurrent likes.
    /// The existing child write rule also refuses writes to deleted lists.
    private func adjustCounter(listId: String, field: String, delta: Int) async throws -> Int {
        guard let url = await makeURL(path: "tier_lists/\(listId)/\(field)") else { throw URLError(.badURL) }
        for _ in 0..<5 {
            var read = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
            read.setValue("true", forHTTPHeaderField: "X-Firebase-ETag")
            let (data, response) = try await session.data(for: read)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let etag = http.value(forHTTPHeaderField: "ETag") else { throw URLError(.badServerResponse) }
            let value = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            let next = max(0, (value as? NSNumber)?.intValue ?? 0) + delta
            var write = URLRequest(url: url, timeoutInterval: 12)
            write.httpMethod = "PUT"
            write.setValue(etag, forHTTPHeaderField: "if-match")
            write.setValue("application/json", forHTTPHeaderField: "Content-Type")
            write.httpBody = try JSONEncoder().encode(max(0, next))
            let (_, result) = try await session.data(for: write)
            guard let status = (result as? HTTPURLResponse)?.statusCode else { throw URLError(.badServerResponse) }
            if status == 412 { continue }
            guard (200..<300).contains(status) else { throw URLError(.badServerResponse) }
            return max(0, next)
        }
        throw URLError(.resourceUnavailable)
    }

    func toggleLike(_ list: TierList) async throws -> (isLiked: Bool, likesCount: Int) {
        guard let userId = accountId else { throw URLError(.userAuthenticationRequired) }
        let key = "like|\(userId)|\(list.id)"
        guard socialWrites.insert(key).inserted else { throw URLError(.resourceUnavailable) }
        defer { socialWrites.remove(key) }
        let liked = !likedIds.contains(list.id)
        let path = "tier_lists_likes/\(list.id)/\(userId)"
        try await dataRequest(path: path, method: liked ? "PUT" : "DELETE", body: liked ? try JSONEncoder().encode(true) : nil)
        let count: Int
        do { count = try await adjustCounter(listId: list.id, field: "likesCount", delta: liked ? 1 : -1) }
        catch {
            // Best effort compensation of the marker; never show a false success.
            try? await dataRequest(path: path, method: liked ? "DELETE" : "PUT", body: liked ? nil : try JSONEncoder().encode(true))
            throw error
        }
        guard accountId == userId else { throw CancellationError() }
        if liked { likedIds.insert(list.id) } else { likedIds.remove(list.id) }
        applyLikeCount(listId: list.id, count: count)
        persistFeed()
        return (liked, count)
    }

    func recordView(_ listId: String) {
        guard let userId = accountId, !viewedIds.contains(listId) else { return }
        let key = "view|\(userId)|\(listId)"
        guard socialWrites.insert(key).inserted else { return }
        Task {
            defer { socialWrites.remove(key) }
            do {
                let body = try JSONEncoder().encode(Int64(Date().timeIntervalSince1970 * 1000))
                try await dataRequest(path: "tier_lists_views/\(listId)/\(userId)", method: "PUT", body: body)
                let count = try await adjustCounter(listId: listId, field: "viewsCount", delta: 1)
                guard accountId == userId else { return }
                viewedIds.insert(listId)
                if let i = publicLists.firstIndex(where: { $0.id == listId }) { publicLists[i].viewsCount = count }
                persistFeed()
            } catch { /* Keep retry eligible after a failed request. */ }
        }
    }

    // MARK: - Шаблоны

    func fetchTemplates(force: Bool = false) async -> [TierTemplate] {
        if !templates.isEmpty && !force { return templates }
        if let inFlight = inFlightTemplates { return await inFlight.value }
        let task = Task<[TierTemplate], Never> { [weak self] in
            guard let self else { return [] }
            guard let url = await self.makeURL(path: "tier_templates") else { return self.templates }
            var request = URLRequest(url: url)
            request.timeoutInterval = 12
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                      let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return self.templates
                }
                let decoded = raw.compactMap { key, value -> TierTemplate? in
                    guard let document = value as? [String: Any] else { return nil }
                    return TierTemplate.decode(id: key, document: document)
                }.sorted {
                    ($0.priority ?? 0) > ($1.priority ?? 0)
                }
                await MainActor.run { self.templates = decoded }
                return decoded
            } catch {
                return self.templates
            }
        }
        inFlightTemplates = task
        let result = await task.value
        inFlightTemplates = nil
        return result
    }

    /// Из шаблона — готовый черновик: все items в пуле «Не распределено».
    func makeDraft(from template: TierTemplate) -> TierList {
        TierList(
            id: "draft_\(UUID().uuidString)",
            title: template.title,
            subtitle: template.subtitle,
            authorId: AuthRepository.shared.currentUser?.id ?? "",
            authorName: AuthRepository.shared.currentUser?.displayName ?? "",
            authorTag: nil,
            authorAvatar: nil,
            createdAtMs: 0,
            updatedAtMs: 0,
            rows: TierRow.defaultRows(),
            unranked: template.items,
            templateId: template.id,
            likesCount: nil,
            viewsCount: nil,
            isDraft: true
        )
    }

    func makeDraft(title: String = "Мой тир-лист") -> TierList {
        TierList(
            id: "draft_\(UUID().uuidString)",
            title: title,
            subtitle: nil,
            authorId: AuthRepository.shared.currentUser?.id ?? "",
            authorName: AuthRepository.shared.currentUser?.displayName ?? "",
            authorTag: nil,
            authorAvatar: nil,
            createdAtMs: 0,
            updatedAtMs: 0,
            rows: TierRow.defaultRows(),
            unranked: [],
            templateId: nil,
            likesCount: nil,
            viewsCount: nil,
            isDraft: true
        )
    }

    // MARK: - Быстрое добавление фильма из карточки («В тир-лист» в Details)

    /// Добавляет фильм в пул «Не распределено»: для черновика — локально,
    /// для опубликованного — правка узла RTDB (авторская правка).
    func addItem(_ item: TierListItem, to target: TierList) async throws {
        let local = target.isDraftList || target.id.hasPrefix("draft_")
        let latest = local ? target : await fetchList(id: target.id, force: true)
        guard var updated = latest else { throw URLError(.resourceUnavailable) }
        guard !updated.unranked.contains(where: { $0.mediaId == item.mediaId }),
              !updated.rows.contains(where: { $0.items.contains(where: { $0.mediaId == item.mediaId }) }) else { return }
        updated.unranked.append(item)
        updated.updatedAtMs = Int64(Date().timeIntervalSince1970 * 1000)

        if target.isDraftList || target.id.hasPrefix("draft_") {
            saveDraft(updated)
            return
        }
        let document = updated.publishDocument.filter { ["rows", "unranked", "updatedAtMs"].contains($0.key) }
        let body = try JSONSerialization.data(withJSONObject: document)
        try await dataRequest(path: "tier_lists/\(updated.id)", method: "PATCH", body: body)
        if let index = publicLists.firstIndex(where: { $0.id == updated.id }) {
            publicLists[index] = updated
        }
    }

    // MARK: - Черновики (локальные, per-user)

    func loadDrafts() -> [TierList] { TierDraftStore(defaults: defaults, userId: accountId).load() }
    func saveDraft(_ draft: TierList) { TierDraftStore(defaults: defaults, userId: accountId).save(draft) }
    func deleteDraft(id: String) { TierDraftStore(defaults: defaults, userId: accountId).delete(id: id) }
}
