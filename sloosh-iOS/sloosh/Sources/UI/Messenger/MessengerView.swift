import SwiftUI

public struct MessengerView: View {
    @StateObject private var repo = MessengerRepository.shared
    @ObservedObject private var authRepo = AuthRepository.shared

    @State private var searchQuery: String = ""
    @State private var selectedPeerUser: SlooshUser? = nil
    @State private var selectedChannel: ChannelModel? = nil
    @State private var showAuthSheet: Bool = false
    @State private var showCreateChannelSheet: Bool = false
    @State private var showNewChatSheet: Bool = false

    // Chat deletion state
    @State private var peerToDelete: SlooshUser? = nil
    @State private var showDeleteChatConfirm: Bool = false

    // Channel action state (Unsubscribe or Delete) - Archived for channels
    @State private var channelToAction: ChannelModel? = nil
    @State private var showChannelActionConfirm: Bool = false

    // Search state
    @State private var searchedPublicChannels: [ChannelModel] = []
    @State private var isSearching: Bool = false
    @State private var searchTask: Task<Void, Never>? = nil

    public init() {}

    private var currentUserId: String {
        authRepo.currentUser?.id ?? ""
    }

    private var unifiedFeedItems: [MessengerFeedItem] {
        var items: [MessengerFeedItem] = []
        if searchQuery.isEmpty {
            items += repo.conversations.map { MessengerFeedItem.directChat($0) }
            // Archived: Channels can be re-enabled here in the future
            // items += repo.subscribedChannels.map { MessengerFeedItem.channel($0) }
        } else {
            let query = searchQuery.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanQuery = TagValidator.sanitize(query)
            let filteredChats = repo.conversations.filter {
                $0.peerUser.displayTitle.localizedCaseInsensitiveContains(query) ||
                $0.peerUser.displayTag.localizedCaseInsensitiveContains(cleanQuery) ||
                $0.lastMessageText.localizedCaseInsensitiveContains(query)
            }
            items += filteredChats.map { MessengerFeedItem.directChat($0) }
            // Archived: Channels can be re-enabled here in the future
            // let filteredSubs = repo.subscribedChannels.filter { ... }
            // items += filteredSubs.map { MessengerFeedItem.channel($0) }
        }
        return items.sorted { $0.timestampMs > $1.timestampMs }
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color(UIColor.systemBackground).ignoresSafeArea()

                if !authRepo.isAuthenticated {
                    guestView
                } else if repo.isLoading && repo.conversations.isEmpty {
                    skeletonList
                } else if repo.conversations.isEmpty && searchQuery.isEmpty {
                    emptyState
                } else {
                    feedList
                }
            }
            .navigationTitle("Чаты")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchQuery, prompt: "Поиск по имени или @тегу")
            .onChange(of: searchQuery) { _, newValue in
                searchTask?.cancel()
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    self.isSearching = false
                    repo.clearSearchResults()
                    return
                }

                self.isSearching = true
                searchTask = Task {
                    try? await Task.sleep(nanoseconds: 180_000_000)
                    if Task.isCancelled { return }

                    _ = await repo.searchUsers(query: trimmed)
                    if Task.isCancelled { return }

                    await MainActor.run {
                        self.isSearching = false
                    }
                }
            }
            .toolbar { toolbarContent }
            .navigationDestination(item: $selectedPeerUser) { peer in
                ChatDetailView(peerUser: peer)
            }
            .navigationDestination(item: $selectedChannel) { channel in
                ChannelDetailView(channel: channel)
            }
            .sheet(isPresented: $showNewChatSheet) {
                NewChatSheet { selectedUser in
                    selectedPeerUser = selectedUser
                }
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
                    // Channels archived per user instructions:
                    // _ = await repo.fetchSubscribedChannels()
                    // _ = await repo.fetchPublicChannels()
                }
            }
            .refreshable {
                if authRepo.isAuthenticated {
                    await repo.fetchConversations()
                    // _ = await repo.fetchSubscribedChannels()
                    // _ = await repo.fetchPublicChannels()
                }
            }
        }
        .tint(Color.primary)
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
                // 0. Индикатор поиска
                if isSearching {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color.primary)
                        Text("Поиск...")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }

                // 1. Поиск: Пользователи
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

                // 2. Основной список диалогов
                if !searchQuery.isEmpty && !repo.searchResults.isEmpty && !unifiedFeedItems.isEmpty {
                    HStack {
                        Text("ЧАТЫ")
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

                // 3. Пустой результат поиска
                if !searchQuery.isEmpty && !isSearching && repo.searchResults.isEmpty && unifiedFeedItems.isEmpty {
                    searchEmptyState
                        .padding(.top, 60)
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var searchEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 44, weight: .light))
                .foregroundColor(.secondary)

            Text("Ничего не найдено")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.primary)

            Text("По запросу «\(searchQuery)» не найдено ни одного пользователя.")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
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
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 52, weight: .thin))
                .foregroundColor(.secondary)

            Text("Нет сообщений")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.primary)

            Text("Найдите собеседника по имени или @тегу через поиск, чтобы начать диалог.")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                showNewChatSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 15, weight: .bold))
                    Text("Написать сообщение")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundColor(Color(UIColor.systemBackground))
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Capsule().fill(Color.primary))
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
                                .frame(width: 140, height: 16)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.secondary.opacity(0.15))
                                .frame(width: 220, height: 14)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
        }
    }

    private var guestView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 64))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.primary, .secondary],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(spacing: 8) {
                Text("Личные сообщения Sloosh")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.primary)

                Text("Войдите в аккаунт, чтобы общаться с друзьями и делиться фильмами!")
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
                .foregroundColor(Color(UIColor.systemBackground))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Capsule().fill(Color.primary))
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
                Button {
                    showNewChatSheet = true
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.primary)
                }
            }
        }
    }

    private func deleteChat(peer: SlooshUser) {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        let chatId = repo.getOrCreateChatId(peerUserId: peer.id)

        withAnimation(.easeInOut(duration: 0.22)) {
            self.repo.removeConversationLocally(chatId: chatId)
        }

        Task {
            _ = await repo.deleteChat(chatId: chatId, peerUserId: peer.id, deleteForEveryone: true)
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
                                .foregroundColor(.primary)
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
                .tint(.red)
            } else {
                Button(role: .destructive) {
                    onAction()
                } label: {
                    Label("Отписаться", systemImage: "arrow.uturn.backward")
                }
                .tint(.red)
            }
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM"
        return formatter
    }()

    private func formatTime(ms: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        if Calendar.current.isDateInToday(date) {
            return Self.timeFormatter.string(from: date)
        } else {
            return Self.dateFormatter.string(from: date)
        }
    }
}

