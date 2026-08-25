import SwiftUI

// MARK: - Admin Dashboard View (iOS 26+ Liquid Glass)

public struct AdminDashboardView: View {
    @StateObject private var repo = AdminRepository.shared
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: AdminTab = .overview
    @State private var userSearchQuery: String = ""
    @State private var channelSearchQuery: String = ""
    @State private var selectedUserForDetails: AdminUserItem? = nil
    @State private var channelToDelete: ChannelModel? = nil
    @State private var showDeleteChannelAlert: Bool = false

    private enum AdminTab: String, CaseIterable, Identifiable {
        case overview = "Обзор"
        case users = "Пользователи"
        case channels = "Каналы"
        case diagnostics = "Логи"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .overview: return "chart.bar.fill"
            case .users: return "person.2.fill"
            case .channels: return "megaphone.fill"
            case .diagnostics: return "waveform.path.ecg"
            }
        }
    }

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                Color(UIColor.systemBackground).ignoresSafeArea()

                VStack(spacing: 0) {
                    tabSelector
                        .padding(.top, 8)
                        .padding(.bottom, 12)

                    TabView(selection: $selectedTab) {
                        overviewTab
                            .tag(AdminTab.overview)

                        usersTab
                            .tag(AdminTab.users)

                        channelsTab
                            .tag(AdminTab.channels)

                        diagnosticsTab
                            .tag(AdminTab.diagnostics)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
            }
            .navigationTitle("Панель управления")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        Task {
                            await repo.fetchOverviewStats()
                        }
                    } label: {
                        if repo.isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Готово") {
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color.slooshAccent)
                }
            }
            .sheet(item: $selectedUserForDetails) { user in
                AdminUserDetailSheet(user: user)
            }
            .task {
                await repo.fetchOverviewStats()
            }
        }
    }

    // MARK: - Scrollable Liquid Glass Tab Selector

    private var tabSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AdminTab.allCases) { tab in
                    let isSelected = selectedTab == tab
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                            selectedTab = tab
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 13, weight: .semibold))

                            Text(tab.rawValue)
                                .font(.system(size: 14, weight: isSelected ? .bold : .medium))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)

                            if tab == .users && repo.users.count > 0 {
                                Text("\(repo.users.count)")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(isSelected ? .black.opacity(0.8) : .secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(isSelected ? Color.black.opacity(0.12) : Color.primary.opacity(0.08))
                                    .clipShape(Capsule())
                            }
                        }
                        .foregroundColor(isSelected ? .black : .primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.slooshAccent : Color.clear)
                        )
                        .glassEffect(in: Capsule())
                    }
                    .buttonStyle(PeakPressButtonStyle())
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Tab 1: Overview & Live Stats

    private var overviewTab: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Key metrics grid
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    statCard(
                        title: "Пользователи",
                        value: "\(repo.stats.totalUsers)",
                        subtitle: "\(repo.stats.onlineUsers) в сети",
                        icon: "person.2.fill",
                        color: Color.slooshAccent
                    )

                    statCard(
                        title: "Каналы",
                        value: "\(repo.stats.totalChannels)",
                        subtitle: "Публичные и авторские",
                        icon: "megaphone.fill",
                        color: .orange
                    )

                    statCard(
                        title: "Всего постов",
                        value: "\(repo.stats.totalPosts)",
                        subtitle: "\(formatCount(repo.stats.totalViews)) просмотров",
                        icon: "doc.text.fill",
                        color: .blue
                    )

                    statCard(
                        title: "Реакции",
                        value: "\(repo.stats.totalReactions)",
                        subtitle: "Эмодзи отклики",
                        icon: "heart.fill",
                        color: .red
                    )
                }

                // Top Channels Section
                if !repo.stats.topChannels.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Топ каналов по аудитории")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 4)

                        VStack(spacing: 0) {
                            ForEach(Array(repo.stats.topChannels.enumerated()), id: \.element.id) { index, channel in
                                HStack(spacing: 12) {
                                    Text("#\(index + 1)")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(index == 0 ? Color.slooshAccent : .secondary)
                                        .frame(width: 24)

                                    SlooshAvatarView(channel: channel, size: 42)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(channel.name)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                        Text(channel.displayTag)
                                            .font(.system(size: 12))
                                            .foregroundColor(Color.slooshAccent)
                                    }

                                    Spacer()

                                    Text(channel.formattedSubscriberCount)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)

                                if index < repo.stats.topChannels.count - 1 {
                                    Divider()
                                        .padding(.leading, 50)
                                }
                            }
                        }
                        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
    }

    private func statCard(title: String, value: String, subtitle: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.16))
                        .frame(width: 38, height: 38)

                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(color)
                }

                Spacer()
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)

                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Tab 2: Users Management

    private var filteredUsers: [AdminUserItem] {
        let query = userSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty { return repo.users }
        return repo.users.filter { u in
            u.displayName.lowercased().contains(query) ||
            (u.tag?.lowercased().contains(query) ?? false) ||
            u.id.lowercased().contains(query) ||
            (u.email?.lowercased().contains(query) ?? false)
        }
    }

    private var usersTab: some View {
        VStack(spacing: 10) {
            // Floating Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField("Поиск по имени, @тегу или ID...", text: $userSearchQuery)
                    .font(.system(size: 15))

                if !userSearchQuery.isEmpty {
                    Button {
                        userSearchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassEffect(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 16)

            // Users list
            if filteredUsers.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.slash.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text("Пользователи не найдены")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 40)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredUsers) { user in
                            userRow(user)
                                .onTapGesture {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    selectedUserForDetails = user
                                }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    private func userRow(_ user: AdminUserItem) -> some View {
        HStack(spacing: 12) {
            SlooshAvatarView(
                avatarSource: user.avatarUrl,
                fallbackText: user.displayTitle,
                size: 46,
                showOnline: true,
                isOnline: user.isOnline
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(user.displayTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    if user.isBanned {
                        Text("БАН")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 6) {
                    if !user.displayTag.isEmpty {
                        Text(user.displayTag)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color.slooshAccent)
                    }

                    Text("•")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    Text(user.isOnline ? "в сети" : "был недавно")
                        .font(.system(size: 11))
                        .foregroundColor(user.isOnline ? Color.slooshAccent : .secondary)
                }
            }

            Spacer()

            Menu {
                Button {
                    UIPasteboard.general.string = user.id
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    ToastManager.shared.show(title: "ID скопирован", icon: "doc.on.doc.fill", iconColor: Color.slooshAccent)
                } label: {
                    Label("Скопировать ID", systemImage: "doc.on.doc")
                }

                if let tag = user.tag, !tag.isEmpty {
                    Button {
                        UIPasteboard.general.string = "@\(tag)"
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        ToastManager.shared.show(title: "Тег скопирован", icon: "at", iconColor: Color.slooshAccent)
                    } label: {
                        Label("Скопировать @тег", systemImage: "at")
                    }
                }

                Button {
                    selectedUserForDetails = user
                } label: {
                    Label("Подробнее", systemImage: "info.circle")
                }

                Divider()

                Button(role: user.isBanned ? .none : .destructive) {
                    Task {
                        _ = await repo.toggleBanUser(userId: user.id, isBanned: !user.isBanned)
                    }
                } label: {
                    Label(user.isBanned ? "Разблокировать" : "Заблокировать (Бан)", systemImage: user.isBanned ? "checkmark.circle" : "nosign")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(8)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Tab 3: Channels Moderation

    private var filteredChannels: [ChannelModel] {
        let query = channelSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty { return repo.channels }
        return repo.channels.filter { ch in
            ch.name.lowercased().contains(query) ||
            ch.tag.lowercased().contains(query) ||
            ch.ownerId.lowercased().contains(query)
        }
    }

    private var channelsTab: some View {
        VStack(spacing: 10) {
            // Floating Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField("Поиск по названию или @тегу канала...", text: $channelSearchQuery)
                    .font(.system(size: 15))

                if !channelSearchQuery.isEmpty {
                    Button {
                        channelSearchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassEffect(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 16)

            // Channels list
            if filteredChannels.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "megaphone")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text("Каналы не найдены")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 40)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredChannels) { channel in
                            channelRow(channel)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                    .padding(.bottom, 24)
                }
            }
        }
        .confirmationDialog(
            "Удалить канал?",
            isPresented: $showDeleteChannelAlert,
            titleVisibility: .visible
        ) {
            Button("Удалить канал навсегда", role: .destructive) {
                if let ch = channelToDelete {
                    Task {
                        _ = await repo.deleteChannel(channelId: ch.id)
                    }
                }
            }
            Button("Отмена", role: .cancel) {}
        }
    }

    private func channelRow(_ channel: ChannelModel) -> some View {
        HStack(spacing: 12) {
            SlooshAvatarView(channel: channel, size: 46)

            VStack(alignment: .leading, spacing: 3) {
                Text(channel.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(channel.displayTag)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color.slooshAccent)

                    Text("•")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    Text(channel.formattedSubscriberCount)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Button {
                channelToDelete = channel
                showDeleteChannelAlert = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundColor(.red.opacity(0.85))
                    .padding(8)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Tab 4: Diagnostics & System Logs

    private var diagnosticsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header status
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Журнал диагностики")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.primary)
                        Text("Системные события и ошибки приложения")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    Spacer()

                    Button("Очистить") {
                        AppDiagnostics.shared.clearLogs()
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.red)
                }

                let logs = AppDiagnostics.shared.recentLogs
                if logs.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 40))
                            .foregroundColor(Color.slooshAccent)
                        Text("Ошибок не зафиксировано")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                        Text("Все подсистемы (Сеть, Alloha, HLS, БД) работают штатно.")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                } else {
                    VStack(spacing: 8) {
                        ForEach(Array(logs.enumerated()), id: \.offset) { _, log in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.orange)
                                    .padding(.top, 2)

                                Text(log)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(12)
                            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
    }

    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000.0)
        }
        return "\(count)"
    }
}

// MARK: - Admin User Detail Sheet

private struct AdminUserDetailSheet: View {
    let user: AdminUserItem
    @Environment(\.dismiss) private var dismiss
    @StateObject private var repo = AdminRepository.shared
    @State private var isBannedState: Bool = false

    init(user: AdminUserItem) {
        self.user = user
        _isBannedState = State(initialValue: user.isBanned)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header Avatar & Name
                    VStack(spacing: 10) {
                        SlooshAvatarView(
                            avatarSource: user.avatarUrl,
                            fallbackText: user.displayTitle,
                            size: 80,
                            showOnline: true,
                            isOnline: user.isOnline
                        )

                        VStack(spacing: 4) {
                            Text(user.displayTitle)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.primary)

                            if !user.displayTag.isEmpty {
                                Text(user.displayTag)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(Color.slooshAccent)
                            }

                            Text(user.isOnline ? "Сейчас в сети" : "Был в сети недавно")
                                .font(.system(size: 13))
                                .foregroundColor(user.isOnline ? Color.slooshAccent : .secondary)
                        }
                    }
                    .padding(.top, 16)

                    // Details Card
                    VStack(spacing: 12) {
                        detailRow(title: "User ID", value: user.id, canCopy: true)
                        Divider()
                        detailRow(title: "Тег", value: user.displayTag.isEmpty ? "Не указан" : user.displayTag, canCopy: !user.displayTag.isEmpty)
                        if let email = user.email, !email.isEmpty {
                            Divider()
                            detailRow(title: "Email", value: email, canCopy: true)
                        }
                        Divider()
                        detailRow(title: "Каналов создано", value: "\(user.channelsCount)", canCopy: false)
                        Divider()
                        detailRow(title: "Статус аккаунта", value: isBannedState ? "Заблокирован 🚫" : "Активен ✅", canCopy: false)
                    }
                    .padding(16)
                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(.horizontal, 16)

                    // Action Buttons
                    VStack(spacing: 10) {
                        Button {
                            Task {
                                let newBan = !isBannedState
                                let success = await repo.toggleBanUser(userId: user.id, isBanned: newBan)
                                if success {
                                    isBannedState = newBan
                                    ToastManager.shared.show(
                                        title: newBan ? "Пользователь заблокирован" : "Пользователь разблокирован",
                                        icon: newBan ? "nosign" : "checkmark.circle.fill",
                                        iconColor: newBan ? .red : Color.slooshAccent
                                    )
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: isBannedState ? "checkmark.circle.fill" : "nosign")
                                Text(isBannedState ? "Разблокировать пользователя" : "Заблокировать (Бан)")
                            }
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(isBannedState ? Color.green : Color.red)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 32)
            }
            .navigationTitle("Профиль пользователя")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Закрыть") {
                        dismiss()
                    }
                    .foregroundColor(Color.slooshAccent)
                }
            }
        }
    }

    private func detailRow(title: String, value: String, canCopy: Bool) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 14))
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)

            if canCopy {
                Button {
                    UIPasteboard.general.string = value
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    ToastManager.shared.show(title: "Скопировано", icon: "doc.on.doc.fill", iconColor: Color.slooshAccent)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12))
                        .foregroundColor(Color.slooshAccent)
                }
            }
        }
    }
}
