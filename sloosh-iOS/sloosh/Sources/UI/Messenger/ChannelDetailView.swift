import SwiftUI

public struct ChannelDetailView: View {
    public let channel: ChannelModel

    @ObservedObject private var authRepo = AuthRepository.shared
    @ObservedObject private var repo = MessengerRepository.shared
    @Environment(\.dismiss) private var dismiss

    @State private var currentChannel: ChannelModel
    @State private var posts: [ChannelPost] = []
    @State private var inputText: String = ""
    @State private var attachedMedia: MediaCardPayload? = nil
    @State private var editingPost: ChannelPost? = nil
    @State private var showMovieSelector: Bool = false
    @State private var isShowingInfo: Bool = false
    @State private var isMuted: Bool = false
    @State private var isSending: Bool = false

    @State private var selectedMovieIdForDetails: String? = nil
    @State private var selectedMediaForDirectPlay: MediaCardPayload? = nil
    @State private var pendingPlayerConfig: PlayerConfig? = nil
    @State private var activePlayerConfig: PlayerConfig? = nil

    @State private var postToDelete: ChannelPost? = nil
    @State private var showDeletePostAlert: Bool = false
    @State private var pollTask: Task<Void, Never>? = nil

    @FocusState private var isInputFocused: Bool

    public init(channel: ChannelModel) {
        self.channel = channel
        self._currentChannel = State(initialValue: channel)
    }

    private var isOwner: Bool {
        guard let currentUserId = authRepo.currentUser?.id else { return false }
        return currentChannel.ownerId == currentUserId
    }

    private var isSubscribed: Bool {
        repo.isSubscribed(channelId: currentChannel.id)
    }

    private var currentUserId: String {
        authRepo.currentUser?.id ?? ""
    }

    private var pinnedPost: ChannelPost? {
        if let pinnedId = currentChannel.pinnedPostId, let found = posts.first(where: { $0.id == pinnedId }) {
            return found
        }
        return posts.first(where: { $0.isPinned })
    }

    private var isMultilineInput: Bool {
        inputText.contains("\n") || inputText.count > 32
    }

    private var hasTextToSending: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || attachedMedia != nil
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

    public var body: some View {
        ZStack {
            // Native grouped background matching ChatDetailView
            Color(UIColor.systemGroupedBackground).ignoresSafeArea()

            postsFeed
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 0) {
                        // Attached Media Card Banner
                        if let media = attachedMedia {
                            HStack(spacing: 8) {
                                Image(systemName: "film")
                                    .foregroundColor(Color.slooshAccent)
                                Text(media.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .lineLimit(1)
                                Spacer()
                                Button {
                                    attachedMedia = nil
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color(UIColor.secondarySystemGroupedBackground))
                        }
                        // Edit post banner
                        else if let editing = editingPost {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Редактирование поста")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(Color.slooshAccent)
                                    Text(editing.text ?? "Медиа пост")
                                        .font(.system(size: 13))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Button {
                                    cancelEditing()
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color(UIColor.secondarySystemGroupedBackground))
                        }

                        if isOwner {
                            authorBroadcastingBar
                        } else {
                            subscriberActionBar
                        }
                    }
                }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button {
                    isShowingInfo = true
                } label: {
                    VStack(spacing: 1) {
                        Text(currentChannel.name)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Text(currentChannel.displayTag)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    isShowingInfo = true
                } label: {
                    SlooshAvatarView(
                        avatarSource: currentChannel.avatarUrl,
                        fallbackText: currentChannel.name,
                        size: 34,
                        isChannel: true
                    )
                }
                .buttonStyle(PeakPressButtonStyle())
            }
        }
        .toolbarVisibility(.hidden, for: .tabBar)
        .navigationDestination(isPresented: $isShowingInfo) {
            ChannelInfoView(channel: currentChannel)
        }
        .navigationDestination(item: $selectedMovieIdForDetails) { movieId in
            DetailsView(movieId: movieId, navigationTransitionID: nil, navigationTransitionNamespace: nil)
        }
        .sheet(isPresented: $showMovieSelector) {
            MovieSelectorSheet { selected in
                self.attachedMedia = selected
            }
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
        .confirmationDialog(
            "Удалить пост?",
            isPresented: $showDeletePostAlert,
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) {
                if let p = postToDelete {
                    deletePostAction(p)
                }
            }
            Button("Отмена", role: .cancel) {}
        }
        .task {
            let cached = repo.loadChannelPostsFromDisk(channelId: currentChannel.id)
            if !cached.isEmpty {
                self.posts = cached
            }
            await loadPosts()
            startPolling()
        }
        .onDisappear {
            pollTask?.cancel()
        }
    }

    // MARK: - Posts Feed

