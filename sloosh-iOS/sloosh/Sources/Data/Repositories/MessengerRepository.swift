import Foundation
import SwiftUI
import Combine

@MainActor
public final class MessengerRepository: ObservableObject {
    public static let shared = MessengerRepository()

    @Published public private(set) var conversations: [ChatConversation] = []
    @Published public private(set) var searchResults: [SlooshUser] = []
    @Published public private(set) var isLoading: Bool = false

    private let databaseBaseURL = "https://sloosh-77434-default-rtdb.firebaseio.com"
    private let knownUsersKey = "sloosh_messenger_known_users"
    private init() {
        self.conversations = loadConversationsFromDisk()
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
}

