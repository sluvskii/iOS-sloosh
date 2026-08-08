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

    private init() {}

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
        
        let urlString = "\(databaseBaseURL)/users/\(user.id).json"
        guard let url = URL(string: urlString) else { return }
        
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "PUT"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(slooshUser)
            _ = try await URLSession.shared.data(for: request)
        } catch {
            AppDiagnostics.shared.log("MessengerRepository sync profile error: \(error.localizedDescription)")
        }
    }

    public func searchUsers(query: String) async -> [SlooshUser] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else {
            self.searchResults = []
            return []
        }

        let urlString = "\(databaseBaseURL)/users.json"
        guard let url = URL(string: urlString) else { return [] }

        isLoading = true
        defer { isLoading = false }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode) else {
                return []
            }

            if data.isEmpty || String(data: data, encoding: .utf8) == "null" {
                return []
            }

            let usersDict = try JSONDecoder().decode([String: SlooshUser].self, from: data)
            let currentUserId = AuthRepository.shared.currentUser?.id ?? ""
            
            let matched = usersDict.values.filter { slooshUser in
                guard slooshUser.id != currentUserId else { return false }
                let nameMatch = slooshUser.displayName.lowercased().contains(trimmed)
                let emailMatch = slooshUser.email.lowercased().contains(trimmed)
                return nameMatch || emailMatch
            }

            let results = Array(matched)
            self.searchResults = results
            return results
        } catch {
            AppDiagnostics.shared.log("MessengerRepository searchUsers error: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Conversations

    public func fetchConversations() async {
        guard let currentUser = AuthRepository.shared.currentUser, !currentUser.isAnonymous else {
            self.conversations = []
            return
        }

        let urlString = "\(databaseBaseURL)/user_chats/\(currentUser.id).json"
        guard let url = URL(string: urlString) else { return }

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
        
        let urlString = "\(databaseBaseURL)/chats/\(chatId)/messages.json"
        guard let url = URL(string: urlString) else { return [] }

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
        mediaPayload: MediaCardPayload? = nil
    ) async -> Bool {
        guard let currentUser = AuthRepository.shared.currentUser, !currentUser.isAnonymous else { return false }
        
        let chatId = getOrCreateChatId(peerUserId: peerUser.id)
        let messageType: MessageType = (mediaPayload != nil) ? .media : .text
        
        let message = ChatMessage(
            senderId: currentUser.id,
            receiverId: peerUser.id,
            type: messageType,
            text: text,
            media: mediaPayload
        )

        let msgUrlString = "\(databaseBaseURL)/chats/\(chatId)/messages/\(message.id).json"
        guard let msgUrl = URL(string: msgUrlString) else { return false }

        do {
            var request = URLRequest(url: msgUrl)
            request.httpMethod = "PUT"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(message)
            
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode) else {
                return false
            }

            let previewText: String
            if let media = mediaPayload {
                previewText = "🎬 \(media.title)"
            } else {
                previewText = text ?? ""
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

            let senderUrlString = "\(databaseBaseURL)/user_chats/\(currentUser.id)/\(chatId).json"
            if let senderUrl = URL(string: senderUrlString) {
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

            let receiverUrlString = "\(databaseBaseURL)/user_chats/\(peerUser.id)/\(chatId).json"
            if let receiverUrl = URL(string: receiverUrlString) {
                var req = URLRequest(url: receiverUrl)
                req.httpMethod = "PUT"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = try? JSONSerialization.data(withJSONObject: receiverEntry)
                _ = try? await URLSession.shared.data(for: req)
            }

            await fetchConversations()
            return true

        } catch {
            AppDiagnostics.shared.log("MessengerRepository sendMessage error: \(error.localizedDescription)")
            return false
        }
    }
}
