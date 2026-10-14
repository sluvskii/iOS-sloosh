import SwiftUI
import UIKit
import AVKit
import Combine

// MARK: - User Profile Detail View (Flagship Liquid Glass Style)

public struct UserProfileDetailView: View {
    public let initialUser: SlooshUser
    public let chatContext: Bool

    @State private var user: SlooshUser
    @State private var authorClips: [MovieClip] = []
    @State private var isLoadingClips: Bool = true
    @State private var livePresence: (isOnline: Bool, lastSeenMs: Int64?)
    @State private var pollTask: Task<Void, Never>? = nil
    @State private var showDeleteConfirm: Bool = false
    @State private var tagCopiedToast: Bool = false
    @State private var selectedClipForPlayback: MovieClip? = nil
    @State private var fullPlayerConfig: PlayerConfig? = nil
    @State private var showDirectChat: Bool = false

    @Environment(\.dismiss) private var dismiss
    @StateObject private var repo = MessengerRepository.shared
    @StateObject private var authRepo = AuthRepository.shared
    @StateObject private var clipsRepo = ClipsRepository.shared

    private let gridColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    public init(user: SlooshUser, chatContext: Bool = false) {
        self.initialUser = user
        self.chatContext = chatContext
        _user = State(initialValue: user)
        let cached = UserPresenceService.shared.getCachedPresence(userId: user.id) ?? (user.isCurrentlyOnline, user.lastSeenMs)
        _livePresence = State(initialValue: cached)
    }

    public init(peerUser: SlooshUser, chatContext: Bool = true) {
        self.init(user: peerUser, chatContext: chatContext)
    }

    private var isCurrentSessionUser: Bool {
        guard let currentId = authRepo.currentUser?.id, !currentId.isEmpty else { return false }
        return currentId == user.id
    }

    private var totalLikes: Int {
        authorClips.reduce(0) { $0 + $1.likesCount }
    }

