import SwiftUI

public struct ChatDetailView: View {
    public let peerUser: SlooshUser

    @StateObject private var repo = MessengerRepository.shared
    @State private var messages: [ChatMessage] = []
    @State private var messageText: String = ""
    @State private var isSending: Bool = false

    @State private var selectedMovieIdForDetails: String? = nil
    @State private var selectedMediaForDirectPlay: MediaCardPayload? = nil
    @State private var pendingPlayerConfig: PlayerConfig? = nil
    @State private var activePlayerConfig: PlayerConfig? = nil
    @State private var isShowingInfo: Bool = false
    @State private var pollTask: Task<Void, Never>? = nil

    // Peak Messenger state variables for Reply & Edit
    @State private var replyingMessage: ChatMessage? = nil
    @State private var editingMessage: ChatMessage? = nil

    @FocusState private var isInputFocused: Bool
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        ZStack {
            // Нативный глубокий задник iOS (в светлой теме не слепяще-белый, а нативный systemGroupedBackground)
            Color(UIColor.systemGroupedBackground).ignoresSafeArea()

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
                            .padding(.vertical, 8)
                            .background(Color(UIColor.secondarySystemGroupedBackground))
                        }
                        // Banner for replying message
                        else if let replying = replyingMessage {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Ответ на сообщение")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.slooshAccent)
                                    Text(replying.text ?? "Медиа карточка")
                                        .font(.system(size: 13))
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
                            .padding(.vertical, 8)
                            .background(Color(UIColor.secondarySystemGroupedBackground))
                        }

