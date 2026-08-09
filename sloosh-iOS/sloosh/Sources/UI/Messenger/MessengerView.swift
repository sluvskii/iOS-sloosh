import SwiftUI

public struct MessengerView: View {
    @StateObject private var repo = MessengerRepository.shared
    @ObservedObject private var authRepo = AuthRepository.shared

    @State private var searchQuery: String = ""
    @State private var selectedPeerUser: SlooshUser? = nil
    @State private var showAuthSheet: Bool = false
    @State private var isSearchFocused: Bool = false
    @State private var peerToDelete: SlooshUser? = nil
    @State private var showDeleteConfirm: Bool = false

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Telegram-style Header Bar
                headerBar

                if !authRepo.isAuthenticated {
                    guestView
                } else {
                    authenticatedContentView
                }
            }
            .toolbar(.hidden, for: .navigationBar)
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

    // MARK: - Header Bar (Telegram iOS Style)

    private var headerBar: some View {
        HStack(alignment: .center) {
            Text("Чаты")
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(.primary)

            Spacer()

            if authRepo.isAuthenticated {
                TelegramGlassIconButton(
                    systemName: "square.and.pencil",
                    iconSize: 18,
                    buttonSize: 38
                ) {
                    // Переключаем фокус на поиск для создания диалога
                    searchQuery = ""
                    isSearchFocused = true
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    // MARK: - Guest View

    private var guestView: some View {
        VStack(spacing: 20) {
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
                Text("Чаты в Sloosh")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)

                Text("Войдите в аккаунт через Google или Email, чтобы общаться с друзьями и делиться любимыми фильмами!")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
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

    // MARK: - Authenticated View

    private var authenticatedContentView: some View {
        VStack(spacing: 10) {
            // Поле поиска друзей в стиле Telegram Pill
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.secondary)

                TextField("Поиск по людям и почте...", text: $searchQuery)
                    .font(.system(size: 15))
                    .onChange(of: searchQuery) { _, newValue in
                        Task {
                            await repo.searchUsers(query: newValue)
                        }
                    }

                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Capsule().glassEffect(.regular.interactive(), in: Capsule()))
            .padding(.horizontal, 16)

            // Результаты поиска или Список диалогов
            if !searchQuery.isEmpty {
                searchResultsList
            } else {
                conversationsList
            }
        }
    }

    // MARK: - Search Results List

    private var searchResultsList: some View {
        Group {
            if repo.isLoading {
                ProgressView()
                    .frame(maxHeight: .infinity)
            } else if repo.searchResults.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.slash")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("Пользователи не найдены")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(repo.searchResults) { user in
                            Button {
                                selectedPeerUser = user
                            } label: {
                                TelegramUserRow(user: user)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                }
            }
        }
    }

    // MARK: - Conversations List (Telegram iOS Style)

    private var conversationsList: some View {
        Group {
            if repo.conversations.isEmpty {
                VStack(spacing: 14) {
                    Spacer()
                    Image(systemName: "bubble.left.and.text.bubble.right.fill")
                        .font(.system(size: 54))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.slooshAccent, .secondary],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Text("У вас пока нет чатов")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.primary)
                    Text("Найдите друга по имени или почте в строке поиска выше и отправьте фильм или сообщение!")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 36)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(repo.conversations) { chat in
                            Button {
                                selectedPeerUser = chat.peerUser
                            } label: {
                                TelegramChatRow(chat: chat)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    peerToDelete = chat.peerUser
                                    showDeleteConfirm = true
                                } label: {
                                    Label("Удалить", systemImage: "trash.fill")
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                }
            }
        }
    }

    private func deleteChat(peer: SlooshUser) {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        // Сбрасываем чат из локального списка
        Task {
            await repo.fetchConversations()
        }
    }
}

// MARK: - Telegram User Search Row

private struct TelegramUserRow: View {
    let user: SlooshUser

    var body: some View {
        HStack(spacing: 14) {
            // Аватар
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.slooshAccent.opacity(0.8), Color.slooshAccent.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)
                    .overlay(
                        Text(String(user.displayTitle.prefix(1)).uppercased())
                            .font(.system(size: 19, weight: .bold))
                            .foregroundColor(.black)
                    )

                if user.isOnline == true {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 13, height: 13)
                        .overlay(
                            Circle().stroke(Color(UIColor.systemBackground), lineWidth: 2)
                        )
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(user.displayTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)

                if !user.email.isEmpty {
                    Text(user.email)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary.opacity(0.6))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Telegram Chat Row View

private struct TelegramChatRow: View {
    let chat: ChatConversation

    var body: some View {
        HStack(spacing: 14) {
            // Аватар с индикатором онлайн
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.slooshAccent, Color.slooshAccent.opacity(0.4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 52, height: 52)
                    .overlay(
                        Text(String(chat.peerUser.displayTitle.prefix(1)).uppercased())
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.black)
                    )

                if chat.peerUser.isOnline == true {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 14, height: 14)
                        .overlay(
                            Circle().stroke(Color(UIColor.systemBackground), lineWidth: 2)
                        )
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(chat.peerUser.displayTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Spacer()

                    Text(formatTime(ms: chat.updatedAtMs))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 4) {
                    Text(chat.lastMessageText)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    Spacer()

                    if chat.unreadCount > 0 {
                        Text("\(chat.unreadCount)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.slooshAccent))
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 18))
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
