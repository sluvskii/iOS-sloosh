import Foundation
import SwiftUI
import Combine

// MARK: - Admin Models

public struct AdminOverviewStats: Sendable, Equatable {
    public var totalUsers: Int = 0
    public var onlineUsers: Int = 0
    public var totalChannels: Int = 0
    public var totalPosts: Int = 0
    public var totalViews: Int = 0
    public var totalReactions: Int = 0
    public var topChannels: [ChannelModel] = []
    public var diagnosticsCount: Int = 0

    public init(
        totalUsers: Int = 0,
        onlineUsers: Int = 0,
        totalChannels: Int = 0,
        totalPosts: Int = 0,
        totalViews: Int = 0,
        totalReactions: Int = 0,
        topChannels: [ChannelModel] = [],
        diagnosticsCount: Int = 0
    ) {
        self.totalUsers = totalUsers
        self.onlineUsers = onlineUsers
        self.totalChannels = totalChannels
        self.totalPosts = totalPosts
        self.totalViews = totalViews
        self.totalReactions = totalReactions
        self.topChannels = topChannels
        self.diagnosticsCount = diagnosticsCount
    }
}

public struct AdminUserItem: Identifiable, Sendable, Equatable {
    public let id: String
    public var displayName: String
    public var tag: String?
    public var avatarUrl: String?
    public var email: String?
    public var isOnline: Bool
    public var isBanned: Bool
    public var createdAtMs: Int64
    public var channelsCount: Int

    public var displayTitle: String {
        if !displayName.isEmpty { return displayName }
        if let t = tag, !t.isEmpty { return "@\(t)" }
        return "Пользователь \(id.prefix(6))"
    }

    public var displayTag: String {
        if let t = tag, !t.isEmpty { return "@\(t)" }
        return ""
    }

    public init(
        id: String,
        displayName: String = "",
        tag: String? = nil,
        avatarUrl: String? = nil,
        email: String? = nil,
        isOnline: Bool = false,
        isBanned: Bool = false,
        createdAtMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        channelsCount: Int = 0
    ) {
        self.id = id
        self.displayName = displayName
        self.tag = tag
        self.avatarUrl = avatarUrl
        self.email = email
        self.isOnline = isOnline
        self.isBanned = isBanned
        self.createdAtMs = createdAtMs
        self.channelsCount = channelsCount
    }
}

// MARK: - Admin Repository

@MainActor
public final class AdminRepository: ObservableObject {
    public static let shared = AdminRepository()

    @Published public private(set) var stats = AdminOverviewStats()
    @Published public private(set) var users: [AdminUserItem] = []
    @Published public private(set) var channels: [ChannelModel] = []
    @Published public private(set) var isLoading: Bool = false

    private init() {}

    private func makeURL(path: String) async -> URL? {
        await MessengerRepository.shared.makeURL(path: path)
    }

    // MARK: - Fetch Overview Stats

    public func fetchOverviewStats() async {
        isLoading = true
        defer { isLoading = false }

        async let fetchedUsers = fetchAllUsers()
        async let fetchedChannels = fetchAllChannels()
        async let postsStats = fetchPostsStats()

        let (allUsers, allChannels, (postsCount, viewsCount, reactionsCount)) = await (fetchedUsers, fetchedChannels, postsStats)

        let onlineCount = allUsers.filter { $0.isOnline }.count
        let sortedTop = allChannels.sorted { $0.subscriberCount > $1.subscriberCount }
        let top5 = Array(sortedTop.prefix(5))

        self.users = allUsers
        self.channels = allChannels
        self.stats = AdminOverviewStats(
            totalUsers: allUsers.count,
            onlineUsers: onlineCount,
            totalChannels: allChannels.count,
            totalPosts: postsCount,
            totalViews: viewsCount,
            totalReactions: reactionsCount,
            topChannels: top5,
            diagnosticsCount: AppDiagnostics.shared.recentLogs.count
        )
    }

    // MARK: - Fetch All Users

    public func fetchAllUsers() async -> [AdminUserItem] {
        guard let url = await makeURL(path: "users") else { return [] }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              !data.isEmpty, String(data: data, encoding: .utf8) != "null",
              let rawDict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return []
        }

        var list: [AdminUserItem] = []
        for (uid, val) in rawDict {
            guard let userDict = val as? [String: Any] else { continue }
            let name = (userDict["displayName"] as? String) ?? (userDict["name"] as? String) ?? ""
            let tag = userDict["tag"] as? String
            let avatar = userDict["avatarUrl"] as? String ?? userDict["photoURL"] as? String
            let email = userDict["email"] as? String
            let isOnline = (userDict["isOnline"] as? Bool) ?? false
            let isBanned = (userDict["isBanned"] as? Bool) ?? false
            let createdAt = (userDict["createdAtMs"] as? NSNumber)?.int64Value ?? Int64(Date().timeIntervalSince1970 * 1000)

            var channelsCount = 0
            if let userChannels = userDict["channels"] as? [String: Any] {
                channelsCount = userChannels.count
            }

            list.append(AdminUserItem(
                id: uid,
                displayName: name,
                tag: tag,
                avatarUrl: avatar,
                email: email,
                isOnline: isOnline,
                isBanned: isBanned,
                createdAtMs: createdAt,
                channelsCount: channelsCount
            ))
        }

        let sorted = list.sorted { $0.createdAtMs > $1.createdAtMs }
        self.users = sorted
        return sorted
    }

    // MARK: - Fetch All Channels

    public func fetchAllChannels() async -> [ChannelModel] {
        let repo = MessengerRepository.shared
        let list = await repo.fetchPublicChannels()
        self.channels = list
        return list
    }

    // MARK: - Fetch Posts Statistics

    private func fetchPostsStats() async -> (postsCount: Int, viewsCount: Int, reactionsCount: Int) {
        guard let url = await makeURL(path: "channel_posts") else { return (0, 0, 0) }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              !data.isEmpty, String(data: data, encoding: .utf8) != "null",
              let rawDict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return (0, 0, 0)
        }

        var totalPosts = 0
        var totalViews = 0
        var totalReactions = 0

        for (_, chanVal) in rawDict {
            guard let postsDict = chanVal as? [String: Any] else { continue }
            for (_, postVal) in postsDict {
                guard let pDict = postVal as? [String: Any] else { continue }
                totalPosts += 1
                if let views = (pDict["viewsCount"] as? NSNumber)?.intValue {
                    totalViews += views
                } else {
                    totalViews += 1
                }
                if let reacts = pDict["reactions"] as? [String: Any] {
                    totalReactions += reacts.count
                }
            }
        }

        return (totalPosts, totalViews, totalReactions)
    }

    // MARK: - Moderation Actions

    public func toggleBanUser(userId: String, isBanned: Bool) async -> Bool {
        guard let url = await makeURL(path: "users/\(userId)/isBanned") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = "\(isBanned)".data(using: .utf8)

        let (_, response) = (try? await URLSession.shared.data(for: req)) ?? (Data(), nil)
        if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
            if let idx = users.firstIndex(where: { $0.id == userId }) {
                users[idx].isBanned = isBanned
            }
            return true
        }
        return false
    }

    public func deleteChannel(channelId: String) async -> Bool {
        let success = await MessengerRepository.shared.deleteChannel(channelId: channelId)
        if success {
            channels.removeAll(where: { $0.id == channelId })
            stats.totalChannels = max(0, stats.totalChannels - 1)
        }
        return success
    }
}