    private var totalViews: Int {
        authorClips.reduce(0) { $0 + $1.viewsCount }
    }

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 20) {
                // MARK: 1. Hero Profile Card
                heroHeaderView

                // MARK: 2. Stats Bar
                statsBarView

                // MARK: 3. Action Buttons
                actionsBarView

                // MARK: 4. Published Clips Shelf
                publishedClipsSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
        .background(
            Color(UIColor.systemGroupedBackground)
                .ignoresSafeArea()
        )
        .navigationTitle(user.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !chatContext {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.primary)
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    shareUserProfile()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.primary)
                }
            }
        }
        .task {
            // 1. Fetch live user details & presence
            if let fresh = await repo.fetchUser(userId: user.id) {
                await MainActor.run {
                    self.user = fresh
                }
            }

            let presence = await UserPresenceService.shared.fetchUserPresence(userId: user.id)
            self.livePresence = presence

            // 2. Fetch author's published clips
            let clips = await clipsRepo.fetchClips(forAuthorId: user.id)
            await MainActor.run {
                self.authorClips = clips
                self.isLoadingClips = false
            }

            // 3. Real-time presence polling
            pollTask?.cancel()
            pollTask = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    if Task.isCancelled { break }
                    let fresh = await UserPresenceService.shared.fetchUserPresence(userId: user.id)
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
        .navigationDestination(isPresented: $showDirectChat) {
            ChatDetailView(peerUser: user)
        }
        .sheet(item: $selectedClipForPlayback) { clip in
            AuthorClipDetailSheet(
                clip: clip,
                onWatchFullMovie: { config in
                    self.fullPlayerConfig = config
                }
            )
        }
        .fullScreenCover(item: $fullPlayerConfig) { config in
            PlayerView(config: config)
                .preferredColorScheme(.dark)
                .environment(\.colorScheme, .dark)
        }
        .confirmationDialog(
            "Удалить чат с \(user.displayTitle)?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Удалить чат", role: .destructive) {
                let chatId = repo.getOrCreateChatId(peerUserId: user.id)
                Task {
                    _ = await repo.deleteChat(chatId: chatId, peerUserId: user.id, deleteForEveryone: true)
                }
                dismiss()
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("История сообщений и диалог будут удалены.")
        }
    }

    // MARK: - Hero Header View

    private var heroHeaderView: some View {
        VStack(spacing: 14) {
            // Avatar with live online badge
            SlooshAvatarView(
                avatarSource: user.avatarUrl,
                fallbackText: user.displayTitle,
                size: 96,
                showOnline: true,
                isOnline: livePresence.isOnline
            )
            .shadow(color: Color.black.opacity(0.12), radius: 10, y: 4)

            // Name & Tag & Presence Info
            VStack(spacing: 6) {
                Text(user.displayTitle)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color.primary)
                    .multilineTextAlignment(.center)

                // User @tag capsule with tap-to-copy
                if !user.displayTag.isEmpty {
                    Button {
                        UIPasteboard.general.string = user.displayTag
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            tagCopiedToast = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                            withAnimation {
                                tagCopiedToast = false
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text(user.displayTag)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.primary.opacity(0.85))

                            Image(systemName: tagCopiedToast ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(tagCopiedToast ? Color.green : Color.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .glassEffect(.regular.interactive(), in: .capsule)
                    }
                    .buttonStyle(.plain)
                }

                // Presence Status Indicator
                HStack(spacing: 6) {
                    if livePresence.isOnline {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                            .shadow(color: Color.green.opacity(0.6), radius: 3)
                    }

                    let statusText = PresenceFormatter.formatLastSeen(isOnlineFlag: livePresence.isOnline, lastSeenMs: livePresence.lastSeenMs)
                    Text(statusText)
                        .font(.system(size: 14, weight: livePresence.isOnline ? .medium : .regular))
                        .foregroundStyle(livePresence.isOnline ? Color.green : Color.secondary)
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    // MARK: - Stats Bar View

    private var statsBarView: some View {
        HStack(spacing: 0) {
            statItem(
                title: "Моментов",
                value: "\(authorClips.count)",
                icon: "sparkles.tv.fill"
            )

            Divider()
                .frame(height: 32)
                .opacity(0.3)

            statItem(
                title: "Лайков",
                value: formatCount(totalLikes),
                icon: "heart.fill",
                iconColor: .red
            )

            Divider()
                .frame(height: 32)
                .opacity(0.3)

            statItem(
                title: "Просмотров",
                value: formatCount(totalViews),
                icon: "eye.fill",
                iconColor: .blue
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    private func statItem(title: String, value: String, icon: String, iconColor: Color = .primary) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(iconColor)

                Text(value)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.primary)
            }

            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Color.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions Bar View

    private var actionsBarView: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                if !isCurrentSessionUser {
                    // "Написать" Button
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        if chatContext {
                            // If opened from inside ChatDetailView, return to conversation
                            dismiss()
                        } else {
                            showDirectChat = true
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .font(.system(size: 15, weight: .bold))

                            Text("Написать")
                                .font(.system(size: 15, weight: .bold))
                        }
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.slooshAccent)
                        .clipShape(Capsule())
                        .glassEffect(.regular.interactive(), in: .capsule)
                    }
                    .buttonStyle(.plain)
                }

                // "Поделиться" Button
                if isCurrentSessionUser {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        shareUserProfile()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 15, weight: .semibold))

                            Text("Поделиться профилем")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundStyle(Color.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .glassEffect(.regular.interactive(), in: .capsule)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        shareUserProfile()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.primary)
                            .frame(width: 44, height: 44)
                            .glassEffect(.regular.interactive(), in: .circle)
                    }
                    .buttonStyle(.plain)
                }
            }

            // "Удалить чат" (if opened from chat context or chat exists)
            if chatContext {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 14))

                        Text("Удалить чат")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundStyle(Color.red)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
    }

    // MARK: - Published Clips Shelf

    private var publishedClipsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 8) {
                Text("Опубликованные моменты")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.primary)

                if !isLoadingClips {
                    Text("\(authorClips.count)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .glassEffect(.regular, in: .capsule)
                }

                Spacer()
            }
            .padding(.top, 6)

            // Content
            if isLoadingClips {
                // Skeleton loading state
                LazyVGrid(columns: gridColumns, spacing: 12) {
                    ForEach(0..<4, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(UIColor.secondarySystemFill))
                            .aspectRatio(9/16, contentMode: .fit)
                            .shimmer()
                    }
                }
            } else if authorClips.isEmpty {
                // Empty state
                VStack(spacing: 12) {
                    Image(systemName: "sparkles.tv")
                        .font(.system(size: 38))
                        .foregroundStyle(Color.secondary.opacity(0.5))

                    Text("Нет опубликованных моментов")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.primary)

                    Text("Пользователь пока не публиковал моменты из фильмов и сериалов")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
                .glassEffect(.regular, in: .rect(cornerRadius: 20))
            } else {
                // Vertical 9:16 grid of clips
                LazyVGrid(columns: gridColumns, spacing: 12) {
                    ForEach(authorClips) { clip in
                        AuthorClipCardView(clip: clip) {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            selectedClipForPlayback = clip
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func shareUserProfile() {
        let title = user.displayTitle
        let tag = user.displayTag
        let shareText = !tag.isEmpty ? "Профиль \(title) (\(tag)) в sloosh! 🎬" : "Профиль \(title) в sloosh! 🎬"
        let av = UIActivityViewController(activityItems: [shareText], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(av, animated: true)
        }
    }

    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000.0)
        }
        return "\(count)"
    }
}

