import SwiftUI

public struct ChannelDetailView: View {
    public let channel: ChannelModel

    @ObservedObject private var authRepo = AuthRepository.shared
    @ObservedObject private var repo = MessengerRepository.shared
    @Environment(\.dismiss) private var dismiss

    @State private var posts: [ChannelPost] = []
    @State private var inputText: String = ""
    @State private var attachedMedia: MediaCardPayload? = nil
    @State private var editingPost: ChannelPost? = nil
    @State private var showMovieSelector: Bool = false
    @State private var isShowingInfo: Bool = false
    @State private var isMuted: Bool = false

    @State private var selectedMovieIdForDetails: String? = nil
    @State private var selectedMediaForDirectPlay: MediaCardPayload? = nil
    @State private var pendingPlayerConfig: PlayerConfig? = nil
    @State private var activePlayerConfig: PlayerConfig? = nil

    @State private var postToDelete: ChannelPost? = nil
    @State private var showDeletePostAlert: Bool = false
    @State private var pollTask: Task<Void, Never>? = nil

    public init(channel: ChannelModel) {
        self.channel = channel
    }

    private var isOwner: Bool {
        guard let currentUserId = authRepo.currentUser?.id else { return false }
        return channel.ownerId == currentUserId
    }

    private var isSubscribed: Bool {
        repo.isSubscribed(channelId: channel.id)
    }

    private var currentUserId: String {
        authRepo.currentUser?.id ?? ""
    }

    private var pinnedPost: ChannelPost? {
        if let pinnedId = channel.pinnedPostId, let found = posts.first(where: { $0.id == pinnedId }) {
            return found
        }
        return posts.first(where: { $0.isPinned })
    }

    public var body: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                // Posts Feed with ScrollViewReader
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            // Pinned Post Floating Bar
                            if let pinned = pinnedPost {
                                PinnedPostBar(
                                    post: pinned,
                                    onTap: { postId in
                                        withAnimation(.easeInOut(duration: 0.3)) {
                                            proxy.scrollTo(postId, anchor: .center)
                                        }
                                    },
                                    onUnpin: isOwner ? {
                                        Task {
                                            _ = await repo.togglePinChannelPost(channelId: channel.id, postId: pinned.id, isPinned: false)
                                            await loadPosts()
                                        }
                                    } : nil
                                )
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                            }

                            if posts.isEmpty {
                                emptyStateView
                                    .padding(.top, 60)
                            } else {
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

                            // Bottom spacing so content is never hidden behind floating bars
                            Spacer()
                                .frame(height: isOwner ? 100 : 90)
                        }
                        .padding(.top, 8)
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

