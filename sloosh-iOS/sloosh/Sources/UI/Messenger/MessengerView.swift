import SwiftUI

public struct MessengerView: View {
    @StateObject private var repo = MessengerRepository.shared
    @ObservedObject private var authRepo = AuthRepository.shared

    @State private var searchQuery: String = ""
    @State private var selectedPeerUser: SlooshUser? = nil
    @State private var showAuthSheet: Bool = false
    @State private var peerToDelete: SlooshUser? = nil
    @State private var showDeleteConfirm: Bool = false

    public init() {}

    private var filteredConversations: [ChatConversation] {
        if searchQuery.isEmpty { return repo.conversations }
        return repo.conversations.filter {
            $0.peerUser.displayTitle.localizedCaseInsensitiveContains(searchQuery) ||
            $0.peerUser.email.localizedCaseInsensitiveContains(searchQuery) ||
            $0.lastMessageText.localizedCaseInsensitiveContains(searchQuery)
        }
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
                    chatList
                }
            }
            .navigationTitle("Чаты")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchQuery, prompt: "Поиск")
            .onChange(of: searchQuery) { _, newValue in
                if !newValue.isEmpty {
                    Task {
                        await repo.searchUsers(query: newValue)
                    }
                }
            }
            .toolbar { toolbarContent }
            .navigationDestination(item: $selectedPeerUser) { peer in
                ChatDetailView(peerUser: peer)
            }
            .fullScreenCover(isPresented: $showAuthSheet) {
                AuthView()
            }
            .confirmationDialog(
                "Удалить чат с \(peerToDelete?.displayTitle ?? "")?",
                isPresented: $showDeleteConfirm,
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
            .task {
                if authRepo.isAuthenticated {
                    await repo.syncCurrentUserProfile()
                    await repo.fetchConversations()
                }
            }
            .refreshable {
                if authRepo.isAuthenticated {
                    await repo.fetchConversations()
                }
            }
        }
    }

    // MARK: - Subviews (Peak Messenger Style)

    private var chatList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Если есть активный поиск и есть найденные пользователи, не входящие в текущие диалоги
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

                ForEach(filteredConversations) { chat in
                    Button {
                        selectedPeerUser = chat.peerUser
                    } label: {
                        PeakChatRow(chat: chat, onDelete: {
                            peerToDelete = chat.peerUser
                            showDeleteConfirm = true
                        })
                    }
                    .buttonStyle(PeakPressButtonStyle())

                    PeakDivider()
                        .padding(.leading, 86)
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48, weight: .thin))
                .foregroundColor(.secondary)
            Text("Пока нет чатов")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.secondary)
            Text("Введи имя или email друга в поиске выше, чтобы начать общение!")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
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
                Text("Чаты Sloosh")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.primary)

                Text("Войдите в аккаунт, чтобы общаться с друзьями и делиться любимыми фильмами!")
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
                Button {
                    searchQuery = ""
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

// MARK: - Peak Chat Row View (Peak Messenger Style)

private struct PeakChatRow: View {
    let chat: ChatConversation
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            // Avatar with Online dot
            PeakAvatarView(user: chat.peerUser, size: 56, showOnline: true)

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
            PeakAvatarView(user: user, size: 56, showOnline: true)

            VStack(alignment: .leading, spacing: 3) {
                Text(user.displayTitle)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)

                if !user.email.isEmpty {
                    Text(user.email)
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
        ZStack(alignment: .bottomTrailing) {
            if let avatarUrl = user.avatarUrl, URL(string: avatarUrl) != nil {
                AsyncCachedImage(urlString: avatarUrl) {
                    fallbackAvatar
                } content: { image in
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                }
            } else {
                fallbackAvatar
            }

            if showOnline && (user.isOnline == true) {
                Circle()
                    .fill(Color(UIColor.systemBackground))
                    .frame(width: size * 0.28 + 2, height: size * 0.28 + 2)
                    .overlay(
                        Circle()
                            .fill(Color.green)
                            .frame(width: size * 0.28, height: size * 0.28)
                    )
                    .offset(x: 1, y: 1)
            }
        }
    }

    private var fallbackAvatar: some View {
        Circle()
            .fill(Color.slooshAccent.opacity(0.35))
            .frame(width: size, height: size)
            .overlay(
                Text(String(user.displayTitle.prefix(1)).uppercased())
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundColor(.primary)
            )
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
