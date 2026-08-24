import SwiftUI

public struct ChannelInfoView: View {
    public let initialChannel: ChannelModel

    @ObservedObject private var authRepo = AuthRepository.shared
    @ObservedObject private var repo = MessengerRepository.shared
    @Environment(\.dismiss) private var dismiss

    @State private var channel: ChannelModel
    @State private var posts: [ChannelPost] = []
    @State private var showEditSheet: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var showUnsubscribeConfirm: Bool = false
    @State private var isMuted: Bool = false

    @State private var selectedMovieIdForDetails: String? = nil
    @State private var selectedMediaForDirectPlay: MediaCardPayload? = nil
    @State private var pendingPlayerConfig: PlayerConfig? = nil
    @State private var activePlayerConfig: PlayerConfig? = nil

    public init(channel: ChannelModel) {
        self.initialChannel = channel
        self._channel = State(initialValue: channel)
    }

    private var isOwner: Bool {
        guard let currentUserId = authRepo.currentUser?.id else { return false }
        return channel.ownerId == currentUserId
    }

    private var isSubscribed: Bool {
        repo.isSubscribed(channelId: channel.id)
    }

    private var pinnedPost: ChannelPost? {
        if let pinnedId = channel.pinnedPostId, let found = posts.first(where: { $0.id == pinnedId }) {
            return found
        }
        return posts.first(where: { $0.isPinned })
    }

    private var sharedMediaList: [MediaCardPayload] {
        var unique: [MediaCardPayload] = []
        var seenIds = Set<String>()
        for post in posts {
            if let media = post.media, !seenIds.contains(media.mediaId) {
                seenIds.insert(media.mediaId)
                unique.append(media)
            }
        }
        return unique
    }

    private var shareURL: URL {
        URL(string: "https://sloosh.app/channel/\(channel.id)") ?? URL(string: "https://sloosh.app")!
    }

    public var body: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // Channel Visual Identity Header
                    headerProfileSection
                        .padding(.top, 16)

                    // Quick Action Buttons
                    quickActionButtonsSection
                        .padding(.horizontal, 16)

                    // Description Section
                    if !channel.description.isEmpty {
                        descriptionSection
                    }

                    // Pinned Post Preview (if available)
                    if let pinned = pinnedPost {
                        pinnedPostSection(pinned)
                    }

                    // Shared Media & Movies Preview (if available)
                    if !sharedMediaList.isEmpty {
                        sharedMediaSection
                    }

                    // Channel Settings & Management Section
                    settingsSection

