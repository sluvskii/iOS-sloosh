import SwiftUI

// MARK: - Watch Party Friend Picker (Liquid Glass Sheet)

struct WatchPartyFriendPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var messengerRepo = MessengerRepository.shared
    @State private var searchText = ""
    let onSelectFriend: (SlooshUser) -> Void

    private var filteredConversations: [ChatConversation] {
        let list = messengerRepo.conversations
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return list
        }
        return list.filter {
            $0.peerUser.displayTitle.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(UIColor.systemBackground).ignoresSafeArea()

                if messengerRepo.conversations.isEmpty {
                    emptyStateView
                } else if filteredConversations.isEmpty {
                    searchEmptyStateView
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(filteredConversations) { conv in
                                conversationRow(conv)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationTitle("Смотреть вместе")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Поиск друга...")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        dismiss()
                    }
                    .foregroundColor(.secondary)
                }
            }
        }
        .presentationDetents([.medium, .fraction(0.75)])
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
                // Unified avatar with online status badge
                SlooshAvatarView(user: conv.peerUser, size: 44, showOnline: true)

                // Name & status
                VStack(alignment: .leading, spacing: 3) {
                    Text(conv.peerUser.displayTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    if !conv.lastMessageText.isEmpty {
                        Text(conv.lastMessageText)
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.65))
                            .lineLimit(1)
                    }
                }

                Spacer()

                // SharePlay action icon
                Image(systemName: "shareplay")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color.green)
                    .frame(width: 36, height: 36)
                    .glassEffect(.regular.interactive(), in: Circle())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty States

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

    private var searchEmptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
                .padding(.bottom, 4)

            Text("Ничего не найдено")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)

            Text("По запросу «\(searchText)» нет диалогов.")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 40)
    }
}
