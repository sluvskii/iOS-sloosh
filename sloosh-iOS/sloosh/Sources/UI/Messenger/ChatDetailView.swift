import SwiftUI

public struct ChatDetailView: View {
    public let peerUser: SlooshUser
    
    @StateObject private var repo = MessengerRepository.shared
    @State private var messages: [ChatMessage] = []
    @State private var messageText: String = ""
    @State private var isSending: Bool = false
    @State private var selectedMovieIdForDetails: String? = nil
    @State private var pollTask: Task<Void, Never>? = nil

    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        VStack(spacing: 0) {
            // Шапка чата
            HStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.primary)
                }

                Circle()
                    .fill(Color.slooshAccent.opacity(0.3))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Text(String(peerUser.displayTitle.prefix(1)).uppercased())
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.primary)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(peerUser.displayTitle)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    if !peerUser.email.isEmpty {
                        Text(peerUser.email)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                VariableBlurView(tintOpacity: 1.0)
                    .ignoresSafeArea(edges: .top)
            )

            // Список сообщений
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(messages) { msg in
                            let isMe = msg.senderId == (AuthRepository.shared.currentUser?.id ?? "")
                            HStack {
                                if isMe { Spacer(minLength: 40) }

                                VStack(alignment: isMe ? .trailing : .leading, spacing: 4) {
                                    if msg.type == .media, let media = msg.media {
                                        MediaMessageCardView(media: media) { movieId in
                                            selectedMovieIdForDetails = movieId
                                        }
                                        if let text = msg.text, !text.isEmpty {
                                            Text(text)
                                                .font(.system(size: 15))
                                                .foregroundColor(isMe ? .black : .primary)
                                                .padding(.horizontal, 14)
                                                .padding(.vertical, 10)
                                                .background(
                                                    Capsule()
                                                        .fill(isMe ? Color.slooshAccent : Color.primary.opacity(0.1))
                                                )
                                        }
                                    } else {
                                        Text(msg.text ?? "")
                                            .font(.system(size: 15))
                                            .foregroundColor(isMe ? .black : .primary)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 10)
                                            .background(
                                                RoundedRectangle(cornerRadius: 18)
                                                    .fill(isMe ? Color.slooshAccent : Color.primary.opacity(0.12))
                                            )
                                    }

                                    Text(formatTime(ms: msg.timestampMs))
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 4)
                                }

                                if !isMe { Spacer(minLength: 40) }
                            }
                            .id(msg.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .onChange(of: messages.count) { _, _ in
                    if let lastId = messages.last?.id {
                        withAnimation {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }

            // Поле ввода сообщения
            HStack(spacing: 10) {
                TextField("Сообщение...", text: $messageText)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .glassEffect(.regular.interactive(), in: Capsule())
                    )

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.black)
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(Color.slooshAccent)
                        )
                }
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                .opacity(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1.0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                VariableBlurView(tintOpacity: 1.0)
                    .ignoresSafeArea(edges: .bottom)
            )
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $selectedMovieIdForDetails) { movieId in
            DetailsView(movieId: movieId, navigationTransitionID: nil, navigationTransitionNamespace: nil)
        }
        .task {
            await loadMessages()
            startPolling()
        }
        .onDisappear {
            pollTask?.cancel()
        }
    }

    private func loadMessages() async {
        let chatId = repo.getOrCreateChatId(peerUserId: peerUser.id)
        let list = await repo.fetchMessages(chatId: chatId)
        self.messages = list
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if Task.isCancelled { break }
                let chatId = repo.getOrCreateChatId(peerUserId: peerUser.id)
                let list = await repo.fetchMessages(chatId: chatId)
                if list != self.messages {
                    self.messages = list
                }
            }
        }
    }

    private func sendMessage() {
        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        messageText = ""
        isSending = true

        Task {
            let success = await repo.sendMessage(toPeerUser: peerUser, text: trimmed)
            isSending = false
            if success {
                await loadMessages()
            }
        }
    }

    private func formatTime(ms: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