                    // Destructive Actions (Owner Delete / Subscriber Leave)
                    destructiveActionsSection
                }
                .padding(.bottom, 48)
            }
        }
        .navigationTitle("Информация")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isOwner {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Изм.") {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showEditSheet = true
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color.slooshAccent)
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            EditChannelSheet(channel: channel) { updatedChannel in
                self.channel = updatedChannel
            }
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
        .alert("Удалить канал?", isPresented: $showDeleteConfirm) {
            Button("Отмена", role: .cancel) {}
            Button("Удалить", role: .destructive) {
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                Task {
                    _ = await repo.deleteChannel(channelId: channel.id)
                    dismiss()
                }
            }
        } message: {
            Text("Канал «\(channel.name)» и все его публикации будут безвозвратно удалены для всех пользователей.")
        }
        .alert("Отписаться от канала?", isPresented: $showUnsubscribeConfirm) {
            Button("Отмена", role: .cancel) {}
            Button("Отписаться", role: .destructive) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                Task {
                    _ = await repo.unsubscribeFromChannel(channelId: channel.id)
                    dismiss()
                }
            }
        } message: {
            Text("Вы больше не будете получать обновления и публикации из канала «\(channel.name)».")
        }
        .task {
            self.isMuted = repo.isChannelMuted(channelId: channel.id)
            let cached = repo.loadChannelPostsFromDisk(channelId: channel.id)
            if !cached.isEmpty {
                self.posts = cached
            }
            let fetched = await repo.fetchChannelPosts(channelId: channel.id)
            if !fetched.isEmpty {
                self.posts = fetched
            }
        }
    }

    // MARK: - Header Profile Section

    private var headerProfileSection: some View {
        VStack(spacing: 14) {
            // Avatar with Liquid Glow & Ring
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                channel.displayAccentColor.opacity(0.35),
                                channel.displayAccentColor.opacity(0.08)
                            ],
                            center: .center,
                            startRadius: 20,
                            endRadius: 55
                        )
                    )
                    .frame(width: 104, height: 104)
                    .overlay(
                        Circle()
                            .stroke(channel.displayAccentColor.opacity(0.7), lineWidth: 2.5)
                    )
                    .overlay(
                        Text(channel.displayAvatarEmoji)
                            .font(.system(size: 52))
                    )
                    .shadow(color: channel.displayAccentColor.opacity(0.3), radius: 16, x: 0, y: 6)

                // Channel Megaphone Badge
                Circle()
                    .fill(Color(UIColor.systemBackground))
                    .frame(width: 30, height: 30)
                    .overlay(
                        Circle()
                            .fill(Color.slooshAccent)
                            .frame(width: 26, height: 26)
                            .overlay(
                                Image(systemName: "megaphone.fill")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.black)
                            )
                    )
                    .offset(x: 2, y: 2)
            }

            // Channel Title & Subscriber Count
            VStack(spacing: 6) {
                Text(channel.name)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Text(channel.formattedSubscriberCount)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.secondary)

                // Owner Badge
                HStack(spacing: 6) {
                    Image(systemName: isOwner ? "crown.fill" : "person.badge.shield.checkmark.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color.slooshAccent)
                    Text("Создатель: \(channel.ownerName)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.slooshAccent)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Color.slooshAccent.opacity(0.12))
                )
                .padding(.top, 2)
            }
        }
    }

    // MARK: - Quick Action Buttons

    private var quickActionButtonsSection: some View {
        HStack(spacing: 12) {
            // Share Link Button
            ShareLink(
                item: shareURL,
                subject: Text(channel.name),
                message: Text("Присоединяйся к каналу «\(channel.name)» в Sloosh!")
            ) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .bold))
                    Text("Поделиться")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                )
                .glassEffect(.regular.interactive(), in: Capsule())
            }
            .buttonStyle(PeakPressButtonStyle())

            // Primary Subscription / Edit Button
            if isOwner {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showEditSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "pencil")
                            .font(.system(size: 14, weight: .bold))
                        Text("Настройки")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(
                        Capsule()
                            .fill(Color.slooshAccent)
                    )
                    .glassEffect(in: Capsule())
                }
                .buttonStyle(PeakPressButtonStyle())
            } else {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    Task {
                        if isSubscribed {
                            showUnsubscribeConfirm = true
                        } else {
                            _ = await repo.subscribeToChannel(channel: channel)
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isSubscribed ? "checkmark.circle.fill" : "plus.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                        Text(isSubscribed ? "Подписан" : "Подписаться")
                            .font(.system(size: 14, weight: .bold))
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
                .buttonStyle(PeakPressButtonStyle())
            }
        }
    }

    // MARK: - Description Section

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ОПИСАНИЕ")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 20)

            VStack(alignment: .leading, spacing: 8) {
                Text(channel.description)
                    .font(.system(size: 15))
                    .foregroundColor(.primary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Pinned Post Section

    private func pinnedPostSection(_ pinned: ChannelPost) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ЗАКРЕПЛЕННЫЙ ПОСТ")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 20)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color.slooshAccent)

                    Text("Закреплено автором")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color.slooshAccent)

                    Spacer(minLength: 0)

                    Text(formatTimestamp(pinned.timestampMs))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                if let text = pinned.text, !text.isEmpty {
                    Text(text)
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                        .lineLimit(3)
                }

                if let media = pinned.media {
                    Button {
                        selectedMovieIdForDetails = media.mediaId
                    } label: {
                        HStack(spacing: 10) {
                            if let posterUrl = media.posterUrl, !posterUrl.isEmpty {
                                AsyncCachedImage(urlString: posterUrl) {
                                    Rectangle().fill(Color.white.opacity(0.08))
                                } content: { img in
                                    Image(uiImage: img)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                }
                                .frame(width: 44, height: 62)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text(media.title)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
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

                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Shared Media Section

    private var sharedMediaSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("МЕДИАФАЙЛЫ КАНАЛА")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(sharedMediaList.count)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color.slooshAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.slooshAccent.opacity(0.15))
                    )
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(sharedMediaList) { media in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            selectedMovieIdForDetails = media.mediaId
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                ZStack(alignment: .topLeading) {
                                    if let posterUrl = media.posterUrl, !posterUrl.isEmpty {
                                        AsyncCachedImage(urlString: posterUrl) {
                                            Rectangle()
                                                .fill(Color.white.opacity(0.08))
                                                .aspectRatio(2/3, contentMode: .fill)
                                        } content: { image in
                                            Image(uiImage: image)
                                                .resizable()
                                                .aspectRatio(2/3, contentMode: .fill)
                                        }
                                        .frame(width: 100, height: 150)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    } else {
                                        Rectangle()
                                            .fill(Color.white.opacity(0.08))
                                            .frame(width: 100, height: 150)
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }

                                    if let rating = media.rating, rating > 0 {
                                        Text(String(format: "%.1f", rating))
                                            .font(.system(size: 10, weight: .heavy))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 2)
                                            .background(Color.rating(rating))
                                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                                            .padding(4)
                                    }
                                }

                                Text(media.title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                    .frame(width: 100, alignment: .leading)
                            }
                        }
                        .buttonStyle(PeakPressButtonStyle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Settings Section

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("НАСТРОЙКИ")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 20)

            VStack(spacing: 1) {
                // Notifications Switch
                HStack {
                    Label {
                        Text("Уведомления")
                            .font(.system(size: 16))
                            .foregroundColor(.primary)
                    } icon: {
                        Image(systemName: isMuted ? "bell.slash.fill" : "bell.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(isMuted ? .secondary : Color.slooshAccent)
                    }

                    Spacer()

                    Toggle("", isOn: Binding(
                        get: { !isMuted },
                        set: { enableNotifications in
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            isMuted = !enableNotifications
                            Task {
                                await repo.setChannelMuted(channelId: channel.id, isMuted: isMuted)
                            }
                        }
                    ))
                    .labelsHidden()
                    .tint(Color.slooshAccent)
                }
                .padding(16)

                Divider()
                    .padding(.leading, 48)

                // Channel Link / ID Row
                HStack {
                    Label {
                        Text("Ссылка на канал")
                            .font(.system(size: 16))
                            .foregroundColor(.primary)
                    } icon: {
                        Image(systemName: "link")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Color.slooshAccent)
                    }

                    Spacer()

                    Text("sloosh.app/\(channel.id.prefix(10))")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)

                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .padding(16)
                .contentShape(Rectangle())
                .onTapGesture {
                    UIPasteboard.general.string = "https://sloosh.app/channel/\(channel.id)"
                    ToastManager.shared.show(title: "Ссылка скопирована", icon: "doc.on.doc.fill")
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Destructive Actions Section

    private var destructiveActionsSection: some View {
        VStack(spacing: 12) {
            if isOwner {
                Button(role: .destructive) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    showDeleteConfirm = true
                } label: {
                    HStack {
                        Label {
                            Text("Удалить канал")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.red)
                        } icon: {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.red)
                        }

                        Spacer()
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            } else if isSubscribed {
                Button(role: .destructive) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    showUnsubscribeConfirm = true
                } label: {
                    HStack {
                        Label {
                            Text("Покинуть канал")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.red)
                        } icon: {
                            Image(systemName: "rectangle.portrait.and.arrow.right.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.red)
                        }

                        Spacer()
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
    }

    private func formatTimestamp(_ timestampMs: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestampMs) / 1000)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Edit Channel Sheet (Author / Owner Profile Management)

public struct EditChannelSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var repo = MessengerRepository.shared

    public let channel: ChannelModel
    public let onSaved: (ChannelModel) -> Void

    @State private var channelName: String
    @State private var channelDescription: String
    @State private var selectedEmoji: String
    @State private var selectedColorHex: String
    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil

    private let emojiPresets = ["📢", "🎬", "🍿", "🚀", "🔥", "👑", "⚡️", "⭐️", "🎧", "🏆", "💎", "🔮", "🌙", "🌊", "🎮", "👾"]
    private let colorPresets = [
        "#FF9F0A", // Orange
        "#FF453A", // Red
        "#30D158", // Green
        "#0A84FF", // Blue
        "#BF5AF2", // Purple
        "#64D2FF", // Cyan
        "#FFD60A", // Yellow
        "#B2FF00"  // Sloosh Neon
    ]

    public init(channel: ChannelModel, onSaved: @escaping (ChannelModel) -> Void) {
        self.channel = channel
        self.onSaved = onSaved
        self._channelName = State(initialValue: channel.name)
        self._channelDescription = State(initialValue: channel.description)
        self._selectedEmoji = State(initialValue: channel.displayAvatarEmoji)
        self._selectedColorHex = State(initialValue: channel.accentColorHex ?? "#FF9F0A")
    }

    private var selectedColor: Color {
        if let uiColor = UIColor(hex: selectedColorHex) {
            return Color(uiColor)
        }
        return .slooshAccent
    }

    private var isFormValid: Bool {
        !channelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Avatar & Visual Preview
                    avatarPreviewSection
                        .padding(.top, 16)

                    // Form Fields
                    formFieldsSection

                    // Emoji Preset Selector
                    emojiPickerSection

                    // Color Palette Selector
                    colorPickerSection

                    if let error = errorMessage {
                        Text(error)
                            .font(.system(size: 14))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }

                    // Save Button
                    saveButton
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, 20)
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Редактирование")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        dismiss()
                    }
                    .foregroundColor(.secondary)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground {
            Color.clear.glassEffect(in: .rect)
        }
    }

    private var avatarPreviewSection: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(selectedColor.opacity(0.25))
                    .frame(width: 96, height: 96)
                    .overlay(
                        Circle()
                            .stroke(selectedColor.opacity(0.7), lineWidth: 2)
                    )
                    .overlay(
                        Text(selectedEmoji)
                            .font(.system(size: 48))
                    )
                    .shadow(color: selectedColor.opacity(0.3), radius: 12, x: 0, y: 4)

                Circle()
                    .fill(Color(UIColor.systemBackground))
                    .frame(width: 28, height: 28)
                    .overlay(
                        Circle()
                            .fill(Color.slooshAccent)
                            .frame(width: 24, height: 24)
                            .overlay(
                                Image(systemName: "megaphone.fill")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.black)
                            )
                    )
                    .offset(x: 2, y: 2)
            }

            Text(channelName.isEmpty ? "Название канала" : channelName)
                .font(.system(size: 19, weight: .bold))
                .foregroundColor(channelName.isEmpty ? .secondary : .primary)
                .lineLimit(1)
        }
    }

    private var formFieldsSection: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("НАЗВАНИЕ")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(.leading, 4)

                TextField("Название канала", text: $channelName)
                    .font(.system(size: 16))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("ОПИСАНИЕ")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(.leading, 4)

                TextField("Описание канала", text: $channelDescription, axis: .vertical)
                    .lineLimit(2...5)
                    .font(.system(size: 15))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
            }
        }
    }

    private var emojiPickerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ИКОНКА КАНАЛА")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.leading, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(emojiPresets, id: \.self) { emoji in
                        Button {
                            selectedEmoji = emoji
                            let feedback = UISelectionFeedbackGenerator()
                            feedback.selectionChanged()
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(selectedEmoji == emoji ? selectedColor.opacity(0.25) : Color.primary.opacity(0.06))
                                    .frame(width: 48, height: 48)

                                Text(emoji)
                                    .font(.system(size: 24))

                                if selectedEmoji == emoji {
                                    Circle()
                                        .stroke(selectedColor, lineWidth: 2)
                                        .frame(width: 48, height: 48)
                                }
                            }
                        }
                        .buttonStyle(PeakPressButtonStyle())
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
            }
        }
    }

    private var colorPickerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("АКЦЕНТНЫЙ ЦВЕТ")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.leading, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(colorPresets, id: \.self) { hex in
                        let color = UIColor(hex: hex).map { Color($0) } ?? .slooshAccent
                        Button {
                            selectedColorHex = hex
                            let feedback = UISelectionFeedbackGenerator()
                            feedback.selectionChanged()
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(color)
                                    .frame(width: 40, height: 40)
                                    .shadow(color: color.opacity(selectedColorHex == hex ? 0.5 : 0.0), radius: 6, x: 0, y: 2)

                                if selectedColorHex == hex {
                                    Circle()
                                        .stroke(Color.white, lineWidth: 3)
                                        .frame(width: 40, height: 40)

                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .black))
                                        .foregroundColor(.white)
                                }
                            }
                        }
                        .buttonStyle(PeakPressButtonStyle())
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
            }
        }
    }

    private var saveButton: some View {
        Button {
            saveChangesAction()
        } label: {
            HStack(spacing: 8) {
                if isSaving {
                    ProgressView()
                        .tint(.black)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                    Text("Сохранить изменения")
                        .font(.system(size: 17, weight: .bold))
                }
            }
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                Capsule()
                    .fill(isFormValid ? Color.slooshAccent : Color.slooshAccent.opacity(0.4))
            )
            .glassEffect(in: Capsule())
        }
        .disabled(!isFormValid)
        .buttonStyle(PeakPressButtonStyle())
    }

    private func saveChangesAction() {
        guard isFormValid else { return }
        isSaving = true
        errorMessage = nil

        var updated = channel
        updated.name = channelName.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.description = channelDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.avatarEmoji = selectedEmoji
        updated.accentColorHex = selectedColorHex

        Task {
            let success = await repo.updateChannelMetadata(channel: updated)
            if success {
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
                isSaving = false
                onSaved(updated)
                dismiss()
            } else {
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.error)
                isSaving = false
                errorMessage = "Не удалось сохранить изменения. Повторите попытку."
            }
        }
    }
}