// MARK: - Public Channel Search Row

public struct PublicChannelSearchRow: View {
    public let channel: ChannelModel

    public init(channel: ChannelModel) {
        self.channel = channel
    }

    public var body: some View {
        HStack(spacing: 14) {
            SlooshAvatarView(channel: channel, size: 56)

            VStack(alignment: .leading, spacing: 3) {
                Text(channel.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(channel.displayTag)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)

                    Text("•")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    Text(channel.formattedSubscriberCount)
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
                            .foregroundColor(Color(UIColor.systemBackground))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.primary))
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
            .tint(.red)
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM"
        return formatter
    }()

    private func formatTime(ms: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        if Calendar.current.isDateInToday(date) {
            return Self.timeFormatter.string(from: date)
        } else {
            return Self.dateFormatter.string(from: date)
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
                        .foregroundColor(.secondary)
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

// MARK: - New Chat Sheet (Direct Messaging User Picker)

private struct NewChatSheet: View {
    let onSelectUser: (SlooshUser) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var repo = MessengerRepository.shared
    @State private var query: String = ""
    @State private var isSearching: Bool = false
    @State private var searchTask: Task<Void, Never>? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color(UIColor.systemBackground).ignoresSafeArea()

                VStack(spacing: 0) {
                    if isSearching {
                        HStack(spacing: 10) {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Color.primary)
                            Text("Поиск...")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }

                    let isQueryEmpty = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    let displayedUsers: [SlooshUser] = {
                        if !isQueryEmpty {
                            return repo.searchResults
                        } else {
                            let recent = repo.conversations.map { $0.peerUser }
                            if !recent.isEmpty {
                                return recent
                            }
                            return Array(repo.getLocalKnownUsers().values)
                        }
                    }()

                    if displayedUsers.isEmpty && !isSearching {
                        VStack(spacing: 12) {
                            Spacer()
                            Image(systemName: isQueryEmpty ? "person.2.fill" : "person.crop.circle.badge.questionmark")
                                .font(.system(size: 48, weight: .thin))
                                .foregroundColor(.secondary)
                            Text(isQueryEmpty ? "Начните новый диалог" : "Пользователь не найден")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)
                            Text(isQueryEmpty ? "Введите имя или @тег пользователя в поиске выше." : "Проверьте правильность написания имени или @тега.")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                            Spacer()
                        }
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                if isQueryEmpty && !displayedUsers.isEmpty {
                                    HStack {
                                        Text("НЕДАВНИЕ КОНТАКТЫ")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(.secondary)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.top, 12)
                                    .padding(.bottom, 4)
                                }

                                ForEach(displayedUsers) { user in
                                    Button {
                                        dismiss()
                                        onSelectUser(user)
                                    } label: {
                                        PeakUserSearchRow(user: user)
                                    }
                                    .buttonStyle(PeakPressButtonStyle())

                                    PeakDivider()
                                        .padding(.leading, 86)
                                }
                            }
                        }
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("Новое сообщение")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Имя или @тег пользователя")
            .onChange(of: query) { _, newQ in
                searchTask?.cancel()
                let trimmed = newQ.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    isSearching = false
                    repo.clearSearchResults()
                    return
                }
                isSearching = true
                searchTask = Task {
                    try? await Task.sleep(nanoseconds: 180_000_000)
                    if Task.isCancelled { return }
                    _ = await repo.searchUsers(query: trimmed)
                    if Task.isCancelled { return }
                    await MainActor.run {
                        isSearching = false
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        dismiss()
                    }
                }
            }
        }
        .tint(Color.primary)
    }
}

