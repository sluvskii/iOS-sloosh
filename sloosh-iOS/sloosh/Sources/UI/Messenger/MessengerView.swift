import SwiftUI

public struct MessengerView: View {
    @StateObject private var repo = MessengerRepository.shared
    @ObservedObject private var authRepo = AuthRepository.shared

    @State private var searchQuery: String = ""
    @State private var selectedPeerUser: SlooshUser? = nil
    @State private var selectedChannel: ChannelModel? = nil
    @State private var showAuthSheet: Bool = false
    @State private var showCreateChannelSheet: Bool = false

    // Chat deletion state
    @State private var peerToDelete: SlooshUser? = nil
    @State private var showDeleteChatConfirm: Bool = false

    // Channel action state (Unsubscribe or Delete)
    @State private var channelToAction: ChannelModel? = nil
    @State private var showChannelActionConfirm: Bool = false

    // Search state
    @State private var searchedPublicChannels: [ChannelModel] = []

    public init() {}

    private var currentUserId: String {
        authRepo.currentUser?.id ?? ""
    }

    private var unifiedFeedItems: [MessengerFeedItem] {
        var items: [MessengerFeedItem] = []
        if searchQuery.isEmpty {
            items += repo.conversations.map { MessengerFeedItem.directChat($0) }
            items += repo.subscribedChannels.map { MessengerFeedItem.channel($0) }
        } else {
            let query = searchQuery.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanQuery = TagValidator.sanitize(query)
            let filteredChats = repo.conversations.filter {
                $0.peerUser.displayTitle.localizedCaseInsensitiveContains(query) ||
                $0.peerUser.displayTag.localizedCaseInsensitiveContains(cleanQuery) ||
                $0.lastMessageText.localizedCaseInsensitiveContains(query)
            }
            let filteredSubs = repo.subscribedChannels.filter {
                $0.name.localizedCaseInsensitiveContains(query) ||
                $0.tag.localizedCaseInsensitiveContains(cleanQuery) ||
                $0.description.localizedCaseInsensitiveContains(query) ||
                ($0.lastPostText?.localizedCaseInsensitiveContains(query) == true)
            }
            items += filteredChats.map { MessengerFeedItem.directChat($0) }
            items += filteredSubs.map { MessengerFeedItem.channel($0) }
        }
        return items.sorted { $0.timestampMs > $1.timestampMs }
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color(UIColor.systemBackground).ignoresSafeArea()

                if !authRepo.isAuthenticated {
                    guestView
                } else if repo.isLoading && repo.conversations.isEmpty && repo.subscribedChannels.isEmpty {
                    skeletonList
                } else if repo.conversations.isEmpty && repo.subscribedChannels.isEmpty && searchQuery.isEmpty {
                    emptyState
                } else {
                    feedList
                }
            }
            .navigationTitle("Чаты")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchQuery, prompt: "Поиск чатов и каналов")
            .onChange(of: searchQuery) { _, newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    Task {
                        await repo.searchUsers(query: trimmed)
                        let channels = await repo.fetchPublicChannels(query: trimmed)
                        self.searchedPublicChannels = channels
                    }
                } else {
                    self.searchedPublicChannels = []
                }
            }
            .toolbar { toolbarContent }
            .navigationDestination(item: $selectedPeerUser) { peer in
                ChatDetailView(peerUser: peer)
            }
            .navigationDestination(item: $selectedChannel) { channel in
                ChannelDetailView(channel: channel)
            }
            .sheet(isPresented: $showCreateChannelSheet) {
                CreateChannelSheet { newChannel in
                    selectedChannel = newChannel
                }
            }
            .fullScreenCover(isPresented: $showAuthSheet) {
                AuthView()
            }
            .confirmationDialog(
                "Удалить чат с \(peerToDelete?.displayTitle ?? "")?",
                isPresented: $showDeleteChatConfirm,
                titleVisibility: .visible
            ) {
                Button("Удалить чат", role: .destructive) {
                    if let peer = peerToDelete {
                        deleteChat(peer: peer)
                    }
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("История сообщений будет удалена.")
            }
            .confirmationDialog(
                channelActionTitle,
                isPresented: $showChannelActionConfirm,
                titleVisibility: .visible
            ) {
                if let channel = channelToAction {
                    let isOwner = (channel.ownerId == currentUserId)
                    if isOwner {
                        Button("Удалить канал", role: .destructive) {
                            Task {
                                _ = await repo.deleteChannel(channelId: channel.id)
                            }
                        }
                    } else {
                        Button("Отписаться от канала", role: .destructive) {
                            Task {
                                _ = await repo.unsubscribeFromChannel(channelId: channel.id)
                            }
                        }
                    }
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text(channelActionMessage)
            }
            .task {
                if authRepo.isAuthenticated {
                    await repo.syncCurrentUserProfile()
                    await repo.fetchConversations()
                    _ = await repo.fetchSubscribedChannels()
                }
            }
            .refreshable {
                if authRepo.isAuthenticated {
                    await repo.fetchConversations()
                    _ = await repo.fetchSubscribedChannels()
                }
            }
        }
    }

    private var channelActionTitle: String {
        guard let channel = channelToAction else { return "" }
        if channel.ownerId == currentUserId {
            return "Удалить канал «\(channel.name)»?"
        } else {
            return "Отписаться от «\(channel.name)»?"
        }
    }

    private var channelActionMessage: String {
        guard let channel = channelToAction else { return "" }
        if channel.ownerId == currentUserId {
            return "Канал и все публикации будут удалены без возможности восстановления."
        } else {
            return "Вы перестанете получать обновления из этого канала."
        }
    }

    // MARK: - Feed List & Search Sections

    private var feedList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // 1. Поиск: Публичные каналы
                if !searchQuery.isEmpty && !searchedPublicChannels.isEmpty {
                    Section {
                        ForEach(searchedPublicChannels) { channel in
                            PublicChannelSearchRow(
                                channel: channel,
                                isSubscribed: repo.isSubscribed(channelId: channel.id),
                                onToggleSubscribe: {
                                    toggleChannelSubscription(channel: channel)
                                },
                                onSelect: {
                                    selectedChannel = channel
                                }
                            )

                            PeakDivider()
                                .padding(.leading, 86)
                        }
                    } header: {
                        HStack {
                            Text("КАНАЛЫ")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, 4)
                    }
                }

                // 2. Поиск: Пользователи
                if !searchQuery.isEmpty && !repo.searchResults.isEmpty {
                    Section {
                        ForEach(repo.searchResults) { user in
                            Button {
                                selectedPeerUser = user
                            } label: {
                                PeakUserSearchRow(user: user)
                            }
                            .buttonStyle(PeakPressButtonStyle())

                            PeakDivider()
                                .padding(.leading, 86)
                        }
                    } header: {
                        HStack {
                            Text("ПОЛЬЗОВАТЕЛИ")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, 4)
                    }
                }

                // 3. Основной объединённый список диалогов и каналов
                if !searchQuery.isEmpty && (!repo.searchResults.isEmpty || !searchedPublicChannels.isEmpty) && !unifiedFeedItems.isEmpty {
                    HStack {
                        Text("ЧАТЫ И ПОДПИСКИ")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 4)
                }

                ForEach(unifiedFeedItems) { item in
                    switch item {
                    case .directChat(let chat):
                        Button {
                            selectedPeerUser = chat.peerUser
                        } label: {
                            PeakChatRow(chat: chat, onDelete: {
                                peerToDelete = chat.peerUser
                                showDeleteChatConfirm = true
                            })
                        }
                        .buttonStyle(PeakPressButtonStyle())

                        PeakDivider()
                            .padding(.leading, 86)

                    case .channel(let channel):
                        Button {
                            selectedChannel = channel
                        } label: {
                            PeakChannelRow(
                                channel: channel,
                                isOwner: channel.ownerId == currentUserId,
                                onAction: {
                                    channelToAction = channel
                                    showChannelActionConfirm = true
                                }
                            )
                        }
                        .buttonStyle(PeakPressButtonStyle())

                        PeakDivider()
                            .padding(.leading, 86)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func toggleChannelSubscription(channel: ChannelModel) {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        Task {
            if repo.isSubscribed(channelId: channel.id) {
                _ = await repo.unsubscribeFromChannel(channelId: channel.id)
            } else {
                _ = await repo.subscribeToChannel(channel: channel)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 48, weight: .thin))
                    .foregroundColor(.secondary)

                Image(systemName: "megaphone.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Color.slooshAccent)
                    .offset(x: 6, y: 6)
            }

            Text("Пока нет чатов и каналов")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.secondary)

            Text("Найдите друзей или интересные каналы через поиск, или создайте свой первый канал!")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)

            Button {
                showCreateChannelSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "megaphone.fill")
                        .font(.system(size: 15, weight: .bold))
                    Text("Создать канал")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundColor(.black)
                .padding(.horizontal, 20)
                .padding(.vertical, 11)
                .background(
                    Capsule()
                        .fill(Color.slooshAccent)
                )
                .glassEffect(in: Capsule())
            }
            .buttonStyle(PeakPressButtonStyle())
            .padding(.top, 8)
        }
    }

    private var skeletonList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(0..<6, id: \.self) { _ in
                    HStack(spacing: 14) {
                        Circle()
                            .fill(Color.secondary.opacity(0.2))
                            .frame(width: 56, height: 56)
                        VStack(alignment: .leading, spacing: 8) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.secondary.opacity(0.2))
                                .frame(width: 120, height: 16)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.secondary.opacity(0.2))
                                .frame(width: 200, height: 14)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .redacted(reason: .placeholder)
                    .opacity(0.4)

                    PeakDivider()
                        .padding(.leading, 86)
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var guestView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 64))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.slooshAccent, .white],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(spacing: 8) {
                Text("Чаты и Каналы Sloosh")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.primary)

                Text("Войдите в аккаунт, чтобы общаться с друзьями, читать авторские каналы и делиться фильмами!")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            Button {
                showAuthSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 18, weight: .bold))
                    Text("Войти в аккаунт")
                        .font(.system(size: 17, weight: .bold))
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Capsule().fill(Color.slooshAccent))
                .padding(.horizontal, 40)
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if authRepo.isAuthenticated {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        showCreateChannelSheet = true
                    } label: {
                        Label("Создать канал", systemImage: "megaphone.fill")
                    }

                    Button {} label: {
                        Label("Создать беседу (Скоро)", systemImage: "person.2.fill")
                    }
                    .disabled(true)
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.slooshAccent)
                }
            }
        }
    }

    private func deleteChat(peer: SlooshUser) {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        Task {
            await repo.fetchConversations()
        }
    }
}

