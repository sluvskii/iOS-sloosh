import Foundation
import SwiftUI
import Combine

@MainActor
public final class MessengerRepository: ObservableObject {
    public static let shared = MessengerRepository()

    @Published public private(set) var conversations: [ChatConversation] = []
    @Published public private(set) var subscribedChannels: [ChannelModel] = []
    @Published public private(set) var publicChannels: [ChannelModel] = []
    @Published public private(set) var searchResults: [SlooshUser] = []
    @Published public private(set) var isLoading: Bool = false

    private let databaseBaseURL = "https://sloosh-77434-default-rtdb.firebaseio.com"
    private let knownUsersKey = "sloosh_messenger_known_users"

    private var cancellables = Set<AnyCancellable>()
    private var lastKnownUserId: String? = nil

    private init() {
        let currentId = AuthRepository.shared.currentUser?.id ?? "guest"
        self.lastKnownUserId = currentId
        self.conversations = loadConversationsFromDisk(userId: currentId)
        self.subscribedChannels = loadSubscribedChannelsFromDisk(userId: currentId)
        self.publicChannels = loadPublicChannelsFromDisk()

        // Subscribe to user account changes in AuthRepository
        AuthRepository.shared.$currentUser
            .receive(on: RunLoop.main)
            .sink { [weak self] newUser in
                self?.handleUserChanged(newUser: newUser)
            }
            .store(in: &cancellables)
    }

    public func handleUserChanged(newUser: UserProfile?) {
        let newId = newUser?.id ?? "guest"
        guard newId != lastKnownUserId else { return }
        lastKnownUserId = newId

        // Clear in-memory user-specific state & reload scoped data
        self.conversations = loadConversationsFromDisk(userId: newId)
        self.subscribedChannels = loadSubscribedChannelsFromDisk(userId: newId)
        self.searchResults = []

        if let user = newUser, !user.isAnonymous {
            Task {
                await self.syncCurrentUserProfile()
                await self.fetchConversations()
                _ = await self.fetchSubscribedChannels()
                _ = await self.fetchPublicChannels()
            }
        }
    }

    // MARK: - Disk Persistence (User-Scoped Instant Cold Start)

