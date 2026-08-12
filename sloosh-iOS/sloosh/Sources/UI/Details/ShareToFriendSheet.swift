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
            VStack(spacing: 14) {
                // Ряд 1: Лента друзей
                friendsHorizontalSection

                Divider()
                    .padding(.horizontal, 16)
                    .opacity(0.12)

                // Ряд 2: Ввод сообщения при выборе друга ИЛИ Красивая плашка фильма
                if !selectedUsers.isEmpty {
                    sendMessageSection
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    moviePreviewCard
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

                // Справа: Кнопка Системный Шеринг (без текста, белая)
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
                                        .scaleEffect(isSelected ? 1.05 : 1.0)

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
                .frame(width: 46, height: 66)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: 5, x: 0, y: 2)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(movie.title ?? movie.originalTitle ?? "Фильм")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let rating = movie.ratings?.kp, rating > 0 {
                        Text(String(format: "%.1f", rating))
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
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

                Text("Выберите друга для отправки")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }

            Spacer()
        }
        .padding(12)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 16)
    }

    private var sendMessageSection: some View {
        VStack(spacing: 12) {
            // Капсульное парящее поле ввода сообщения (как на экране авторизации)
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
                }
            }
            .padding(.horizontal, 18)
            .frame(height: 48)
            .glassEffect(.regular.interactive(), in: Capsule())
            .padding(.horizontal, 16)

            // Главная акцентная капсульная кнопка "Отправить" в стиле Sloosh (высота 50pt, slooshAccent)
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
                        Text(selectedUsers.count > 1 ? "Отправить (\(selectedUsers.count))" : "Отправить")
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
            .disabled(isSending || selectedUsers.isEmpty)
            .opacity(selectedUsers.isEmpty ? 0.5 : 1.0)
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
