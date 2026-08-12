import SwiftUI

struct ShareToFriendSheet: View {
    let movie: MediaDetailsDto
    @Environment(\.dismiss) private var dismiss

    @StateObject private var repo = MessengerRepository.shared
    @State private var searchQuery: String = ""
    @State private var isSearchActive: Bool = false
    @State private var selectedUsers: [SlooshUser] = []
    @State private var customMessage: String = ""
    @State private var isSending: Bool = false
    @State private var showSystemShareSheet: Bool = false

    init(movie: MediaDetailsDto) {
        self.movie = movie
    }

    var body: some View {
        VStack(spacing: 16) {
            // Шапка шторки: Поиск | Заголовок | Закрыть
            headerView

            // Разворачиваемое поле поиска
            if isSearchActive {
                searchBarView
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Ряд 1: Горизонтальная лента друзей
            friendsHorizontalSection

            Divider()
                .opacity(0.15)
                .padding(.horizontal, 16)

            // Нижний блок: Ввод сообщения + кнопка "Отправить" при выборе друга, ИЛИ Быстрые системные действия
            if !selectedUsers.isEmpty {
                sendMessageSection
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                quickActionsSection
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.vertical, 14)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedUsers)
        .animation(.easeInOut(duration: 0.2), value: isSearchActive)
        .task {
            await repo.fetchConversations()
        }
        .sheet(isPresented: $showSystemShareSheet) {
            if let shareUrl = movieShareUrl {
                ShareSheet(items: [shareUrl, movie.title ?? "Фильм"])
            }
        }

        .preferredColorScheme(.dark)
    }

    // MARK: - Subviews

    private var headerView: some View {
        HStack {
            // Кнопка поиска
            Button {
                withAnimation {
                    isSearchActive.toggle()
                }
            } label: {
                Image(systemName: isSearchActive ? "magnifyingglass.circle.fill" : "magnifyingglass")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isSearchActive ? Color.slooshAccent : .white)
                    .frame(width: 32, height: 32)
            }

            Spacer()

            Text("Отправить")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)

            Spacer()

            // Крестик закрытия
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 32, height: 32)
            }
        }
        .padding(.horizontal, 16)
    }

    private var searchBarView: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Поиск по нику или email...", text: $searchQuery)
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
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.white.opacity(0.1)))
        .padding(.horizontal, 16)
    }

    private var friendsHorizontalSection: some View {
        let displayList = searchQuery.isEmpty ? repo.conversations.map { $0.peerUser } : repo.searchResults

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                if displayList.isEmpty {
                    VStack(spacing: 4) {
                        Image(systemName: "person.2")
                            .font(.system(size: 24))
                            .foregroundStyle(.tertiary)
                        Text(searchQuery.isEmpty ? "Нет диалогов" : "Не найдено")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 100, height: 75)
                } else {
                    ForEach(displayList) { friend in
                        let isSelected = selectedUsers.contains(where: { $0.id == friend.id })
                        
                        Button {
                            toggleUserSelection(friend)
                        } label: {
                            VStack(spacing: 6) {
                                ZStack(alignment: .bottomTrailing) {
                                    UserAvatarView(user: friend, size: 56)
                                        .scaleEffect(isSelected ? 1.05 : 1.0)
                                    
                                    if isSelected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 18, weight: .bold))
                                            .foregroundStyle(.white, Color.blue)
                                            .background(Circle().fill(Color.white))
                                            .offset(x: 2, y: 2)
                                    }
                                }

                                Text(friend.displayTitle)
                                    .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                                    .foregroundStyle(isSelected ? .white : .secondary)
                                    .lineLimit(1)
                                    .frame(width: 68)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 82)
    }

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Поделиться в других приложениях")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    // Скопировать ссылку
                    quickActionButton(
                        title: "Скопировать",
                        icon: "doc.on.doc.fill",
                        color: Color.blue
                    ) {
                        copyMovieLink()
                    }

                    // Системный шеринг
                    quickActionButton(
                        title: "Еще...",
                        icon: "square.and.arrow.up.fill",
                        color: Color.purple
                    ) {
                        showSystemShareSheet = true
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func quickActionButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.2))
                        .frame(width: 52, height: 52)

                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(color)
                }

                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    private var sendMessageSection: some View {
        VStack(spacing: 12) {
            // Поле ввода сообщения
            HStack(spacing: 8) {
                TextField("Напишите сообщение...", text: $customMessage)
                    .font(.system(size: 15))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.white.opacity(0.1)))

                if !customMessage.isEmpty {
                    Button {
                        customMessage = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)

            // Кнопка Отправить
            Button {
                sendToSelectedFriends()
            } label: {
                HStack(spacing: 8) {
                    if isSending {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 15, weight: .bold))
                        Text(selectedUsers.count > 1 ? "Отправить (\(selectedUsers.count))" : "Отправить")
                            .font(.system(size: 16, weight: .bold))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(Capsule().fill(Color.blue))
            }
            .buttonStyle(.plain)
            .disabled(isSending)
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Actions

    private func toggleUserSelection(_ friend: SlooshUser) {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

        if let index = selectedUsers.firstIndex(where: { $0.id == friend.id }) {
            selectedUsers.remove(at: index)
        } else {
            selectedUsers.append(friend)
        }
    }

    private var movieShareUrl: URL? {
        let idStr = movie.id ?? String(movie.ids?.kp ?? 0)
        return URL(string: "https://sloosh.app/movie/\(idStr)")
    }

    private func copyMovieLink() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        if let url = movieShareUrl {
            UIPasteboard.general.string = url.absoluteString
            ToastManager.shared.show(
                title: "Ссылка скопирована! 🔗",
                subtitle: movie.title ?? "Фильм",
                icon: "doc.on.doc.fill"
            )
            dismiss()
        }
    }

    private func sendToSelectedFriends() {
        guard !selectedUsers.isEmpty else { return }

        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        isSending = true

        let mediaPayload = MediaCardPayload(
            mediaId: movie.id ?? String(movie.ids?.kp ?? 0),
            type: movie.type ?? "movie",
            title: movie.title ?? movie.originalTitle ?? "Фильм",
            posterUrl: movie.displayPosterUrl,
            rating: movie.ratings?.kp,
            year: movie.year?.description
        )

        let textComment = customMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let targets = selectedUsers

        Task {
            for friend in targets {
                // 1. Отправляем карточку фильма
                _ = await repo.sendMessage(toPeerUser: friend, mediaPayload: mediaPayload)
                
                // 2. Если пользователь ввел сообщение, отправляем его вдогонку
                if !textComment.isEmpty {
                    _ = await repo.sendMessage(toPeerUser: friend, text: textComment)
                }
            }

            isSending = false
            ToastManager.shared.show(
                title: "Отправлено! 🚀",
                subtitle: targets.count == 1 ? "Фильм отправлен \(targets.first?.displayTitle ?? "")" : "Фильм отправлен друзьям (\(targets.count))",
                icon: "paperplane.fill"
            )
            dismiss()
        }
    }
}

// MARK: - User Avatar Component

private struct UserAvatarView: View {
    let user: SlooshUser
    let size: CGFloat

    var body: some View {
        if let avatarUrl = user.avatarUrl, let url = URL(string: avatarUrl), !avatarUrl.isEmpty {
            AsyncCachedImage(url: url) {
                fallbackAvatar
            } content: { image in
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } fallback: {
                fallbackAvatar
            }
        } else {
            fallbackAvatar
        }
    }

    private var fallbackAvatar: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.blue.opacity(0.6), Color.purple.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)

            Text(String(user.displayTitle.prefix(1)).uppercased())
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}
