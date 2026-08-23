import SwiftUI

struct ShareToFriendSheet: View {
    let movie: MediaDetailsDto
    @Environment(\.dismiss) private var dismiss

    @StateObject private var repo = MessengerRepository.shared
    @State private var searchQuery: String = ""
    @State private var selectedUsers: [SlooshUser] = []
    @State private var customMessage: String = ""
    @State private var isSending: Bool = false
    @State private var showSystemShareSheet: Bool = false

    init(movie: MediaDetailsDto) {
        self.movie = movie
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // 1. Поиск (парящая Liquid Glass капсула)
                searchBar

                // 2. Горизонтальная лента друзей
                friendsSection

                // 3. Нижняя секция: Карточка фильма ИЛИ ввод сообщения и кнопка "Отправить"
                if !selectedUsers.isEmpty {
                    sendMessageSection
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else {
                    moviePreviewCard
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 16)
            .navigationTitle("Отправить")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Кнопка Закрыть
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .tint(.white)
                }

                // Кнопка Системный Шеринг
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showSystemShareSheet = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .tint(.white)
                }
            }
            .task {
                await repo.fetchConversations()
            }
            .sheet(isPresented: $showSystemShareSheet) {
                if let shareUrl = movieShareUrl {
                    ShareSheet(items: [shareUrl, movie.title ?? movie.originalTitle ?? "Фильм"])
                }
            }
        }
        .presentationBackground { Color.clear.glassEffect(in: .rect) }
        .presentationDragIndicator(.visible)
        .presentationDetents([.height(340)])
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selectedUsers.isEmpty)
        .preferredColorScheme(.dark)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("Поиск", text: $searchQuery)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: searchQuery) { _, newValue in
                    Task {
                        await repo.searchUsers(query: newValue)
                    }
                }

            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                    Task {
                        await repo.searchUsers(query: "")
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .glassEffect(.regular.interactive(), in: Capsule())
    }

    // MARK: - Friends Section

    private var friendsSection: some View {
        let displayList = searchQuery.isEmpty ? repo.conversations.map { $0.peerUser } : repo.searchResults

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                if displayList.isEmpty {
                    VStack(spacing: 4) {
                        Image(systemName: "person.2")
                            .font(.system(size: 22))
                            .foregroundStyle(.tertiary)
                        Text(searchQuery.isEmpty ? "Нет диалогов" : "Не найдено")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 80)
                    .padding(.horizontal, 20)
                } else {
                    ForEach(displayList) { friend in
                        let isSelected = selectedUsers.contains(where: { $0.id == friend.id })

                        Button {
                            toggleUserSelection(friend)
                        } label: {
                            VStack(spacing: 5) {
                                ZStack(alignment: .bottomTrailing) {
                                    UserAvatarView(user: friend, size: 52)

                                    if isSelected {
                                        ZStack {
                                            Circle()
                                                .fill(Color.slooshAccent.opacity(0.85))
                                                .frame(width: 20, height: 20)
                                                .glassEffect(.regular.interactive(), in: Circle())

                                            Image(systemName: "checkmark")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundStyle(.black)
                                        }
                                        .offset(x: 2, y: 2)
                                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                                    }
                                }

                                Text(friend.displayTitle)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .frame(width: 64)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 80)
        .padding(.horizontal, -16)
    }

    // MARK: - Movie Preview Card

    private var moviePreviewCard: some View {
        HStack(spacing: 12) {
            if let posterUrl = movie.displayPosterUrl, !posterUrl.isEmpty {
                AsyncCachedImage(urlString: posterUrl) {
                    Rectangle().fill(Color.white.opacity(0.08))
                } content: { image in
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
                .frame(width: 44, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 2)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(movie.title ?? movie.originalTitle ?? "Фильм")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let rating = movie.ratings?.kp, rating > 0 {
                        Text(String(format: "%.1f", rating))
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.rating(rating))
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }

                    if let year = movie.year {
                        Text(year.description)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    if let genres = movie.genres, let firstGenre = genres.first, !firstGenre.isEmpty {
                        Text("•  \(firstGenre)")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Send Message Section

    private var sendMessageSection: some View {
        VStack(spacing: 10) {
            // Поле ввода сообщения
            HStack(spacing: 8) {
                TextField("Напишите сообщение...", text: $customMessage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)

                if !customMessage.isEmpty {
                    Button {
                        customMessage = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .glassEffect(.regular.interactive(), in: Capsule())

            // Главная акцентная кнопка "Отправить"
            Button {
                sendToSelectedFriends()
            } label: {
                HStack(spacing: 8) {
                    if isSending {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.black)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 15, weight: .bold))
                        Text(selectedUsers.count > 1 ? "Отправить (\(selectedUsers.count))" : "Отправить")
                            .font(.system(size: 15, weight: .bold))
                    }
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color.slooshAccent, in: Capsule())
            }
            .buttonStyle(ScaleButtonStyle())
            .disabled(isSending || selectedUsers.isEmpty)
        }
    }

    // MARK: - Actions

    private func toggleUserSelection(_ friend: SlooshUser) {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

        withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
            if let index = selectedUsers.firstIndex(where: { $0.id == friend.id }) {
                selectedUsers.remove(at: index)
            } else {
                selectedUsers.append(friend)
            }
        }
    }

    private var movieShareUrl: URL? {
        let idStr = movie.id ?? String(movie.ids?.kp ?? 0)
        return URL(string: "https://sloosh.app/movie/\(idStr)")
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
                _ = await repo.sendMessage(toPeerUser: friend, mediaPayload: mediaPayload)
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

// MARK: - Scale Button Style

private struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
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