                // Bottom Control / Composer Overlay
                if isOwner {
                    authorBroadcastingBar
                } else {
                    subscriberActionBar
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                channelHeaderTitle
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    isShowingInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.primary)
                }
            }
        }
        .toolbarVisibility(.hidden, for: .tabBar)
        .sheet(isPresented: $showMovieSelector) {
            MovieSelectorSheet { payload in
                self.attachedMedia = payload
            }
        }
        .navigationDestination(isPresented: $isShowingInfo) {
            ChannelInfoView(channel: channel)
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
        .alert("Удалить публикацию?", isPresented: $showDeletePostAlert) {
            Button("Отмена", role: .cancel) {
                postToDelete = nil
            }
            Button("Удалить", role: .destructive) {
                if let post = postToDelete {
                    deletePost(post)
                }
            }
        } message: {
            Text("Публикация будет удалена из канала для всех подписчиков.")
        }
        .task {
            let cached = repo.loadChannelPostsFromDisk(channelId: channel.id)
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

    // MARK: - Toolbar Header

    private var channelHeaderTitle: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            isShowingInfo = true
        } label: {
            VStack(spacing: 2) {
                HStack(spacing: 6) {
                    Text(channel.displayAvatarEmoji)
                        .font(.system(size: 16))
                    Text(channel.name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }

                Text(channel.formattedSubscriberCount)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Circle()
                .fill(channel.displayAccentColor.opacity(0.15))
                .frame(width: 80, height: 80)
                .overlay(
                    Text(channel.displayAvatarEmoji)
                        .font(.system(size: 40))
                )

            Text("В канале пока нет публикаций")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.primary)

            Text(isOwner ? "Опубликуйте первую запись или прикрепите фильм для ваших подписчиков." : "Автор канала скоро опубликует новые материалы.")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Author Broadcasting Bar

    private var authorBroadcastingBar: some View {
        VStack(spacing: 6) {
            // Editing post banner
            if let editing = editingPost {
                HStack(spacing: 8) {
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color.slooshAccent)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Редактирование публикации")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color.slooshAccent)
                        Text(editing.text ?? (editing.media?.title ?? "Медиа"))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    Button {
                        cancelEditing()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 16)
            }

            // Attached Media Preview Chip
            if let media = attachedMedia {
                HStack(spacing: 10) {
                    Image(systemName: "film.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color.slooshAccent)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(media.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        HStack(spacing: 6) {
                            if let year = media.year {
                                Text(year)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            if let rating = media.rating, rating > 0 {
                                Text(String(format: "★ %.1f", rating))
                                    .font(.system(size: 11, weight: .heavy))
                                    .foregroundColor(Color.slooshAccent)
                            }
                        }
                    }

                    Spacer(minLength: 0)

                    Button {
                        withAnimation {
                            self.attachedMedia = nil
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 16)
            }

            // Main Composing Input
            HStack(spacing: 8) {
                // Attach Movie Button
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showMovieSelector = true
                } label: {
                    Image(systemName: attachedMedia == nil ? "film.badge.plus" : "film.stack.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(attachedMedia == nil ? .secondary : Color.slooshAccent)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.06))
                        )
                        .glassEffect(.regular.interactive(), in: Circle())
                }
                .buttonStyle(.plain)

                // Text Input Field
                TextField("Транслировать в канал...", text: $inputText, axis: .vertical)
                    .font(.system(size: 15))
                    .foregroundColor(.primary)
                    .lineLimit(1...5)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.06))
                    )
                    .glassEffect(.regular.interactive(), in: Capsule())

                // Send / Save Button
                let canSend = !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || attachedMedia != nil
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    submitPost()
                } label: {
                    Image(systemName: editingPost != nil ? "checkmark" : "arrow.up")
                        .font(.system(size: 15, weight: .black))
                        .foregroundColor(canSend ? .black : .secondary)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(canSend ? Color.slooshAccent : Color.white.opacity(0.08))
                        )
                        .glassEffect(in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Rectangle()
                    .fill(Color(UIColor.systemGroupedBackground).opacity(0.85))
            )
            .glassEffect(.regular.interactive(), in: Rectangle())
        }
    }

    // MARK: - Subscriber Action Bar

    private var subscriberActionBar: some View {
        HStack(spacing: 12) {
            // Subscribe / Unsubscribe Button
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                Task {
                    if isSubscribed {
                        _ = await repo.unsubscribeFromChannel(channelId: channel.id)
                    } else {
                        _ = await repo.subscribeToChannel(channel: channel)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isSubscribed ? "checkmark.circle.fill" : "plus.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                    Text(isSubscribed ? "Вы подписаны" : "Подписаться")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundColor(isSubscribed ? .primary : .black)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    Capsule()
                        .fill(isSubscribed ? Color.white.opacity(0.08) : Color.slooshAccent)
                )
                .glassEffect(in: Capsule())
            }
            .buttonStyle(.plain)

            // Mute / Unmute Toggle Button
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation {
                    isMuted.toggle()
                }
            } label: {
                Image(systemName: isMuted ? "bell.slash.fill" : "bell.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(isMuted ? .secondary : Color.slooshAccent)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.08))
                    )
                    .glassEffect(.regular.interactive(), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Rectangle()
                .fill(Color(UIColor.systemGroupedBackground).opacity(0.85))
        )
        .glassEffect(.regular.interactive(), in: Rectangle())
    }

    // MARK: - Post Actions & Logic

    private func loadPosts() async {
        let fetched = await repo.fetchChannelPosts(channelId: channel.id)
        if !fetched.isEmpty || posts.isEmpty {
            self.posts = fetched
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if Task.isCancelled { break }
                let updated = await repo.fetchChannelPosts(channelId: channel.id)
                if !Task.isCancelled && !updated.isEmpty {
                    self.posts = updated
                }
            }
        }
    }

    private func submitPost() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let media = attachedMedia

        if let editing = editingPost {
            // Edit existing post
            Task {
                _ = await repo.editChannelPost(
                    channelId: channel.id,
                    postId: editing.id,
                    newText: trimmed.isEmpty ? nil : trimmed,
                    mediaPayload: media
                )
                cancelEditing()
                await loadPosts()
            }
        } else {
            // Publish new post
            Task {
                _ = await repo.publishChannelPost(
                    channelId: channel.id,
                    text: trimmed.isEmpty ? nil : trimmed,
                    mediaPayload: media,
                    isPinned: false
                )
                inputText = ""
                attachedMedia = nil
                await loadPosts()
            }
        }
    }

    private func startEditing(post: ChannelPost) {
        self.editingPost = post
        self.inputText = post.text ?? ""
        self.attachedMedia = post.media
    }

    private func cancelEditing() {
        self.editingPost = nil
        self.inputText = ""
        self.attachedMedia = nil
    }

    private func togglePin(post: ChannelPost) {
        let newPinState = !post.isPinned
        Task {
            _ = await repo.togglePinChannelPost(
                channelId: channel.id,
                postId: post.id,
                isPinned: newPinState
            )
            await loadPosts()
        }
    }

    private func toggleReaction(emoji: String, on post: ChannelPost) {
        Task {
            _ = await repo.toggleChannelPostReaction(
                channelId: channel.id,
                postId: post.id,
                emoji: emoji
            )
            await loadPosts()
        }
    }

    private func deletePost(_ post: ChannelPost) {
        Task {
            _ = await repo.deleteChannelPost(channelId: channel.id, postId: post.id)
            postToDelete = nil
            await loadPosts()
        }
    }
}

