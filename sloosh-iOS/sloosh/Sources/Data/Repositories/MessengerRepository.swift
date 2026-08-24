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
    private init() {
        self.conversations = loadConversationsFromDisk()
        self.subscribedChannels = loadSubscribedChannelsFromDisk()
        self.publicChannels = loadPublicChannelsFromDisk()
    }

    // MARK: - Disk Persistence (Instant Cold Start)

    public func saveConversationsToDisk(_ list: [ChatConversation]) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: "sloosh_messenger_conversations_v1")
        }
    }

    public func loadConversationsFromDisk() -> [ChatConversation] {
        guard let data = UserDefaults.standard.data(forKey: "sloosh_messenger_conversations_v1"),
              let list = try? JSONDecoder().decode([ChatConversation].self, from: data) else {
            return []
        }
        return list.sorted { $0.updatedAtMs > $1.updatedAtMs }
    }

    public func saveSubscribedChannelsToDisk(_ list: [ChannelModel]) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: "sloosh_messenger_subscribed_channels_v1")
        }
    }

    public func loadSubscribedChannelsFromDisk() -> [ChannelModel] {
        guard let data = UserDefaults.standard.data(forKey: "sloosh_messenger_subscribed_channels_v1"),
              let list = try? JSONDecoder().decode([ChannelModel].self, from: data) else {
            return []
        }
        return list.sorted { ($0.lastPostTimestampMs ?? $0.updatedAtMs) > ($1.lastPostTimestampMs ?? $1.updatedAtMs) }
    }

    public func savePublicChannelsToDisk(_ list: [ChannelModel]) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: "sloosh_messenger_public_channels_v1")
        }
    }

    public func loadPublicChannelsFromDisk() -> [ChannelModel] {
        guard let data = UserDefaults.standard.data(forKey: "sloosh_messenger_public_channels_v1"),
              let list = try? JSONDecoder().decode([ChannelModel].self, from: data) else {
            return []
        }
        return list.sorted { $0.subscriberCount > $1.subscriberCount }
    }

    public func saveChannelPostsToDisk(_ posts: [ChannelPost], channelId: String) {
        let key = "sloosh_channel_posts_v1_\(channelId)"
        if let data = try? JSONEncoder().encode(posts) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    public func loadChannelPostsFromDisk(channelId: String) -> [ChannelPost] {
        let key = "sloosh_channel_posts_v1_\(channelId)"
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([ChannelPost].self, from: data) else {
            return []
        }
        return list.sorted { $0.timestampMs < $1.timestampMs }
    }

    public func saveMessagesToDisk(_ messages: [ChatMessage], chatId: String) {
        let key = "sloosh_messenger_messages_v1_\(chatId)"
        if let data = try? JSONEncoder().encode(messages) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    public func loadMessagesFromDisk(chatId: String) -> [ChatMessage] {
        let key = "sloosh_messenger_messages_v1_\(chatId)"
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

    // MARK: - User Registration & Search

    public func syncCurrentUserProfile() async {
        guard let user = AuthRepository.shared.currentUser, !user.isAnonymous else { return }
        
        let slooshUser = SlooshUser(
            id: user.id,
            displayName: user.displayTitle,
            email: user.email ?? "",
            avatarUrl: user.photoURL,
            isOnline: true
        )

        // Сохраняем локально на устройстве
        saveLocalKnownUser(slooshUser)
        
        guard let body = try? JSONEncoder().encode(slooshUser) else { return }

        // 1. Сохраняем в публичный каталог профилей /user_profiles/{uid}.json
        if let url1 = await makeURL(path: "user_profiles/\(user.id)") {
            var req = URLRequest(url: url1)
            req.httpMethod = "PUT"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
            do {
                let (data, response) = try await URLSession.shared.data(for: req)
                if let httpResp = response as? HTTPURLResponse, !(200...299).contains(httpResp.statusCode) {
                    let errStr = String(data: data, encoding: .utf8) ?? ""
                    AppDiagnostics.shared.log("MessengerRepository: sync user_profiles HTTP \(httpResp.statusCode): \(errStr)")
                }
            } catch {
                AppDiagnostics.shared.log("MessengerRepository: sync user_profiles error: \(error.localizedDescription)")
            }
        }

        // 2. Сохраняем профиль под ветку пользователя /users/{uid}/profile.json
        if let url2 = await makeURL(path: "users/\(user.id)/profile") {
            var req = URLRequest(url: url2)
            req.httpMethod = "PUT"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
            do {
                let (data, response) = try await URLSession.shared.data(for: req)
                if let httpResp = response as? HTTPURLResponse, !(200...299).contains(httpResp.statusCode) {
                    let errStr = String(data: data, encoding: .utf8) ?? ""
                    AppDiagnostics.shared.log("MessengerRepository: sync users/profile HTTP \(httpResp.statusCode): \(errStr)")
                }
            } catch {
                AppDiagnostics.shared.log("MessengerRepository: sync users/profile error: \(error.localizedDescription)")
            }
        }
    }

    public func searchUsers(query: String) async -> [SlooshUser] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else {
            self.searchResults = []
            return []
        }

        isLoading = true
        defer { isLoading = false }

        // Гарантируем синхронизацию профиля текущего пользователя в Firebase
        await syncCurrentUserProfile()

        var allUsersMap: [String: SlooshUser] = [:]

        // 1. Загружаем локально сохранённых пользователей с этого устройства
        let localUsers = getLocalKnownUsers()
        for (uId, user) in localUsers {
            allUsersMap[uId] = user
        }

        // 2. Загружаем профили из /user_profiles.json
        if let profiles = await fetchUsersFromNode("user_profiles") {
            for p in profiles {
                allUsersMap[p.id] = p
                saveLocalKnownUser(p)
            }
        }

        // 3. Загружаем профили из /users.json (fallback)
        if let users = await fetchUsersFromNode("users") {
            for u in users {
                if allUsersMap[u.id] == nil {
                    allUsersMap[u.id] = u
                    saveLocalKnownUser(u)
                }
            }
        }

        let currentUserId = AuthRepository.shared.currentUser?.id ?? ""
        let matched = allUsersMap.values.filter { slooshUser in
            let nameMatch = slooshUser.displayName.lowercased().contains(trimmed)
            let emailMatch = slooshUser.email.lowercased().contains(trimmed)
            let idMatch = slooshUser.id.lowercased().contains(trimmed)
            return nameMatch || emailMatch || idMatch
        }

        let results = matched.map { user -> SlooshUser in
            if user.id == currentUserId && !user.displayName.contains("(Вы)") {
                return SlooshUser(
                    id: user.id,
                    displayName: "\(user.displayName) (Вы)",
                    email: user.email,
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
        AppDiagnostics.shared.log("MessengerRepository: searchUsers('\(trimmed)') matched \(finalArray.count) users (total in DB/local: \(allUsersMap.count))")
        return finalArray
    }

    private func fetchUsersFromNode(_ nodeName: String) async -> [SlooshUser]? {
        guard let url = await makeURL(path: nodeName) else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResp = response as? HTTPURLResponse else {
                return nil
            }

            if !(200...299).contains(httpResp.statusCode) {
                let errBody = String(data: data, encoding: .utf8) ?? ""
                AppDiagnostics.shared.log("MessengerRepository fetchUsersFromNode '\(nodeName)' HTTP \(httpResp.statusCode): \(errBody)")
                if httpResp.statusCode == 401 || httpResp.statusCode == 403 {
                    ToastManager.shared.show(
                        title: "Доступ Firebase ограничен (\(httpResp.statusCode))",
                        subtitle: "Проверьте правила Realtime Database",
                        icon: "lock.shield.fill"
                    )
                }
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
                let email = (sourceDict["email"] as? String) ?? ""
                let avatarUrl = sourceDict["avatarUrl"] as? String
                let isOnline = sourceDict["isOnline"] as? Bool ?? true

                if !displayName.isEmpty || !email.isEmpty {
                    let user = SlooshUser(
                        id: id,
                        displayName: displayName,
                        email: email,
                        avatarUrl: avatarUrl,
                        isOnline: isOnline
                    )
                    results.append(user)
                }
            }
            return results
        } catch {
            AppDiagnostics.shared.log("MessengerRepository fetchUsersFromNode error: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Conversations

    public func fetchConversations() async {
        guard let currentUser = AuthRepository.shared.currentUser, !currentUser.isAnonymous else {
            self.conversations = []
            return
        }

        // 1. Показываем мгновенно из дискового кэша, если текущий список пуст
        if self.conversations.isEmpty {
            self.conversations = loadConversationsFromDisk()
        }

        guard let url = await makeURL(path: "user_chats/\(currentUser.id)") else { return }

        // Если есть локальные чаты, не вешаем полноэкранный spinner
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

                // Если в локальном кэше нет непрочитанных входящих, принудительно обнуляем unreadCount
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

        // Ищем непрочитанные входящие сообщения
        let unreadIncoming = messages.filter { $0.senderId == peerUserId && $0.isRead != true }
        guard !unreadIncoming.isEmpty else { return }

        // Обновляем локальный кэш прочитанности
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

                // Отправляем статус isRead в Firebase
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

        // Обнуляем unreadCount для текущего пользователя в user_chats
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

        // 1. Оптимистичное локальное обновление (0мс задержки для отправителя)
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

        // 2. Фоновая отправка в Firebase в отдельном Task без ожидания
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

                // Update user_chats for sender
                let senderEntry = [
                    "chatId": chatId,
                    "peerUser": [
                        "id": peerUser.id,
                        "displayName": peerUser.displayName,
                        "email": peerUser.email,
                        "avatarUrl": peerUser.avatarUrl ?? ""
                    ] as [String: Any],
                    "lastMessageText": previewText,
                    "unreadCount": 0,
                    "updatedAtMs": message.timestampMs
                ] as [String: Any]

                if let senderUrl = await makeURL(path: "user_chats/\(currentUser.id)/\(chatId)") {
                    var req = URLRequest(url: senderUrl)
                    req.httpMethod = "PUT"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.httpBody = try? JSONSerialization.data(withJSONObject: senderEntry)
                    _ = try? await URLSession.shared.data(for: req)
                }

                // Update user_chats for receiver
                let currentSlooshUser = SlooshUser(
                    id: currentUser.id,
                    displayName: currentUser.displayTitle,
                    email: currentUser.email ?? "",
                    avatarUrl: currentUser.photoURL
                )
                let receiverEntry = [
                    "chatId": chatId,
                    "peerUser": [
                        "id": currentSlooshUser.id,
                        "displayName": currentSlooshUser.displayName,
                        "email": currentSlooshUser.email,
                        "avatarUrl": currentSlooshUser.avatarUrl ?? ""
                    ] as [String: Any],
                    "lastMessageText": previewText,
                    "unreadCount": 1,
                    "updatedAtMs": message.timestampMs
                ] as [String: Any]

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

    // MARK: - Message Deletion (Physical Delete from Firebase & Local Disk)

    public func deleteMessage(
        chatId: String,
        messageId: String,
        peerUser: SlooshUser
    ) async {
        guard let currentUser = AuthRepository.shared.currentUser, !currentUser.isAnonymous else { return }

        // 1. Оптимистичное локальное удаление с диска
        var currentMessages = loadMessagesFromDisk(chatId: chatId)
        currentMessages.removeAll(where: { $0.id == messageId })
        saveMessagesToDisk(currentMessages, chatId: chatId)

        // 2. Обновление previewText в user_chats
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

        // 3. Физическое удаление в Firebase Realtime Database
        if let msgUrl = await makeURL(path: "chats/\(chatId)/messages/\(messageId)") {
            var req = URLRequest(url: msgUrl)
            req.httpMethod = "DELETE"
            _ = try? await URLSession.shared.data(for: req)
        }

        // 4. Обновление user_chats для обоих участников
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
        avatarEmoji: String? = "📢",
        accentColorHex: String? = "#FF9F0A"
    ) async -> ChannelModel? {
        guard let currentUser = AuthRepository.shared.currentUser, !currentUser.isAnonymous else {
            return nil
        }

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let channelId = "ch_\(now)_\(UUID().uuidString.prefix(6).lowercased())"
        let creatorName = currentUser.displayTitle

        let channel = ChannelModel(
            id: channelId,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            avatarEmoji: avatarEmoji,
            avatarUrl: nil,
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

        // 1. Optimistically insert into subscribedChannels & disk cache
        var currentSubscribed = self.subscribedChannels
        currentSubscribed.insert(channel, at: 0)
        self.subscribedChannels = currentSubscribed
        saveSubscribedChannelsToDisk(currentSubscribed)

        // 2. Firebase REST Calls
        // 2a. PUT /channels/{channelId}.json
        if let channelUrl = await makeURL(path: "channels/\(channelId)") {
            var req = URLRequest(url: channelUrl)
            req.httpMethod = "PUT"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONEncoder().encode(channel)
            do {
                _ = try await URLSession.shared.data(for: req)
            } catch {
                AppDiagnostics.shared.log("MessengerRepository createChannel error: \(error.localizedDescription)")
            }
        }

        // 2b. PUT /user_channel_subscriptions/{userId}/{channelId}.json
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

        // 2c. PUT /channel_subscribers/{channelId}/{userId}.json
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

    public func updateChannelMetadata(channel: ChannelModel) async -> Bool {
        var updated = channel
        updated.updatedAtMs = Int64(Date().timeIntervalSince1970 * 1000)

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

        // 2. PUT /channels/{channelId}.json
        if let channelUrl = await makeURL(path: "channels/\(channel.id)") {
            var req = URLRequest(url: channelUrl)
            req.httpMethod = "PUT"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONEncoder().encode(updated)
            _ = try? await URLSession.shared.data(for: req)
        }

        // 3. PUT /user_channel_subscriptions/{ownerId}/{channelId}/channel.json
        if let subUrl = await makeURL(path: "user_channel_subscriptions/\(channel.ownerId)/\(channel.id)/channel") {
            var req = URLRequest(url: subUrl)
            req.httpMethod = "PUT"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONEncoder().encode(updated)
            _ = try? await URLSession.shared.data(for: req)
        }

        return true
    }

    public func deleteChannel(channelId: String) async -> Bool {
        guard let currentUser = AuthRepository.shared.currentUser, !currentUser.isAnonymous else {
            return false
        }

        // 1. Remove from local published collections and disk caches
        self.subscribedChannels.removeAll(where: { $0.id == channelId })
        saveSubscribedChannelsToDisk(self.subscribedChannels)

        self.publicChannels.removeAll(where: { $0.id == channelId })
        savePublicChannelsToDisk(self.publicChannels)

        saveChannelPostsToDisk([], channelId: channelId)

        // 2. REST deletions
        Task {
            // DELETE /channels/{channelId}.json
            if let channelUrl = await makeURL(path: "channels/\(channelId)") {
                var req = URLRequest(url: channelUrl)
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
            self.subscribedChannels = loadSubscribedChannelsFromDisk()
        }

        guard let url = await makeURL(path: "user_channel_subscriptions/\(currentUser.id)") else {
            return self.subscribedChannels
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode) else {
                return self.subscribedChannels
            }

            if data.isEmpty || String(data: data, encoding: .utf8) == "null" {
                self.subscribedChannels = []
                saveSubscribedChannelsToDisk([])
                return []
            }

            let subDict = try JSONDecoder().decode([String: ChannelSubscription].self, from: data)
            var channelsList: [ChannelModel] = []

            // Also refresh latest channel metadata from /channels.json if available
            if let allChannelsUrl = await makeURL(path: "channels") {
                if let (channelsData, resp2) = try? await URLSession.shared.data(from: allChannelsUrl),
                   let httpResp2 = resp2 as? HTTPURLResponse, (200...299).contains(httpResp2.statusCode),
                   !channelsData.isEmpty, String(data: channelsData, encoding: .utf8) != "null",
                   let allDict = try? JSONDecoder().decode([String: ChannelModel].self, from: channelsData) {
                    
                    channelsList = subDict.compactMap { (chId, sub) -> ChannelModel? in
                        return allDict[chId] ?? sub.channel
                    }
                } else {
                    channelsList = subDict.compactMap { $0.value.channel }
                }
            } else {
                channelsList = subDict.compactMap { $0.value.channel }
            }

            let sorted = channelsList.sorted { ($0.lastPostTimestampMs ?? $0.updatedAtMs) > ($1.lastPostTimestampMs ?? $1.updatedAtMs) }
            self.subscribedChannels = sorted
            saveSubscribedChannelsToDisk(sorted)
            return sorted
        } catch {
            AppDiagnostics.shared.log("MessengerRepository fetchSubscribedChannels error: \(error.localizedDescription)")
            return self.subscribedChannels
        }
    }

    public func fetchPublicChannels(query: String? = nil) async -> [ChannelModel] {
        if self.publicChannels.isEmpty {
            self.publicChannels = loadPublicChannelsFromDisk()
        }

        guard let url = await makeURL(path: "channels") else {
            return filterChannels(self.publicChannels, query: query)
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode) else {
                return filterChannels(self.publicChannels, query: query)
            }

            if data.isEmpty || String(data: data, encoding: .utf8) == "null" {
                if query == nil || query?.isEmpty == true {
                    self.publicChannels = []
                    savePublicChannelsToDisk([])
                }
                return []
            }

            let dict = try JSONDecoder().decode([String: ChannelModel].self, from: data)
            let allPublic = dict.values.filter { $0.isPublic }.sorted { $0.subscriberCount > $1.subscriberCount }

            self.publicChannels = allPublic
            savePublicChannelsToDisk(allPublic)

            return filterChannels(allPublic, query: query)
        } catch {
            AppDiagnostics.shared.log("MessengerRepository fetchPublicChannels error: \(error.localizedDescription)")
            return filterChannels(self.publicChannels, query: query)
        }
    }

    private func filterChannels(_ list: [ChannelModel], query: String?) -> [ChannelModel] {
        guard let query = query?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !query.isEmpty else {
            return list
        }
        return list.filter {
            $0.name.lowercased().contains(query) || $0.description.lowercased().contains(query)
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

        // Update in publicChannels if present
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

    // MARK: - Channel Posts & Reactions

    public func fetchChannelPosts(channelId: String) async -> [ChannelPost] {
        guard !channelId.isEmpty else { return [] }
        let cached = loadChannelPostsFromDisk(channelId: channelId)

        guard let url = await makeURL(path: "channel_posts/\(channelId)") else {
            return cached
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode) else {
                return cached
            }

            if data.isEmpty || String(data: data, encoding: .utf8) == "null" {
                saveChannelPostsToDisk([], channelId: channelId)
                return []
            }

            let postsDict = try JSONDecoder().decode([String: ChannelPost].self, from: data)
            let list = Array(postsDict.values).sorted(by: { $0.timestampMs < $1.timestampMs })
            saveChannelPostsToDisk(list, channelId: channelId)
            return list
        } catch {
            AppDiagnostics.shared.log("MessengerRepository fetchChannelPosts error: \(error.localizedDescription)")
            return cached
        }
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

        // 1. Optimistically append to local posts disk cache
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

        // 2. Determine preview text
        let previewText: String
        if let media = mediaPayload {
            previewText = "🎬 \(media.title)"
        } else {
            previewText = text ?? ""
        }

        // 3. Update Channel in subscribedChannels and publicChannels
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

        // 4. Background REST upload
        Task {
            // 4a. PUT /channel_posts/{channelId}/{postId}.json
            if let postUrl = await makeURL(path: "channel_posts/\(channelId)/\(postId)") {
                var req = URLRequest(url: postUrl)
                req.httpMethod = "PUT"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = try? JSONEncoder().encode(post)
                _ = try? await URLSession.shared.data(for: req)
            }

            // 4b. Update channel last post info
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

