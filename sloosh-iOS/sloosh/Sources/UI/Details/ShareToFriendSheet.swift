import SwiftUI

struct ShareToFriendSheet: View {
    let movie: MediaDetailsDto
    @Environment(\.dismiss) private var dismiss

    @StateObject private var repo = MessengerRepository.shared
    @State private var searchQuery: String = ""
    @State private var sendingToUserId: String? = nil
    @State private var sentUserIds: Set<String> = []

    init(movie: MediaDetailsDto) {
        self.movie = movie
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Парящая стеклянная карточка делящегося фильма
                floatingMediaCard
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                // Список друзей / результатов поиска
                let displayList = searchQuery.isEmpty ? repo.conversations.map { $0.peerUser } : repo.searchResults

                if displayList.isEmpty {
                    emptyStateView
                } else {
                    List {
                        Section {
                            ForEach(displayList) { friend in
                                friendRow(friend)
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.visible)
                                    .listRowSeparatorTint(Color.white.opacity(0.08))
                            }
                        } header: {
                            Text(searchQuery.isEmpty ? "Друзья" : "Результаты поиска")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .textCase(nil)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Поделиться")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchQuery, prompt: "Поиск по нику или email")
            .onChange(of: searchQuery) { _, newValue in
                Task {
                    await repo.searchUsers(query: newValue)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Color.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .task {
                await repo.fetchConversations()
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Subviews

    private var floatingMediaCard: some View {
        HStack(spacing: 14) {
            if let posterUrl = movie.displayPosterUrl, !posterUrl.isEmpty {
                AsyncCachedImage(urlString: posterUrl) {
                    Rectangle().fill(Color.white.opacity(0.08))
                } content: { image in
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
                .frame(width: 48, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 3)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(movie.title ?? movie.originalTitle ?? "Фильм")
                    .font(.system(size: 16, weight: .bold))
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

                    if let genres = movie.genres, let firstGenre = genres.first?.name {
                        Text("•  \(firstGenre)")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()
        }
        .padding(12)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: searchQuery.isEmpty ? "person.2" : "magnifyingglass")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.tertiary)
            
            Text(searchQuery.isEmpty ? "У вас пока нет активных диалогов" : "Никого не найдено")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
            
            Text(searchQuery.isEmpty ? "Найдите друга через поиск вверху" : "Проверьте правильность ника или email")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func friendRow(_ friend: SlooshUser) -> some View {
        HStack(spacing: 14) {
            // Настоящая аватарка пользователя с фолбэком на инициалы
            UserAvatarView(user: friend, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(friend.displayTitle)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.primary)
                
                if !friend.email.isEmpty {
                    Text(friend.email)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button {
                sendToFriend(friend)
            } label: {
                if sendingToUserId == friend.id {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 32, height: 32)
                } else if sentUserIds.contains(friend.id) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                        Text("Отправлено")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.1)))
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text("Отправить")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.white))
                }
            }
            .buttonStyle(.plain)
            .disabled(sendingToUserId != nil || sentUserIds.contains(friend.id))
        }
        .padding(.vertical, 4)
    }

    private func sendToFriend(_ friend: SlooshUser) {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        sendingToUserId = friend.id

        let mediaPayload = MediaCardPayload(
            mediaId: movie.id ?? String(movie.ids?.kp ?? 0),
            type: movie.type ?? "movie",
            title: movie.title ?? movie.originalTitle ?? "Фильм",
            posterUrl: movie.displayPosterUrl,
            rating: movie.ratings?.kp,
            year: movie.year?.description
        )

        Task {
            let success = await repo.sendMessage(toPeerUser: friend, mediaPayload: mediaPayload)
            sendingToUserId = nil
            if success {
                withAnimation {
                    sentUserIds.insert(friend.id)
                }
                ToastManager.shared.show(
                    title: "Отправлено! 🚀",
                    subtitle: "Фильм отправлен \(friend.displayTitle)",
                    icon: "paperplane.fill"
                )
            } else {
                ToastManager.shared.show(
                    title: "Ошибка отправки",
                    subtitle: "Попробуйте ещё раз",
                    icon: "exclamationmark.triangle.fill"
                )
            }
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
