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
        let cleanName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanName.isEmpty { return cleanName }
        if let t = tag, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "@\(t.replacingOccurrences(of: "@", with: ""))"
        }
        if let em = email, !em.isEmpty {
            let part = em.components(separatedBy: "@").first ?? em
            return part
        }
        return "Пользователь \(id.prefix(6))"
    }

    public var displayTag: String {
        if let t = tag, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "@\(t.replacingOccurrences(of: "@", with: ""))"
        }
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
        var userMap: [String: AdminUserItem] = [:]

        // 1. First fetch all profiles from /user_profiles.json (Most up-to-date and formatted)
        if let url = await makeURL(path: "user_profiles"),
           let (data, response) = try? await URLSession.shared.data(from: url),
           let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
           !data.isEmpty, String(data: data, encoding: .utf8) != "null",
           let rawDict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            for (uid, val) in rawDict {
                guard let dict = val as? [String: Any] else { continue }
                let name = (dict["displayName"] as? String) ?? (dict["name"] as? String) ?? ""
                let tag = dict["tag"] as? String
                let avatar = dict["avatarUrl"] as? String ?? dict["photoUrl"] as? String ?? dict["photoURL"] as? String
                let email = dict["email"] as? String
                let isOnline = (dict["isOnline"] as? Bool) ?? false
                let isBanned = (dict["isBanned"] as? Bool) ?? false
                let createdAt = (dict["createdAtMs"] as? NSNumber)?.int64Value ?? Int64(Date().timeIntervalSince1970 * 1000)

                userMap[uid] = AdminUserItem(
                    id: uid,
                    displayName: name,
                    tag: tag,
                    avatarUrl: avatar,
                    email: email,
                    isOnline: isOnline,
                    isBanned: isBanned,
                    createdAtMs: createdAt,
                    channelsCount: 0
                )
            }
        }

        // 2. Fetch /public_users.json (To catch any public directory entries)
        if let url = await makeURL(path: "public_users"),
           let (data, response) = try? await URLSession.shared.data(from: url),
           let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
           !data.isEmpty, String(data: data, encoding: .utf8) != "null",
           let rawDict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            for (uid, val) in rawDict {
                guard let dict = val as? [String: Any] else { continue }
                let name = (dict["displayName"] as? String) ?? (dict["name"] as? String) ?? ""
                let tag = dict["tag"] as? String
                let avatar = dict["avatarUrl"] as? String ?? dict["photoUrl"] as? String ?? dict["photoURL"] as? String
                let isOnline = (dict["isOnline"] as? Bool) ?? false

                if var existing = userMap[uid] {
                    if existing.displayName.isEmpty && !name.isEmpty { existing.displayName = name }
                    if (existing.tag == nil || existing.tag?.isEmpty == true) && tag != nil { existing.tag = tag }
                    if existing.avatarUrl == nil && avatar != nil { existing.avatarUrl = avatar }
                    userMap[uid] = existing
                } else {
                    userMap[uid] = AdminUserItem(
                        id: uid,
                        displayName: name,
                        tag: tag,
                        avatarUrl: avatar,
                        email: nil,
                        isOnline: isOnline,
                        isBanned: false,
                        createdAtMs: Int64(Date().timeIntervalSince1970 * 1000),
                        channelsCount: 0
                    )
                }
            }
        }

        // 3. Fetch /users.json (Parse nested 'profile' and count channels)
        if let url = await makeURL(path: "users"),
           let (data, response) = try? await URLSession.shared.data(from: url),
           let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
           !data.isEmpty, String(data: data, encoding: .utf8) != "null",
           let rawDict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            for (uid, val) in rawDict {
                guard let userDict = val as? [String: Any] else { continue }
                let profileDict = (userDict["profile"] as? [String: Any]) ?? userDict
                let name = (profileDict["displayName"] as? String) ?? (profileDict["name"] as? String) ?? (userDict["displayName"] as? String) ?? ""
                let tag = (profileDict["tag"] as? String) ?? (userDict["tag"] as? String)
                let avatar = (profileDict["avatarUrl"] as? String) ?? (profileDict["photoUrl"] as? String) ?? (profileDict["photoURL"] as? String) ?? (userDict["avatarUrl"] as? String)
                let email = (profileDict["email"] as? String) ?? (userDict["email"] as? String)
                let isOnline = (profileDict["isOnline"] as? Bool) ?? (userDict["isOnline"] as? Bool) ?? false
                let isBanned = (userDict["isBanned"] as? Bool) ?? false
                let createdAt = (userDict["createdAtMs"] as? NSNumber)?.int64Value ?? Int64(Date().timeIntervalSince1970 * 1000)

                var channelsCount = 0
                if let userChannels = userDict["channels"] as? [String: Any] {
                    channelsCount = userChannels.count
                }

                if var existing = userMap[uid] {
                    if existing.displayName.isEmpty && !name.isEmpty { existing.displayName = name }
                    if (existing.tag == nil || existing.tag?.isEmpty == true) && tag != nil { existing.tag = tag }
                    if existing.avatarUrl == nil && avatar != nil { existing.avatarUrl = avatar }
                    if existing.email == nil && email != nil { existing.email = email }
                    existing.channelsCount = max(existing.channelsCount, channelsCount)
                    existing.isBanned = isBanned
                    userMap[uid] = existing
                } else {
                    userMap[uid] = AdminUserItem(
                        id: uid,
                        displayName: name,
                        tag: tag,
                        avatarUrl: avatar,
                        email: email,
                        isOnline: isOnline,
                        isBanned: isBanned,
                        createdAtMs: createdAt,
                        channelsCount: channelsCount
                    )
                }
            }
        }

        // 4. Also check /userTags.json to attach any tags
        if let url = await makeURL(path: "userTags"),
           let (data, response) = try? await URLSession.shared.data(from: url),
           let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
           !data.isEmpty, String(data: data, encoding: .utf8) != "null",
           let tagsDict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            for (tagKey, uidVal) in tagsDict {
                let uid = (uidVal as? String) ?? "\(uidVal)"
                if var user = userMap[uid] {
                    if user.tag == nil || user.tag?.isEmpty == true {
                        user.tag = tagKey
                        if user.displayName.isEmpty {
                            user.displayName = tagKey
                        }
                        userMap[uid] = user
                    }
                }
            }
        }

        // 5. Merge local known users from MessengerRepository
        let localKnown = MessengerRepository.shared.getLocalKnownUsers()
        for (uid, localUser) in localKnown {
            if var existing = userMap[uid] {
                if existing.displayName.isEmpty && !localUser.displayName.isEmpty {
                    existing.displayName = localUser.displayName
                }
                if (existing.tag == nil || existing.tag?.isEmpty == true) && localUser.tag != nil {
                    existing.tag = localUser.tag
                }
                if existing.avatarUrl == nil && localUser.avatarUrl != nil {
                    existing.avatarUrl = localUser.avatarUrl
                }
                userMap[uid] = existing
            } else if !localUser.displayName.isEmpty || localUser.tag != nil {
                userMap[uid] = AdminUserItem(
                    id: uid,
                    displayName: localUser.displayName,
                    tag: localUser.tag,
                    avatarUrl: localUser.avatarUrl,
                    email: nil,
                    isOnline: localUser.isOnline ?? false,
                    isBanned: false,
                    createdAtMs: Int64(Date().timeIntervalSince1970 * 1000),
                    channelsCount: 0
                )
            }
        }

        let sorted = Array(userMap.values).sorted {
            if $0.isOnline != $1.isOnline { return $0.isOnline }
            return $0.createdAtMs > $1.createdAtMs
        }
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
