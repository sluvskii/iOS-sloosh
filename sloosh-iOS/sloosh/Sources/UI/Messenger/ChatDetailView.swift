import SwiftUI

public struct ChatDetailView: View {
    public let peerUser: SlooshUser

    @StateObject private var repo = MessengerRepository.shared
    @State private var messages: [ChatMessage] = []
    @State private var messageText: String = ""
    @State private var isSending: Bool = false

    @State private var selectedMovieIdForDetails: String? = nil
    @State private var isShowingInfo: Bool = false
    @State private var pollTask: Task<Void, Never>? = nil

    // Peak Messenger state variables for Reply & Edit
    @State private var replyingMessage: ChatMessage? = nil
    @State private var editingMessage: ChatMessage? = nil

    @FocusState private var isInputFocused: Bool
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        ZStack {
            Color(UIColor.systemBackground).ignoresSafeArea()

            messageList
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 0) {
                        // Banner for editing message
                        if let editing = editingMessage {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Редактирование")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.slooshAccent)
                                    Text(editing.text ?? "")
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Button {
                                    editingMessage = nil
                                    messageText = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .padding(.horizontal, 14)
                            .padding(.bottom, 8)
                        }

                        // Banner for replying message
                        if let replying = replyingMessage {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Ответ")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.slooshAccent)
                                    Text(replying.text ?? "Медиа")
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Button {
                                    replyingMessage = nil
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .padding(.horizontal, 14)
                            .padding(.bottom, 8)
                        }

                        inputBar
                    }
                    .background(Color.clear)
                }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { navBarContent }
        .toolbarVisibility(.hidden, for: .tabBar)
        .navigationDestination(isPresented: $isShowingInfo) {
            ChatInfoView(peerUser: peerUser)
        }
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

    // MARK: - Navigation Bar Content (Peak Messenger Style with Liquid Glass Avatar Button on Trailing)

    @ToolbarContentBuilder
    private var navBarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Button {
                isShowingInfo = true
            } label: {
                VStack(spacing: 1) {
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
            }
            .buttonStyle(.plain)
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                isShowingInfo = true
            } label: {
                PeakAvatarView(user: peerUser, size: 34, showOnline: true)
            }
            .buttonStyle(PeakPressButtonStyle())
        }
    }

    // MARK: - Message List (Peak Messenger Style)

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(messages) { message in
                        let isFromMe = message.senderId == (AuthRepository.shared.currentUser?.id ?? "")
                        
                        PeakMessageBubbleView(
                            message: message,
                            isFromMe: isFromMe,
                            allMessages: messages,
                            onOpenMovie: { movieId in
                                selectedMovieIdForDetails = movieId
                            },
                            onReply: { msg in
                                replyingMessage = msg
                                isInputFocused = true
                            },
                            onEdit: { msg in
                                editingMessage = msg
                                messageText = msg.text ?? ""
                                isInputFocused = true
                            },
                            onReact: { emoji, msg in
                                addReaction(emoji, to: msg)
                            }
                        )
                        .id(message.id)
                    }
                }
                .padding(.vertical, 8)
            }
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) { _, _ in
                if let lastId = messages.last?.id {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Animated Telegram Style Input Bar (iOS 26+ Liquid Glass)

    private var hasTextToSending: Bool {
        !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // Floating Glass Text Field Capsule
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Сообщение", text: $messageText, axis: .vertical)
                    .font(.system(size: 16))
                    .foregroundColor(.primary)
                    .lineLimit(1...6)
                    .focused($isInputFocused)
                    .padding(.vertical, 9)
                    .padding(.horizontal, 16)
            }
            .glassEffect(.regular.interactive(), in: Capsule())

            // Telegram-style Animated Sliding/Popping Send Button
            if hasTextToSending {
                Button {
                    sendMessage()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.slooshAccent)
                            .frame(width: 40, height: 40)

                        Image(systemName: "arrow.up")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.black)
                    }
                    .glassEffect(.regular.interactive(), in: Circle())
                }
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.3).combined(with: .opacity).combined(with: .move(edge: .trailing)),
                        removal: .scale(scale: 0.3).combined(with: .opacity).combined(with: .move(edge: .trailing))
                    )
                )
                .disabled(isSending)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: hasTextToSending)
    }

    // MARK: - Actions & Logic

    private func loadMessages() async {
        let chatId = repo.getOrCreateChatId(peerUserId: peerUser.id)
        
        // 1. Показываем кэш с диска за 0мс!
        let cached = repo.loadMessagesFromDisk(chatId: chatId)
        if !cached.isEmpty {
            self.messages = cached
            await repo.markMessagesAsRead(chatId: chatId, peerUserId: peerUser.id, messages: cached)
        }
        
        // 2. Фоновая сеть
        let list = await repo.fetchMessages(chatId: chatId)
        self.messages = list
        await repo.markMessagesAsRead(chatId: chatId, peerUserId: peerUser.id, messages: list)
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                if Task.isCancelled { break }
                let chatId = repo.getOrCreateChatId(peerUserId: peerUser.id)
                let list = await repo.fetchMessages(chatId: chatId)
                if list != self.messages {
                    self.messages = list
                    await repo.markMessagesAsRead(chatId: chatId, peerUserId: peerUser.id, messages: list)
                }
            }
        }
    }

    private func sendMessage() {
        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        let replyId = replyingMessage?.id
        let currentUserId = AuthRepository.shared.currentUser?.id ?? ""

        // Оптимистичное создание сообщения за 0мс!
        let optimisticMessage = ChatMessage(
            senderId: currentUserId,
            receiverId: peerUser.id,
            type: .text,
            text: trimmed,
            replyToId: replyId,
            isRead: false
        )

        messageText = ""
        replyingMessage = nil
        editingMessage = nil
        isSending = false

        // Добавляем на UI мгновенно за 0мс
        withAnimation(.easeOut(duration: 0.15)) {
            self.messages.append(optimisticMessage)
        }

        Task {
            _ = await repo.sendMessage(toPeerUser: peerUser, text: trimmed, replyToId: replyId)
            await loadMessages()
        }
    }

    private func addReaction(_ emoji: String, to msg: ChatMessage) {
        guard let myId = AuthRepository.shared.currentUser?.id else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            var newReactions = msg.reactions ?? [:]
            newReactions[myId] = emoji
            let updatedMsg = ChatMessage(
                id: msg.id,
                senderId: msg.senderId,
                receiverId: msg.receiverId,
                type: msg.type,
                text: msg.text,
                media: msg.media,
                timestampMs: msg.timestampMs,
                replyToId: msg.replyToId,
                reactions: newReactions,
                isEdited: msg.isEdited,
                isRead: msg.isRead
            )
            let chatId = repo.getOrCreateChatId(peerUserId: peerUser.id)
            await repo.postMessageToFirebase(chatId: chatId, message: updatedMsg)
            await loadMessages()
        }
    }
}

