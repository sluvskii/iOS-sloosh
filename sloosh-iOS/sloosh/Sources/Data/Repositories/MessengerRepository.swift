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

    private init() {}

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

        guard let url = await makeURL(path: "user_chats/\(currentUser.id)") else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode) else {
                return
            }

            if data.isEmpty || String(data: data, encoding: .utf8) == "null" {
                self.conversations = []
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
            let list = chatsDict.values.map {
                ChatConversation(
                    chatId: $0.chatId,
                    peerUser: $0.peerUser,
                    lastMessageText: $0.lastMessageText,
                    unreadCount: $0.unreadCount ?? 0,
                    updatedAtMs: $0.updatedAtMs
                )
            }.sorted { $0.updatedAtMs > $1.updatedAtMs }

            self.conversations = list
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
        
        guard let url = await makeURL(path: "chats/\(chatId)/messages") else { return [] }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode) else {
                return []
            }

            if data.isEmpty || String(data: data, encoding: .utf8) == "null" {
                return []
            }

            let messagesDict = try JSONDecoder().decode([String: ChatMessage].self, from: data)
            return messagesDict.values.sorted { $0.timestampMs < $1.timestampMs }
        } catch {
            AppDiagnostics.shared.log("MessengerRepository fetchMessages error: \(error.localizedDescription)")
            return []
        }
    }

    public func sendMessage(
        toPeerUser peerUser: SlooshUser,
        text: String? = nil,
        mediaPayload: MediaCardPayload? = nil,
        replyToId: String? = nil
    ) async -> Bool {
        guard let currentUser = AuthRepository.shared.currentUser, !currentUser.isAnonymous else { return false }
        
        let chatId = getOrCreateChatId(peerUserId: peerUser.id)
        let messageType: MessageType = (mediaPayload != nil) ? .media : .text
        
        let message = ChatMessage(
            senderId: currentUser.id,
            receiverId: peerUser.id,
            type: messageType,
            text: text,
            media: mediaPayload,
            replyToId: replyToId
        )

        return await postMessageToFirebase(chatId: chatId, message: message, peerUser: peerUser)
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
}

