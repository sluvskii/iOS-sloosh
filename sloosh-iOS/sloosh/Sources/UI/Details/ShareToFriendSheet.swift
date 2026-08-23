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
                // 1. Поиск (Liquid Glass капсула)
                searchBar

                // 2. Горизонтальный список друзей
                friendsSection

                // 3. Нижняя карточка: Карточка фильма ИЛИ ввод сообщения с отправкой
                bottomCardSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
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
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .glassEffect(.regular.interactive(), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Закрыть")
                }

                // Кнопка Системный Шеринг
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showSystemShareSheet = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .glassEffect(.regular.interactive(), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Поделиться ссылкой")
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
        .presentationDetents([.height(310)])
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selectedUsers)
        .preferredColorScheme(.dark)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
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
        .padding(.horizontal, 12)
        .frame(height: 36)
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
                            .font(.system(size: 20))
                            .foregroundStyle(.tertiary)
                        Text(searchQuery.isEmpty ? "Нет диалогов" : "Не найдено")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 76)
                    .padding(.horizontal, 20)
                } else {
                    ForEach(displayList) { friend in
                        let isSelected = selectedUsers.contains(where: { $0.id == friend.id })

                        Button {
                            toggleUserSelection(friend)
                        } label: {
                            VStack(spacing: 4) {
                                ZStack(alignment: .bottomTrailing) {
                                    UserAvatarView(user: friend, size: 50)
                                        .scaleEffect(isSelected ? 1.05 : 1.0)

                                    if isSelected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundStyle(.black, Color.slooshAccent)
                                            .background(Circle().fill(Color.white))
                                            .offset(x: 2, y: 2)
                                    }
                                }

                                Text(friend.displayTitle)
                                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                                    .foregroundStyle(isSelected ? .primary : .secondary)
                                    .lineLimit(1)
                                    .frame(width: 60)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 78)
        .padding(.horizontal, -16)
    }

    // MARK: - Bottom Section

    private var bottomCardSection: some View {
        Group {
            if selectedUsers.isEmpty {
                // Карточка фильма
                HStack(spacing: 12) {
                    if let posterUrl = movie.displayPosterUrl, !posterUrl.isEmpty {
                        AsyncCachedImage(urlString: posterUrl) {
                            Rectangle().fill(Color.white.opacity(0.08))
                        } content: { image in
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        }
                        .frame(width: 36, height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(movie.title ?? movie.originalTitle ?? "Фильм")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        HStack(spacing: 6) {
                            if let rating = movie.ratings?.kp, rating > 0 {
                                Text(String(format: "%.1f", rating))
                                    .font(.system(size: 10, weight: .heavy))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(Color.rating(rating))
                                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            }

                            if let year = movie.year {
                                Text(year.description)
                                    .font(.system(size: 12))
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
                .padding(10)
                .frame(height: 56)
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                // Поле ввода сообщения + Кнопка отправки
                HStack(spacing: 10) {
                    if let posterUrl = movie.displayPosterUrl, !posterUrl.isEmpty {
                        AsyncCachedImage(urlString: posterUrl) {
                            Rectangle().fill(Color.white.opacity(0.08))
                        } content: { image in
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        }
                        .frame(width: 32, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }

                    HStack(spacing: 6) {
                        TextField("Сообщение...", text: $customMessage)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.primary)

                        if !customMessage.isEmpty {
                            Button {
                                customMessage = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .glassEffect(.regular.interactive(), in: Capsule())

                    Button {
                        sendToSelectedFriends()
                    } label: {
                        ZStack {
                            if isSending {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.black)
                            } else {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(.black)
                            }
                        }
                        .frame(width: 44, height: 44)
                        .background(Color.slooshAccent)
                        .clipShape(Circle())
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .disabled(isSending)
                }
                .frame(height: 56)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
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
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
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
