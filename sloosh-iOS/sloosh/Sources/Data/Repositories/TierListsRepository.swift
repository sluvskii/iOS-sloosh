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

    private let databaseBaseURL = "https://sloosh-77434-default-rtdb.firebaseio.com"
    private let likedDefaultsKey = "sloosh_liked_tier_lists_v1"
    private let viewedDefaultsKey = "sloosh_viewed_tier_lists_v1"
    private let feedCacheKey = "sloosh_tier_lists_cache_v1"
    private let draftsKey = "sloosh_tier_drafts_v1"

    private var inFlightLists: Task<[TierList], Never>?
    private var inFlightTemplates: Task<[TierTemplate], Never>?
    private var lastFetchDate: Date?
    private var likedIds: Set<String> = []
    private var viewedIds: Set<String> = []

    private let encoder = JSONEncoder()

    private init() {
        likedIds = Set(UserDefaults.standard.stringArray(forKey: likedDefaultsKey) ?? [])
        viewedIds = Set(UserDefaults.standard.stringArray(forKey: viewedDefaultsKey) ?? [])
        if let data = UserDefaults.standard.data(forKey: feedCacheKey),
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
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse) // отличимая от сети ошибка прав доступа/валидации
        }
        _ = data
    }

    // MARK: - Публичные списки

    /// Последние 100 публичных списков (orderBy createdAtMs). Дедуп параллельных вызовов,
    /// короткий TTL и дисковый снапшот для мгновенного холодного старта.
    func fetchPublicLists(force: Bool = false) async -> [TierList] {
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
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    return self.publicLists
                }
                guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return self.publicLists
                }
                let decoded = raw.compactMap { key, value -> TierList? in
                    guard let document = value as? [String: Any] else { return nil }
                    return TierList.decode(id: key, document: document)
                }.sorted { $0.createdAtMs > $1.createdAtMs }
                await MainActor.run {
                    self.publicLists = decoded
                    self.lastFetchDate = Date()
                }
                if let snapshot = try? self.encoder.encode(decoded) {
                    UserDefaults.standard.set(snapshot, forKey: self.feedCacheKey)
                }
                return decoded
            } catch {
                return self.publicLists
            }
        }
        inFlightLists = task
        let result = await task.value
        inFlightLists = nil
        return result
    }

    /// Один список по id (deep link / просмотрщик).
    func fetchList(id: String) async -> TierList? {
        if let cached = publicLists.first(where: { $0.id == id }) { return cached }
        guard let url = await makeURL(path: "tier_lists/\(id)") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        guard let (data, response) = try? await URLSession.shared.data(for: request),
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
        let all = await fetchPublicLists()
        return all.filter { $0.authorId == authorId }
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
        var list = draft
        let wasDraft = list.isDraftList || list.id.hasPrefix("draft_")
        let listId = wasDraft ? UUID().uuidString : list.id
        list.id = listId
        list.isDraft = nil
        list.authorId = author.id
        list.authorName = author.name
        list.authorTag = author.tag
        list.authorAvatar = author.avatar
        if wasDraft || list.createdAtMs == 0 { list.createdAtMs = Int64(Date().timeIntervalSince1970 * 1000) }
        list.updatedAtMs = Int64(Date().timeIntervalSince1970 * 1000)

        guard let body = try? JSONSerialization.data(withJSONObject: list.publishDocument) else { return nil }
        try await dataRequest(path: "tier_lists/\(listId)", method: "PUT", body: body)

        // Публикация черновика: локальный черновик больше не нужен
        if wasDraft { deleteDraft(id: draft.id) }

        if let index = publicLists.firstIndex(where: { $0.id == listId }) {
            publicLists[index] = list
        } else {
            publicLists.insert(list, at: 0)
        }
        return list
    }

    /// Удаление своего списка + каскадная чистка лайков/просмотров (паттерн deleteClip).
    func deleteList(id: String) async throws {
        try await dataRequest(path: "tier_lists/\(id)", method: "DELETE", body: nil)
        try? await dataRequest(path: "tier_lists_likes/\(id)", method: "DELETE", body: nil)
        try? await dataRequest(path: "tier_lists_views/\(id)", method: "DELETE", body: nil)
        publicLists.removeAll { $0.id == id }
        if let snapshot = try? encoder.encode(publicLists) {
            UserDefaults.standard.set(snapshot, forKey: feedCacheKey)
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

    func toggleLike(_ list: TierList) async -> (isLiked: Bool, likesCount: Int) {
        let userId = AuthRepository.shared.currentUser?.id ?? "guest_\(UIDevice.current.identifierForVendor?.uuidString ?? "unknown")"
        let wasLiked = likedIds.contains(list.id)
        let newIsLiked = !wasLiked
        let baseCount = list.likesCount ?? 0
        let currentCount = max(0, baseCount + (newIsLiked ? 1 : -1))

        // 1. Оптимистичное локальное состояние
        if newIsLiked { likedIds.insert(list.id) } else { likedIds.remove(list.id) }
        UserDefaults.standard.set(Array(likedIds), forKey: likedDefaultsKey)
        if let index = publicLists.firstIndex(where: { $0.id == list.id }) {
            publicLists[index].likesCount = currentCount
        }

        // 2. Сеть: лайк — свой узел, счётчик — только при живом содержимом
        let liked = newIsLiked
        let count = currentCount
        let listId = list.id
        Task.detached { [databaseBaseURL] in
            let token = await AuthRepository.shared.ensureFreshToken()
            func url(_ path: String) -> URL? {
                URL(string: "\(databaseBaseURL)/\(path).json?auth=\(token ?? "")")
            }
            if let likeUrl = url("tier_lists_likes/\(listId)/\(userId)") {
                var likeReq = URLRequest(url: likeUrl)
                likeReq.httpMethod = liked ? "PUT" : "DELETE"
                if liked {
                    likeReq.httpBody = try? JSONEncoder().encode(true)
                    likeReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
                }
                _ = try? await URLSession.shared.data(for: likeReq)
            }
            // Счётчик пишем только если список ещё существует — иначе запись по
            // пути likesCount «воскресит» удалённый список одним полем.
            if let contentUrl = url("tier_lists/\(listId)/title"), let (raw, _) = try? await URLSession.shared.data(from: contentUrl),
               let text = String(data: raw, encoding: .utf8), text != "null", !text.isEmpty,
               let countUrl = url("tier_lists/\(listId)/likesCount") {
                var countReq = URLRequest(url: countUrl)
                countReq.httpMethod = "PUT"
                countReq.httpBody = try? JSONSerialization.data(withJSONObject: count)
                countReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
                _ = try? await URLSession.shared.data(for: countReq)
            }
        }
        return (newIsLiked, currentCount)
    }

    // MARK: - Просмотры (дедуп: один просмотр на пользователя)

    func recordView(_ listId: String) {
        guard !viewedIds.contains(listId) else { return }
        viewedIds.insert(listId)
        UserDefaults.standard.set(Array(viewedIds), forKey: viewedDefaultsKey)
        let userId = AuthRepository.shared.currentUser?.id ?? "guest_\(UIDevice.current.identifierForVendor?.uuidString ?? "unknown")"
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        Task.detached { [databaseBaseURL] in
            let token = await AuthRepository.shared.ensureFreshToken()
            func url(_ path: String) -> URL? {
                URL(string: "\(databaseBaseURL)/\(path).json?auth=\(token ?? "")")
            }
            if let viewUrl = url("tier_lists_views/\(listId)/\(userId)") {
                var viewReq = URLRequest(url: viewUrl)
                viewReq.httpMethod = "PUT"
                viewReq.httpBody = try? JSONSerialization.data(withJSONObject: nowMs)
                viewReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
                _ = try? await URLSession.shared.data(for: viewReq)
            }
            // Счётчик: read-modify-write с guard-ом содержимого (как likesCount у клипов)
            if let contentUrl = url("tier_lists/\(listId)/title"),
               let (raw, _) = try? await URLSession.shared.data(from: contentUrl),
               let text = String(data: raw, encoding: .utf8), text != "null", !text.isEmpty {
                var current = 0
                if let countUrl = url("tier_lists/\(listId)/viewsCount"),
                   let (countData, _) = try? await URLSession.shared.data(from: countUrl),
                   let value = try? JSONSerialization.jsonObject(with: countData) as? NSNumber {
                    current = value.intValue
                }
                if let countUrl = url("tier_lists/\(listId)/viewsCount") {
                    var countReq = URLRequest(url: countUrl)
                    countReq.httpMethod = "PUT"
                    countReq.httpBody = try? JSONSerialization.data(withJSONObject: current + 1)
                    countReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    _ = try? await URLSession.shared.data(for: countReq)
                }
            }
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
                let (data, response) = try await URLSession.shared.data(for: request)
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
        var updated = target
        guard !updated.unranked.contains(where: { $0.mediaId == item.mediaId }),
              !updated.rows.contains(where: { $0.items.contains(where: { $0.mediaId == item.mediaId }) }) else { return }
        updated.unranked.append(item)
        updated.updatedAtMs = Int64(Date().timeIntervalSince1970 * 1000)

        if target.isDraftList || target.id.hasPrefix("draft_") {
            saveDraft(updated)
            return
        }
        guard let body = try? JSONSerialization.data(withJSONObject: updated.publishDocument) else { return }
        try await dataRequest(path: "tier_lists/\(updated.id)", method: "PUT", body: body)
        if let index = publicLists.firstIndex(where: { $0.id == updated.id }) {
            publicLists[index] = updated
        }
    }

    // MARK: - Черновики (локальные, per-user)

    func loadDrafts() -> [TierList] {
        guard let data = UserDefaults.standard.data(forKey: draftsKey),
              let drafts = try? JSONDecoder().decode([TierList].self, from: data) else { return [] }
        return drafts.sorted { $0.updatedAtMs > $1.updatedAtMs }
    }

    func saveDraft(_ draft: TierList) {
        var drafts = loadDrafts()
        var draft = draft
        draft.isDraft = true
        draft.updatedAtMs = Int64(Date().timeIntervalSince1970 * 1000)
        if let index = drafts.firstIndex(where: { $0.id == draft.id }) {
            drafts[index] = draft
        } else {
            drafts.insert(draft, at: 0)
        }
        if drafts.count > 20 { drafts = Array(drafts.prefix(20)) }
        if let data = try? encoder.encode(drafts) {
            UserDefaults.standard.set(data, forKey: draftsKey)
        }
    }

    func deleteDraft(id: String) {
        var drafts = loadDrafts()
        drafts.removeAll { $0.id == id }
        if let data = try? encoder.encode(drafts) {
            UserDefaults.standard.set(data, forKey: draftsKey)
        }
    }
}