    private var postsFeed: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    // Pinned Post Floating Bar
                    if let pinned = pinnedPost {
                        PinnedPostBar(
                            post: pinned,
                            onTap: { postId in
                                withAnimation {
                                    proxy.scrollTo(postId, anchor: .center)
                                }
                            },
                            onUnpin: isOwner ? {
                                Task {
                                    _ = await repo.togglePinChannelPost(channelId: currentChannel.id, postId: pinned.id, isPinned: false)
                                    await loadPosts()
                                }
                            } : nil
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                    }

                    if posts.isEmpty {
                        emptyStateView
                            .padding(.top, 60)
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(posts) { post in
                                ChannelPostRowView(
                                    post: post,
                                    isAuthor: isOwner,
                                    currentUserId: currentUserId,
                                    onOpenDetails: { movieId in
                                        selectedMovieIdForDetails = movieId
                                    },
                                    onPlayDirectly: { media in
                                        selectedMediaForDirectPlay = media
                                    },
                                    onToggleReaction: { emoji in
                                        toggleReaction(emoji: emoji, on: post)
                                    },
                                    onEditPost: {
                                        startEditing(post: post)
                                    },
                                    onTogglePin: {
                                        togglePin(post: post)
                                    },
                                    onDeletePost: {
                                        postToDelete = post
                                        showDeletePostAlert = true
                                    }
                                )
                                .id(post.id)
                            }
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 16)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: posts.count) { _, _ in
                if let lastPost = posts.last {
                    withAnimation {
                        proxy.scrollTo(lastPost.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Author Broadcasting Bar

    private var authorBroadcastingBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // Attach Movie Button
            Button {
                showMovieSelector = true
            } label: {
                ZStack {
                    Circle()
                        .fill(attachedMedia != nil ? Color.slooshAccent : Color.primary.opacity(0.08))
                        .frame(width: 40, height: 40)

                    Image(systemName: "film.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(attachedMedia != nil ? .black : .primary)
                }
                .glassEffect(.regular.interactive(), in: Circle())
            }
            .buttonStyle(OpaquePressButtonStyle())

            // Floating Glass Text Field
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Опубликовать пост...", text: $inputText, axis: .vertical)
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

            // Send Button
            if hasTextToSending {
                Button {
                    publishPostAction()
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

    // MARK: - Subscriber Action Bar

    private var subscriberActionBar: some View {
        HStack(spacing: 12) {
            if isSubscribed {
                Button {
                    toggleMuteAction()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isMuted ? "bell.fill" : "bell.slash.fill")
                            .font(.system(size: 15, weight: .semibold))
                        Text(isMuted ? "Включить звук" : "Без звука")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .glassEffect(in: Capsule())
                }
                .buttonStyle(PeakPressButtonStyle())
            } else {
                Button {
                    subscribeAction()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "megaphone.fill")
                            .font(.system(size: 15, weight: .bold))
                        Text("Подписаться")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        Capsule()
                            .fill(Color.slooshAccent)
                    )
                    .glassEffect(in: Capsule())
                }
                .buttonStyle(PeakPressButtonStyle())
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 6)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "megaphone")
                .font(.system(size: 48))
                .foregroundColor(Color.slooshAccent)

            Text("Пока нет постов")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.primary)

            Text(isOwner ? "Опубликуйте ваш первый пост или прикрепите фильм для подписчиков!" : "Автор канала скоро опубликует первые новости!")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    // MARK: - Actions

    private func loadPosts() async {
        let list = await repo.fetchChannelPosts(channelId: currentChannel.id)
        if !list.isEmpty {
            self.posts = list.sorted(by: { $0.timestampMs < $1.timestampMs })
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                if Task.isCancelled { break }
                let list = await repo.fetchChannelPosts(channelId: currentChannel.id)
                let sorted = list.sorted(by: { $0.timestampMs < $1.timestampMs })
                if sorted != self.posts {
                    await MainActor.run {
                        self.posts = sorted
                    }
                }
            }
        }
    }

    private func publishPostAction() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || attachedMedia != nil else { return }

        isSending = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        if let editing = editingPost {
            Task {
                _ = await repo.editChannelPost(
                    channelId: currentChannel.id,
                    postId: editing.id,
                    newText: text,
                    mediaPayload: attachedMedia
                )
                await MainActor.run {
                    self.isSending = false
                    self.inputText = ""
                    self.attachedMedia = nil
                    self.editingPost = nil
                }
                await loadPosts()
            }
        } else {
            let media = attachedMedia
            let postText = text.isEmpty ? nil : text
            Task {
                _ = await repo.publishChannelPost(
                    channelId: currentChannel.id,
                    text: postText,
                    mediaPayload: media
                )
                await MainActor.run {
                    self.isSending = false
                    self.inputText = ""
                    self.attachedMedia = nil
                }
                await loadPosts()
            }
        }
    }

    private func startEditing(post: ChannelPost) {
        editingPost = post
        inputText = post.text ?? ""
        attachedMedia = post.media
        isInputFocused = true
    }

    private func cancelEditing() {
        editingPost = nil
        inputText = ""
        attachedMedia = nil
    }

    private func togglePin(post: ChannelPost) {
        Task {
            _ = await repo.togglePinChannelPost(channelId: currentChannel.id, postId: post.id, isPinned: !post.isPinned)
            await loadPosts()
        }
    }

    private func deletePostAction(_ post: ChannelPost) {
        Task {
            _ = await repo.deleteChannelPost(channelId: currentChannel.id, postId: post.id)
            await loadPosts()
        }
    }

    private func toggleReaction(emoji: String, on post: ChannelPost) {
        Task {
            _ = await repo.toggleChannelPostReaction(channelId: currentChannel.id, postId: post.id, emoji: emoji)
            await loadPosts()
        }
    }

    private func subscribeAction() {
        Task {
            _ = await repo.subscribeToChannel(channel: currentChannel)
        }
    }

    private func toggleMuteAction() {
        isMuted.toggle()
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