                        inputBar
                    }
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
        .sheet(item: $selectedMediaForDirectPlay, onDismiss: {
            if let pending = pendingPlayerConfig {
                pendingPlayerConfig = nil
                DispatchQueue.main.async {
                    activePlayerConfig = pending
                }
            }
        }) { media in
            HomeDirectPlayWrapper(movieId: media.mediaId, fallbackTitle: media.title) { config in
                pendingPlayerConfig = config
                selectedMediaForDirectPlay = nil
            }
        }
        .fullScreenCover(item: $activePlayerConfig, onDismiss: {
            activePlayerConfig = nil
        }) { config in
            PlayerView(
                iframeUrl: config.iframeUrl,
                fallbackTitle: config.title,
                kpId: config.kpId,
                season: config.season,
                episode: config.episode,
                selectedVoiceover: config.voiceover,
                directStreamUrl: config.streamUrl,
                voices: config.voices,
                subtitles: config.subtitles,
                initialQuality: config.quality,
                seriesResult: config.seriesResult
            )
        }
        .task {
            let chatId = repo.getOrCreateChatId(peerUserId: peerUser.id)
            let cached = repo.loadMessagesFromDisk(chatId: chatId)
            if !cached.isEmpty {
                self.messages = cached
            }
            await loadMessages()
            startPolling()
        }
        .onDisappear {
            pollTask?.cancel()
        }
    }

    // MARK: - Navigation Bar Content

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
                SlooshAvatarView(user: peerUser, size: 34, showOnline: true)
            }
            .buttonStyle(PeakPressButtonStyle())
        }
    }

    // MARK: - Message List (Minute-Grouping Enabled)

    private var messageList: some View {
        ScrollViewReader { proxy in
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)

                        LazyVStack(spacing: 0) {
                            ForEach(messages) { message in
                                let isFromMe = message.senderId == (AuthRepository.shared.currentUser?.id ?? "")
                                let showMeta = shouldShowMeta(for: message)

                                PeakMessageBubbleView(
                                    message: message,
                                    isFromMe: isFromMe,
                                    showMeta: showMeta,
                                    allMessages: messages,
                                    onOpenMovie: { movieId in
                                        selectedMovieIdForDetails = movieId
                                    },
                                    onPlayDirectly: { media in
                                        selectedMediaForDirectPlay = media
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
                                    onDelete: { msg in
                                        deleteMessage(msg)
                                    },
                                    onReact: { emoji, msg in
                                        addReaction(emoji, to: msg)
                                    }
                                )
                                .id(message.id)
                            }
                        }
                    }
                    .frame(minHeight: geometry.size.height, alignment: .bottom)
                    .padding(.vertical, 8)
                }
                .defaultScrollAnchor(.bottom)
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.count) { _, _ in
                    if let lastId = messages.last?.id {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: isInputFocused) { _, isFocused in
                    if isFocused, let lastId = messages.last?.id {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                proxy.scrollTo(lastId, anchor: .bottom)
                            }
                        }
                    }
                }
                .onAppear {
                    if let lastId = messages.last?.id {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func shouldShowMeta(for message: ChatMessage) -> Bool {
        guard let index = messages.firstIndex(where: { $0.id == message.id }), index < messages.count - 1 else { return true }
        let next = messages[index + 1]
        if message.senderId == next.senderId && isSameMinute(ms1: message.timestampMs, ms2: next.timestampMs) {
            return false
        }
        return true
    }

    private func isSameMinute(ms1: Int64, ms2: Int64) -> Bool {
        let date1 = Date(timeIntervalSince1970: TimeInterval(ms1) / 1000.0)
        let date2 = Date(timeIntervalSince1970: TimeInterval(ms2) / 1000.0)
        return Calendar.current.isDate(date1, equalTo: date2, toGranularity: .minute)
    }

    // MARK: - Animated Telegram Style Input Bar (iOS 26+ Liquid Glass)

    private var hasTextToSending: Bool {
        !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isMultilineInput: Bool {
        messageText.contains("\n") || messageText.count > 32
    }

    private var inputBarCornerRadius: CGFloat {
        isMultilineInput ? 18 : 22
    }

    private var inputBarHorizontalPadding: CGFloat {
        isInputFocused ? 6 : 24
    }

    private var inputBarVerticalPadding: CGFloat {
        isInputFocused ? 8 : 2
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // Floating Glass Text Field Capsule / Rounded Box (Telegram-style morphing shape)
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Сообщение", text: $messageText, axis: .vertical)
                    .font(.system(size: 16))
                    .foregroundColor(.primary)
                    .lineLimit(1...6)
                    .focused($isInputFocused)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 40)
            }
            .glassEffect(
                .regular.interactive(),
                in: RoundedRectangle(cornerRadius: inputBarCornerRadius, style: .continuous)
            )
            .animation(.easeInOut(duration: 0.2), value: isMultilineInput)

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
                .buttonStyle(OpaquePressButtonStyle())
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.3).combined(with: .opacity).combined(with: .move(edge: .trailing)),
                        removal: .scale(scale: 0.3).combined(with: .opacity).combined(with: .move(edge: .trailing))
                    )
                )
                .disabled(isSending)
            }
        }
        .padding(.horizontal, inputBarHorizontalPadding)
        .padding(.vertical, inputBarVerticalPadding)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isInputFocused)
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: hasTextToSending)
    }

    // MARK: - Actions & Logic

    private func syncMessages(remoteList: [ChatMessage]) async {
        let sortedRemote = remoteList.sorted(by: { $0.timestampMs < $1.timestampMs })
        
        // 1. Если пришедший список полностью идентичен текущему UI — ранний выход (0 сбросов меню)
        guard sortedRemote != self.messages else { return }

        // 2. Если изменился лишь статус/реакции в существующих сообщениях (без добавлений/удалений)
        let isContentOnlyUpdate = (sortedRemote.count == self.messages.count) &&
            zip(sortedRemote, self.messages).allSatisfy { $0.id == $1.id }

        if isContentOnlyUpdate {
            // Обновляем данные без структурной инвалидации LazyVStack и без сброса .contextMenu
            self.messages = sortedRemote
        } else {
            // Структурные изменения (новые/удаленные сообщения) анимируем плавно
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                self.messages = sortedRemote
            }
        }

        let chatId = repo.getOrCreateChatId(peerUserId: peerUser.id)
        await repo.markMessagesAsRead(chatId: chatId, peerUserId: peerUser.id, messages: sortedRemote)
    }

    private func loadMessages() async {
        let chatId = repo.getOrCreateChatId(peerUserId: peerUser.id)
        let list = await repo.fetchMessages(chatId: chatId)
        await syncMessages(remoteList: list)
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_800_000_000)
                if Task.isCancelled { break }
                let chatId = repo.getOrCreateChatId(peerUserId: peerUser.id)
                let list = await repo.fetchMessages(chatId: chatId)
                await syncMessages(remoteList: list)
            }
        }
    }

    private func sendMessage() {
        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        // Handle editing an existing message
        if let editing = editingMessage {
            editingMessage = nil
            messageText = ""
            isSending = false

            let chatId = repo.getOrCreateChatId(peerUserId: peerUser.id)
            var updatedMsg = editing
            updatedMsg.text = trimmed
            updatedMsg.isEdited = true

            if let idx = self.messages.firstIndex(where: { $0.id == editing.id }) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                    self.messages[idx] = updatedMsg
                }
            }

            Task {
                _ = await repo.postMessageToFirebase(chatId: chatId, message: updatedMsg, peerUser: peerUser)
                await loadMessages()
            }
            return
        }

        let replyId = replyingMessage?.id
        let currentUserId = AuthRepository.shared.currentUser?.id ?? ""

        // Оптимистичное создание сообщения за 0мс с единым стабильным ID!
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

        // Добавляем на UI мгновенно за 0мс без мигания
        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
            self.messages.append(optimisticMessage)
        }

        Task {
            _ = await repo.sendMessage(toPeerUser: peerUser, message: optimisticMessage)
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

    private func deleteMessage(_ msg: ChatMessage) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.easeInOut(duration: 0.22)) {
            self.messages.removeAll(where: { $0.id == msg.id })
        }
        let chatId = repo.getOrCreateChatId(peerUserId: peerUser.id)
        Task {
            await repo.deleteMessage(chatId: chatId, messageId: msg.id, peerUser: peerUser)
        }
    }
}

