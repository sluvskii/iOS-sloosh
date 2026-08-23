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

    var body: some View {
        VStack(spacing: 0) {
            // MARK: — Header
            sheetHeader
                .padding(.top, 20)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            // MARK: — Search field
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("Поиск друзей...", text: $searchQuery)
                    .font(.system(size: 15))
                    .autocorrectionDisabled()
                    .onChange(of: searchQuery) { _, q in
                        Task { await repo.searchUsers(query: q) }
                    }

                if !searchQuery.isEmpty {
                    Button { searchQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 42)
            .glassEffect(.regular.interactive(), in: Capsule())
            .padding(.horizontal, 16)

            Divider()
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .opacity(0.1)

            // MARK: — Friends list
            friendsScrollSection
                .padding(.top, 12)

            Divider()
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .opacity(0.1)

            // MARK: — Bottom section: movie card OR send controls
            Group {
                if selectedUsers.isEmpty {
                    moviePreviewCard
                        .padding(.top, 14)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity.animation(.easeIn(duration: 0.12))
                        ))
                } else {
                    sendSection
                        .padding(.top, 14)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity.animation(.easeIn(duration: 0.12))
                        ))
                }
            }
            .padding(.bottom, 20)
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: selectedUsers.isEmpty)
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.regularMaterial)
        .task { await repo.fetchConversations() }
        .sheet(isPresented: $showSystemShareSheet) {
            if let shareUrl = movieShareUrl {
                ShareSheet(items: [shareUrl, movie.title ?? "Фильм"])
            }
        }
    }

    // MARK: — Header

    private var sheetHeader: some View {
        HStack(alignment: .center) {
            Text("Отправить")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.primary)

            Spacer()

            // Системный шеринг
            Button {
                showSystemShareSheet = true
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
                    .glassEffect(.regular.interactive(), in: Circle())
            }
            .buttonStyle(.plain)

            // Закрыть
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
                    .glassEffect(.regular.interactive(), in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: — Friends horizontal scroll

    private var friendsScrollSection: some View {
        let displayList = searchQuery.isEmpty
            ? repo.conversations.map { $0.peerUser }
            : repo.searchResults

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                if displayList.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: searchQuery.isEmpty ? "person.2" : "magnifyingglass")
                            .font(.system(size: 22))
                            .foregroundStyle(.tertiary)
                        Text(searchQuery.isEmpty ? "Нет диалогов" : "Ничего не найдено")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 84)
                    .padding(.horizontal, 16)
                } else {
                    ForEach(displayList) { friend in
                        let isSelected = selectedUsers.contains(where: { $0.id == friend.id })

                        Button {
                            toggleUser(friend)
                        } label: {
                            VStack(spacing: 6) {
                                ZStack(alignment: .bottomTrailing) {
                                    UserAvatarView(user: friend, size: 54)
                                        .scaleEffect(isSelected ? 1.06 : 1.0)
                                        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: isSelected)

                                    if isSelected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 17, weight: .bold))
                                            .foregroundStyle(.black, Color.slooshAccent)
                                            .background(Circle().fill(.white).padding(-1))
                                            .offset(x: 2, y: 2)
                                            .transition(.scale.combined(with: .opacity))
                                    }
                                }

                                Text(friend.displayTitle)
                                    .font(.caption)
                                    .fontWeight(isSelected ? .semibold : .regular)
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
        .frame(height: 90)
    }

    // MARK: — Movie preview card (no friend selected)

    private var moviePreviewCard: some View {
        HStack(spacing: 14) {
            if let posterUrl = movie.displayPosterUrl, !posterUrl.isEmpty {
                AsyncCachedImage(urlString: posterUrl) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                } content: { image in
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
                .frame(width: 46, height: 66)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 3)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(movie.title ?? movie.originalTitle ?? "Фильм")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

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
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    if let genres = movie.genres, let g = genres.first, !g.isEmpty {
                        Text("· \(g)")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()
        }
        .padding(14)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 16)
    }

    // MARK: — Send section (friend(s) selected)

    private var sendSection: some View {
        VStack(spacing: 12) {
            // Поле сообщения
            HStack(spacing: 10) {
                TextField("Добавьте сообщение...", text: $customMessage, axis: .vertical)
                    .font(.system(size: 15))
                    .lineLimit(1...3)

                if !customMessage.isEmpty {
                    Button { customMessage = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 16)

            // Кнопка «Отправить»
            Button {
                sendToFriends()
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
                .frame(height: 50)
                .background(isSending || selectedUsers.isEmpty ? Color.slooshAccent.opacity(0.5) : Color.slooshAccent)
                .clipShape(Capsule())
            }
            .buttonStyle(ShareScaleButtonStyle())
            .disabled(isSending || selectedUsers.isEmpty)
            .padding(.horizontal, 16)
        }
    }

    // MARK: — Helpers

    private func toggleUser(_ friend: SlooshUser) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if let idx = selectedUsers.firstIndex(where: { $0.id == friend.id }) {
            selectedUsers.remove(at: idx)
        } else {
            selectedUsers.append(friend)
        }
    }

    private var movieShareUrl: URL? {
        let idStr = movie.id ?? String(movie.ids?.kp ?? 0)
        return URL(string: "https://sloosh.app/movie/\(idStr)")
    }

    private func sendToFriends() {
        guard !selectedUsers.isEmpty else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        isSending = true

        let payload = MediaCardPayload(
            mediaId: movie.id ?? String(movie.ids?.kp ?? 0),
            type: movie.type ?? "movie",
            title: movie.title ?? movie.originalTitle ?? "Фильм",
            posterUrl: movie.displayPosterUrl,
            rating: movie.ratings?.kp,
            year: movie.year?.description
        )
        let text = customMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let targets = selectedUsers

        Task {
            for friend in targets {
                _ = await repo.sendMessage(toPeerUser: friend, mediaPayload: payload)
                if !text.isEmpty {
                    _ = await repo.sendMessage(toPeerUser: friend, text: text)
                }
            }
            isSending = false
            ToastManager.shared.show(
                title: "Отправлено! 🚀",
                subtitle: targets.count == 1
                    ? "Фильм отправлен \(targets.first?.displayTitle ?? "")"
                    : "Фильм отправлен друзьям (\(targets.count))",
                icon: "paperplane.fill"
            )
            dismiss()
        }
    }
}

// MARK: — Button style

private struct ShareScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

// MARK: — User Avatar

private struct UserAvatarView: View {
    let user: SlooshUser
    let size: CGFloat

    var body: some View {
        if let urlStr = user.avatarUrl, !urlStr.isEmpty, let url = URL(string: urlStr) {
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
                .fill(LinearGradient(
                    colors: [.blue.opacity(0.65), .purple.opacity(0.65)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: size, height: size)

            Text(String(user.displayTitle.prefix(1)).uppercased())
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}