// MARK: - Author Clip Card View (9:16 Aspect Ratio)

private struct AuthorClipCardView: View {
    let clip: MovieClip
    let onTap: () -> Void

    private var thumbnailURL: URL? {
        if let path = clip.posterPath ?? clip.backdropPath {
            if path.hasPrefix("http://") || path.hasPrefix("https://") {
                return URL(string: path)
            }
            if let normalized = normalizeImageUrl(path: path) {
                return URL(string: normalized)
            }
        }
        return nil
    }

    var body: some View {
        Button {
            onTap()
        } label: {
            ZStack(alignment: .bottomLeading) {
                // 1. Poster Image
                if let url = thumbnailURL {
                    AsyncCachedImage(url: url) {
                        Color(UIColor.secondarySystemFill)
                    } content: { img in
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } fallback: {
                        Color(UIColor.secondarySystemFill)
                            .overlay(
                                Image(systemName: "film")
                                    .font(.system(size: 24))
                                    .foregroundStyle(Color.secondary)
                            )
                    }
                } else {
                    Color(UIColor.secondarySystemFill)
                        .overlay(
                            Image(systemName: "film")
                                .font(.system(size: 24))
                                .foregroundStyle(Color.secondary)
                        )
                }

                // 2. Dark Scrim Gradient for text contrast
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.35),
                        .init(color: Color.black.opacity(0.55), location: 0.7),
                        .init(color: Color.black.opacity(0.92), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // 3. Top-Right Duration Pill
                VStack {
                    HStack {
                        Spacer()

                        Text(clip.formattedDuration)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3.5)
                            .glassEffect(.regular, in: .capsule)
                            .padding(8)
                    }
                    Spacer()
                }

                // 4. Bottom Info: Title, Caption, Stats
                VStack(alignment: .leading, spacing: 4) {
                    Text(clip.title)
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(Color.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if !clip.caption.isEmpty {
                        Text(clip.caption)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(Color.white.opacity(0.8))
                            .lineLimit(1)
                    }

                    HStack(spacing: 10) {
                        HStack(spacing: 3) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.red)
                            Text("\(clip.likesCount)")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.9))
                        }

                        if clip.viewsCount > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "eye.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.white.opacity(0.7))
                                Text("\(clip.viewsCount)")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Color.white.opacity(0.9))
                            }
                        }

                        Spacer()
                    }
                    .padding(.top, 2)
                }
                .padding(10)
            }
            .aspectRatio(9/16, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(CardPressButtonStyle())
    }
}

// MARK: - Author Clip Detail Sheet (Seamless Moment Playback)

public struct AuthorClipDetailSheet: View {
    public let clip: MovieClip
    public let onWatchFullMovie: (PlayerConfig) -> Void