// MARK: - Peak Channel Row View

public struct PeakChannelRow: View {
    public let channel: ChannelModel
    public let isOwner: Bool
    public let onAction: () -> Void

    public init(channel: ChannelModel, isOwner: Bool, onAction: @escaping () -> Void) {
        self.channel = channel
        self.isOwner = isOwner
        self.onAction = onAction
    }

    public var body: some View {
        HStack(spacing: 14) {
            SlooshAvatarView(channel: channel, size: 56)

            // Content
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    HStack(spacing: 6) {
                        Text(channel.name)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        if isOwner {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Color.slooshAccent)
                        }
                    }

                    Spacer()

                    Text(formatTime(ms: channel.lastPostTimestampMs ?? channel.updatedAtMs))
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }

                HStack(alignment: .bottom) {
                    Text(channel.lastPostText ?? (channel.description.isEmpty ? "Канал создан" : channel.description))
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    Spacer()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .contextMenu {
            if isOwner {
                Button(role: .destructive) {
                    onAction()
                } label: {
                    Label("Удалить канал", systemImage: "trash")
                }
            } else {
                Button(role: .destructive) {
                    onAction()
                } label: {
                    Label("Отписаться", systemImage: "arrow.uturn.backward")
                }
            }
        }
    }

    private func formatTime(ms: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "dd.MM"
            return formatter.string(from: date)
        }
    }
}