// MARK: - Peak Message Bubble View

private struct PeakMessageBubbleView: View {
    let message: ChatMessage
    let isFromMe: Bool
    let allMessages: [ChatMessage]
    let onOpenMovie: (String) -> Void
    let onReply: (ChatMessage) -> Void
    let onEdit: (ChatMessage) -> Void
    let onReact: (String, ChatMessage) -> Void

    private var repliedMessage: ChatMessage? {
        if let replyToId = message.replyToId {
            return allMessages.first(where: { $0.id == replyToId })
        }
        return nil
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if isFromMe { Spacer(minLength: 60) }

            VStack(alignment: isFromMe ? .trailing : .leading, spacing: 4) {
                ZStack(alignment: isFromMe ? .bottomTrailing : .bottomLeading) {
                    bubbleBody
                        .onTapGesture(count: 2) {
                            onReact("❤️", message)
                        }

                    if let msgReactions = message.reactions, !msgReactions.isEmpty {
                        reactionsOverlay(msgReactions)
                    }
                }
                .padding(.bottom, (message.reactions?.isEmpty == false) ? 8 : 0)

                metaRow
            }

            if !isFromMe { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var bubbleBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Replied Message Header
            if let replied = repliedMessage {
                HStack(spacing: 8) {
                    Capsule()
                        .fill(isFromMe ? Color.black : Color.slooshAccent)
                        .frame(width: 2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ответ")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(isFromMe ? .black : .slooshAccent)
                        Text(replied.text ?? "Медиа")
                            .font(.system(size: 13))
                            .foregroundColor(isFromMe ? .black.opacity(0.65) : .secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.bottom, 2)
            }

            // Movie Card
            if message.type == .media, let media = message.media {
                MediaMessageCardView(media: media) { movieId in
                    onOpenMovie(movieId)
                }
            }

            // Text content
            if let text = message.text, !text.isEmpty {
                Text(text)
                    .font(.system(size: 16))
                    .foregroundColor(isFromMe ? .black : .primary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Group {
                if isFromMe {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.slooshAccent)
                } else {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(UIColor.secondarySystemGroupedBackground))
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: isFromMe ? 0 : 0.5)
        )
        .contextMenu {
            Section("Реакция") {
                Button("❤️") { onReact("❤️", message) }
                Button("👍") { onReact("👍", message) }
                Button("🔥") { onReact("🔥", message) }
                Button("😂") { onReact("😂", message) }
                Button("😢") { onReact("😢", message) }
                Button("👏") { onReact("👏", message) }
            }

            Button {
                onReply(message)
            } label: {
                Label("Ответить", systemImage: "arrowshape.turn.up.left")
            }

            if isFromMe && message.type == .text {
                Button {
                    onEdit(message)
                } label: {
                    Label("Редактировать", systemImage: "pencil")
                }
            }
        }
    }

    private var metaRow: some View {
        HStack(spacing: 4) {
            Text(formatTime(ms: message.timestampMs))
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            if isFromMe {
                Image(systemName: message.isRead == true ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }

            if message.isEdited == true {
                Text("изм.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private func reactionsOverlay(_ reactionsDict: [String: String]) -> some View {
        let grouped = Dictionary(grouping: reactionsDict.values, by: { $0 })
        HStack(spacing: 4) {
            ForEach(grouped.map { ($0.key, $0.value.count) }, id: \.0) { emoji, count in
                HStack(spacing: 2) {
                    Text(emoji)
                        .font(.system(size: 11))
                    if count > 1 {
                        Text("\(count)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(isFromMe ? .black : .primary)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(isFromMe ? Color.white : Color(white: 0.18))
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.1), radius: 1)
            }
        }
        .offset(y: 10)
        .padding(.horizontal, 8)
    }

    private func formatTime(ms: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - Chat Info View (Peak Messenger Style)

public struct ChatInfoView: View {
    public let peerUser: SlooshUser

    @StateObject private var repo = MessengerRepository.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm: Bool = false

    public var body: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // Header Section (Avatar + Username)
                    VStack(spacing: 12) {
                        PeakAvatarView(user: peerUser, size: 100, showOnline: true)
                            .padding(4)
                            .glassEffect(.regular.interactive(), in: Circle())

                        VStack(spacing: 4) {
                            Text(peerUser.displayTitle)
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.primary)

                            Text(peerUser.isOnline == true ? "в сети" : "был(а) недавно")
                                .font(.system(size: 15))
                                .foregroundColor(peerUser.isOnline == true ? .slooshAccent : .secondary)
                        }
                    }
                    .padding(.top, 24)

                    // Info Section
                    VStack(spacing: 0) {
                        if !peerUser.email.isEmpty {
                            HStack(spacing: 14) {
                                Image(systemName: "envelope.fill")
                                    .frame(width: 22)
                                    .foregroundColor(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Email")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                    Text(peerUser.email)
                                        .font(.system(size: 16))
                                        .foregroundColor(.primary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)

                            PeakDivider().padding(.leading, 52)
                        }

                        HStack(spacing: 14) {
                            Image(systemName: "person.fill")
                                .frame(width: 22)
                                .foregroundColor(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("ID пользователя")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                Text(peerUser.id)
                                    .font(.system(size: 14, design: .monospaced))
                                    .foregroundColor(.primary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(UIColor.secondarySystemGroupedBackground))
                    )
                    .padding(.horizontal, 16)

                    // Actions Section
                    VStack(spacing: 0) {
                        Button {
                            showDeleteConfirm = true
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "trash.fill")
                                    .frame(width: 22)
                                    .foregroundColor(.red)
                                Text("Удалить чат")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.red)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(PeakPressButtonStyle())
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(UIColor.secondarySystemGroupedBackground))
                    )
                    .padding(.horizontal, 16)
                }
            }
        }
        .navigationTitle("Информация")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Удалить чат с \(peerUser.displayTitle)?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Удалить чат", role: .destructive) {
                dismiss()
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("История сообщений будет удалена.")
        }
    }
}
