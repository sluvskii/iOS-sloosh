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
            // Telegram Header Bar
            telegramHeaderBar

            // Message History
            messageHistoryView

            // Telegram Input Bar
            telegramInputBar
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

    // MARK: - Telegram Header Bar

    private var telegramHeaderBar: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .bold))
                    Text("Чаты")
                        .font(.system(size: 16, weight: .medium))
                }
                .foregroundColor(.primary)
            }

            Spacer()

            // Avatar & Online Info (Center Header)
            VStack(spacing: 2) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.slooshAccent, Color.slooshAccent.opacity(0.4)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 28, height: 28)
                        .overlay(
                            Text(String(peerUser.displayTitle.prefix(1)).uppercased())
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.black)
                        )

                    Text(peerUser.displayTitle)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }

                HStack(spacing: 4) {
                    if peerUser.isOnline == true {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text("в сети")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color.green)
                    } else {
                        Text("был(а) недавно")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // Action Button
            TelegramGlassIconButton(
                systemName: "phone.fill",
                iconSize: 15,
                buttonSize: 34
            ) {
                ToastManager.shared.show(
                    title: "Звонки Sloosh",
                    subtitle: "Функция аудиозвонков в разработке",
                    icon: "phone.fill"
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            VariableBlurView(tintOpacity: 1.0)
                .ignoresSafeArea(edges: .top)
        )
    }

    // MARK: - Message History View

    private var messageHistoryView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    // Floating Date Header
                    dateHeaderPill

                    ForEach(messages) { msg in
                        let isMe = msg.senderId == (AuthRepository.shared.currentUser?.id ?? "")
                        
                        HStack(alignment: .bottom, spacing: 6) {
                            if isMe { Spacer(minLength: 50) }

                            TelegramMessageBubble(
                                message: msg,
                                isMe: isMe,
                                onOpenMovie: { movieId in
                                    selectedMovieIdForDetails = movieId
                                }
                            )

                            if !isMe { Spacer(minLength: 50) }
                        }
                        .id(msg.id)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .onChange(of: messages.count) { _, _ in
                if let lastId = messages.last?.id {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var dateHeaderPill: some View {
        Text("Сегодня")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Capsule().glassEffect(.regular, in: Capsule()))
            .padding(.vertical, 4)
    }

    // MARK: - Telegram Input Bar

    private var telegramInputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // Attachment Button
            TelegramGlassIconButton(
                systemName: "plus",
                iconSize: 18,
                buttonSize: 38
            ) {
                ToastManager.shared.show(
                    title: "Поделиться медиа",
                    subtitle: "Используйте кнопку Отправить на карточке фильма",
                    icon: "film.fill"
                )
            }

            // Expanding Text Input Field
            TextField("Сообщение...", text: $messageText, axis: .vertical)
                .font(.system(size: 16))
                .lineLimit(1...5)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 20))
                )

            // Dynamic Telegram Send / Mic Button
            Button {
                sendMessage()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.slooshAccent)
                        .frame(width: 38, height: 38)

                    Image(systemName: messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "mic.fill" : "paperplane.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.black)
                }
            }
            .disabled(isSending)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            VariableBlurView(tintOpacity: 1.0)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - Actions & Logic

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
}

// MARK: - Telegram Message Bubble View

private struct TelegramMessageBubble: View {
    let message: ChatMessage
    let isMe: Bool
    let onOpenMovie: (String) -> Void

    var body: some View {
        VStack(alignment: isMe ? .trailing : .leading, spacing: 4) {
            if message.type == .media, let media = message.media {
                MediaMessageCardView(media: media) { movieId in
                    onOpenMovie(movieId)
                }
            }

            if let text = message.text, !text.isEmpty {
                HStack(alignment: .bottom, spacing: 8) {
                    Text(text)
                        .font(.system(size: 15))
                        .foregroundColor(isMe ? .black : .primary)

                    // Inline timestamp + double checkmarks
                    HStack(spacing: 3) {
                        Text(formatTime(ms: message.timestampMs))
                            .font(.system(size: 11))
                            .foregroundColor(isMe ? .black.opacity(0.65) : .secondary)

                        if isMe {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.black.opacity(0.7))
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    Group {
                        if isMe {
                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color.slooshAccent)
                        } else {
                            RoundedRectangle(cornerRadius: 18)
                                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
                        }
                    }
                )
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
