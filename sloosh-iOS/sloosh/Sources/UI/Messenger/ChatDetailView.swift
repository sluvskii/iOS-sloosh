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

    @State private var replyingMessage: ChatMessage? = nil
    @State private var editingMessage: ChatMessage? = nil

    @State private var isPeerTyping: Bool = false
    @State private var livePresence: (isOnline: Bool, lastSeenMs: Int64?)

    @FocusState private var isInputFocused: Bool
    @Environment(\.dismiss) private var dismiss

    public init(peerUser: SlooshUser) {
        self.peerUser = peerUser
        let cached = UserPresenceService.shared.getCachedPresence(userId: peerUser.id) ?? (peerUser.isCurrentlyOnline, peerUser.lastSeenMs)
        _livePresence = State(initialValue: cached)
    }

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

            let (online, lastSeen) = await UserPresenceService.shared.fetchUserPresence(userId: peerUser.id)
            self.livePresence = (online, lastSeen)
        }
        .onChange(of: messageText) { _, newVal in
            let chatId = repo.getOrCreateChatId(peerUserId: peerUser.id)
            if !newVal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                UserPresenceService.shared.sendTyping(chatId: chatId)
            } else {
                UserPresenceService.shared.clearTyping(chatId: chatId)
            }
        }
        .onDisappear {
            let chatId = repo.getOrCreateChatId(peerUserId: peerUser.id)
            UserPresenceService.shared.clearTyping(chatId: chatId)
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

                    if isPeerTyping {
                        HStack(spacing: 4) {
                            Text("печатает...")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color.slooshAccent)
                        }
                        .transition(.opacity)
                    } else {
                        let online = livePresence.isOnline || (peerUser.isCurrentlyOnline && livePresence.lastSeenMs == nil)
                        let lastSeen = livePresence.lastSeenMs ?? peerUser.lastSeenMs
                        let statusText = PresenceFormatter.formatLastSeen(isOnlineFlag: online, lastSeenMs: lastSeen)

                        Text(statusText)
                            .font(.system(size: 12, weight: online ? .medium : .regular))
                            .foregroundColor(online ? Color.slooshAccent : .secondary)
                            .transition(.opacity)
                    }
                }
            }
            .buttonStyle(.plain)
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                isShowingInfo = true
            } label: {
                let online = livePresence.isOnline || (peerUser.isCurrentlyOnline && livePresence.lastSeenMs == nil)
                SlooshAvatarView(
                    avatarSource: peerUser.avatarUrl,
                    fallbackText: peerUser.displayTitle,
                    size: 34,
                    showOnline: true,
                    isOnline: online
                )
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
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
                .onChange(of: isInputFocused) { _, isFocused in
                    if isFocused, let lastId = messages.last?.id {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            proxy.scrollTo(lastId, anchor: .bottom)
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
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let currentUserId = AuthRepository.shared.currentUser?.id ?? ""

        // 1. Сохраняем свежие оптимистичные сообщения
        let pendingOptimistic = self.messages.filter { local in
            local.senderId == currentUserId &&
            (now - local.timestampMs) < 15_000 &&
            !remoteList.contains(where: { $0.id == local.id })
        }

        // 2. Умное слияние реакций: сохраняем локальные реакции текущего пользователя, пока сервер обновляется
        var mergedRemote: [ChatMessage] = []
        for remoteMsg in sortedRemote {
            var msg = remoteMsg
            if let localMsg = self.messages.first(where: { $0.id == remoteMsg.id }) {
                if let localReactions = localMsg.reactions, let myEmoji = localReactions[currentUserId] {
                    var dict = remoteMsg.reactions ?? [:]
                    dict[currentUserId] = myEmoji
                    msg.reactions = dict
                } else if let localReactions = localMsg.reactions, localReactions[currentUserId] == nil, var dict = remoteMsg.reactions {
                    dict.removeValue(forKey: currentUserId)
                    msg.reactions = dict.isEmpty ? nil : dict
                }
            }
            mergedRemote.append(msg)
        }

        var merged = mergedRemote
        merged.append(contentsOf: pendingOptimistic)
        let sortedMerged = merged.sorted(by: { $0.timestampMs < $1.timestampMs })

        guard sortedMerged != self.messages else { return }

        // Обновляем список сообщений мгновенно и нативно
        self.messages = sortedMerged

        let chatId = repo.getOrCreateChatId(peerUserId: peerUser.id)
        await repo.markMessagesAsRead(chatId: chatId, peerUserId: peerUser.id, messages: sortedMerged)
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
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                if Task.isCancelled { break }
                let chatId = repo.getOrCreateChatId(peerUserId: peerUser.id)

                async let fetchMsg = repo.fetchMessages(chatId: chatId)
                async let fetchPresence = UserPresenceService.shared.fetchUserPresence(userId: peerUser.id)
                async let fetchTyping = UserPresenceService.shared.isPeerTyping(chatId: chatId, peerUserId: peerUser.id)

                let (list, presence, typing) = await (fetchMsg, fetchPresence, fetchTyping)

                if Task.isCancelled { break }

                await syncMessages(remoteList: list)

                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.livePresence = presence
                        self.isPeerTyping = typing
                    }
                }
            }
        }
    }

    private func sendMessage() {
        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let chatId = repo.getOrCreateChatId(peerUserId: peerUser.id)
        UserPresenceService.shared.clearTyping(chatId: chatId)

        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        // Handle editing an existing message
        if let editing = editingMessage {
            editingMessage = nil
            messageText = ""
            isSending = false

            var updatedMsg = editing
            updatedMsg.text = trimmed
            updatedMsg.isEdited = true

            if let idx = self.messages.firstIndex(where: { $0.id == editing.id }) {
                self.messages[idx] = updatedMsg
            }

            Task {
                _ = await repo.postMessageToFirebase(chatId: chatId, message: updatedMsg, peerUser: peerUser)
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

        // Добавляем на UI мгновенно за 0мс без мигания и скачков
        self.messages.append(optimisticMessage)

        Task {
            _ = await repo.sendMessage(toPeerUser: peerUser, message: optimisticMessage)
        }
    }

    private func addReaction(_ emoji: String, to msg: ChatMessage) {
        guard let myId = AuthRepository.shared.currentUser?.id else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        var newReactions = msg.reactions ?? [:]
        if newReactions[myId] == emoji {
            newReactions.removeValue(forKey: myId)
        } else {
            newReactions[myId] = emoji
        }

        let updatedMsg = ChatMessage(
            id: msg.id,
            senderId: msg.senderId,
            receiverId: msg.receiverId,
            type: msg.type,
            text: msg.text,
            media: msg.media,
            timestampMs: msg.timestampMs,
            replyToId: msg.replyToId,
            reactions: newReactions.isEmpty ? nil : newReactions,
            isEdited: msg.isEdited,
            isRead: msg.isRead
        )

        // МГНОВЕННОЕ обновление на UI за 0мс с плавной нативной анимацией
        if let idx = self.messages.firstIndex(where: { $0.id == msg.id }) {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                self.messages[idx] = updatedMsg
            }
        }

        let chatId = repo.getOrCreateChatId(peerUserId: peerUser.id)
        repo.saveMessagesToDisk(self.messages, chatId: chatId)

        Task {
            _ = await repo.toggleChatMessageReaction(chatId: chatId, messageId: msg.id, emoji: emoji)
            _ = await repo.postMessageToFirebase(chatId: chatId, message: updatedMsg)
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
                            .transition(.scale(scale: 0.01, anchor: isFromMe ? .bottomTrailing : .bottomLeading).combined(with: .opacity))
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
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
                }

                // Text content
                if let text = message.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
                        Label("Скопировать", systemImage: "doc.on.doc")
                    }
                }

                if isFromMe {
                    Button {
                        onEdit(message)
                    } label: {
                        Label("Редактировать", systemImage: "pencil")
                    }
                }

                Button(role: .destructive) {
                    onDelete(message)
                } label: {
                    Label("Удалить у всех", systemImage: "trash")
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
        let currentUserId = AuthRepository.shared.currentUser?.id ?? ""
        HStack(spacing: 4) {
            ForEach(grouped.map { ($0.key, $0.value.count) }, id: \.0) { emoji, count in
                let isMyReaction = (reactionsDict[currentUserId] == emoji)
                Button {
                    onReact(emoji, message)
                } label: {
                    HStack(spacing: 3) {
                        Text(emoji)
                            .font(.system(size: 12.5))
                        if count > 1 {
                            Text("\(count)")
                                .font(.system(size: 11.5, weight: .bold))
                                .foregroundColor(isMyReaction ? .black : .primary)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(
                        isMyReaction ? Color.slooshAccent : Color(UIColor.secondarySystemGroupedBackground)
                    )
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(
                                isMyReaction ? Color.slooshAccent : Color(UIColor.separator).opacity(0.4),
                                lineWidth: 0.8
                            )
                    )
                    .shadow(color: Color.black.opacity(0.08), radius: 2, x: 0, y: 1)
                }
                .buttonStyle(PeakPressButtonStyle())
                .transition(.scale(scale: 0.01, anchor: .center).combined(with: .opacity))
            }
        }
        .offset(y: 10)
        .padding(.horizontal, 8)
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: reactionsDict)
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
    @State private var livePresence: (isOnline: Bool, lastSeenMs: Int64?)
    @State private var pollTask: Task<Void, Never>? = nil

    public init(peerUser: SlooshUser) {
        self.peerUser = peerUser
        let cached = UserPresenceService.shared.getCachedPresence(userId: peerUser.id) ?? (peerUser.isCurrentlyOnline, peerUser.lastSeenMs)
        _livePresence = State(initialValue: cached)
    }

    public var body: some View {
        List {
            // Header Section: Avatar + Name + Live Status
            Section {
                VStack(spacing: 12) {
                    let isOnline = livePresence.isOnline
                    SlooshAvatarView(
                        avatarSource: peerUser.avatarUrl,
                        fallbackText: peerUser.displayTitle,
                        size: 96,
                        showOnline: true,
                        isOnline: isOnline
                    )

                    VStack(spacing: 4) {
                        Text(peerUser.displayTitle)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.primary)

                        let statusText = PresenceFormatter.formatLastSeen(isOnlineFlag: isOnline, lastSeenMs: livePresence.lastSeenMs)

                        Text(statusText)
                            .font(.system(size: 14, weight: isOnline ? .semibold : .regular))
                            .foregroundColor(isOnline ? Color.slooshAccent : .secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            // Info Section: Tag
            if !peerUser.displayTag.isEmpty {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "at")
                            .foregroundStyle(Color.slooshAccent)
                            .font(.system(size: 18))
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Тег пользователя")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(peerUser.displayTag)
                                .font(.body)
                                .foregroundColor(.primary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }

            // Actions Section: Delete Chat
            Section {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "trash.fill")
                            .foregroundStyle(Color.red)
                            .font(.system(size: 18))
                            .frame(width: 24)

                        Text("Удалить чат")
                            .font(.body)
                            .foregroundColor(.red)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Информация")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let presence = await UserPresenceService.shared.fetchUserPresence(userId: peerUser.id)
            self.livePresence = presence

            pollTask?.cancel()
            pollTask = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    if Task.isCancelled { break }
                    let fresh = await UserPresenceService.shared.fetchUserPresence(userId: peerUser.id)
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            self.livePresence = fresh
                        }
                    }
                }
            }
        }
        .onDisappear {
            pollTask?.cancel()
        }
        .confirmationDialog(
            "Удалить чат с \(peerUser.displayTitle)?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Удалить чат", role: .destructive) {
                let chatId = repo.getOrCreateChatId(peerUserId: peerUser.id)
                Task {
                    _ = await repo.deleteChat(chatId: chatId, peerUserId: peerUser.id, deleteForEveryone: true)
                }
                dismiss()
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("История сообщений и диалог будут удалены.")
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
