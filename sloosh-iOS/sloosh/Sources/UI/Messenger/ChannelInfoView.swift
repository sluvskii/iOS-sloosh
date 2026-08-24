import SwiftUI
import PhotosUI

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

    public var body: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // Channel Visual Identity Header
                    headerProfileSection
                        .padding(.top, 16)

                    // Quick Action Button (Non-Owners Subscribe/Unsubscribe)
                    if !isOwner {
                        quickActionButtonsSection
                            .padding(.horizontal, 16)
                    }

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

                    // Channel Settings Section (Notifications)
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
                    Button("Изменить") {
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
            SlooshAvatarView(channel: channel, size: 104)

            // Channel Title & Subscriber Count
            VStack(spacing: 6) {
                Text(channel.name)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                HStack(spacing: 6) {
                    Text(channel.displayTag)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color.slooshAccent)

                    Text("•")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)

                    Text(channel.formattedSubscriberCount)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.secondary)
                }

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
                    .font(.system(size: 15, weight: .bold))
                Text(isSubscribed ? "Подписан" : "Подписаться")
                    .font(.system(size: 15, weight: .bold))
            }
            .foregroundColor(isSubscribed ? .primary : .black)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                Capsule()
                    .fill(isSubscribed ? Color.white.opacity(0.08) : Color.slooshAccent)
            )
            .glassEffect(in: Capsule())
        }
        .buttonStyle(PeakPressButtonStyle())
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
    @State private var channelTag: String
    @State private var channelDescription: String
    @State private var avatarDataString: String?
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var selectedColorHex: String

    @State private var isCheckingTag: Bool = false
    @State private var tagStatusMessage: String? = nil
    @State private var isTagAvailable: Bool = true
    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil

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
        self._channelTag = State(initialValue: channel.tag)
        self._channelDescription = State(initialValue: channel.description)
        self._avatarDataString = State(initialValue: channel.avatarUrl)
        self._selectedColorHex = State(initialValue: channel.accentColorHex ?? "#FF9F0A")
    }

    private var selectedColor: Color {
        if let uiColor = UIColor(hex: selectedColorHex) {
            return Color(uiColor)
        }
        return .slooshAccent
    }

    private var cleanTag: String {
        TagValidator.sanitize(channelTag)
    }

    private var isFormValid: Bool {
        guard !channelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !isSaving else { return false }
        if cleanTag != channel.tag {
            return isTagAvailable && !cleanTag.isEmpty
        }
        return true
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
            PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                ZStack(alignment: .bottomTrailing) {
                    SlooshAvatarView(
                        avatarSource: avatarDataString,
                        fallbackText: channelName.isEmpty ? (cleanTag.isEmpty ? "S" : cleanTag) : channelName,
                        size: 96,
                        accentColor: selectedColor,
                        isChannel: true
                    )

                    // Camera / Edit Photo Badge
                    Circle()
                        .fill(Color(UIColor.systemBackground))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Circle()
                                .fill(Color.slooshAccent)
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.black)
                                )
                        )
                        .offset(x: 2, y: 2)
                }
            }
            .buttonStyle(.plain)
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        if let compressedBase64 = AvatarImageProcessor.processAvatar(image: image) {
                            await MainActor.run {
                                self.avatarDataString = compressedBase64
                            }
                        }
                    }
                }
            }

            if avatarDataString != nil {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    self.avatarDataString = nil
                    self.selectedPhotoItem = nil
                } label: {
                    Text("Удалить фото")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.red)
                }
            }
        }
    }

    private var formFieldsSection: some View {
        VStack(spacing: 16) {
            // Name Field
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

            // Tag Field
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("ТЕГ КАНАЛА")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary)
                    Spacer()
                    if isCheckingTag {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                }
                .padding(.leading, 4)

                HStack(spacing: 4) {
                    Text("@")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.secondary)

                    TextField("cinema_club", text: $channelTag)
                        .font(.system(size: 16))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: channelTag) { _, newValue in
                            checkTagRealtime(newValue)
                        }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            !cleanTag.isEmpty && !isTagAvailable && cleanTag != channel.tag
                                ? Color.red.opacity(0.5)
                                : Color.primary.opacity(0.1),
                            lineWidth: 1
                        )
                )

                if let msg = tagStatusMessage, !cleanTag.isEmpty {
                    Text(msg)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(isTagAvailable ? .secondary : .red)
                        .padding(.leading, 4)
                }
            }

            // Description Field
            VStack(alignment: .leading, spacing: 6) {
                Text("ОПИСАНИЕ")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(.leading, 4)

                TextField("Описание", text: $channelDescription, axis: .vertical)
                    .lineLimit(2...4)
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
            saveChannelAction()
        } label: {
            HStack(spacing: 8) {
                if isSaving {
                    ProgressView()
                        .tint(.black)
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                    Text("Сохранить")
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

    private func checkTagRealtime(_ rawTag: String) {
        let clean = TagValidator.sanitize(rawTag)
        guard !clean.isEmpty else {
            tagStatusMessage = nil
            isTagAvailable = false
            return
        }

        if clean == channel.tag {
            tagStatusMessage = "Текущий тег канала"
            isTagAvailable = true
            return
        }

        let validation = TagValidator.validate(clean)
        guard validation.isValid else {
            tagStatusMessage = validation.message
            isTagAvailable = false
            return
        }

        isCheckingTag = true
        Task {
            let result = await repo.checkChannelTagAvailability(tag: clean)
            await MainActor.run {
                self.isCheckingTag = false
                self.isTagAvailable = result.isAvailable
                self.tagStatusMessage = result.message
            }
        }
    }

    private func saveChannelAction() {
        guard isFormValid else { return }
        isSaving = true
        errorMessage = nil

        var updated = channel
        let oldTag = channel.tag
        updated.name = channelName.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.tag = cleanTag
        updated.description = channelDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.avatarUrl = avatarDataString
        updated.accentColorHex = selectedColorHex

        Task {
            let success = await repo.updateChannelMetadata(channel: updated, oldTag: oldTag != updated.tag ? oldTag : nil)
            await MainActor.run {
                self.isSaving = false
                if success {
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    dismiss()
                    onSaved(updated)
                } else {
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.error)
                    self.errorMessage = "Не удалось сохранить изменения."
                }
            }
        }
    }
}
