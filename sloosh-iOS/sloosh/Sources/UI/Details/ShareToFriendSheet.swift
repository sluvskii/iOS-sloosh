import SwiftUI

struct ShareToFriendSheet: View {
    let movie: MediaDetailsDto?
    let clip: MovieClip?
    @Environment(\.dismiss) private var dismiss

    @StateObject private var repo = MessengerRepository.shared
    @State private var searchQuery: String = ""
    @State private var selectedUsers: [SlooshUser] = []
    @State private var customMessage: String = ""
    @State private var isSending: Bool = false
    @State private var showSystemShareSheet: Bool = false

    init(movie: MediaDetailsDto) {
        self.movie = movie
        self.clip = nil
    }

    init(clip: MovieClip) {
        self.movie = nil
        self.clip = clip
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // 1. Поиск (парящая Liquid Glass капсула)
                searchBar

                // 2. Горизонтальная лента друзей
                friendsSection

                // 3. Нижняя секция: Карточка фильма / момента ИЛИ ввод сообщения и кнопка "Отправить"
                if !selectedUsers.isEmpty {
                    sendMessageSection
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else if let clip {
                    clipPreviewCard(clip)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else if let movie {
                    moviePreviewCard(movie)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .toolbar(.hidden, for: .navigationBar)
            .ignoresSafeArea(.container, edges: .top)
            .safeAreaInset(edge: .top, spacing: 0) {
                SlooshTopBar.sheet(
                    title: clip != nil ? "Поделиться моментом" : "Отправить",
                    scrollOffset: .constant(0),
                    leadingAction: { dismiss() },
                    titleMaxWidth: 240,
                    trailing: {
                        TelegramGlassIconButton(systemName: "square.and.arrow.up") {
                            showSystemShareSheet = true
                        }
                        .accessibilityLabel("Поделиться")
                    }
                )
            }
            .task {
                await repo.fetchConversations()
            }
            .sheet(isPresented: $showSystemShareSheet) {
                if let clip {
                    let shareUrl = DeepLinkManager.shared.createClipShareURL(for: clip.id)
                    let text = DeepLinkManager.shared.createClipShareMessage(title: clip.title, clipId: clip.id, caption: clip.caption)
                    ShareSheet(items: [text, shareUrl])
                } else if let movie, let shareUrl = movieShareUrl {
                    ShareSheet(items: [shareUrl, movie.title ?? movie.originalTitle ?? "Фильм"])
                }
            }
        }
        .presentationBackground { Color.clear.glassEffect(in: .rect) }
        .presentationDragIndicator(.hidden)
        .presentationDetents([.height(380)])
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
            HStack(spacing: 12) {
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
                                        .overlay(
                                            Circle()
                                                .fill(Color.black.opacity(isSelected ? 0.35 : 0.0))
                                        )

                                    if isSelected {
                                        ZStack {
                                            Circle()
                                                .fill(Color.white)
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
                                    .frame(width: 58)
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

    private func moviePreviewCard(_ movie: MediaDetailsDto) -> some View {
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

    // MARK: - Clip Preview Card

    private func clipPreviewCard(_ clip: MovieClip) -> some View {
        HStack(spacing: 12) {
            if let thumbUrl = clip.displayThumbnailUrl, !thumbUrl.isEmpty {
                AsyncCachedImage(urlString: thumbUrl) {
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

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    HStack(spacing: 3) {
                        Image(systemName: "sparkles.tv")
                            .font(.system(size: 8.5, weight: .semibold))
                        Text("Момент")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .glassEffect(.regular, in: Capsule())

                    Text(clip.timecodeFormatted)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                }

                Text(clip.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                let cleanCaption = clip.caption.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleanCaption.isEmpty {
                    Text("«\(cleanCaption)»")
                        .font(.system(size: 11.5, weight: .regular))
                        .foregroundStyle(.secondary)
                        .italic()
                        .lineLimit(1)
                } else if !clip.subtitleInfo.isEmpty {
                    Text(clip.subtitleInfo)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
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
                .background(Color.white, in: Capsule())
                .glassEffect(.regular.interactive(), in: Capsule())
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
        guard let movie else { return nil }
        let idStr = movie.id ?? String(movie.ids?.kp ?? 0)
        return DeepLinkManager.shared.createShareURL(for: idStr)
    }

    private func sendToSelectedFriends() {
        guard !selectedUsers.isEmpty else { return }

        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        isSending = true

        let mediaPayload: MediaCardPayload
        let toastTitle: String
        let toastSubtitle: (Int) -> String

        if let clip {
            mediaPayload = MediaCardPayload(
                mediaId: "\(clip.mediaId)",
                type: "clip",
                title: clip.title,
                posterUrl: clip.displayThumbnailUrl,
                rating: nil,
                year: nil,
                clipId: clip.id,
                caption: clip.caption,
                startTime: clip.startTime,
                endTime: clip.endTime,
                duration: clip.duration,
                authorName: clip.authorName,
                season: clip.season,
                episode: clip.episode,
                translationName: clip.translationName,
                kpId: clip.kpId,
                tmdbId: clip.tmdbId
            )
            toastTitle = "Момент отправлен! 🚀"
            toastSubtitle = { count in
                count == 1 ? "Момент отправлен \(selectedUsers.first?.displayTitle ?? "")" : "Момент отправлен друзьям (\(count))"
            }
        } else if let movie {
            mediaPayload = MediaCardPayload(
                mediaId: movie.id ?? String(movie.ids?.kp ?? 0),
                type: movie.type ?? "movie",
                title: movie.title ?? movie.originalTitle ?? "Фильм",
                posterUrl: movie.displayPosterUrl,
                rating: movie.ratings?.kp,
                year: movie.year?.description
            )
            toastTitle = "Отправлено! 🚀"
            toastSubtitle = { count in
                count == 1 ? "Фильм отправлен \(selectedUsers.first?.displayTitle ?? "")" : "Фильм отправлен друзьям (\(count))"
            }
        } else {
            isSending = false
            return
        }

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
                title: toastTitle,
                subtitle: toastSubtitle(targets.count),
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
        SlooshAvatarView(user: user, size: size, showOnline: true)
    }
}
