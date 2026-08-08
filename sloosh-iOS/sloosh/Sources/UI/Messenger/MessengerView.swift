import SwiftUI

public struct MessengerView: View {
    @StateObject private var repo = MessengerRepository.shared
    @ObservedObject private var authRepo = AuthRepository.shared

    @State private var searchQuery: String = ""
    @State private var selectedPeerUser: SlooshUser? = nil
    @State private var showAuthSheet: Bool = false

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Шапка
                ZStack {
                    Text("Сообщения")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.primary)

                    HStack {
                        Spacer()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

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
                Text("Общайтесь с друзьями в Sloosh")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)

                Text("Войдите в аккаунт через Google или Email, чтобы находить друзей, переписываться и делиться любимыми фильмами!")
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

    private var authenticatedContentView: some View {
        VStack(spacing: 12) {
            // Поле поиска друзей
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Поиск по email или никнейму...", text: $searchQuery)
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
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Capsule().glassEffect(.regular.interactive(), in: Capsule()))
            .padding(.horizontal, 16)

            // Контент: Результаты поиска или Список диалогов
            if !searchQuery.isEmpty {
                searchResultsList
            } else {
                conversationsList
            }
        }
    }

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
                    LazyVStack(spacing: 10) {
                        ForEach(repo.searchResults) { user in
                            Button {
                                selectedPeerUser = user
                            } label: {
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(Color.slooshAccent.opacity(0.3))
                                        .frame(width: 44, height: 44)
                                        .overlay(
                                            Text(String(user.displayTitle.prefix(1)).uppercased())
                                                .font(.system(size: 18, weight: .bold))
                                                .foregroundColor(.primary)
                                        )

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(user.displayTitle)
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundColor(.primary)

                                        if !user.email.isEmpty {
                                            Text(user.email)
                                                .font(.system(size: 13))
                                                .foregroundColor(.secondary)
                                        }
                                    }

                                    Spacer()

                                    Image(systemName: "bubble.right.fill")
                                        .font(.system(size: 16))
                                        .foregroundColor(Color.slooshAccent)
                                }
                                .padding(12)
                                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    private var conversationsList: some View {
        Group {
            if repo.conversations.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "bubble.left.and.text.bubble.right")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("У вас пока нет сообщений")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.primary)
                    Text("Найдите друга по имейлу или нику в строке поиска выше, чтобы начать диалог!")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(repo.conversations) { chat in
                            Button {
                                selectedPeerUser = chat.peerUser
                            } label: {
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(Color.slooshAccent.opacity(0.3))
                                        .frame(width: 48, height: 48)
                                        .overlay(
                                            Text(String(chat.peerUser.displayTitle.prefix(1)).uppercased())
                                                .font(.system(size: 20, weight: .bold))
                                                .foregroundColor(.primary)
                                        )

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

                                        Text(chat.lastMessageText)
                                            .font(.system(size: 14))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .padding(12)
                                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
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
