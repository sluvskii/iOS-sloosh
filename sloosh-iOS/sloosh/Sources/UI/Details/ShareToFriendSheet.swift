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
    @FocusState private var isInputFocused: Bool

    init(movie: MediaDetailsDto) {
        self.movie = movie
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                // Ряд 1: Горизонтальная лента друзей
                friendsHorizontalSection

                Divider()
                    .padding(.horizontal, 16)
                    .opacity(0.12)

                // Ряд 2: Динамический блок (когда никто не выбран -> Скопировать ссылку, когда выбран -> Поле ввода и Кнопка Отправить)
                if selectedUsers.isEmpty {
                    unselectedStateBottomView
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    selectedStateSendMessageView
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 12)
            .navigationTitle("Отправить")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchQuery, placement: .navigationBarDrawer(displayMode: .always), prompt: "Поиск")
            .onChange(of: searchQuery) { _, newValue in
                Task {
                    await repo.searchUsers(query: newValue)
                }
            }
            .toolbar {
                // Слева: Кнопка Закрыть
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

                // Справа: Иконки Быстрый Копировать + Системный Шеринг
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 14) {
                        Button {
                            copyMovieLink()
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.white)
                        }

                        Button {
                            showSystemShareSheet = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                    .tint(.white)
                }
            }
            .task {
                await repo.fetchConversations()
            }
            .sheet(isPresented: $showSystemShareSheet) {
                if let shareUrl = movieShareUrl {
                    ShareSheet(items: [shareUrl, movie.title ?? "Фильм"])
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selectedUsers)
        .preferredColorScheme(.dark)
    }

    // MARK: - Subviews

    private var friendsHorizontalSection: some View {
        let displayList = searchQuery.isEmpty ? repo.conversations.map { $0.peerUser } : repo.searchResults

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                if displayList.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "person.2")
                            .font(.title2)
                            .foregroundStyle(.tertiary)
                        Text(searchQuery.isEmpty ? "Нет диалогов" : "Не найдено")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 100, height: 80)
                } else {
                    ForEach(displayList) { friend in
                        let isSelected = selectedUsers.contains(where: { $0.id == friend.id })

                        Button {
                            toggleUserSelection(friend)
                        } label: {
                            VStack(spacing: 6) {
                                ZStack(alignment: .bottomTrailing) {
                                    UserAvatarView(user: friend, size: 56)
                                        .scaleEffect(isSelected ? 1.06 : 1.0)

                                    if isSelected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 18, weight: .bold))
                                            .foregroundStyle(.black, Color.slooshAccent)
                                            .background(Circle().fill(Color.white))
                                            .offset(x: 2, y: 2)
                                    }
                                }

                                Text(friend.displayTitle)
                                    .font(.caption)
                                    .fontWeight(isSelected ? .bold : .medium)
                                    .foregroundStyle(isSelected ? .primary : .secondary)
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
        .frame(height: 84)
    }

    // Состояние когда НИКТО не выбран
    private var unselectedStateBottomView: some View {
        VStack(spacing: 12) {
            Text("Выберите друга из списка выше, чтобы отправить фильм в чат")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button {
                copyMovieLink()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.on.doc.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Скопировать ссылку на фильм")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    Capsule()
                        .fill(Color(uiColor: .tertiarySystemFill))
                )
            }
            .buttonStyle(ScaleButtonStyle())
            .padding(.horizontal, 16)
        }
        .padding(.top, 4)
    }

    // Состояние когда ВЫБРАН хотя бы один друг
    private var selectedStateSendMessageView: some View {
        VStack(spacing: 12) {
            // Капсульное парящее поле ввода с мини-превью фильма
            HStack(spacing: 10) {
                // Мини-значок фильма
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 24, height: 24)

                    Image(systemName: "film")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.slooshAccent)
                }

                TextField("Добавить сообщение к фильму...", text: $customMessage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                    .focused($isInputFocused)

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
            .frame(height: 48)
            .glassEffect(.regular.interactive(), in: Capsule())
            .padding(.horizontal, 16)

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
                            .font(.system(size: 16, weight: .bold))
                        Text(selectedUsers.count > 1 ? "Отправить друзьям (\(selectedUsers.count))" : "Отправить в Sloosh")
                            .font(.system(size: 16, weight: .bold))
                    }
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.slooshAccent)
                .clipShape(Capsule())
            }
            .buttonStyle(ScaleButtonStyle())
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
