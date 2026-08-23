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
    @FocusState private var isSearchFocused: Bool
    @FocusState private var isMessageFocused: Bool

    init(movie: MediaDetailsDto) {
        self.movie = movie
    }

    var body: some View {
        VStack(spacing: 0) {
            // 1. Верхняя панель (Закрыть | Заголовок | Системный шеринг)
            headerView
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

            // 2. Летающий поисковик с Liquid Glass
            floatingSearchBar
                .padding(.horizontal, 16)
                .padding(.bottom, 14)

            // 3. Горизонтальная лента друзей
            friendsHorizontalSection
                .padding(.bottom, 14)

            // 4. Тонкий акцентный разделитель
            Divider()
                .padding(.horizontal, 16)
                .opacity(0.12)
                .padding(.bottom, 14)

            // 5. Динамическая нижняя секция (Превью фильма ИЛИ Ввод сообщения + Отправить)
            bottomDynamicSection
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .task {
            await repo.fetchConversations()
        }
        .sheet(isPresented: $showSystemShareSheet) {
            if let shareUrl = movieShareUrl {
                ShareSheet(items: [shareUrl, movie.title ?? movie.originalTitle ?? "Фильм"])
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selectedUsers)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: searchQuery)
        .preferredColorScheme(.dark)
    }

    // MARK: - Subviews

    private var headerView: some View {
        HStack(alignment: .center) {
            // Кнопка Закрыть
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .glassEffect(.regular.interactive(), in: Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Отправить")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.primary)

            Spacer()

            // Кнопка Системного шеринга
            Button {
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                showSystemShareSheet = true
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .glassEffect(.regular.interactive(), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Поделиться через другие приложения")
        }
    }

    private var floatingSearchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("Поиск друзей...", text: $searchQuery)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
                .focused($isSearchFocused)
                .submitLabel(.search)
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
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .glassEffect(.regular.interactive(), in: Capsule())
    }

    private var friendsHorizontalSection: some View {
        let displayList = searchQuery.isEmpty ? repo.conversations.map { $0.peerUser } : repo.searchResults

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                if displayList.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: searchQuery.isEmpty ? "person.2.fill" : "magnifyingglass")
                            .font(.system(size: 22))
                            .foregroundStyle(.tertiary)
                        Text(searchQuery.isEmpty ? "Нет диалогов" : "Не найдено")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 84)
                    .padding(.horizontal, 32)
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
                                            .foregroundStyle(.black, Color.slooshAccent)
                                            .background(Circle().fill(Color.white))
                                            .offset(x: 2, y: 2)
                                            .transition(.scale.combined(with: .opacity))
                                    }
                                }

                                Text(friend.displayTitle)
                                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                                    .foregroundStyle(isSelected ? .primary : .secondary)
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
        .frame(height: 86)
    }

    @ViewBuilder
    private var bottomDynamicSection: some View {
        if !selectedUsers.isEmpty {
            VStack(spacing: 10) {
                // Поле ввода комментария
                HStack(spacing: 8) {
                    TextField("Добавить сообщение...", text: $customMessage)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                        .focused($isMessageFocused)

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
                .frame(height: 46)
                .glassEffect(.regular.interactive(), in: Capsule())

                // Кнопка "Отправить"
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
                                .font(.system(size: 16, weight: .bold))
                        }
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.slooshAccent)
                    .clipShape(Capsule())
                }
                .buttonStyle(ScaleButtonStyle())
                .disabled(isSending)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            moviePreviewCard
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var moviePreviewCard: some View {
        HStack(spacing: 14) {
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
                .shadow(color: .black.opacity(0.35), radius: 5, x: 0, y: 2)
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
                            .padding(.vertical, 2.5)
                            .background(Color.rating(rating))
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }

                    if let year = movie.year {
                        Text(year.description)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    if let genres = movie.genres, let firstGenre = genres.first, !firstGenre.isEmpty {
                        Text("•  \(firstGenre)")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            Text("Выберите друга")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
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
