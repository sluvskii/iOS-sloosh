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
            // Нативная Telegram шапка
            telegramTopBar

            // Область сообщений
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        // Капсула даты
                        dateHeaderPill

                        ForEach(messages) { msg in
                            let isMe = msg.senderId == (AuthRepository.shared.currentUser?.id ?? "")
                            TelegramMessageBubble(
                                message: msg,
                                isMe: isMe,
                                onOpenMovie: { movieId in
                                    selectedMovieIdForDetails = movieId
                                }
                            )
                            .id(msg.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
                .onChange(of: messages.count) { _, _ in
                    if let lastId = messages.last?.id {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }

            // Нижняя панель ввода Telegram
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

    // MARK: - Telegram Top Navigation Bar

    private var telegramTopBar: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Чаты")
                        .font(.system(size: 17))
                }
                .foregroundColor(.slooshAccent)
            }

            Spacer()

            // Профиль собеседника по центру
            VStack(spacing: 2) {
                Text(peerUser.displayTitle)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                if peerUser.isOnline == true {
                    Text("в сети")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.slooshAccent)
                } else {
                    Text("был(а) недавно")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Аватар справа
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(Color.slooshAccent.opacity(0.3))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Text(String(peerUser.displayTitle.prefix(1)).uppercased())
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.primary)
                    )

                if peerUser.isOnline == true {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Color(UIColor.systemBackground), lineWidth: 1.5))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            VariableBlurView(tintOpacity: 1.0)
                .ignoresSafeArea(edges: .top)
        )
    }

    // MARK: - Date Header Pill

    private var dateHeaderPill: some View {
        Text("Сегодня")
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color(UIColor.tertiarySystemFill))
            )
            .padding(.vertical, 4)
    }

    // MARK: - Telegram Input Bar

    private var telegramInputBar: some View {
        HStack(spacing: 10) {
            TextField("Сообщение...", text: $messageText, axis: .vertical)
                .font(.system(size: 16))
                .lineLimit(1...5)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(UIColor.secondarySystemGroupedBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )

            Button {
                sendMessage()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.slooshAccent)
                        .frame(width: 36, height: 36)

                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.black)
                }
            }
            .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
            .opacity(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.35 : 1.0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            VariableBlurView(tintOpacity: 1.0)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - Logic

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

// MARK: - Telegram Authentic Message Bubble

private struct TelegramMessageBubble: View {
    let message: ChatMessage
    let isMe: Bool
    let onOpenMovie: (String) -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if isMe { Spacer(minLength: 44) }

            VStack(alignment: isMe ? .trailing : .leading, spacing: 4) {
                if message.type == .media, let media = message.media {
                    MediaMessageCardView(media: media) { movieId in
                        onOpenMovie(movieId)
                    }
                }

                if let text = message.text, !text.isEmpty {
                    HStack(alignment: .bottom, spacing: 6) {
                        Text(text)
                            .font(.system(size: 16))
                            .foregroundColor(isMe ? .black : .primary)
                            .fixedSize(horizontal: false, vertical: true)

                        // Время и галочка прочтения внизу СПРАВА ВНУТРИ БАББЛА (Telegram Style)
                        HStack(spacing: 2) {
                            Text(formatTime(ms: message.timestampMs))
                                .font(.system(size: 11))
                                .foregroundColor(isMe ? .black.opacity(0.6) : .secondary)

                            if isMe {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.black.opacity(0.7))
                            }
                        }
                        .padding(.leading, 4)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Group {
                            if isMe {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color.slooshAccent)
                            } else {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color(UIColor.secondarySystemGroupedBackground))
                            }
                        }
                    )
                    .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
                }
            }

            if !isMe { Spacer(minLength: 44) }
        }
    }

    private func formatTime(ms: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
