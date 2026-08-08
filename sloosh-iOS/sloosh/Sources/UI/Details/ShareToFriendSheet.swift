import SwiftUI

public struct ShareToFriendSheet: View {
    public let movie: MediaDetailsDto
    @Environment(\.dismiss) private var dismiss

    @StateObject private var repo = MessengerRepository.shared
    @State private var searchQuery: String = ""
    @State private var sendingToUserId: String? = nil

    public init(movie: MediaDetailsDto) {
        self.movie = movie
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Карточка делящегося фильма
                HStack(spacing: 12) {
                    if let posterUrl = movie.displayPosterUrl, !posterUrl.isEmpty {
                        AsyncCachedImage(url: posterUrl) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Rectangle().fill(Color.secondary.opacity(0.2))
                        }
                        .frame(width: 50, height: 70)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(movie.title ?? movie.originalTitle ?? "Фильм")
                            .font(.system(size: 16, weight: .bold))
                            .lineLimit(2)

                        if let year = movie.year {
                            Text(year.description)
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()
                }
                .padding(12)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))

                // Поиск друга
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Поиск друга по нику или email...", text: $searchQuery)
                        .onChange(of: searchQuery) { _, newValue in
                            Task {
                                await repo.searchUsers(query: newValue)
                            }
                        }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Capsule().glassEffect(.regular.interactive(), in: .capsule))

                // Список друзей / результатов поиска
                let displayList = searchQuery.isEmpty ? repo.conversations.map { $0.peerUser } : repo.searchResults

                if displayList.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "person.2.slash")
                            .font(.system(size: 36))
                            .foregroundColor(.secondary)
                        Text(searchQuery.isEmpty ? "У вас пока нет активных диалогов" : "Пользователи не найдены")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(displayList) { friend in
                                HStack {
                                    Circle()
                                        .fill(Color.slooshAccent.opacity(0.3))
                                        .frame(width: 42, height: 42)
                                        .overlay(
                                            Text(String(friend.displayTitle.prefix(1)).uppercased())
                                                .font(.system(size: 17, weight: .bold))
                                        )

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(friend.displayTitle)
                                            .font(.system(size: 16, weight: .semibold))
                                        if !friend.email.isEmpty {
                                            Text(friend.email)
                                                .font(.system(size: 12))
                                                .foregroundColor(.secondary)
                                        }
                                    }

                                    Spacer()

                                    Button {
                                        sendToFriend(friend)
                                    } label: {
                                        if sendingToUserId == friend.id {
                                            ProgressView()
                                                .controlSize(.small)
                                        } else {
                                            Text("Отправить")
                                                .font(.system(size: 14, weight: .bold))
                                                .foregroundColor(.black)
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 8)
                                                .background(Capsule().fill(Color.slooshAccent))
                                        }
                                    }
                                    .disabled(sendingToUserId != nil)
                                }
                                .padding(12)
                                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
                            }
                        }
                    }
                }
            }
            .padding(16)
            .navigationTitle("Отправить другу")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
            .task {
                await repo.fetchConversations()
            }
        }
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
                ToastManager.shared.show(
                    title: "Отправлено! 🚀",
                    subtitle: "Фильм отправлен \(friend.displayTitle)",
                    icon: "paperplane.fill"
                )
                dismiss()
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
