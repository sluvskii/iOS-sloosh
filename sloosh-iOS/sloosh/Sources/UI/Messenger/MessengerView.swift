import SwiftUI

/// Pushed from Moments: back returns to the feed, compose opens a real user picker.
public struct MessengerView: View {
    @ObservedObject private var repo = MessengerRepository.shared
    @ObservedObject private var authRepo = AuthRepository.shared
    @Environment(\.dismiss) private var dismiss
    @State private var searchQuery = ""
    @State private var scrollOffset: CGFloat = 0
    @State private var selectedPeerUser: SlooshUser?
    @State private var pendingPeerUser: SlooshUser?
    @State private var showAuthSheet = false
    @State private var showNewChatSheet = false
    @State private var peerToDelete: SlooshUser?
    @State private var showDeleteChatConfirm = false
    @State private var foundUsers: [SlooshUser] = []
    @State private var isSearching = false

    public init() {}

    private var query: MessengerSearchQuery { MessengerSearchQuery(searchQuery) }

    private var filteredConversations: [ChatConversation] {
        repo.conversations.filter {
            query.matches(name: $0.peerUser.displayTitle, tag: $0.peerUser.displayTag, message: $0.lastMessageText)
        }.sorted { $0.updatedAtMs > $1.updatedAtMs }
    }

    // An existing conversation is already a search result: don't show it twice.
    private var newPeople: [SlooshUser] {
        let visibleIds = Set(filteredConversations.map { $0.peerUser.id })
        return foundUsers.filter { !visibleIds.contains($0.id) }
    }

    public var body: some View {
        ZStack {
            Color(UIColor.systemBackground).ignoresSafeArea()
            if !authRepo.isAuthenticated {
                AppEmptyStateView(
                    icon: "bubble.left.and.bubble.right",
                    title: "Сообщения для своих",
                    description: "Войдите, чтобы переписываться и делиться фильмами и моментами.",
                    action: .init(label: "Войти в аккаунт", handler: { showAuthSheet = true })
                )
            } else {
                conversationList
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            SlooshTopBar(
                title: "Чаты",
                scrollOffset: $scrollOffset,
                leadingAction: { dismiss() },
                showsBottom: authRepo.isAuthenticated,
                trailing: {
                    if authRepo.isAuthenticated {
                        TelegramGlassIconButton(systemName: "square.and.pencil") {
                            showNewChatSheet = true
                        }
                        .accessibilityLabel("Новое сообщение")
                    }
                },
                bottom: {
                    SlooshSearchField(text: $searchQuery, prompt: "Имя, @тег или сообщение")
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
            )
        }
        .navigationDestination(item: $selectedPeerUser) { peer in
            ChatDetailView(peerUser: peer)
        }
        .sheet(isPresented: $showNewChatSheet, onDismiss: {
            // Push only after dismissal, not during the sheet's transition.
            if let peer = pendingPeerUser {
                pendingPeerUser = nil
                selectedPeerUser = peer
            }
        }) {
            NewChatSheet { pendingPeerUser = $0 }
        }
        .fullScreenCover(isPresented: $showAuthSheet) { AuthView() }
        .confirmationDialog(
            "Удалить чат с \(peerToDelete?.displayTitle ?? "")?",
            isPresented: $showDeleteChatConfirm,
            titleVisibility: .visible
        ) {
            Button("Удалить чат", role: .destructive) {
                if let peer = peerToDelete {
                    let chatId = repo.getOrCreateChatId(peerUserId: peer.id)
                    Task { _ = await repo.deleteChat(chatId: chatId, peerUserId: peer.id, deleteForEveryone: true) }
                }
                peerToDelete = nil
            }
            Button("Отмена", role: .cancel) { peerToDelete = nil }
        } message: {
            Text("Чат и история сообщений будут удалены у вас и у собеседника. Это действие нельзя отменить.")
        }
        .task(id: authRepo.currentUser?.id) {
            guard authRepo.isAuthenticated else { return }
            await repo.syncCurrentUserProfile()
            await repo.fetchConversations()
        }
        .task(id: query.text) { await searchPeople() }
        .onChange(of: authRepo.currentUser?.id) { _, _ in
            searchQuery = ""
            foundUsers = []
            pendingPeerUser = nil
            showNewChatSheet = false
        }
        .fullWidthSwipeBack()
        .tint(.primary)
    }

    private var conversationList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if isSearching {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Поиск пользователей…").font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(16)
                }

                if !query.isEmpty && !filteredConversations.isEmpty {
                    sectionTitle("Чаты")
                }
                ForEach(filteredConversations) { chat in
                    Button { selectedPeerUser = chat.peerUser } label: {
                        MessengerConversationRow(chat: chat)
                    }
                    .buttonStyle(PeakPressButtonStyle())
                    .contextMenu {
                        Button(role: .destructive) {
                            peerToDelete = chat.peerUser
                            showDeleteChatConfirm = true
                        } label: {
                            Label("Удалить чат", systemImage: "trash")
                        }
                    }
                    PeakDivider().padding(.leading, 86)
                }

                if !query.isEmpty && !newPeople.isEmpty {
                    sectionTitle("Пользователи")
                    ForEach(newPeople) { user in
                        Button { selectedPeerUser = user } label: { MessengerUserRow(user: user) }
                            .buttonStyle(PeakPressButtonStyle())
                        PeakDivider().padding(.leading, 86)
                    }
                }
            }
            .padding(.top, 8)
        }
        .overlay {
            if query.isEmpty && repo.conversations.isEmpty {
                if repo.isLoading {
                    ProgressView("Загрузка чатов…")
                } else {
                    AppEmptyStateView(
                        icon: "bubble.left.and.bubble.right",
                        title: "Пока нет сообщений",
                        description: "Найдите собеседника по имени или @тегу и отправьте первое сообщение.",
                        action: .init(label: "Написать сообщение", handler: { showNewChatSheet = true })
                    )
                }
            } else if !query.isEmpty && !isSearching && filteredConversations.isEmpty && newPeople.isEmpty {
                AppEmptyStateView(
                    icon: "magnifyingglass", title: "Ничего не найдено",
                    description: "Попробуйте другое имя, @тег или текст сообщения."
                )
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, offset in
            scrollOffset = offset
        }
        .refreshable { await repo.fetchConversations() }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 6)
    }

    @MainActor
    private func searchPeople() async {
        let requestedQuery = query
        let userId = authRepo.currentUser?.id
        foundUsers = []
        isSearching = !requestedQuery.isEmpty && authRepo.isAuthenticated
        guard isSearching else { return }
        do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
        let results = await repo.searchUsers(query: requestedQuery.text, publishResults: false)
        guard !Task.isCancelled, query == requestedQuery, authRepo.currentUser?.id == userId else { return }
        foundUsers = results
        isSearching = false
    }
}

