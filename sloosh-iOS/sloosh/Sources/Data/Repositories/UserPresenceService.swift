import Foundation
import SwiftUI
import Combine

// MARK: - Presence Formatter

public enum PresenceFormatter {
    private static let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ru_RU")
        df.dateFormat = "HH:mm"
        return df
    }()

    private static let shortDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ru_RU")
        df.dateFormat = "d MMM в HH:mm"
        return df
    }()

    public static func isOnline(isOnlineFlag: Bool?, lastSeenMs: Int64?) -> Bool {
        guard let flag = isOnlineFlag, flag else { return false }
        guard let lastSeen = lastSeenMs, lastSeen > 0 else { return false }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let diffMs = now - lastSeen
        // Активен в течение последних 2.5 минут (150 секунд)
        return diffMs >= 0 && diffMs < 150_000
    }

    public static func formatLastSeen(isOnlineFlag: Bool?, lastSeenMs: Int64?) -> String {
        if isOnline(isOnlineFlag: isOnlineFlag, lastSeenMs: lastSeenMs) {
            return "в сети"
        }

        guard let lastSeen = lastSeenMs, lastSeen > 0 else {
            return "был(а) недавно"
        }

        let now = Date()
        let lastSeenDate = Date(timeIntervalSince1970: Double(lastSeen) / 1000.0)
        let calendar = Calendar.current

        let diffSec = Int(now.timeIntervalSince(lastSeenDate))

        if diffSec < 90 {
            return "был(а) только что"
        }

        if calendar.isDateInToday(lastSeenDate) {
            return "был(а) в \(timeFormatter.string(from: lastSeenDate))"
        }

        if calendar.isDateInYesterday(lastSeenDate) {
            return "был(а) вчера в \(timeFormatter.string(from: lastSeenDate))"
        }

        let daysDiff = calendar.dateComponents([.day], from: lastSeenDate, to: now).day ?? 0
        if daysDiff < 7 {
            return "был(а) \(shortDateFormatter.string(from: lastSeenDate))"
        }

        return "был(а) давно"
    }
}

// MARK: - User Presence Service

@MainActor
public final class UserPresenceService: ObservableObject {
    public static let shared = UserPresenceService()

    private var heartbeatTimer: Timer?
    private var typingDebounceTask: Task<Void, Never>?

    private init() {}

    private func makeURL(path: String) async -> URL? {
        await MessengerRepository.shared.makeURL(path: path)
    }

    // MARK: - Heartbeat & Online Lifecycle

    public func startHeartbeat() {
        stopHeartbeat()
        setOnline()

        // Пинг каждые 45 секунд
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 45.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sendHeartbeat()
            }
        }
    }

    public func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    public func setOnline() {
        sendHeartbeat(isOnline: true)
    }

    public func setOffline() {
        stopHeartbeat()
        sendHeartbeat(isOnline: false)
    }

    private func sendHeartbeat(isOnline: Bool = true) {
        guard let currentUser = AuthRepository.shared.currentUser, !currentUser.isAnonymous else { return }
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)

        Task {
            let presenceDict: [String: Any] = [
                "isOnline": isOnline,
                "lastSeenMs": nowMs
            ]

            guard let jsonData = try? JSONSerialization.data(withJSONObject: presenceDict) else { return }

            // 1. Update /user_profiles/{uid}
            if let url = await makeURL(path: "user_profiles/\(currentUser.id)/presence") {
                var req = URLRequest(url: url)
                req.httpMethod = "PUT"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = jsonData
                _ = try? await URLSession.shared.data(for: req)
            }

            // Also update top-level isOnline & lastSeenMs under /user_profiles/{uid}
            if let url2 = await makeURL(path: "user_profiles/\(currentUser.id)/isOnline") {
                var req = URLRequest(url: url2)
                req.httpMethod = "PUT"
                req.httpBody = "\(isOnline)".data(using: .utf8)
                _ = try? await URLSession.shared.data(for: req)
            }
            if let url3 = await makeURL(path: "user_profiles/\(currentUser.id)/lastSeenMs") {
                var req = URLRequest(url: url3)
                req.httpMethod = "PUT"
                req.httpBody = "\(nowMs)".data(using: .utf8)
                _ = try? await URLSession.shared.data(for: req)
            }

            // 2. Update /users/{uid}/presence
            if let url4 = await makeURL(path: "users/\(currentUser.id)/presence") {
                var req = URLRequest(url: url4)
                req.httpMethod = "PUT"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = jsonData
                _ = try? await URLSession.shared.data(for: req)
            }
        }
    }

    // MARK: - Live User Presence Query

    public func fetchUserPresence(userId: String) async -> (isOnline: Bool, lastSeenMs: Int64?) {
        guard let url = await makeURL(path: "user_profiles/\(userId)") else {
            return (false, nil)
        }

        guard let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              !data.isEmpty, String(data: data, encoding: .utf8) != "null",
              let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return (false, nil)
        }

        let isOnline = (dict["isOnline"] as? Bool) ?? (dict["presence"] as? [String: Any])?["isOnline"] as? Bool ?? false
        let lastSeen = (dict["lastSeenMs"] as? NSNumber)?.int64Value ?? ((dict["presence"] as? [String: Any])?["lastSeenMs"] as? NSNumber)?.int64Value

        let trulyOnline = PresenceFormatter.isOnline(isOnlineFlag: isOnline, lastSeenMs: lastSeen)
        return (trulyOnline, lastSeen)
    }

    // MARK: - Typing Indicator

    public func sendTyping(chatId: String) {
        guard let currentUser = AuthRepository.shared.currentUser, !currentUser.isAnonymous else { return }
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)

        typingDebounceTask?.cancel()

        Task {
            if let url = await makeURL(path: "chats/\(chatId)/typing/\(currentUser.id)") {
                var req = URLRequest(url: url)
                req.httpMethod = "PUT"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = "\(nowMs)".data(using: .utf8)
                _ = try? await URLSession.shared.data(for: req)
            }
        }

        // Автоматически очистить статус печатания через 3.5 секунды бездействия
        typingDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled else { return }
            self.clearTyping(chatId: chatId)
        }
    }

    public func clearTyping(chatId: String) {
        guard let currentUser = AuthRepository.shared.currentUser, !currentUser.isAnonymous else { return }
        typingDebounceTask?.cancel()
        typingDebounceTask = nil

        Task {
            if let url = await makeURL(path: "chats/\(chatId)/typing/\(currentUser.id)") {
                var req = URLRequest(url: url)
                req.httpMethod = "DELETE"
                _ = try? await URLSession.shared.data(for: req)
            }
        }
    }

    public func isPeerTyping(chatId: String, peerUserId: String) async -> Bool {
        guard let url = await makeURL(path: "chats/\(chatId)/typing/\(peerUserId)") else { return false }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              !data.isEmpty,
              let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              str != "null",
              let timestamp = Int64(str) else {
            return false
        }

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        return (now - timestamp) >= 0 && (now - timestamp) < 4_500
    }
}