private struct iMessageReactionPickerView: View {
    let onSelect: (String) -> Void
    private let emojis = ["❤️", "👍", "🔥", "😂", "😢", "👏"]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(emojis, id: \.self) { emoji in
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onSelect(emoji)
                } label: {
                    Text(emoji)
                        .font(.system(size: 24))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(OpaquePressButtonStyle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular.interactive(), in: Capsule())
        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
    }
}

// MARK: - Peak Message Bubble View (Adaptive Theme + Minute Grouping)

private struct PeakMessageBubbleView: View {
    let message: ChatMessage
    let isFromMe: Bool
    let showMeta: Bool
    let allMessages: [ChatMessage]
    let onOpenMovie: (String) -> Void
    let onPlayDirectly: (MediaCardPayload) -> Void
    let onReply: (ChatMessage) -> Void
    let onEdit: (ChatMessage) -> Void
    let onDelete: (ChatMessage) -> Void
    let onReact: (String, ChatMessage) -> Void

    @State private var showReactionPicker: Bool = false

    private var repliedMessage: ChatMessage? {
        if let replyToId = message.replyToId {
            return allMessages.first(where: { $0.id == replyToId })
        }
        return nil
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if isFromMe { Spacer(minLength: 60) }

            VStack(alignment: isFromMe ? .trailing : .leading, spacing: 5) {
                if showReactionPicker {
                    iMessageReactionPickerView { emoji in
                        onReact(emoji, message)
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                            showReactionPicker = false
                        }
                    }
                    .transition(.scale(scale: 0.35).combined(with: .opacity).combined(with: .move(edge: .bottom)))
                }

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

                if showMeta {
                    metaRow
                }
            }

