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
        ZStack(alignment: .top) {
            // Элементы истории сообщений (Edge-to-edge)
            messageHistoryView

            // Летающая верхняя панель iOS 26+ Liquid Glass (Назад + Капсула Профиля)
            floatingHeaderBar
        }
        .safeAreaInset(edge: .bottom) {
            // Летающая нижняя панель ввода iOS 26+ Liquid Glass
            floatingInputBar
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

    // MARK: - Floating Header Bar (iOS 26+ Liquid Glass)

    private var floatingHeaderBar: some View {
        HStack(spacing: 10) {
            // Летающая кругленькая кнопка Назад в стиле Liquid Glass
            TelegramGlassIconButton(
                systemName: "chevron.left",
                iconSize: 16,
                buttonSize: 40
            ) {
                dismiss()
            }

            Spacer()

            // Летающая капсула профиля собеседника с Liquid Glass
            HStack(spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    Circle()
                        .fill(Color.slooshAccent.opacity(0.35))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Text(String(peerUser.displayTitle.prefix(1)).uppercased())
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.primary)
                        )

                    if peerUser.isOnline == true {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 9, height: 9)
                            .overlay(Circle().stroke(Color(UIColor.systemBackground), lineWidth: 1.5))
                    }
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(peerUser.displayTitle)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    if peerUser.isOnline == true {
                        Text("в сети")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color.green)
                    } else {
                        Text("был(а) недавно")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .glassEffect(.regular.interactive(), in: Capsule())

            Spacer()

            // Невидимый балансировочный элемент
            Spacer()
                .frame(width: 40, height: 40)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    // MARK: - Message History View

    private var messageHistoryView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    Spacer()
                        .frame(height: 56)

                    // Летающая капсула даты
                    dateHeaderPill

                    ForEach(messages) { msg in
                        let isMe = msg.senderId == (AuthRepository.shared.currentUser?.id ?? "")
                        
                        LiquidGlassTelegramBubble(
                            message: msg,
                            isMe: isMe,
                            onOpenMovie: { movieId in
                                selectedMovieIdForDetails = movieId
                            }
                        )
                        .id(msg.id)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
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
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .glassEffect(.regular, in: Capsule())
            .padding(.vertical, 4)
    }

    // MARK: - Floating Bottom Input Bar (iOS 26+ Liquid Glass Capsule)

    private var floatingInputBar: some View {
        HStack(spacing: 10) {
            TextField("Сообщение...", text: $messageText)
                .font(.system(size: 16))
                .padding(.leading, 6)

            Button {
                sendMessage()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.slooshAccent)
                        .frame(width: 38, height: 38)

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
        .glassEffect(.regular.interactive(), in: Capsule())
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
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

// MARK: - Liquid Glass Telegram Message Bubble (iOS 26+)

private struct LiquidGlassTelegramBubble: View {
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
                            .font(.system(size: 15))
                            .foregroundColor(isMe ? .black : .primary)
                            .fixedSize(horizontal: false, vertical: true)

                        // Время и галочка ВНУТРИ баббла внизу справа (Telegram Style)
                        HStack(spacing: 2) {
                            Text(formatTime(ms: message.timestampMs))
                                .font(.system(size: 11))
                                .foregroundColor(isMe ? .black.opacity(0.65) : .secondary)

                            if isMe {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.black.opacity(0.75))
                            }
                        }
                        .padding(.leading, 4)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        Group {
                            if isMe {
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(Color.slooshAccent)
                            } else {
                                RoundedRectangle(cornerRadius: 20)
                                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 20))
                            }
                        }
                    )
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
