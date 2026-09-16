import SwiftUI
import UIKit

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
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme

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
                    inputBar
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
            PlayerView(config: config)
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
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && activePlayerConfig == nil {
                startPolling()
            } else {
                pollTask?.cancel()
            }
        }
        .onChange(of: activePlayerConfig != nil) { _, isPlaying in
            if isPlaying {
                pollTask?.cancel()
            } else if scenePhase == .active {
                startPolling()
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
                                .foregroundColor(.secondary)
                        }
                        .transition(.opacity)
                    } else {
                        let online = livePresence.isOnline || (peerUser.isCurrentlyOnline && livePresence.lastSeenMs == nil)
                        let lastSeen = livePresence.lastSeenMs ?? peerUser.lastSeenMs
                        let statusText = PresenceFormatter.formatLastSeen(isOnlineFlag: online, lastSeenMs: lastSeen)

                        Text(statusText)
                            .font(.system(size: 12, weight: online ? .medium : .regular))
                            .foregroundColor(online ? .primary : .secondary)
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
                                    peerUser: peerUser,
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
                                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                            replyingMessage = msg
                                            editingMessage = nil
                                        }
                                        isInputFocused = true
                                    },
                                    onEdit: { msg in
                                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                            editingMessage = msg
                                            replyingMessage = nil
                                            messageText = msg.text ?? ""
                                        }
                                        isInputFocused = true
                                    },
                                    onDelete: { msg in
                                        deleteMessage(msg)
                                    },
                                    onReact: { emoji, msg in
                                        addReaction(emoji, to: msg)
                                    },
                                    onRetry: { msg in
                                        retryMessage(msg)
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
                .onChange(of: messages.count) { oldCount, newCount in
                    if newCount > oldCount, let lastId = messages.last?.id {
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
        return true
    }

    // MARK: - Animated Telegram Style Input Bar (iOS 26+ Liquid Glass)

    private var hasTextToSending: Bool {
        !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isMultilineInput: Bool {
        messageText.contains("\n") || messageText.count > 32
    }

    private var isExpandedInput: Bool {
        isMultilineInput || replyingMessage != nil || editingMessage != nil
    }

    private var inputBarCornerRadius: CGFloat {
        isExpandedInput ? 20 : 22
    }

    private var deviceBottomSafeArea: CGFloat {
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.compactMap { $0 as? UIWindowScene }.first(where: { $0.activationState == .foregroundActive })
            ?? scenes.compactMap { $0 as? UIWindowScene }.first
        let keyWindow = windowScene?.windows.first(where: { $0.isKeyWindow })
            ?? windowScene?.windows.first
        let bottom = keyWindow?.safeAreaInsets.bottom ?? 34
        return bottom > 0 ? bottom : 34
    }

    private var collapsedHorizontalPadding: CGFloat {
        deviceBottomSafeArea + 2
    }

    private var inputBarHorizontalPadding: CGFloat {
        isInputFocused ? 6 : collapsedHorizontalPadding
    }

    private var inputBarVerticalPadding: CGFloat {
        isInputFocused ? 8 : 2
    }

    private func replyHeaderTitle(for msg: ChatMessage) -> String {
        if msg.senderId == peerUser.id {
            return "В ответ \(peerUser.displayTitle)"
        } else {
            return "В ответ себе"
        }
    }

    private func replyPreviewText(for msg: ChatMessage) -> String {
        if let text = msg.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
        if msg.type == .media, let media = msg.media {
            return media.title
        }
        return "Медиа"
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // Floating Glass Text Field Capsule / Morphing Box (Telegram-style inline reply/edit)
            VStack(alignment: .leading, spacing: 6) {
                // 1. Inline Reply Preview
                if let replying = replyingMessage {
                    HStack(spacing: 8) {
                        Capsule()
                            .fill(colorScheme == .dark ? Color.white : Color.primary)
                            .frame(width: 2.5, height: 32)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(replyHeaderTitle(for: replying))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .white : .primary)
                                .lineLimit(1)

                            Text(replyPreviewText(for: replying))
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 4)

                        Button {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                replyingMessage = nil
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.secondary)
                                .padding(6)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 2)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .bottom)),
                        removal: .opacity.combined(with: .move(edge: .bottom))
                    ))
                }
                // 2. Inline Edit Preview
                else if let editing = editingMessage {
                    HStack(spacing: 8) {
                        Capsule()
                            .fill(colorScheme == .dark ? Color.white : Color.primary)
                            .frame(width: 2.5, height: 32)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Редактирование")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .white : .primary)
                                .lineLimit(1)

                            Text(editing.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? (editing.text ?? "") : "Сообщение")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 4)

                        Button {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                editingMessage = nil
                                messageText = ""
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.secondary)
                                .padding(6)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 2)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .bottom)),
                        removal: .opacity.combined(with: .move(edge: .bottom))
                    ))
                }

                // 3. Text Input Field
                TextField("Сообщение", text: $messageText, axis: .vertical)
                    .font(.system(size: 16))
                    .foregroundColor(.primary)
                    .lineLimit(1...6)
                    .focused($isInputFocused)
                    .frame(minHeight: isExpandedInput ? 24 : 38)
            }
            .padding(.vertical, isExpandedInput ? 8 : 2)
            .padding(.horizontal, 14)
            .glassEffect(
                .regular.interactive(),
                in: RoundedRectangle(cornerRadius: inputBarCornerRadius, style: .continuous)
            )
            .animation(.spring(response: 0.32, dampingFraction: 0.82), value: replyingMessage != nil)
            .animation(.spring(response: 0.32, dampingFraction: 0.82), value: editingMessage != nil)
            .animation(.easeInOut(duration: 0.2), value: isMultilineInput)

            // Telegram-style Animated Sliding/Popping Send Button
            if hasTextToSending {
                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(colorScheme == .dark ? .black : .white)
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(colorScheme == .dark ? Color.white : Color.black)
                        )
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.glassPress)
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
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: replyingMessage != nil)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: editingMessage != nil)
    }

    // MARK: - Actions & Logic

    private func syncMessages(remoteList: [ChatMessage]) async {
        let filteredRemote = remoteList.filter { !repo.isMessageDeletedLocally($0.id) }
        let currentUserId = AuthRepository.shared.currentUser?.id ?? ""
        let chatId = repo.getOrCreateChatId(peerUserId: peerUser.id)

        // 1. Сохраняем свежие оптимистичные сообщения (только если не удалены локально!)
        let pendingLocals = self.messages.filter { local in
            local.senderId == currentUserId &&
            !repo.isMessageDeletedLocally(local.id) &&
            (local.deliveryStatus == .sending || local.deliveryStatus == .failed || repo.isMessageInOutbox(chatId: chatId, messageId: local.id)) &&
            !filteredRemote.contains(where: { $0.id == local.id })
        }

        // 2. Умное слияние реакций и статуса доставки
        var mergedRemote: [ChatMessage] = []
        for remoteMsg in filteredRemote {
            var msg = remoteMsg
            if let localMsg = self.messages.first(where: { $0.id == remoteMsg.id }) {
                if msg.deliveryStatus == nil {
                    msg.deliveryStatus = localMsg.deliveryStatus ?? .sent
                }
                if let localReactions = localMsg.reactions, let myEmoji = localReactions[currentUserId] {
                    var dict = remoteMsg.reactions ?? [:]
                    dict[currentUserId] = myEmoji
                    msg.reactions = dict
                } else if let localReactions = localMsg.reactions, localReactions[currentUserId] == nil, var dict = remoteMsg.reactions {
                    dict.removeValue(forKey: currentUserId)
                    msg.reactions = dict.isEmpty ? nil : dict
                }
            } else if msg.deliveryStatus == nil {
                msg.deliveryStatus = .sent
            }
            mergedRemote.append(msg)
        }

        var merged = mergedRemote
        merged.append(contentsOf: pendingLocals)
        let sortedMerged = merged.sorted(by: { $0.timestampMs < $1.timestampMs || ($0.timestampMs == $1.timestampMs && $0.id < $1.id) })

        guard sortedMerged != self.messages else { return }

        // Обновляем список сообщений мгновенно и нативно
        self.messages = sortedMerged

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
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                if Task.isCancelled { break }
                let chatId = repo.getOrCreateChatId(peerUserId: peerUser.id)

                async let fetchMsg = repo.fetchMessages(chatId: chatId)
                async let fetchPresence = UserPresenceService.shared.fetchUserPresence(userId: peerUser.id)
                async let fetchTyping = UserPresenceService.shared.isPeerTyping(chatId: chatId, peerUserId: peerUser.id)

                let (list, presence, typing) = await (fetchMsg, fetchPresence, fetchTyping)

                if Task.isCancelled { break }

                await syncMessages(remoteList: list)

                await MainActor.run {
                    if self.livePresence.isOnline != presence.isOnline || self.livePresence.lastSeenMs != presence.lastSeenMs || self.isPeerTyping != typing {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            self.livePresence = presence
                            self.isPeerTyping = typing
                        }
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
        let monotonicTs = repo.generateMonotonicTimestamp()

        // Оптимистичное создание сообщения за 0мс с единым стабильным ID и монотонным временем!
        let optimisticMessage = ChatMessage(
            senderId: currentUserId,
            receiverId: peerUser.id,
            type: .text,
            text: trimmed,
            timestampMs: monotonicTs,
            replyToId: replyId,
            isRead: false,
            deliveryStatus: .sending
        )

        messageText = ""
        replyingMessage = nil
        editingMessage = nil
        isSending = false

        // Добавляем на UI мгновенно за 0мс без мигания и скачков
        self.messages.append(optimisticMessage)
        self.messages.sort { $0.timestampMs < $1.timestampMs || ($0.timestampMs == $1.timestampMs && $0.id < $1.id) }

        Task {
            _ = await repo.sendMessage(toPeerUser: peerUser, message: optimisticMessage)
        }
    }

    private func retryMessage(_ msg: ChatMessage) {
        let chatId = repo.getOrCreateChatId(peerUserId: peerUser.id)
        if let idx = self.messages.firstIndex(where: { $0.id == msg.id }) {
            self.messages[idx].deliveryStatus = .sending
        }
        Task {
            await repo.retrySendMessage(chatId: chatId, messageId: msg.id, peerUser: peerUser)
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
        repo.markMessageAsDeletedLocally(msg.id)
        withAnimation(.easeInOut(duration: 0.22)) {
            self.messages.removeAll(where: { $0.id == msg.id })
        }
        let chatId = repo.getOrCreateChatId(peerUserId: peerUser.id)
        repo.saveMessagesToDisk(self.messages, chatId: chatId)
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

// MARK: - Adaptive Monochrome Messenger Theme Colors

private let outgoingBubbleColor = Color(UIColor { trait in
    trait.userInterfaceStyle == .dark
        ? UIColor(red: 0.20, green: 0.20, blue: 0.21, alpha: 1.0)
        : UIColor(red: 0.88, green: 0.88, blue: 0.90, alpha: 1.0)
})

private let incomingBubbleColor = Color(UIColor { trait in
    trait.userInterfaceStyle == .dark
        ? UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1.0)
        : UIColor.systemBackground
})

private let activeReactionBgColor = Color(UIColor { trait in
    trait.userInterfaceStyle == .dark
        ? UIColor(white: 0.32, alpha: 1.0)
        : UIColor(red: 0.88, green: 0.88, blue: 0.90, alpha: 1.0)
})

private let inactiveReactionBgColor = Color(UIColor { trait in
    trait.userInterfaceStyle == .dark
        ? UIColor(white: 0.16, alpha: 0.95)
        : UIColor.systemBackground
})

// MARK: - Peak Message Bubble View (Adaptive Theme + Minute Grouping)

private struct PeakMessageBubbleView: View {
    let message: ChatMessage
    let peerUser: SlooshUser
    let isFromMe: Bool
    let showMeta: Bool
    let allMessages: [ChatMessage]
    let onOpenMovie: (String) -> Void
    let onPlayDirectly: (MediaCardPayload) -> Void
    let onReply: (ChatMessage) -> Void
    let onEdit: (ChatMessage) -> Void
    let onDelete: (ChatMessage) -> Void
    let onReact: (String, ChatMessage) -> Void
    let onRetry: ((ChatMessage) -> Void)?

    @State private var showReactionPicker: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    private var outgoingTextColor: Color {
        colorScheme == .dark ? .white : .primary
    }

    private var outgoingMetaColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.65) : .secondary
    }

    private var outgoingReadCheckmarkColor: Color {
        colorScheme == .dark ? .white : .primary
    }

    private var repliedMessage: ChatMessage? {
        if let replyToId = message.replyToId {
            return allMessages.first(where: { $0.id == replyToId })
        }
        return nil
    }

    private var repliedAuthorTitle: String {
        guard let replied = repliedMessage else { return "Ответ" }
        if replied.senderId == peerUser.id {
            return peerUser.displayTitle
        } else {
            return "Вы"
        }
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
                            .fill(isFromMe ? (colorScheme == .dark ? Color.white.opacity(0.6) : Color.primary.opacity(0.35)) : Color.primary.opacity(0.35))
                            .frame(width: 2)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(repliedAuthorTitle)
                                .font(.system(size: 11.5, weight: .bold))
                                .foregroundColor(isFromMe ? outgoingTextColor : .primary)
                                .lineLimit(1)
                            Text(replied.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? (replied.text ?? "") : (replied.type == .media ? (replied.media?.title ?? "Медиа") : "Медиа"))
                                .font(.system(size: 13))
                                .foregroundColor(isFromMe ? outgoingMetaColor : .secondary)
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
                        .foregroundColor(isFromMe ? outgoingTextColor : .primary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(isFromMe ? outgoingBubbleColor : incomingBubbleColor)
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
                .foregroundColor(isFromMe ? outgoingMetaColor : .secondary)

            if isFromMe {
                switch message.deliveryStatus {
                case .sending:
                    Image(systemName: "clock")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(outgoingMetaColor)
                case .failed:
                    Button {
                        onRetry?(message)
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.red)
                            Text("Повторить")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.red)
                        }
                    }
                    .buttonStyle(.plain)
                case .sent, .none:
                    Image(systemName: message.isRead == true ? "checkmark.circle.fill" : "checkmark.circle")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(message.isRead == true ? outgoingReadCheckmarkColor : outgoingMetaColor)
                }
            }

            if message.isEdited == true {
                Text("изм.")
                    .font(.system(size: 11))
                    .foregroundColor(isFromMe ? outgoingMetaColor : .secondary)
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
                                .foregroundColor(.primary)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(
                        Capsule().fill(isMyReaction ? activeReactionBgColor : inactiveReactionBgColor)
                    )
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
                        size: 104,
                        showOnline: true,
                        isOnline: isOnline
                    )

                    VStack(spacing: 4) {
                        Text(peerUser.displayTitle)
                            .font(.system(size: 25, weight: .bold))
                            .foregroundColor(.primary)

                        let statusText = PresenceFormatter.formatLastSeen(isOnlineFlag: isOnline, lastSeenMs: livePresence.lastSeenMs)

                        Text(statusText)
                            .font(.system(size: 15, weight: isOnline ? .semibold : .regular))
                            .foregroundColor(isOnline ? .primary : .secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
                .padding(.bottom, 6)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            // Info Section: Tag
            if !peerUser.displayTag.isEmpty {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "at")
                            .foregroundStyle(Color.primary)
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