    @StateObject private var playback = ClipPlaybackCoordinator()
    @StateObject private var clipsRepo = ClipsRepository.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showHeartAnimation: Bool = false
    @State private var heartPosition: CGPoint = .zero

    public init(clip: MovieClip, onWatchFullMovie: @escaping (PlayerConfig) -> Void) {
        self.clip = clip
        self.onWatchFullMovie = onWatchFullMovie
    }

    public var body: some View {
        ZStack {
            // Dark Background
            Color.black.ignoresSafeArea()

            // 1. Video Layer
            if let player = playback.activePlayer {
                VideoLayerView(player: player)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        playback.togglePlayPause()
                    }
            } else if playback.isResolving {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.3)
            }

            // 2. Play/Pause Overlay indicator when paused
            if !playback.isPlaying && !playback.isResolving {
                Image(systemName: "play.fill")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .frame(width: 80, height: 80)
                    .glassEffect(.regular, in: .circle)
                    .allowsHitTesting(false)
            }

            // 3. Floating Double-Tap Heart
            if showHeartAnimation {
                Image(systemName: "heart.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(Color.red)
                    .shadow(color: Color.red.opacity(0.6), radius: 12)
                    .scaleEffect(showHeartAnimation ? 1.0 : 0.4)
                    .opacity(showHeartAnimation ? 1.0 : 0.0)
                    .animation(.spring(response: 0.28, dampingFraction: 0.6), value: showHeartAnimation)
            }

            // 4. Overlays: Top Close Button & Bottom Controls
            VStack {
                // Top Bar
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(Color.white.opacity(0.85))
                            .glassEffect(.regular.interactive(), in: .circle)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    // Timecode range pill
                    Text(clip.timecodeRangeFormatted)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .glassEffect(.regular, in: .capsule)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                Spacer()

                // Bottom Content
                VStack(alignment: .leading, spacing: 12) {
                    // Movie Title & Subtitle
                    VStack(alignment: .leading, spacing: 4) {
                        Text(clip.title)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Color.white)

                        Text(clip.subtitleInfo)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.75))

                        if !clip.caption.isEmpty {
                            Text(clip.caption)
                                .font(.system(size: 13))
                                .foregroundStyle(Color.white.opacity(0.95))
                                .padding(.top, 2)
                        }
                    }

                    // Progress Bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.2))
                                .frame(height: 4)

                            Capsule()
                                .fill(Color.white)
                                .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(playback.clipProgress))), height: 4)
                        }
                    }
                    .frame(height: 4)
                    .padding(.vertical, 4)

                    // Actions Row: Like + "Смотреть фильм"
                    HStack(spacing: 12) {
                        // Like Button
                        let isLiked = clipsRepo.isLiked(clipId: clip.id)
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            Task {
                                _ = await clipsRepo.toggleLike(for: clip.id)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: isLiked ? "heart.fill" : "heart")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(isLiked ? Color.red : Color.white)

                                Text("\(clip.likesCount)")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Color.white)
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 44)
                            .glassEffect(.regular.interactive(), in: .capsule)
                        }
                        .buttonStyle(.plain)

                        // "Смотреть фильм" Button
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            playback.pause()
                            let config = PlayerConfig(
                                iframeUrl: nil,
                                title: clip.title,
                                kpId: clip.kpId,
                                season: clip.season,
                                episode: clip.episode,
                                voiceover: clip.translationName,
                                streamUrl: nil,
                                voices: clip.translationName != nil ? [clip.translationName!] : [],
                                tmdbId: clip.tmdbId,
                                posterUrl: clip.posterPath,
                                backdropUrl: clip.backdropPath,
                                logoUrl: clip.logoPath,
                                initialPlaybackTime: clip.startTime
                            )
                            dismiss()
                            onWatchFullMovie(config)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 14, weight: .bold))

                                Text("Смотреть фильм")
                                    .font(.system(size: 15, weight: .bold))
                            }
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .glassEffect(.regular.interactive(), in: .capsule)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .task {
            playback.setupPlayer(for: clip)
        }
        .onDisappear {
            playback.cleanup()
        }
        .preferredColorScheme(.dark)
        .environment(\.colorScheme, .dark)
    }
}