    public func saveConversationsToDisk(_ list: [ChatConversation], userId: String? = nil) {
        let uid = userId ?? AuthRepository.shared.currentUser?.id ?? "guest"
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: "sloosh_messenger_conversations_v2_\(uid)")
        }
    }

    public func loadConversationsFromDisk(userId: String? = nil) -> [ChatConversation] {
        let uid = userId ?? AuthRepository.shared.currentUser?.id ?? "guest"
        if let data = UserDefaults.standard.data(forKey: "sloosh_messenger_conversations_v2_\(uid)"),
           let list = try? JSONDecoder().decode([ChatConversation].self, from: data) {
            return list.sorted { $0.updatedAtMs > $1.updatedAtMs }
        }
        // Fallback migration from v1
        if let data1 = UserDefaults.standard.data(forKey: "sloosh_messenger_conversations_v1"),
           let list1 = try? JSONDecoder().decode([ChatConversation].self, from: data1), !list1.isEmpty {
            saveConversationsToDisk(list1, userId: uid)
            return list1.sorted { $0.updatedAtMs > $1.updatedAtMs }
        }
        return []
    }

    public func saveSubscribedChannelsToDisk(_ list: [ChannelModel], userId: String? = nil) {
        let uid = userId ?? AuthRepository.shared.currentUser?.id ?? "guest"
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: "sloosh_messenger_subscribed_channels_v2_\(uid)")
        }
    }

    public func loadSubscribedChannelsFromDisk(userId: String? = nil) -> [ChannelModel] {
        let uid = userId ?? AuthRepository.shared.currentUser?.id ?? "guest"
        if let data = UserDefaults.standard.data(forKey: "sloosh_messenger_subscribed_channels_v2_\(uid)"),
           let list = try? JSONDecoder().decode([ChannelModel].self, from: data) {
            return list.sorted { ($0.lastPostTimestampMs ?? $0.updatedAtMs) > ($1.lastPostTimestampMs ?? $1.updatedAtMs) }
        }
        // Fallback migration from v1
        if let data1 = UserDefaults.standard.data(forKey: "sloosh_messenger_subscribed_channels_v1"),
           let list1 = try? JSONDecoder().decode([ChannelModel].self, from: data1), !list1.isEmpty {
            let userChannels = list1.filter { $0.ownerId == uid || uid == "guest" }
            if !userChannels.isEmpty {
                saveSubscribedChannelsToDisk(userChannels, userId: uid)
                return userChannels.sorted { ($0.lastPostTimestampMs ?? $0.updatedAtMs) > ($1.lastPostTimestampMs ?? $1.updatedAtMs) }
            }
        }
        return []
    }

    public func savePublicChannelsToDisk(_ list: [ChannelModel]) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: "sloosh_messenger_public_channels_v2")
        }
    }

    public func loadPublicChannelsFromDisk() -> [ChannelModel] {
        guard let data = UserDefaults.standard.data(forKey: "sloosh_messenger_public_channels_v2"),
              let list = try? JSONDecoder().decode([ChannelModel].self, from: data) else {
            return []
        }
        return list.sorted { $0.subscriberCount > $1.subscriberCount }
    }

    public func saveChannelPostsToDisk(_ posts: [ChannelPost], channelId: String) {
        let key = "sloosh_channel_posts_v2_\(channelId)"
        if let data = try? JSONEncoder().encode(posts) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    public func loadChannelPostsFromDisk(channelId: String) -> [ChannelPost] {
        let key = "sloosh_channel_posts_v2_\(channelId)"
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([ChannelPost].self, from: data) else {
            return []
        }
        return list.sorted { $0.timestampMs < $1.timestampMs }
    }

    public func saveMessagesToDisk(_ messages: [ChatMessage], chatId: String, userId: String? = nil) {
        let uid = userId ?? AuthRepository.shared.currentUser?.id ?? "guest"
        let key = "sloosh_messenger_messages_v2_\(uid)_\(chatId)"
        if let data = try? JSONEncoder().encode(messages) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    public func loadMessagesFromDisk(chatId: String, userId: String? = nil) -> [ChatMessage] {
        let uid = userId ?? AuthRepository.shared.currentUser?.id ?? "guest"
        let key = "sloosh_messenger_messages_v2_\(uid)_\(chatId)"
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([ChatMessage].self, from: data) else {
            return []
        }
        return list.sorted { $0.timestampMs < $1.timestampMs }
    }

    // MARK: - Local Known Users Persistence

    public func saveLocalKnownUser(_ user: SlooshUser) {
        var current = getLocalKnownUsers()
        current[user.id] = user
        if let data = try? JSONEncoder().encode(current) {
            UserDefaults.standard.set(data, forKey: knownUsersKey)
        }
    }

    public func getLocalKnownUsers() -> [String: SlooshUser] {
        guard let data = UserDefaults.standard.data(forKey: knownUsersKey),
              let dict = try? JSONDecoder().decode([String: SlooshUser].self, from: data) else {
            return [:]
        }
        return dict
    }

    private func makeURL(path: String) async -> URL? {
        let safePath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        var urlString = "\(databaseBaseURL)/\(safePath).json"
        if let token = await AuthRepository.shared.ensureFreshToken(), !token.isEmpty {
            urlString += "?auth=\(token)"
        }
        return URL(string: urlString)
    }

    // MARK: - Tag Management & Availability

    public func checkChannelTagAvailability(tag: String, excludingChannelId: String? = nil) async -> (isAvailable: Bool, message: String) {
        let clean = TagValidator.sanitize(tag)
        let validation = TagValidator.validate(clean)
        guard validation.isValid else {
            return (false, validation.message)
        }

        // Check local memory first
        if let existing = self.publicChannels.first(where: { $0.tag == clean }) ?? self.subscribedChannels.first(where: { $0.tag == clean }) {
            if let excl = excludingChannelId, existing.id == excl {
                return (true, "Текущий тег канала")
            }
            return (false, "Тег @\(clean) уже занят")
        }

        guard let url = await makeURL(path: "channelTags/\(clean)") else {
            return (true, "Тег доступен")
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode) else {
                return (true, "Тег свободен")
            }
            if data.isEmpty || String(data: data, encoding: .utf8) == "null" {
                return (true, "Тег свободен")
            } else {
                let occupantId = (try? JSONDecoder().decode(String.self, from: data)) ?? ""
                if let excl = excludingChannelId, occupantId == excl {
                    return (true, "Текущий тег канала")
                }
                return (false, "Тег @\(clean) уже занят")
            }
        } catch {
            return (true, "Тег свободен")
        }
    }

    public func checkUserTagAvailability(tag: String) async -> (isAvailable: Bool, message: String) {
        let clean = TagValidator.sanitize(tag)
        let currentUserId = AuthRepository.shared.currentUser?.id ?? ""
        let validation = TagValidator.validate(clean)
        guard validation.isValid else {
            return (false, validation.message)
        }

        guard let url = await makeURL(path: "userTags/\(clean)") else {
            return (true, "Тег доступен")
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode) else {
                return (true, "Тег свободен")
            }
            if data.isEmpty || String(data: data, encoding: .utf8) == "null" {
                return (true, "Тег свободен")
            }
            let occupantId = (try? JSONDecoder().decode(String.self, from: data)) ?? ""
            if occupantId == currentUserId {
                return (true, "Это ваш текущий тег")
            }
            return (false, "Тег @\(clean) уже занят")
        } catch {
            return (true, "Тег свободен")
        }
    }

    public func claimChannelTag(_ tag: String, channelId: String) async {
        let clean = TagValidator.sanitize(tag)
        guard !clean.isEmpty, let url = await makeURL(path: "channelTags/\(clean)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode(channelId)
        _ = try? await URLSession.shared.data(for: req)
    }

    public func releaseChannelTag(_ tag: String) async {
        let clean = TagValidator.sanitize(tag)
        guard !clean.isEmpty, let url = await makeURL(path: "channelTags/\(clean)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        _ = try? await URLSession.shared.data(for: req)
    }

    public func claimUserTag(_ tag: String, userId: String) async {
        let clean = TagValidator.sanitize(tag)
        guard !clean.isEmpty, let url = await makeURL(path: "userTags/\(clean)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode(userId)
        _ = try? await URLSession.shared.data(for: req)
    }

    public func releaseUserTag(_ tag: String) async {
        let clean = TagValidator.sanitize(tag)
        guard !clean.isEmpty, let url = await makeURL(path: "userTags/\(clean)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        _ = try? await URLSession.shared.data(for: req)
    }

    // MARK: - Safe Channel Parsing & Tag Lookups

    public func decodeChannelModel(from data: Data, fallbackId: String? = nil) -> ChannelModel? {
        if var model = try? JSONDecoder().decode(ChannelModel.self, from: data) {
            if model.id.isEmpty, let fid = fallbackId { model.id = fid }
            return model
        }
        guard let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return parseChannelDict(dict, fallbackId: fallbackId)
    }

    public func parseChannelDict(_ dict: [String: Any], fallbackId: String? = nil) -> ChannelModel? {
        let id = (dict["id"] as? String) ?? fallbackId ?? ""
        guard !id.isEmpty else { return nil }
        let name = (dict["name"] as? String) ?? ""
        let rawTag = (dict["tag"] as? String) ?? ""
        let tag: String
        if !rawTag.isEmpty {
            tag = TagValidator.sanitize(rawTag)
        } else {
            let nameTag = TagValidator.sanitize(name)
            if nameTag.count >= 3 {
                tag = nameTag
            } else {
                tag = "channel_\(id.prefix(6))"
            }
        }
        let description = (dict["description"] as? String) ?? ""
        let avatarEmoji = dict["avatarEmoji"] as? String
        let avatarUrl = dict["avatarUrl"] as? String
        let accentColorHex = dict["accentColorHex"] as? String
        let ownerId = (dict["ownerId"] as? String) ?? ""
        let ownerName = (dict["ownerName"] as? String) ?? ""
        let createdAtMs = (dict["createdAtMs"] as? NSNumber)?.int64Value ?? Int64(Date().timeIntervalSince1970 * 1000)
        let updatedAtMs = (dict["updatedAtMs"] as? NSNumber)?.int64Value ?? createdAtMs
        let subscriberCount = (dict["subscriberCount"] as? NSNumber)?.intValue ?? 1
        let pinnedPostId = dict["pinnedPostId"] as? String
        let isPublic = (dict["isPublic"] as? Bool) ?? true
        let lastPostText = dict["lastPostText"] as? String
        let lastPostTimestampMs = (dict["lastPostTimestampMs"] as? NSNumber)?.int64Value

        return ChannelModel(
            id: id,
            tag: tag,
            name: name,
            description: description,
            avatarEmoji: avatarEmoji,
            avatarUrl: avatarUrl,
            accentColorHex: accentColorHex,
            ownerId: ownerId,
            ownerName: ownerName,
            createdAtMs: createdAtMs,
            updatedAtMs: updatedAtMs,
            subscriberCount: subscriberCount,
            pinnedPostId: pinnedPostId,
            isPublic: isPublic,
            lastPostText: lastPostText,
            lastPostTimestampMs: lastPostTimestampMs
        )
    }

    public func lookupChannelByTag(_ tag: String) async -> ChannelModel? {
        let clean = TagValidator.sanitize(tag)
        guard !clean.isEmpty else { return nil }

        // 1. Direct tag index lookup
        if let tagUrl = await makeURL(path: "channelTags/\(clean)"),
           let (data, resp) = try? await URLSession.shared.data(from: tagUrl),
           let httpResp = resp as? HTTPURLResponse, (200...299).contains(httpResp.statusCode) {
            let rawString = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let raw = rawString, raw != "null" && !raw.isEmpty {
                let channelId = (try? JSONDecoder().decode(String.self, from: data)) ??
                    raw.trimmingCharacters(in: CharacterSet(charactersIn: "\" \n\r\t"))
                if !channelId.isEmpty,
                   let chUrl = await makeURL(path: "channels/\(channelId)"),
                   let (chData, chResp) = try? await URLSession.shared.data(from: chUrl),
                   let httpChResp = chResp as? HTTPURLResponse, (200...299).contains(httpChResp.statusCode),
                   let model = decodeChannelModel(from: chData, fallbackId: channelId) {
                    return model
                }
            }
        }

        // 2. Direct channel id lookup if tag equals id
        if let chUrl = await makeURL(path: "channels/\(clean)"),
           let (chData, chResp) = try? await URLSession.shared.data(from: chUrl),
           let httpChResp = chResp as? HTTPURLResponse, (200...299).contains(httpChResp.statusCode),
           let model = decodeChannelModel(from: chData, fallbackId: clean) {
            return model
        }

        // 3. Search in local pools by tag OR by name
        if let found = self.publicChannels.first(where: {
            $0.tag.lowercased() == clean.lowercased() ||
            TagValidator.sanitize($0.name).lowercased() == clean.lowercased() ||
            $0.name.localizedCaseInsensitiveContains(clean)
        }) {
            return found
        }
        if let found = self.subscribedChannels.first(where: {
            $0.tag.lowercased() == clean.lowercased() ||
            TagValidator.sanitize($0.name).lowercased() == clean.lowercased() ||
            $0.name.localizedCaseInsensitiveContains(clean)
        }) {
            return found
        }

        return nil
    }

    public func lookupUserByTag(_ tag: String) async -> SlooshUser? {
        let clean = TagValidator.sanitize(tag)
        guard !clean.isEmpty else { return nil }

        if let tagUrl = await makeURL(path: "userTags/\(clean)"),
           let (data, resp) = try? await URLSession.shared.data(from: tagUrl),
           let httpResp = resp as? HTTPURLResponse, (200...299).contains(httpResp.statusCode) {
            let rawString = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let raw = rawString, raw != "null" && !raw.isEmpty {
                let userId = (try? JSONDecoder().decode(String.self, from: data)) ??
                    raw.trimmingCharacters(in: CharacterSet(charactersIn: "\" \n\r\t"))
                if !userId.isEmpty {
                    if let user = getLocalKnownUsers()[userId] {
                        return user
                    }
                    if let pUrl = await makeURL(path: "user_profiles/\(userId)"),
                       let (pData, pResp) = try? await URLSession.shared.data(from: pUrl),
                       let httpPResp = pResp as? HTTPURLResponse, (200...299).contains(httpPResp.statusCode),
                       let user = try? JSONDecoder().decode(SlooshUser.self, from: pData) {
                        saveLocalKnownUser(user)
                        return user
                    }
                }
            }
        }

        return nil
    }

    // MARK: - User Registration, Sanitized Sync & Channel Propagation

    public func syncCurrentUserProfile() async {
        guard let user = AuthRepository.shared.currentUser, !user.isAnonymous else { return }

        // Auto-assign user tag from display title if tag is empty
        var effectiveTag = user.tag
        if effectiveTag == nil || effectiveTag?.isEmpty == true {
            let candidate = TagValidator.sanitize(user.displayTitle)
            if candidate.count >= 3 {
                effectiveTag = candidate
                let updatedUser = UserProfile(
                    id: user.id,
                    email: user.email,
                    displayName: user.displayName,
                    tag: candidate,
                    photoURL: user.photoURL,
                    isAnonymous: user.isAnonymous,
                    provider: user.provider,
                    idToken: user.idToken,
                    refreshToken: user.refreshToken,
                    createdAt: user.createdAt
                )
                AuthRepository.shared.saveUser(updatedUser)
            }
        }

        // Sanitize: do NOT include email or private auth fields
        let slooshUser = SlooshUser(
            id: user.id,
            displayName: user.displayTitle,
            tag: effectiveTag,
            avatarUrl: user.photoURL,
            isOnline: true
        )

        // Save locally on device
        saveLocalKnownUser(slooshUser)

        if let tag = effectiveTag, !tag.isEmpty {
            await claimUserTag(tag, userId: user.id)
        }

        guard let body = try? JSONEncoder().encode(slooshUser) else { return }

        // 1. Save to public directory /user_profiles/{uid}.json (Sanitized, NO EMAIL!)
        if let url1 = await makeURL(path: "user_profiles/\(user.id)") {
            var req = URLRequest(url: url1)
            req.httpMethod = "PUT"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
            _ = try? await URLSession.shared.data(for: req)
        }

        // 2. Save under user branch /users/{uid}/profile.json
        if let url2 = await makeURL(path: "users/\(user.id)/profile") {
            var req = URLRequest(url: url2)
            req.httpMethod = "PUT"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
            _ = try? await URLSession.shared.data(for: req)
        }

        // 3. Save under public_users/{uid}.json
        if let url3 = await makeURL(path: "public_users/\(user.id)") {
            var req = URLRequest(url: url3)
            req.httpMethod = "PUT"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
            _ = try? await URLSession.shared.data(for: req)
        }

        // 4. Also push all owned channels to Firebase to ensure they exist on the server
        await syncOwnedChannelsToFirebase()
    }

    public func syncOwnedChannelsToFirebase() async {
        guard let currentUser = AuthRepository.shared.currentUser, !currentUser.isAnonymous else { return }

        let myChannels = (self.subscribedChannels + self.publicChannels).filter { $0.ownerId == currentUser.id }
        var uniqueMap: [String: ChannelModel] = [:]
        for ch in myChannels {
            var mutable = ch
            // Auto-migrate synthetic tags to clean name tag if available
            if mutable.tag.hasPrefix("channel_") || mutable.tag.isEmpty {
                let nameTag = TagValidator.sanitize(mutable.name)
                if nameTag.count >= 3 {
                    mutable.tag = nameTag
                }
            }
            uniqueMap[mutable.id] = mutable
        }

        // Save updated channels locally
        let updatedSubs = self.subscribedChannels.map { uniqueMap[$0.id] ?? $0 }
        self.subscribedChannels = updatedSubs
        saveSubscribedChannelsToDisk(updatedSubs)

        let updatedPubs = self.publicChannels.map { uniqueMap[$0.id] ?? $0 }
        self.publicChannels = updatedPubs
        savePublicChannelsToDisk(updatedPubs)

        for (_, channel) in uniqueMap {
            let encodedData = try? JSONEncoder().encode(channel)

            // 1. Root /channels/{id}
            if let url = await makeURL(path: "channels/\(channel.id)") {
                var req = URLRequest(url: url)
                req.httpMethod = "PUT"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = encodedData
                _ = try? await URLSession.shared.data(for: req)
            }

            // 2. /public_channels/{id}
            if let url = await makeURL(path: "public_channels/\(channel.id)") {
                var req = URLRequest(url: url)
                req.httpMethod = "PUT"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = encodedData
                _ = try? await URLSession.shared.data(for: req)
            }

            // 3. /users/{uid}/channels/{id}
            if let url = await makeURL(path: "users/\(currentUser.id)/channels/\(channel.id)") {
                var req = URLRequest(url: url)
                req.httpMethod = "PUT"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = encodedData
                _ = try? await URLSession.shared.data(for: req)
            }

            // 4. Claim tag in /channelTags
            let clean = TagValidator.sanitize(channel.tag)
            if !clean.isEmpty {
                await claimChannelTag(clean, channelId: channel.id)
            }

            // 5. Also claim name tag if different and valid
            let cleanName = TagValidator.sanitize(channel.name)
            if !cleanName.isEmpty && cleanName != clean && cleanName.count >= 3 {
                await claimChannelTag(cleanName, channelId: channel.id)
            }

            // 6. Push all local channel posts to Firebase
            let posts = loadChannelPostsFromDisk(channelId: channel.id)
            for post in posts {
                let postData = try? JSONEncoder().encode(post)
                if let url = await makeURL(path: "channel_posts/\(channel.id)/\(post.id)") {
                    var req = URLRequest(url: url)
                    req.httpMethod = "PUT"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.httpBody = postData
                    _ = try? await URLSession.shared.data(for: req)
                }
                if let url = await makeURL(path: "channels/\(channel.id)/posts/\(post.id)") {
                    var req = URLRequest(url: url)
                    req.httpMethod = "PUT"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.httpBody = postData
                    _ = try? await URLSession.shared.data(for: req)
                }
                if let url = await makeURL(path: "public_channels/\(channel.id)/posts/\(post.id)") {
                    var req = URLRequest(url: url)
                    req.httpMethod = "PUT"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.httpBody = postData
                    _ = try? await URLSession.shared.data(for: req)
                }
                if let url = await makeURL(path: "users/\(currentUser.id)/channel_posts/\(channel.id)/\(post.id)") {
                    var req = URLRequest(url: url)
                    req.httpMethod = "PUT"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.httpBody = postData
                    _ = try? await URLSession.shared.data(for: req)
                }
                if let url = await makeURL(path: "users/\(currentUser.id)/channels/\(channel.id)/posts/\(post.id)") {
                    var req = URLRequest(url: url)
                    req.httpMethod = "PUT"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.httpBody = postData
                    _ = try? await URLSession.shared.data(for: req)
                }
            }
        }
    }

    public func searchUsers(query: String) async -> [SlooshUser] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            self.searchResults = []
            return []
        }

        isLoading = true
        defer { isLoading = false }

        await syncCurrentUserProfile()

        var allUsersMap: [String: SlooshUser] = [:]

        // 1. Direct tag lookup (ALWAYS check if cleanTag is valid)
        let cleanTag = TagValidator.sanitize(trimmed)
        if !cleanTag.isEmpty {
            if let directUser = await lookupUserByTag(cleanTag) {
                allUsersMap[directUser.id] = directUser
                saveLocalKnownUser(directUser)
            }
        }

        // 2. Local cached users
        let localUsers = getLocalKnownUsers()
        for (uId, user) in localUsers {
            allUsersMap[uId] = user
        }

        // 3. Load profiles from /user_profiles.json
        if let profiles = await fetchUsersFromNode("user_profiles") {
            for p in profiles {
                allUsersMap[p.id] = p
                saveLocalKnownUser(p)
            }
        }

        // 4. Load from /public_users.json
        if let pubUsers = await fetchUsersFromNode("public_users") {
            for u in pubUsers {
                if allUsersMap[u.id] == nil {
                    allUsersMap[u.id] = u
                    saveLocalKnownUser(u)
                }
            }
        }

        // 5. Fallback /users.json
        if let users = await fetchUsersFromNode("users") {
            for u in users {
                if allUsersMap[u.id] == nil {
                    allUsersMap[u.id] = u
                    saveLocalKnownUser(u)
                }
            }
        }

        // 6. Direct userTags query
        if let url = await makeURL(path: "userTags"),
           let (data, response) = try? await URLSession.shared.data(from: url),
           let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode),
           !data.isEmpty && String(data: data, encoding: .utf8) != "null",
           let tagsDict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            for (tKey, uVal) in tagsDict {
                let uId = (uVal as? String) ?? "\(uVal)"
                if !uId.isEmpty && uId != "null" && allUsersMap[uId] == nil {
                    if let user = await lookupUserByTag(tKey) {
                        allUsersMap[user.id] = user
                    }
                }
            }
        }

        let currentUserId = AuthRepository.shared.currentUser?.id ?? ""
        let queryLower = trimmed.lowercased()

        let matched = allUsersMap.values.filter { slooshUser in
            let nameMatch = slooshUser.displayName.localizedCaseInsensitiveContains(queryLower)
            let tagMatch = slooshUser.tag?.localizedCaseInsensitiveContains(queryLower) == true ||
                (!cleanTag.isEmpty && slooshUser.tag?.localizedCaseInsensitiveContains(cleanTag) == true)
            return nameMatch || tagMatch
        }

        let results = matched.map { user -> SlooshUser in
            if user.id == currentUserId && !user.displayName.contains("(Вы)") {
                return SlooshUser(
                    id: user.id,
                    displayName: "\(user.displayName) (Вы)",
                    tag: user.tag,
                    avatarUrl: user.avatarUrl,
                    isOnline: user.isOnline
                )
            }
            return user
        }

        let finalArray = Array(results).sorted { u1, u2 in
            if u1.id == currentUserId { return true }
            if u2.id == currentUserId { return false }
            return u1.displayName < u2.displayName
        }

        self.searchResults = finalArray
        return finalArray
    }

    private func fetchUsersFromNode(_ nodeName: String) async -> [SlooshUser]? {
        guard let url = await makeURL(path: nodeName) else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode) else {
                return nil
            }

            if data.isEmpty || String(data: data, encoding: .utf8) == "null" {
                return nil
            }

            guard let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }

            var results: [SlooshUser] = []
            for (key, val) in jsonObject {
                guard let dict = val as? [String: Any] else { continue }

                let sourceDict: [String: Any]
                if let profileDict = dict["profile"] as? [String: Any] {
                    sourceDict = profileDict
                } else {
                    sourceDict = dict
                }

                let id = (sourceDict["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? key
                let displayName = (sourceDict["displayName"] as? String)
                    ?? (sourceDict["name"] as? String)
                    ?? ""
                let tag = sourceDict["tag"] as? String
                let avatarUrl = sourceDict["avatarUrl"] as? String
                let isOnline = sourceDict["isOnline"] as? Bool ?? true

                if !displayName.isEmpty || tag != nil {
                    let user = SlooshUser(
                        id: id,
                        displayName: displayName,
                        tag: tag,
                        avatarUrl: avatarUrl,
                        isOnline: isOnline
                    )
                    results.append(user)
                }
            }
            return results
        } catch {
            return nil
        }
    }

    // MARK: - Conversations

    public func fetchConversations() async {
        guard let currentUser = AuthRepository.shared.currentUser, !currentUser.isAnonymous else {
            self.conversations = []
            return
        }

        if self.conversations.isEmpty {
            self.conversations = loadConversationsFromDisk()
        }

        guard let url = await makeURL(path: "user_chats/\(currentUser.id)") else { return }

        if self.conversations.isEmpty {
            isLoading = true
        }
        defer { isLoading = false }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode) else {
                return
            }

            if data.isEmpty || String(data: data, encoding: .utf8) == "null" {
                self.conversations = []
                saveConversationsToDisk([])
                return
            }

            struct RawChatEntry: Codable {
                let chatId: String
                let peerUser: SlooshUser
                let lastMessageText: String
                let unreadCount: Int?
                let updatedAtMs: Int64
            }

            let chatsDict = try JSONDecoder().decode([String: RawChatEntry].self, from: data)
            let list = chatsDict.values.map { raw -> ChatConversation in
                let cachedMsgs = self.loadMessagesFromDisk(chatId: raw.chatId)
                let currentUserId = AuthRepository.shared.currentUser?.id ?? ""
                let hasUnreadIncoming = cachedMsgs.contains(where: { $0.senderId != currentUserId && $0.isRead != true })

                let finalUnread = hasUnreadIncoming ? (raw.unreadCount ?? 0) : 0

                return ChatConversation(
                    chatId: raw.chatId,
                    peerUser: raw.peerUser,
                    lastMessageText: raw.lastMessageText,
                    unreadCount: finalUnread,
                    updatedAtMs: raw.updatedAtMs
                )
            }.sorted { $0.updatedAtMs > $1.updatedAtMs }

            self.conversations = list
            saveConversationsToDisk(list)
        } catch {
            AppDiagnostics.shared.log("MessengerRepository fetchConversations error: \(error.localizedDescription)")
        }
    }

    // MARK: - Messages

    public func getOrCreateChatId(peerUserId: String) -> String {
        guard let currentUserId = AuthRepository.shared.currentUser?.id else { return UUID().uuidString }
        return [currentUserId, peerUserId].sorted().joined(separator: "_")
    }

    public func fetchMessages(chatId: String) async -> [ChatMessage] {
        guard !chatId.isEmpty else { return [] }

        let localCached = loadMessagesFromDisk(chatId: chatId)

        guard let url = await makeURL(path: "chats/\(chatId)/messages") else { return localCached }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode) else {
                return localCached
            }

            if data.isEmpty || String(data: data, encoding: .utf8) == "null" {
                return localCached
            }

            let messagesDict = try JSONDecoder().decode([String: ChatMessage].self, from: data)
            let list = Array(messagesDict.values).sorted(by: { $0.timestampMs < $1.timestampMs })
            saveMessagesToDisk(list, chatId: chatId)
            return list
        } catch {
            AppDiagnostics.shared.log("MessengerRepository fetchMessages error: \(error.localizedDescription)")
            return localCached
        }
    }

    // MARK: - Read Receipts (isRead Sync)

    public func markMessagesAsRead(chatId: String, peerUserId: String, messages: [ChatMessage]) async {
        guard let currentUserId = AuthRepository.shared.currentUser?.id else { return }

        let unreadIncoming = messages.filter { $0.senderId == peerUserId && $0.isRead != true }
        guard !unreadIncoming.isEmpty else { return }

        var updatedList = messages
        for msg in unreadIncoming {
            if let idx = updatedList.firstIndex(where: { $0.id == msg.id }) {
                let readMsg = ChatMessage(
                    id: msg.id,
                    senderId: msg.senderId,
                    receiverId: msg.receiverId,
                    type: msg.type,
                    text: msg.text,
                    media: msg.media,
                    timestampMs: msg.timestampMs,
                    replyToId: msg.replyToId,
                    reactions: msg.reactions,
                    isEdited: msg.isEdited,
                    isRead: true
                )
                updatedList[idx] = readMsg

                Task {
                    if let msgUrl = await makeURL(path: "chats/\(chatId)/messages/\(msg.id)") {
                        var req = URLRequest(url: msgUrl)
                        req.httpMethod = "PUT"
                        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                        req.httpBody = try? JSONEncoder().encode(readMsg)
                        _ = try? await URLSession.shared.data(for: req)
                    }
                }
            }
        }
        saveMessagesToDisk(updatedList, chatId: chatId)

        if let currentConvIdx = conversations.firstIndex(where: { $0.chatId == chatId }) {
            let old = conversations[currentConvIdx]
            let updatedConv = ChatConversation(
                chatId: old.chatId,
                peerUser: old.peerUser,
                lastMessageText: old.lastMessageText,
                unreadCount: 0,
                updatedAtMs: old.updatedAtMs
            )
            conversations[currentConvIdx] = updatedConv
            saveConversationsToDisk(conversations)
        }

        if let unreadUrl = await makeURL(path: "user_chats/\(currentUserId)/\(chatId)/unreadCount") {
            var req = URLRequest(url: unreadUrl)
            req.httpMethod = "PUT"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = "0".data(using: .utf8)
            _ = try? await URLSession.shared.data(for: req)
        }
    }

    public func sendMessage(
        toPeerUser peerUser: SlooshUser,
        message: ChatMessage
    ) async -> Bool {
        guard let currentUser = AuthRepository.shared.currentUser, !currentUser.isAnonymous else { return false }

        let chatId = getOrCreateChatId(peerUserId: peerUser.id)

        // 1. Optimistic local update
        var currentMessages = loadMessagesFromDisk(chatId: chatId)
        if let idx = currentMessages.firstIndex(where: { $0.id == message.id }) {
            currentMessages[idx] = message
        } else {
            currentMessages.append(message)
        }
        saveMessagesToDisk(currentMessages, chatId: chatId)

        let previewText: String
        if let media = message.media {
            previewText = "🎬 \(media.title)"
        } else {
            previewText = message.text ?? ""
        }

        let updatedConv = ChatConversation(
            chatId: chatId,
            peerUser: peerUser,
            lastMessageText: previewText,
            unreadCount: 0,
            updatedAtMs: message.timestampMs
        )
        var convs = self.conversations
        if let idx = convs.firstIndex(where: { $0.chatId == chatId }) {
            convs[idx] = updatedConv
        } else {
            convs.insert(updatedConv, at: 0)
        }
        convs.sort { $0.updatedAtMs > $1.updatedAtMs }
        self.conversations = convs
        saveConversationsToDisk(convs)

        // 2. Background REST
        Task {
            _ = await postMessageToFirebase(chatId: chatId, message: message, peerUser: peerUser)
        }
        return true
    }

    public func sendMessage(
        toPeerUser peerUser: SlooshUser,
        text: String? = nil,
        mediaPayload: MediaCardPayload? = nil,
        replyToId: String? = nil
    ) async -> Bool {
        guard let currentUser = AuthRepository.shared.currentUser, !currentUser.isAnonymous else { return false }
        let messageType: MessageType = (mediaPayload != nil) ? .media : .text

        let message = ChatMessage(
            senderId: currentUser.id,
            receiverId: peerUser.id,
            type: messageType,
            text: text,
            media: mediaPayload,
            replyToId: replyToId
        )
        return await sendMessage(toPeerUser: peerUser, message: message)
    }

    public func postMessageToFirebase(
        chatId: String,
        message: ChatMessage,
        peerUser: SlooshUser? = nil
    ) async -> Bool {
        guard let currentUser = AuthRepository.shared.currentUser, !currentUser.isAnonymous else { return false }
        guard let msgUrl = await makeURL(path: "chats/\(chatId)/messages/\(message.id)") else { return false }

        do {
            var request = URLRequest(url: msgUrl)
            request.httpMethod = "PUT"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(message)

            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode) else {
                return false
            }

            if let peerUser = peerUser {
                let previewText: String
                if let media = message.media {
                    previewText = "🎬 \(media.title)"
                } else {
                    previewText = message.text ?? ""
                }

                // Update user_chats for sender (Sanitized, NO EMAIL!)
                var peerDict: [String: Any] = [
                    "id": peerUser.id,
                    "displayName": peerUser.displayName,
                    "avatarUrl": peerUser.avatarUrl ?? ""
                ]
                if let tag = peerUser.tag {
                    peerDict["tag"] = tag
                }

                let senderEntry: [String: Any] = [
                    "chatId": chatId,
                    "peerUser": peerDict,
                    "lastMessageText": previewText,
                    "unreadCount": 0,
                    "updatedAtMs": message.timestampMs
                ]

                if let senderUrl = await makeURL(path: "user_chats/\(currentUser.id)/\(chatId)") {
                    var req = URLRequest(url: senderUrl)
                    req.httpMethod = "PUT"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.httpBody = try? JSONSerialization.data(withJSONObject: senderEntry)
                    _ = try? await URLSession.shared.data(for: req)
                }

                // Update user_chats for receiver (Sanitized, NO EMAIL!)
                var currentDict: [String: Any] = [
                    "id": currentUser.id,
                    "displayName": currentUser.displayTitle,
                    "avatarUrl": currentUser.photoURL ?? ""
                ]
                if let tag = currentUser.tag {
                    currentDict["tag"] = tag
                }

                let receiverEntry: [String: Any] = [
                    "chatId": chatId,
                    "peerUser": currentDict,
                    "lastMessageText": previewText,
                    "unreadCount": 1,
                    "updatedAtMs": message.timestampMs
                ]

                if let receiverUrl = await makeURL(path: "user_chats/\(peerUser.id)/\(chatId)") {
                    var req = URLRequest(url: receiverUrl)
                    req.httpMethod = "PUT"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.httpBody = try? JSONSerialization.data(withJSONObject: receiverEntry)
                    _ = try? await URLSession.shared.data(for: req)
                }
            }

            return true
        } catch {
            AppDiagnostics.shared.log("MessengerRepository postMessageToFirebase error: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Message Deletion

    public func deleteMessage(
        chatId: String,
        messageId: String,
        peerUser: SlooshUser
    ) async {
        guard let currentUser = AuthRepository.shared.currentUser, !currentUser.isAnonymous else { return }

        var currentMessages = loadMessagesFromDisk(chatId: chatId)
        currentMessages.removeAll(where: { $0.id == messageId })
        saveMessagesToDisk(currentMessages, chatId: chatId)

        let lastMsg = currentMessages.last
        let previewText: String
        if let media = lastMsg?.media {
            previewText = "🎬 \(media.title)"
        } else {
            previewText = lastMsg?.text ?? ""
        }
        let lastTimestamp = lastMsg?.timestampMs ?? Int64(Date().timeIntervalSince1970 * 1000)

        let updatedConv = ChatConversation(
            chatId: chatId,
            peerUser: peerUser,
            lastMessageText: previewText,
            unreadCount: 0,
            updatedAtMs: lastTimestamp
        )
        var convs = self.conversations
        if let idx = convs.firstIndex(where: { $0.chatId == chatId }) {
            convs[idx] = updatedConv
        }
        self.conversations = convs
        saveConversationsToDisk(convs)

        if let msgUrl = await makeURL(path: "chats/\(chatId)/messages/\(messageId)") {
            var req = URLRequest(url: msgUrl)
            req.httpMethod = "DELETE"
            _ = try? await URLSession.shared.data(for: req)
        }

        if let senderUrl = await makeURL(path: "user_chats/\(currentUser.id)/\(chatId)/lastMessageText") {
            var req = URLRequest(url: senderUrl)
            req.httpMethod = "PUT"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONEncoder().encode(previewText)
            _ = try? await URLSession.shared.data(for: req)
        }

        if let receiverUrl = await makeURL(path: "user_chats/\(peerUser.id)/\(chatId)/lastMessageText") {
            var req = URLRequest(url: receiverUrl)
            req.httpMethod = "PUT"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONEncoder().encode(previewText)
            _ = try? await URLSession.shared.data(for: req)
        }
    }

    // MARK: - Channel Creation & Management

    public func createChannel(
        name: String,
        description: String = "",
        tag: String,
        avatarUrl: String? = nil,
        accentColorHex: String? = "#FF9F0A"
    ) async -> ChannelModel? {
        guard let currentUser = AuthRepository.shared.currentUser, !currentUser.isAnonymous else {
            return nil
        }

        let cleanTag = TagValidator.sanitize(tag)
        let validation = TagValidator.validate(cleanTag)
        guard validation.isValid else { return nil }

        // Check availability
        let check = await checkChannelTagAvailability(tag: cleanTag)
        guard check.isAvailable else { return nil }

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let channelId = "ch_\(now)_\(UUID().uuidString.prefix(6).lowercased())"
        let creatorName = currentUser.displayTitle

        let channel = ChannelModel(
            id: channelId,
            tag: cleanTag,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            avatarEmoji: nil,
            avatarUrl: avatarUrl,
            accentColorHex: accentColorHex,
            ownerId: currentUser.id,
            ownerName: creatorName,
            createdAtMs: now,
            updatedAtMs: now,
            subscriberCount: 1,
            pinnedPostId: nil,
            isPublic: true,
            lastPostText: nil,
            lastPostTimestampMs: nil
        )

        // 1. Optimistically insert into subscribedChannels & publicChannels & disk cache
        var currentSubscribed = self.subscribedChannels
        currentSubscribed.insert(channel, at: 0)
        self.subscribedChannels = currentSubscribed
        saveSubscribedChannelsToDisk(currentSubscribed)

        var currentPublic = self.publicChannels
        if !currentPublic.contains(where: { $0.id == channel.id }) {
            currentPublic.insert(channel, at: 0)
            self.publicChannels = currentPublic
            savePublicChannelsToDisk(currentPublic)
        }

        // 2. Claim tag index
        await claimChannelTag(cleanTag, channelId: channelId)

        // 3. Firebase REST Calls
        let encodedData = try? JSONEncoder().encode(channel)

        // 3a. PUT /channels/{channelId}.json
        if let channelUrl = await makeURL(path: "channels/\(channelId)") {
            var req = URLRequest(url: channelUrl)
            req.httpMethod = "PUT"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = encodedData
            _ = try? await URLSession.shared.data(for: req)
        }

        // 3b. PUT /public_channels/{channelId}.json
        if let pubUrl = await makeURL(path: "public_channels/\(channelId)") {
            var req = URLRequest(url: pubUrl)
            req.httpMethod = "PUT"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = encodedData
            _ = try? await URLSession.shared.data(for: req)
        }

        // 3c. PUT /users/{userId}/channels/{channelId}.json (Guaranteed write permission)
        if let userChanUrl = await makeURL(path: "users/\(currentUser.id)/channels/\(channelId)") {
            var req = URLRequest(url: userChanUrl)
            req.httpMethod = "PUT"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = encodedData
            _ = try? await URLSession.shared.data(for: req)
        }

        // 3d. PUT /user_channel_subscriptions/{userId}/{channelId}.json
        let subscription = ChannelSubscription(
            channelId: channelId,
            channel: channel,
            subscribedAtMs: now,
            isMuted: false
        )
        if let subUrl = await makeURL(path: "user_channel_subscriptions/\(currentUser.id)/\(channelId)") {
            var req = URLRequest(url: subUrl)
            req.httpMethod = "PUT"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONEncoder().encode(subscription)
            _ = try? await URLSession.shared.data(for: req)
        }

        // 3e. PUT /channel_subscribers/{channelId}/{userId}.json
        if let subscriberUrl = await makeURL(path: "channel_subscribers/\(channelId)/\(currentUser.id)") {
            var req = URLRequest(url: subscriberUrl)
            req.httpMethod = "PUT"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let subPayload: [String: Any] = ["subscribedAtMs": now]
            req.httpBody = try? JSONSerialization.data(withJSONObject: subPayload)
            _ = try? await URLSession.shared.data(for: req)
        }

        return channel
    }

    public func updateChannelMetadata(channel: ChannelModel, oldTag: String? = nil) async -> Bool {
        var updated = channel
        updated.updatedAtMs = Int64(Date().timeIntervalSince1970 * 1000)

        if let old = oldTag, !old.isEmpty && old != updated.tag {
            await releaseChannelTag(old)
            await claimChannelTag(updated.tag, channelId: updated.id)
        }

        // 1. Optimistic update
        var subs = self.subscribedChannels
        if let sIdx = subs.firstIndex(where: { $0.id == channel.id }) {
            subs[sIdx] = updated
            self.subscribedChannels = subs
            saveSubscribedChannelsToDisk(subs)
        }

        var pubs = self.publicChannels
        if let pIdx = pubs.firstIndex(where: { $0.id == channel.id }) {
            pubs[pIdx] = updated
            self.publicChannels = pubs
            savePublicChannelsToDisk(pubs)
        }

        let updatedData = try? JSONEncoder().encode(updated)

        // 2. PUT /channels/{channelId}.json
        if let channelUrl = await makeURL(path: "channels/\(channel.id)") {
            var req = URLRequest(url: channelUrl)
            req.httpMethod = "PUT"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = updatedData
            _ = try? await URLSession.shared.data(for: req)
        }

        // 3. PUT /public_channels/{channelId}.json
        if let pubUrl = await makeURL(path: "public_channels/\(channel.id)") {
            var req = URLRequest(url: pubUrl)
            req.httpMethod = "PUT"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = updatedData
            _ = try? await URLSession.shared.data(for: req)
        }

        // 4. PUT /users/{ownerId}/channels/{channelId}.json
        if let userChanUrl = await makeURL(path: "users/\(channel.ownerId)/channels/\(channel.id)") {
            var req = URLRequest(url: userChanUrl)
            req.httpMethod = "PUT"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = updatedData
            _ = try? await URLSession.shared.data(for: req)
        }

        // 5. PUT /user_channel_subscriptions/{ownerId}/{channelId}/channel.json
        if let subUrl = await makeURL(path: "user_channel_subscriptions/\(channel.ownerId)/\(channel.id)/channel") {
            var req = URLRequest(url: subUrl)
            req.httpMethod = "PUT"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = updatedData
            _ = try? await URLSession.shared.data(for: req)
        }

        return true
    }

    public func deleteChannel(channelId: String) async -> Bool {
        guard let currentUser = AuthRepository.shared.currentUser, !currentUser.isAnonymous else {
            return false
        }

        let existingTag = subscribedChannels.first(where: { $0.id == channelId })?.tag
            ?? publicChannels.first(where: { $0.id == channelId })?.tag

        // 1. Remove from local collections and disk caches
        self.subscribedChannels.removeAll(where: { $0.id == channelId })
        saveSubscribedChannelsToDisk(self.subscribedChannels)

        self.publicChannels.removeAll(where: { $0.id == channelId })
        savePublicChannelsToDisk(self.publicChannels)

        saveChannelPostsToDisk([], channelId: channelId)

        // 2. REST deletions
        Task {
            if let tag = existingTag, !tag.isEmpty {
                await releaseChannelTag(tag)
            }

            // DELETE /channels/{channelId}.json
            if let channelUrl = await makeURL(path: "channels/\(channelId)") {
                var req = URLRequest(url: channelUrl)
                req.httpMethod = "DELETE"
                _ = try? await URLSession.shared.data(for: req)
            }

            // DELETE /public_channels/{channelId}.json
            if let pubUrl = await makeURL(path: "public_channels/\(channelId)") {
                var req = URLRequest(url: pubUrl)
                req.httpMethod = "DELETE"
                _ = try? await URLSession.shared.data(for: req)
            }

            // DELETE /users/{userId}/channels/{channelId}.json
            if let userChanUrl = await makeURL(path: "users/\(currentUser.id)/channels/\(channelId)") {
                var req = URLRequest(url: userChanUrl)
                req.httpMethod = "DELETE"
                _ = try? await URLSession.shared.data(for: req)
            }

            // DELETE /channel_posts/{channelId}.json
            if let postsUrl = await makeURL(path: "channel_posts/\(channelId)") {
                var req = URLRequest(url: postsUrl)
                req.httpMethod = "DELETE"
                _ = try? await URLSession.shared.data(for: req)
            }

            // DELETE /channel_subscribers/{channelId}.json
            if let subsUrl = await makeURL(path: "channel_subscribers/\(channelId)") {
                var req = URLRequest(url: subsUrl)
                req.httpMethod = "DELETE"
                _ = try? await URLSession.shared.data(for: req)
            }

            // DELETE /user_channel_subscriptions/{userId}/{channelId}.json
            if let userSubUrl = await makeURL(path: "user_channel_subscriptions/\(currentUser.id)/\(channelId)") {
                var req = URLRequest(url: userSubUrl)
                req.httpMethod = "DELETE"
                _ = try? await URLSession.shared.data(for: req)
            }
        }

        return true
    }

    // MARK: - Channel Subscriptions & Discovery

    public func isSubscribed(channelId: String) -> Bool {
        return subscribedChannels.contains(where: { $0.id == channelId })
    }

    public func fetchSubscribedChannels() async -> [ChannelModel] {
        guard let currentUser = AuthRepository.shared.currentUser, !currentUser.isAnonymous else {
            return self.subscribedChannels
        }

        if self.subscribedChannels.isEmpty {
            self.subscribedChannels = loadSubscribedChannelsFromDisk(userId: currentUser.id)
        }

        var combinedMap: [String: ChannelModel] = [:]
        // Pre-fill with cached channels owned by this user
        for ch in self.subscribedChannels where ch.ownerId == currentUser.id {
            combinedMap[ch.id] = ch
        }

        // 1. Fetch user subscriptions from /user_channel_subscriptions/{userId}.json
        if let subUrl = await makeURL(path: "user_channel_subscriptions/\(currentUser.id)"),
           let (data, response) = try? await URLSession.shared.data(from: subUrl),
           let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode),
           !data.isEmpty && String(data: data, encoding: .utf8) != "null",
           let subDict = try? JSONDecoder().decode([String: ChannelSubscription].self, from: data) {
            for (chId, sub) in subDict {
                if let ch = sub.channel {
                    combinedMap[ch.id] = ch
                } else if !chId.isEmpty {
                    if let direct = await lookupChannelByTag(chId) {
                        combinedMap[direct.id] = direct
                    }
                }
            }
        }

        // 2. Fetch owned channels from /users/{userId}/channels.json
        if let ownedUrl = await makeURL(path: "users/\(currentUser.id)/channels"),
           let (ownedData, ownedResp) = try? await URLSession.shared.data(from: ownedUrl),
           let httpOwnedResp = ownedResp as? HTTPURLResponse, (200...299).contains(httpOwnedResp.statusCode),
           !ownedData.isEmpty && String(data: ownedData, encoding: .utf8) != "null" {
            if let ownedDict = try? JSONDecoder().decode([String: ChannelModel].self, from: ownedData) {
                for (_, ch) in ownedDict {
                    combinedMap[ch.id] = ch
                }
            } else if let rawDict = (try? JSONSerialization.jsonObject(with: ownedData)) as? [String: Any] {
                for (chId, val) in rawDict {
                    if let chDict = val as? [String: Any],
                       let ch = parseChannelDict(chDict, fallbackId: chId) {
                        combinedMap[ch.id] = ch
                    }
                }
            }
        }

        // 3. Fetch from /channels.json and find any channels owned by this user
        if let allChannelsUrl = await makeURL(path: "channels"),
           let (channelsData, resp2) = try? await URLSession.shared.data(from: allChannelsUrl),
           let httpResp2 = resp2 as? HTTPURLResponse, (200...299).contains(httpResp2.statusCode),
           !channelsData.isEmpty && String(data: channelsData, encoding: .utf8) != "null",
           let rawDict = (try? JSONSerialization.jsonObject(with: channelsData)) as? [String: Any] {
            for (chId, val) in rawDict {
                if let chDict = val as? [String: Any],
                   let ch = parseChannelDict(chDict, fallbackId: chId) {
                    if ch.ownerId == currentUser.id || combinedMap[ch.id] != nil {
                        combinedMap[ch.id] = ch
                    }
                }
            }
        }

        let sorted = Array(combinedMap.values).sorted { ($0.lastPostTimestampMs ?? $0.updatedAtMs) > ($1.lastPostTimestampMs ?? $1.updatedAtMs) }
        self.subscribedChannels = sorted
        saveSubscribedChannelsToDisk(sorted, userId: currentUser.id)
        return sorted
    }

    public func fetchPublicChannels(query: String? = nil) async -> [ChannelModel] {
        if self.publicChannels.isEmpty {
            self.publicChannels = loadPublicChannelsFromDisk()
        }

        let trimmed = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var directMatch: ChannelModel? = nil

        let cleanTag = TagValidator.sanitize(trimmed)
        if !cleanTag.isEmpty {
            directMatch = await lookupChannelByTag(cleanTag)
        }

        var combinedPool: [String: ChannelModel] = [:]
        for ch in self.publicChannels {
            combinedPool[ch.id] = ch
        }
        for ch in self.subscribedChannels {
            combinedPool[ch.id] = ch
        }
        if let direct = directMatch {
            combinedPool[direct.id] = direct
        }

        // 1. Fetch from /channels.json
        if let url = await makeURL(path: "channels"),
           let (data, response) = try? await URLSession.shared.data(from: url),
           let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode),
           !data.isEmpty && String(data: data, encoding: .utf8) != "null" {
            if let rawDict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                for (chId, val) in rawDict {
                    if let channelDict = val as? [String: Any],
                       let model = parseChannelDict(channelDict, fallbackId: chId) {
                        combinedPool[model.id] = model
                    }
                }
            } else if let rawArray = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] {
                for channelDict in rawArray {
                    if let model = parseChannelDict(channelDict) {
                        combinedPool[model.id] = model
                    }
                }
            }
        }

        // 2. Fetch from /public_channels.json
        if let url = await makeURL(path: "public_channels"),
           let (data, response) = try? await URLSession.shared.data(from: url),
           let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode),
           !data.isEmpty && String(data: data, encoding: .utf8) != "null" {
            if let rawDict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                for (chId, val) in rawDict {
                    if let channelDict = val as? [String: Any],
                       let model = parseChannelDict(channelDict, fallbackId: chId) {
                        combinedPool[model.id] = model
                    }
                }
            }
        }

        // 3. Scan all users in /users.json to discover channels created by any user
        if let url = await makeURL(path: "users"),
           let (data, response) = try? await URLSession.shared.data(from: url),
           let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode),
           !data.isEmpty && String(data: data, encoding: .utf8) != "null",
           let usersDict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            for (_, userVal) in usersDict {
                guard let userObj = userVal as? [String: Any] else { continue }
                if let userChannels = userObj["channels"] as? [String: Any] {
                    for (chId, chanVal) in userChannels {
                        if let chanDict = chanVal as? [String: Any],
                           let model = parseChannelDict(chanDict, fallbackId: chId) {
                            combinedPool[model.id] = model
                        }
                    }
                }
            }
        }

        // 4. Fetch from /channelTags.json to resolve all indexed channels
        if let url = await makeURL(path: "channelTags"),
           let (data, response) = try? await URLSession.shared.data(from: url),
           let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode),
           !data.isEmpty && String(data: data, encoding: .utf8) != "null",
           let tagsDict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            for (tagKey, val) in tagsDict {
                let chanId = (val as? String) ?? "\(val)"
                if !chanId.isEmpty && chanId != "null" && combinedPool[chanId] == nil {
                    if let direct = await lookupChannelByTag(tagKey) {
                        combinedPool[direct.id] = direct
                    }
                }
            }
        }

        let allPublic = Array(combinedPool.values).sorted { $0.subscriberCount > $1.subscriberCount }
        self.publicChannels = allPublic
        savePublicChannelsToDisk(allPublic)

        return filterChannels(allPublic, query: query, directMatch: directMatch)
    }

    private func filterChannels(_ list: [ChannelModel], query: String?, directMatch: ChannelModel?) -> [ChannelModel] {
        var results = list
        if let direct = directMatch, !results.contains(where: { $0.id == direct.id }) {
            results.insert(direct, at: 0)
        }

        guard let query = query?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty else {
            return results
        }

        let queryLower = query.lowercased()
        let cleanTag = TagValidator.sanitize(query)

        return results.filter { ch in
            ch.name.localizedCaseInsensitiveContains(queryLower) ||
            ch.tag.localizedCaseInsensitiveContains(queryLower) ||
            (!cleanTag.isEmpty && ch.tag.localizedCaseInsensitiveContains(cleanTag)) ||
            (!cleanTag.isEmpty && TagValidator.sanitize(ch.name).localizedCaseInsensitiveContains(cleanTag))
        }
    }

    public func subscribeToChannel(channel: ChannelModel) async -> Bool {
        guard let currentUser = AuthRepository.shared.currentUser, !currentUser.isAnonymous else {
            return false
        }

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        var updatedChannel = channel
        if !isSubscribed(channelId: channel.id) {
            updatedChannel.subscriberCount += 1
        }

        // 1. Optimistic local update
        var subs = self.subscribedChannels
        if !subs.contains(where: { $0.id == channel.id }) {
            subs.insert(updatedChannel, at: 0)
        }
        self.subscribedChannels = subs
        saveSubscribedChannelsToDisk(subs)

        var pubs = self.publicChannels
        if let pIdx = pubs.firstIndex(where: { $0.id == channel.id }) {
            pubs[pIdx] = updatedChannel
            self.publicChannels = pubs
            savePublicChannelsToDisk(pubs)
        }

        // 2. PUT to user_channel_subscriptions/{userId}/{channelId}.json
        let subscription = ChannelSubscription(
            channelId: channel.id,
            channel: updatedChannel,
            subscribedAtMs: now,
            isMuted: false
        )
        if let subUrl = await makeURL(path: "user_channel_subscriptions/\(currentUser.id)/\(channel.id)") {
            var req = URLRequest(url: subUrl)
            req.httpMethod = "PUT"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONEncoder().encode(subscription)
            _ = try? await URLSession.shared.data(for: req)
        }

        // 3. PUT to channel_subscribers/{channelId}/{userId}.json
        if let subscriberUrl = await makeURL(path: "channel_subscribers/\(channel.id)/\(currentUser.id)") {
            var req = URLRequest(url: subscriberUrl)
            req.httpMethod = "PUT"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let subPayload: [String: Any] = ["subscribedAtMs": now]
            req.httpBody = try? JSONSerialization.data(withJSONObject: subPayload)
            _ = try? await URLSession.shared.data(for: req)
        }

        // 4. Update subscriberCount on /channels/{channelId}/subscriberCount.json
        if let countUrl = await makeURL(path: "channels/\(channel.id)/subscriberCount") {
            var req = URLRequest(url: countUrl)
            req.httpMethod = "PUT"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = "\(updatedChannel.subscriberCount)".data(using: .utf8)
            _ = try? await URLSession.shared.data(for: req)
        }

        return true
    }

    public func unsubscribeFromChannel(channelId: String) async -> Bool {
        guard let currentUser = AuthRepository.shared.currentUser, !currentUser.isAnonymous else {
            return false
        }

        // 1. Optimistic local update
        var subs = self.subscribedChannels
        var updatedCount = 1
        if let idx = subs.firstIndex(where: { $0.id == channelId }) {
            updatedCount = max(0, subs[idx].subscriberCount - 1)
            subs.remove(at: idx)
        }
        self.subscribedChannels = subs
        saveSubscribedChannelsToDisk(subs)

        var pubs = self.publicChannels
        if let pIdx = pubs.firstIndex(where: { $0.id == channelId }) {
            pubs[pIdx].subscriberCount = updatedCount
            self.publicChannels = pubs
            savePublicChannelsToDisk(pubs)
        }

        // 2. DELETE /user_channel_subscriptions/{userId}/{channelId}.json
        if let subUrl = await makeURL(path: "user_channel_subscriptions/\(currentUser.id)/\(channelId)") {
            var req = URLRequest(url: subUrl)
            req.httpMethod = "DELETE"
            _ = try? await URLSession.shared.data(for: req)
        }

        // 3. DELETE /channel_subscribers/{channelId}/{userId}.json
        if let subscriberUrl = await makeURL(path: "channel_subscribers/\(channelId)/\(currentUser.id)") {
            var req = URLRequest(url: subscriberUrl)
            req.httpMethod = "DELETE"
            _ = try? await URLSession.shared.data(for: req)
        }

        // 4. Update subscriberCount on /channels/{channelId}/subscriberCount.json
        if let countUrl = await makeURL(path: "channels/\(channelId)/subscriberCount") {
            var req = URLRequest(url: countUrl)
            req.httpMethod = "PUT"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = "\(updatedCount)".data(using: .utf8)
            _ = try? await URLSession.shared.data(for: req)
        }

        return true
    }

    // MARK: - Safe Channel Post Parsing & Multi-Path Storage

    public func decodeChannelPost(from data: Data, fallbackId: String? = nil) -> ChannelPost? {
        if var model = try? JSONDecoder().decode(ChannelPost.self, from: data) {
            return model
        }
        guard let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return parseChannelPostDict(dict, fallbackId: fallbackId)
    }

    public func parseChannelPostDict(_ dict: [String: Any], fallbackId: String? = nil) -> ChannelPost? {
        let id = (dict["id"] as? String) ?? fallbackId ?? ""
        guard !id.isEmpty else { return nil }
        let channelId = (dict["channelId"] as? String) ?? ""
        let authorId = (dict["authorId"] as? String) ?? ""
        let text = dict["text"] as? String

        var mediaPayload: MediaCardPayload? = nil
        if let mediaDict = dict["media"] as? [String: Any],
           let mediaData = try? JSONSerialization.data(withJSONObject: mediaDict) {
            mediaPayload = try? JSONDecoder().decode(MediaCardPayload.self, from: mediaData)
        }

        var reactions: [String: String]? = nil
        if let reactDict = dict["reactions"] as? [String: Any] {
            var map: [String: String] = [:]
            for (k, v) in reactDict {
                if let emojiStr = v as? String {
                    map[k] = emojiStr
                }
            }
            if !map.isEmpty { reactions = map }
        }

        let timestampMs = (dict["timestampMs"] as? NSNumber)?.int64Value ?? Int64(Date().timeIntervalSince1970 * 1000)
        let isPinned = (dict["isPinned"] as? Bool) ?? false
        let isEdited = dict["isEdited"] as? Bool
        let viewsCount = (dict["viewsCount"] as? NSNumber)?.intValue

        return ChannelPost(
            id: id,
            channelId: channelId,
            authorId: authorId,
            text: text,
            media: mediaPayload,
            reactions: reactions,
            timestampMs: timestampMs,
            isPinned: isPinned,
            isEdited: isEdited,
            viewsCount: viewsCount
        )
    }

    public func fetchChannelPosts(channelId: String) async -> [ChannelPost] {
        guard !channelId.isEmpty else { return [] }
        let cached = loadChannelPostsFromDisk(channelId: channelId)
        var combinedMap: [String: ChannelPost] = [:]
        for p in cached {
            combinedMap[p.id] = p
        }

        // 1. Fetch from /channel_posts/{channelId}.json
        if let url1 = await makeURL(path: "channel_posts/\(channelId)"),
           let (data1, resp1) = try? await URLSession.shared.data(from: url1),
           let http1 = resp1 as? HTTPURLResponse, (200...299).contains(http1.statusCode),
           !data1.isEmpty && String(data: data1, encoding: .utf8) != "null" {
            if let rawDict = (try? JSONSerialization.jsonObject(with: data1)) as? [String: Any] {
                for (pId, val) in rawDict {
                    if let postDict = val as? [String: Any],
                       let post = parseChannelPostDict(postDict, fallbackId: pId) {
                        combinedMap[post.id] = post
                    }
                }
            } else if let rawArray = (try? JSONSerialization.jsonObject(with: data1)) as? [[String: Any]] {
                for postDict in rawArray {
                    if let post = parseChannelPostDict(postDict) {
                        combinedMap[post.id] = post
                    }
                }
            }
        }

        // 2. Fetch from /channels/{channelId}/posts.json
        if let url2 = await makeURL(path: "channels/\(channelId)/posts"),
           let (data2, resp2) = try? await URLSession.shared.data(from: url2),
           let http2 = resp2 as? HTTPURLResponse, (200...299).contains(http2.statusCode),
           !data2.isEmpty && String(data: data2, encoding: .utf8) != "null" {
            if let rawDict = (try? JSONSerialization.jsonObject(with: data2)) as? [String: Any] {
                for (pId, val) in rawDict {
                    if let postDict = val as? [String: Any],
                       let post = parseChannelPostDict(postDict, fallbackId: pId) {
                        combinedMap[post.id] = post
                    }
                }
            } else if let rawArray = (try? JSONSerialization.jsonObject(with: data2)) as? [[String: Any]] {
                for postDict in rawArray {
                    if let post = parseChannelPostDict(postDict) {
                        combinedMap[post.id] = post
                    }
                }
            }
        }

        // 3. Fetch from /public_channels/{channelId}/posts.json
        if let url3 = await makeURL(path: "public_channels/\(channelId)/posts"),
           let (data3, resp3) = try? await URLSession.shared.data(from: url3),
           let http3 = resp3 as? HTTPURLResponse, (200...299).contains(http3.statusCode),
           !data3.isEmpty && String(data: data3, encoding: .utf8) != "null" {
            if let rawDict = (try? JSONSerialization.jsonObject(with: data3)) as? [String: Any] {
                for (pId, val) in rawDict {
                    if let postDict = val as? [String: Any],
                       let post = parseChannelPostDict(postDict, fallbackId: pId) {
                        combinedMap[post.id] = post
                    }
                }
            }
        }

        // 4. Fetch from channel owner user node if available
        let ownerId = self.publicChannels.first(where: { $0.id == channelId })?.ownerId ??
            self.subscribedChannels.first(where: { $0.id == channelId })?.ownerId
        if let owner = ownerId, !owner.isEmpty {
            if let url4 = await makeURL(path: "users/\(owner)/channel_posts/\(channelId)"),
               let (data4, resp4) = try? await URLSession.shared.data(from: url4),
               let http4 = resp4 as? HTTPURLResponse, (200...299).contains(http4.statusCode),
               !data4.isEmpty && String(data: data4, encoding: .utf8) != "null",
               let rawDict = (try? JSONSerialization.jsonObject(with: data4)) as? [String: Any] {
                for (pId, val) in rawDict {
                    if let postDict = val as? [String: Any],
                       let post = parseChannelPostDict(postDict, fallbackId: pId) {
                        combinedMap[post.id] = post
                    }
                }
            }
        }

        let sorted = Array(combinedMap.values).sorted(by: { $0.timestampMs < $1.timestampMs })
        saveChannelPostsToDisk(sorted, channelId: channelId)
        return sorted
    }

    public func publishChannelPost(
        channelId: String,
        text: String? = nil,
        mediaPayload: MediaCardPayload? = nil,
        isPinned: Bool = false
    ) async -> ChannelPost? {
        guard let currentUser = AuthRepository.shared.currentUser, !currentUser.isAnonymous else {
            return nil
        }

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let postId = "post_\(now)_\(UUID().uuidString.prefix(6).lowercased())"
        let post = ChannelPost(
            id: postId,
            channelId: channelId,
            authorId: currentUser.id,
            text: text,
            media: mediaPayload,
            reactions: nil,
            timestampMs: now,
            isPinned: isPinned,
            isEdited: false,
            viewsCount: 1
        )

        var currentPosts = loadChannelPostsFromDisk(channelId: channelId)
        if isPinned {
            for i in 0..<currentPosts.count {
                if currentPosts[i].isPinned {
                    currentPosts[i].isPinned = false
                }
            }
        }
        currentPosts.append(post)
        saveChannelPostsToDisk(currentPosts, channelId: channelId)

        let previewText: String
        if let media = mediaPayload {
            previewText = "🎬 \(media.title)"
        } else {
            previewText = text ?? ""
        }

        var subs = self.subscribedChannels
        if let idx = subs.firstIndex(where: { $0.id == channelId }) {
            subs[idx].lastPostText = previewText
            subs[idx].lastPostTimestampMs = now
            subs[idx].updatedAtMs = now
            if isPinned {
                subs[idx].pinnedPostId = postId
            }
            self.subscribedChannels = subs
            saveSubscribedChannelsToDisk(subs)
        }

        var pubs = self.publicChannels
        if let pIdx = pubs.firstIndex(where: { $0.id == channelId }) {
            pubs[pIdx].lastPostText = previewText
            pubs[pIdx].lastPostTimestampMs = now
            pubs[pIdx].updatedAtMs = now
            if isPinned {
                pubs[pIdx].pinnedPostId = postId
            }
            self.publicChannels = pubs
            savePublicChannelsToDisk(pubs)
        }

        let postData = try? JSONEncoder().encode(post)

        Task {
            // 1. PUT /channel_posts/{channelId}/{postId}.json
            if let postUrl = await makeURL(path: "channel_posts/\(channelId)/\(postId)") {
                var req = URLRequest(url: postUrl)
                req.httpMethod = "PUT"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = postData
                _ = try? await URLSession.shared.data(for: req)
            }

            // 2. PUT /channels/{channelId}/posts/{postId}.json
            if let chPostUrl = await makeURL(path: "channels/\(channelId)/posts/\(postId)") {
                var req = URLRequest(url: chPostUrl)
                req.httpMethod = "PUT"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = postData
                _ = try? await URLSession.shared.data(for: req)
            }

            // 3. PUT /public_channels/{channelId}/posts/{postId}.json
            if let pubPostUrl = await makeURL(path: "public_channels/\(channelId)/posts/\(postId)") {
                var req = URLRequest(url: pubPostUrl)
                req.httpMethod = "PUT"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = postData
                _ = try? await URLSession.shared.data(for: req)
            }

            // 4. PUT /users/{uid}/channel_posts/{channelId}/{postId}.json
            if let userPostUrl = await makeURL(path: "users/\(currentUser.id)/channel_posts/\(channelId)/\(postId)") {
                var req = URLRequest(url: userPostUrl)
                req.httpMethod = "PUT"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = postData
                _ = try? await URLSession.shared.data(for: req)
            }

            // 5. PUT /users/{uid}/channels/{channelId}/posts/{postId}.json
            if let userChPostUrl = await makeURL(path: "users/\(currentUser.id)/channels/\(channelId)/posts/\(postId)") {
                var req = URLRequest(url: userChPostUrl)
                req.httpMethod = "PUT"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = postData
                _ = try? await URLSession.shared.data(for: req)
            }

            // Update preview text and timestamp
            if let lastTextUrl = await makeURL(path: "channels/\(channelId)/lastPostText") {
                var req = URLRequest(url: lastTextUrl)
                req.httpMethod = "PUT"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = try? JSONEncoder().encode(previewText)
                _ = try? await URLSession.shared.data(for: req)
            }

            if let lastTimeUrl = await makeURL(path: "channels/\(channelId)/lastPostTimestampMs") {
                var req = URLRequest(url: lastTimeUrl)
                req.httpMethod = "PUT"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = "\(now)".data(using: .utf8)
                _ = try? await URLSession.shared.data(for: req)
            }

            if let updatedUrl = await makeURL(path: "channels/\(channelId)/updatedAtMs") {
                var req = URLRequest(url: updatedUrl)
                req.httpMethod = "PUT"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = "\(now)".data(using: .utf8)
                _ = try? await URLSession.shared.data(for: req)
            }

            if isPinned {
                if let pinUrl = await makeURL(path: "channels/\(channelId)/pinnedPostId") {
                    var req = URLRequest(url: pinUrl)
                    req.httpMethod = "PUT"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.httpBody = try? JSONEncoder().encode(postId)
                    _ = try? await URLSession.shared.data(for: req)
                }
            }
        }

        return post
    }

    public func editChannelPost(
        channelId: String,
        postId: String,
        newText: String?,
        mediaPayload: MediaCardPayload?
    ) async -> Bool {
        var currentPosts = loadChannelPostsFromDisk(channelId: channelId)
        guard let idx = currentPosts.firstIndex(where: { $0.id == postId }) else { return false }

        currentPosts[idx].text = newText
        currentPosts[idx].media = mediaPayload
        currentPosts[idx].isEdited = true
        saveChannelPostsToDisk(currentPosts, channelId: channelId)

        let updatedPost = currentPosts[idx]

        Task {
            if let postUrl = await makeURL(path: "channel_posts/\(channelId)/\(postId)") {
                var req = URLRequest(url: postUrl)
                req.httpMethod = "PUT"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = try? JSONEncoder().encode(updatedPost)
                _ = try? await URLSession.shared.data(for: req)
            }
        }

        return true
    }

    public func deleteChannelPost(channelId: String, postId: String) async -> Bool {
        var currentPosts = loadChannelPostsFromDisk(channelId: channelId)
        guard let idx = currentPosts.firstIndex(where: { $0.id == postId }) else { return false }

        let wasPinned = currentPosts[idx].isPinned
        currentPosts.remove(at: idx)
        saveChannelPostsToDisk(currentPosts, channelId: channelId)

        let lastPost = currentPosts.last
        let previewText: String? = lastPost?.media != nil ? "🎬 \(lastPost!.media!.title)" : lastPost?.text
        let previewTime = lastPost?.timestampMs

        var subs = self.subscribedChannels
        if let sIdx = subs.firstIndex(where: { $0.id == channelId }) {
            subs[sIdx].lastPostText = previewText
            subs[sIdx].lastPostTimestampMs = previewTime
            if wasPinned {
                subs[sIdx].pinnedPostId = nil
            }
            self.subscribedChannels = subs
            saveSubscribedChannelsToDisk(subs)
        }

        var pubs = self.publicChannels
        if let pIdx = pubs.firstIndex(where: { $0.id == channelId }) {
            pubs[pIdx].lastPostText = previewText
            pubs[pIdx].lastPostTimestampMs = previewTime
            if wasPinned {
                pubs[pIdx].pinnedPostId = nil
            }
            self.publicChannels = pubs
            savePublicChannelsToDisk(pubs)
        }

        Task {
            if let postUrl = await makeURL(path: "channel_posts/\(channelId)/\(postId)") {
                var req = URLRequest(url: postUrl)
                req.httpMethod = "DELETE"
                _ = try? await URLSession.shared.data(for: req)
            }

            if wasPinned {
                if let pinUrl = await makeURL(path: "channels/\(channelId)/pinnedPostId") {
                    var req = URLRequest(url: pinUrl)
                    req.httpMethod = "DELETE"
                    _ = try? await URLSession.shared.data(for: req)
                }
            }

            if let textUrl = await makeURL(path: "channels/\(channelId)/lastPostText") {
                var req = URLRequest(url: textUrl)
                if let pt = previewText {
                    req.httpMethod = "PUT"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.httpBody = try? JSONEncoder().encode(pt)
                } else {
                    req.httpMethod = "DELETE"
                }
                _ = try? await URLSession.shared.data(for: req)
            }

            if let timeUrl = await makeURL(path: "channels/\(channelId)/lastPostTimestampMs") {
                var req = URLRequest(url: timeUrl)
                if let tm = previewTime {
                    req.httpMethod = "PUT"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.httpBody = "\(tm)".data(using: .utf8)
                } else {
                    req.httpMethod = "DELETE"
                }
                _ = try? await URLSession.shared.data(for: req)
            }
        }

        return true
    }

    public func togglePinChannelPost(channelId: String, postId: String, isPinned: Bool) async -> Bool {
        var currentPosts = loadChannelPostsFromDisk(channelId: channelId)
        for i in 0..<currentPosts.count {
            if currentPosts[i].id == postId {
                currentPosts[i].isPinned = isPinned
            } else if isPinned && currentPosts[i].isPinned {
                currentPosts[i].isPinned = false
            }
        }
        saveChannelPostsToDisk(currentPosts, channelId: channelId)

        let pinnedId = isPinned ? postId : nil

        var subs = self.subscribedChannels
        if let sIdx = subs.firstIndex(where: { $0.id == channelId }) {
            subs[sIdx].pinnedPostId = pinnedId
            self.subscribedChannels = subs
            saveSubscribedChannelsToDisk(subs)
        }

        var pubs = self.publicChannels
        if let pIdx = pubs.firstIndex(where: { $0.id == channelId }) {
            pubs[pIdx].pinnedPostId = pinnedId
            self.publicChannels = pubs
            savePublicChannelsToDisk(pubs)
        }

        Task {
            if let postPinUrl = await makeURL(path: "channel_posts/\(channelId)/\(postId)/isPinned") {
                var req = URLRequest(url: postPinUrl)
                req.httpMethod = "PUT"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = (isPinned ? "true" : "false").data(using: .utf8)
                _ = try? await URLSession.shared.data(for: req)
            }

            if let channelPinUrl = await makeURL(path: "channels/\(channelId)/pinnedPostId") {
                var req = URLRequest(url: channelPinUrl)
                if let pid = pinnedId {
                    req.httpMethod = "PUT"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.httpBody = try? JSONEncoder().encode(pid)
                } else {
                    req.httpMethod = "DELETE"
                }
                _ = try? await URLSession.shared.data(for: req)
            }
        }

        return true
    }

    public func toggleChannelPostReaction(channelId: String, postId: String, emoji: String) async -> Bool {
        guard let currentUser = AuthRepository.shared.currentUser, !currentUser.isAnonymous else {
            return false
        }

        var currentPosts = loadChannelPostsFromDisk(channelId: channelId)
        guard let idx = currentPosts.firstIndex(where: { $0.id == postId }) else { return false }

        var reactions = currentPosts[idx].reactions ?? [:]
        let isRemoving = (reactions[currentUser.id] == emoji)

        if isRemoving {
            reactions.removeValue(forKey: currentUser.id)
        } else {
            reactions[currentUser.id] = emoji
        }

        currentPosts[idx].reactions = reactions.isEmpty ? nil : reactions
        saveChannelPostsToDisk(currentPosts, channelId: channelId)

        Task {
            if let reactionUrl = await makeURL(path: "channel_posts/\(channelId)/\(postId)/reactions/\(currentUser.id)") {
                var req = URLRequest(url: reactionUrl)
                if isRemoving {
                    req.httpMethod = "DELETE"
                } else {
                    req.httpMethod = "PUT"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.httpBody = try? JSONEncoder().encode(emoji)
                }
                _ = try? await URLSession.shared.data(for: req)
            }
        }

        return true
    }

    // MARK: - Channel Notifications (Mute / Unmute)

    public func isChannelMuted(channelId: String) -> Bool {
        UserDefaults.standard.bool(forKey: "sloosh_channel_muted_\(channelId)")
    }

    public func setChannelMuted(channelId: String, isMuted: Bool) async {
        UserDefaults.standard.set(isMuted, forKey: "sloosh_channel_muted_\(channelId)")

        guard let currentUser = AuthRepository.shared.currentUser, !currentUser.isAnonymous else { return }
        if let subUrl = await makeURL(path: "user_channel_subscriptions/\(currentUser.id)/\(channelId)/isMuted") {
            var req = URLRequest(url: subUrl)
            req.httpMethod = "PUT"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = (isMuted ? "true" : "false").data(using: .utf8)
            _ = try? await URLSession.shared.data(for: req)
        }
    }
}
