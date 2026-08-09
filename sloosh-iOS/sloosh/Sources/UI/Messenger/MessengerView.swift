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

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
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

    // MARK: - Guest View

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

                Text("Войдите в аккаунт, чтобы переписываться с друзьями и делиться фильмами!")
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

    // MARK: - Authenticated Content View

    private var authenticatedContentView: some View {
        ScrollView {
            VStack(spacing: 14) {
                // Плавающий заголовок экранов iOS 26+
                HStack {
                    Text("Чаты")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.primary)

                    Spacer()
                }
                .padding(.horizontal, 4)
                .padding(.top, 12)

                // Поиск по людям в стиле Liquid Glass Pill
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.secondary)

                    TextField("Поиск по имени или имейлу...", text: $searchQuery)
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
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .glassEffect(.regular.interactive(), in: Capsule())

                // Результаты поиска или Список диалогов
                if !searchQuery.isEmpty {
                    searchResultsSection
                } else {
                    conversationsSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Search Results Section

    private var searchResultsSection: some View {
        Group {
            if repo.isLoading {
                ProgressView()
                    .padding(.top, 40)
            } else if repo.searchResults.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.slash")
                        .font(.system(size: 38))
                        .foregroundColor(.secondary)
                    Text("Пользователи не найдены")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 40)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(repo.searchResults) { user in
                        Button {
                            selectedPeerUser = user
                        } label: {
                            LiquidGlassUserRow(user: user)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Conversations Section

    private var conversationsSection: some View {
        Group {
            if repo.conversations.isEmpty {
                VStack(spacing: 14) {
                    Spacer()
                        .frame(height: 40)
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("У вас пока нет чатов")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.primary)
                    Text("Введи имя или email друга в поиске выше, чтобы начать диалог!")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(repo.conversations) { chat in
                        Button {
                            selectedPeerUser = chat.peerUser
                        } label: {
                            LiquidGlassChatRow(chat: chat)
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

// MARK: - Liquid Glass User Row

private struct LiquidGlassUserRow: View {
    let user: SlooshUser

    var body: some View {
        HStack(spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(Color.slooshAccent.opacity(0.35))
                    .frame(width: 48, height: 48)
                    .overlay(
                        Text(String(user.displayTitle.prefix(1)).uppercased())
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.primary)
                    )

                if user.isOnline == true {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 12, height: 12)
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
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.secondary.opacity(0.6))
        }
        .padding(12)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - Liquid Glass Chat Row

private struct LiquidGlassChatRow: View {
    let chat: ChatConversation

    var body: some View {
        HStack(spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(Color.slooshAccent.opacity(0.35))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Text(String(chat.peerUser.displayTitle.prefix(1)).uppercased())
                            .font(.system(size: 19, weight: .bold))
                            .foregroundColor(.primary)
                    )

                if chat.peerUser.isOnline == true {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 13, height: 13)
                        .overlay(
                            Circle().stroke(Color(UIColor.systemBackground), lineWidth: 2)
                        )
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(chat.peerUser.displayTitle)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Spacer()

                    Text(formatTime(ms: chat.updatedAtMs))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text(chat.lastMessageText)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    Spacer()

                    if chat.unreadCount > 0 {
                        Text("\(chat.unreadCount)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.slooshAccent))
                    }
                }
            }
        }
        .padding(12)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 20))
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
