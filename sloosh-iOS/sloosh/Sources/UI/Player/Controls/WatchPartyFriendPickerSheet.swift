import SwiftUI

// MARK: - Watch Party Friend Picker (Liquid Glass Sheet)

struct WatchPartyFriendPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var messengerRepo = MessengerRepository.shared
    let onSelectFriend: (SlooshUser) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if messengerRepo.conversations.isEmpty {
                    emptyStateView
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(messengerRepo.conversations) { conv in
                                conversationRow(conv)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationTitle("Смотреть вместе")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        dismiss()
                    }
                    .foregroundColor(.secondary)
                }
            }
        }
        .presentationDetents([.medium, .fraction(0.65)])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
        .task {
            await messengerRepo.fetchConversations()
        }
    }

    // MARK: - Row

    private func conversationRow(_ conv: ChatConversation) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            dismiss()
            onSelectFriend(conv.peerUser)
        } label: {
            HStack(spacing: 12) {
                // Avatar
                ZStack {
                    if let urlStr = conv.peerUser.avatarUrl, let url = URL(string: urlStr) {
                        AsyncCachedImage(url: url) {
                            Circle().fill(Color.white.opacity(0.1))
                        } content: { image in
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        } fallback: {
                            avatarPlaceholder(for: conv.peerUser)
                        }
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                    } else {
                        avatarPlaceholder(for: conv.peerUser)
                            .frame(width: 44, height: 44)
                    }
                }

                // Name & status
                VStack(alignment: .leading, spacing: 3) {
                    Text(conv.peerUser.displayTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text(conv.lastMessageText)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.65))
                        .lineLimit(1)
                }

                Spacer()

                // SharePlay icon action pill
                Image(systemName: "shareplay")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .glassEffect(.regular, in: Circle())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func avatarPlaceholder(for user: SlooshUser) -> some View {
        Circle()
            .fill(Color.white.opacity(0.12))
            .overlay {
                Text(String(user.displayTitle.prefix(1)).uppercased())
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white.opacity(0.85))
            }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.4))
                .padding(.bottom, 4)

            Text("Нет недавних диалогов")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)

            Text("Начните переписку с другом в мессенджере, чтобы пригласить его к просмотру.")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.vertical, 40)
    }
}