            if !isFromMe { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, showMeta ? 3 : 1)
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: showReactionPicker)
    }

    @ViewBuilder
    private var bubbleBody: some View {
        if message.type == .media, let media = message.media {
            MediaMessageCardView(media: media, onOpenDetails: { movieId in
                onOpenMovie(movieId)
            }, onPlayDirectly: { payload in
                onPlayDirectly(payload)
            })
            .contextMenu {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                        showReactionPicker.toggle()
                    }
                } label: {
                    Label("Реакция...", systemImage: "face.smiling")
                }

                Button {
                    onReply(message)
                } label: {
                    Label("Ответить", systemImage: "arrowshape.turn.up.left")
                }

                Button(role: .destructive) {
                    onDelete(message)
                } label: {
                    Label("Удалить у всех", systemImage: "trash")
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                // Replied Message Header
                if let replied = repliedMessage {
                    HStack(spacing: 8) {
                        Capsule()
                            .fill(isFromMe ? Color(UIColor.systemBackground) : Color.slooshAccent)
                            .frame(width: 2)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ответ")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(isFromMe ? Color(UIColor.systemBackground) : .slooshAccent)
                            Text(replied.text ?? "Медиа")
                                .font(.system(size: 13))
                                .foregroundColor(isFromMe ? Color(UIColor.systemBackground).opacity(0.7) : .secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.bottom, 2)
                }

                // Text content
                if let text = message.text, !text.isEmpty {
                    Text(text)
                        .font(.system(size: 16))
                        .foregroundColor(isFromMe ? Color(UIColor.systemBackground) : .primary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Group {
                    if isFromMe {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.primary)
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
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                        showReactionPicker.toggle()
                    }
                } label: {
                    Label("Реакция...", systemImage: "face.smiling")
                }

                Button {
                    onReply(message)
                } label: {
                    Label("Ответить", systemImage: "arrowshape.turn.up.left")
                }

                if let text = message.text, !text.isEmpty {
                    Button {
                        UIPasteboard.general.string = text
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Label("Скопировать текст", systemImage: "doc.on.doc")
                    }
                }

                if isFromMe && message.type == .text {
                    Button {
                        onEdit(message)
                    } label: {
                        Label("Редактировать", systemImage: "pencil")
                    }
                }

                Button(role: .destructive) {
                    onDelete(message)
                } label: {
                    Label(isFromMe ? "Удалить у всех" : "Удалить", systemImage: "trash")
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
                            .foregroundColor(isFromMe ? Color(UIColor.systemBackground) : .primary)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(isFromMe ? Color.primary : Color(white: 0.18))
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
                        SlooshAvatarView(user: peerUser, size: 100, showOnline: true)

                        VStack(spacing: 4) {
                            Text(peerUser.displayTitle)
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.primary)

                            if !peerUser.displayTag.isEmpty {
                                Text(peerUser.displayTag)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(Color.slooshAccent)
                            }

                            Text(peerUser.isOnline == true ? "в сети" : "был(а) недавно")
                                .font(.system(size: 14))
                                .foregroundColor(peerUser.isOnline == true ? .slooshAccent : .secondary)
                                .padding(.top, 2)
                        }
                    }
                    .padding(.top, 24)

                    // Info Section (Privacy-Safe Handle / Status)
                    if !peerUser.displayTag.isEmpty {
                        VStack(spacing: 0) {
                            HStack(spacing: 14) {
                                Image(systemName: "at")
                                    .frame(width: 22)
                                    .foregroundColor(Color.slooshAccent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Тег пользователя")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                    Text(peerUser.displayTag)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.primary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color(UIColor.secondarySystemGroupedBackground))
                        )
                        .padding(.horizontal, 16)
                    }

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

private struct OpaquePressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .opacity(1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.68), value: configuration.isPressed)
    }
}