// MARK: - Public Channel Search Row

public struct PublicChannelSearchRow: View {
    public let channel: ChannelModel
    public let isSubscribed: Bool
    public let onToggleSubscribe: () -> Void
    public let onSelect: () -> Void

    public init(
        channel: ChannelModel,
        isSubscribed: Bool,
        onToggleSubscribe: @escaping () -> Void,
        onSelect: @escaping () -> Void
    ) {
        self.channel = channel
        self.isSubscribed = isSubscribed
        self.onToggleSubscribe = onToggleSubscribe
        self.onSelect = onSelect
    }

    public var body: some View {
        HStack(spacing: 14) {
            SlooshAvatarView(channel: channel, size: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text(channel.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(channel.displayTag)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.slooshAccent)

                    Text("•")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    Text(channel.formattedSubscriberCount)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Button {
                onToggleSubscribe()
            } label: {
                HStack(spacing: 4) {
                    if isSubscribed {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                        Text("Подписан")
                            .font(.system(size: 13, weight: .semibold))
                    } else {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text("Подписаться")
                            .font(.system(size: 13, weight: .bold))
                    }
                }
                .foregroundColor(isSubscribed ? .secondary : .black)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(isSubscribed ? Color.primary.opacity(0.08) : Color.slooshAccent)
                )
                .glassEffect(in: Capsule())
            }
            .buttonStyle(PeakPressButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }
}

// MARK: - Peak Chat Row View (Peak Messenger Style)

private struct PeakChatRow: View {
    let chat: ChatConversation
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            SlooshAvatarView(user: chat.peerUser, size: 56, showOnline: true)

            // Content
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(chat.peerUser.displayTitle)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Spacer()

                    Text(formatTime(ms: chat.updatedAtMs))
                        .font(.system(size: 13))
                        .foregroundColor(chat.unreadCount > 0 ? .primary : .secondary)
                }

                HStack(alignment: .bottom) {
                    HStack(spacing: 4) {
                        Text(chat.lastMessageText)
                            .font(.system(size: 15))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    if chat.unreadCount > 0 {
                        Text("\(chat.unreadCount)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.slooshAccent))
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .contextMenu {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Удалить чат", systemImage: "trash")
            }
        }
    }

    private func formatTime(ms: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "dd.MM"
            return formatter.string(from: date)
        }
    }
}

// MARK: - Peak User Search Row

private struct PeakUserSearchRow: View {
    let user: SlooshUser

    var body: some View {
        HStack(spacing: 14) {
            SlooshAvatarView(user: user, size: 56, showOnline: true)

            VStack(alignment: .leading, spacing: 3) {
                Text(user.displayTitle)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)

                if !user.displayTag.isEmpty {
                    Text(user.displayTag)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color.slooshAccent)
                } else {
                    Text("Пользователь Sloosh")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.secondary.opacity(0.5))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

// MARK: - Reusable Peak Components

public struct PeakAvatarView: View {
    public let user: SlooshUser
    public let size: CGFloat
    public var showOnline: Bool = false

    public init(user: SlooshUser, size: CGFloat, showOnline: Bool = false) {
        self.user = user
        self.size = size
        self.showOnline = showOnline
    }

    public var body: some View {
        SlooshAvatarView(user: user, size: size, showOnline: showOnline)
    }
}

public struct PeakPressButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.spring(duration: 0.2, bounce: 0.3), value: configuration.isPressed)
    }
}

public struct PeakDivider: View {
    public init() {}
    public var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(height: 0.5)
    }
}