// MARK: - Conversation row

private struct MessengerConversationRow: View {
    let chat: ChatConversation

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

// MARK: - User search row

private struct MessengerUserRow: View {
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

// MARK: - New message

private struct NewChatSheet: View {
    let onSelectUser: (SlooshUser) -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var repo = MessengerRepository.shared
    @State private var searchText = ""
    @State private var results: [SlooshUser] = []
    @State private var isSearching = false
    @State private var scrollOffset: CGFloat = 0

    private var query: MessengerSearchQuery { MessengerSearchQuery(searchText) }

    private var displayedUsers: [SlooshUser] {
        if !query.isEmpty { return results }
        // Only actual recent conversations, never a random cached user directory.
        return repo.conversations.sorted { $0.updatedAtMs > $1.updatedAtMs }.map(\.peerUser)
    }

    var body: some View {
        ZStack {
            Color.clear.ignoresSafeArea()
            ScrollView {
                LazyVStack(spacing: 0) {
                    if isSearching { ProgressView().padding(16) }
                    if query.isEmpty && !displayedUsers.isEmpty {
                        Text("Недавние собеседники")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                    }
                    ForEach(displayedUsers) { user in
                        Button {
                            onSelectUser(user)
                            dismiss()
                        } label: { MessengerUserRow(user: user) }
                            .buttonStyle(PeakPressButtonStyle())
                        PeakDivider().padding(.leading, 86)
                    }
                }
            }
            .overlay {
                if displayedUsers.isEmpty && !isSearching {
                    AppEmptyStateView(
                        icon: query.isEmpty ? "square.and.pencil" : "magnifyingglass",
                        title: query.isEmpty ? "Кому напишем?" : "Пользователь не найден",
                        description: query.isEmpty ? "Введите имя или @тег в поиске." : "Проверьте имя или @тег и попробуйте ещё раз."
                    )
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, offset in
                scrollOffset = offset
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            SlooshTopBar(
                title: "Новое сообщение", scrollOffset: $scrollOffset,
                leadingIcon: "xmark", leadingAction: { dismiss() },
                tintColor: .clear, topPadding: 8, bottomPadding: 4, blurOverflow: -30,
                trailing: { EmptyView() },
                bottom: {
                    SlooshSearchField(text: $searchText, prompt: "Имя или @тег")
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
            )
        }
        .task(id: query.text) { await searchPeople() }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground { Color.clear.glassEffect(in: .rect) }
        .tint(.primary)
    }

    @MainActor
    private func searchPeople() async {
        let requestedQuery = query
        let userId = AuthRepository.shared.currentUser?.id
        results = []
        isSearching = !requestedQuery.isEmpty
        guard isSearching else { return }
        do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
        let users = await repo.searchUsers(query: requestedQuery.text, publishResults: false)
        guard !Task.isCancelled, query == requestedQuery, AuthRepository.shared.currentUser?.id == userId else { return }
        results = users
        isSearching = false
    }
}
