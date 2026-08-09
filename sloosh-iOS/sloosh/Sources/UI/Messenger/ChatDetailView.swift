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
            // Фоновая область сообщений
            messageHistoryView

            // Плавающая верхняя панель шапки в стиле iOS 26+ Liquid Glass Pill
            floatingHeaderBar
        }
        .safeAreaInset(edge: .bottom) {
            // Плавающая нижняя панель ввода в стиле iOS 26+ Liquid Glass Pill
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

    // MARK: - Floating Top Header Bar (iOS 26+ Liquid Glass Pill)

    private var floatingHeaderBar: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .bold))
                    Text("Чаты")
                        .font(.system(size: 15, weight: .medium))
                }
                .foregroundColor(.primary)
            }

            Spacer()

            // Данные пользователя
            VStack(spacing: 2) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.slooshAccent.opacity(0.4))
                        .frame(width: 26, height: 26)
                        .overlay(
                            Text(String(peerUser.displayTitle.prefix(1)).uppercased())
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.primary)
                        )

                    Text(peerUser.displayTitle)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }

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

            Spacer()

            // Невидимая заглушка для симметричного центрирования заголовка
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .bold))
                Text("Чаты")
                    .font(.system(size: 15, weight: .medium))
            }
            .opacity(0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular.interactive(), in: Capsule())
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Message History View

    private var messageHistoryView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    Spacer()
                        .frame(height: 56)

                    ForEach(messages) { msg in
                        let isMe = msg.senderId == (AuthRepository.shared.currentUser?.id ?? "")

                        VStack(alignment: isMe ? .trailing : .leading, spacing: 4) {
                            HStack(alignment: .bottom, spacing: 6) {
                                if isMe { Spacer(minLength: 50) }

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
                                                    RoundedRectangle(cornerRadius: 20)
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
                                                Group {
                                                    if isMe {
                                                        RoundedRectangle(cornerRadius: 20)
                                                            .fill(Color.slooshAccent)
                                                    } else {
                                                        RoundedRectangle(cornerRadius: 20)
                                                            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
                                                    }
                                                }
                                            )
                                    }
                                }

                                if !isMe { Spacer(minLength: 50) }
                            }

                            // Время сообщения ВНИЗУ ПОД БАББЛОМ (как заказывал пользователь)
                            Text(formatTime(ms: msg.timestampMs))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                        }
                        .id(msg.id)
                    }
                }
                .padding(.horizontal, 16)
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

    // MARK: - Floating Bottom Input Bar (iOS 26+ Liquid Glass Pill)

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
                        .frame(width: 36, height: 36)

                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.black)
                }
            }
            .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
            .opacity(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1.0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular.interactive(), in: Capsule())
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
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

    private func formatTime(ms: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
