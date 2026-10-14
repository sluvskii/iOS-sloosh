import SwiftUI
import UIKit
import Combine

// MARK: - User Profile Detail Screen (Flagship Full-Screen Liquid Glass)

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
    @State private var fullPlayerConfig: PlayerConfig? = nil
    @State private var showDirectChat: Bool = false
    @State private var isTitleVisible: Bool = false

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
        ZStack(alignment: .top) {
            // Dark Cinema Background
            Color.black.ignoresSafeArea()

            // Main Scrollable Content
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 22) {
                    // Spacer for top safe area bar
                    Color.clear.frame(height: 52)

                    // 1. Hero Profile Card
                    heroHeaderView

                    // 2. Stats Bar
                    statsBarView

                    // 3. Action Bar (Primary action: Написать, or Delete Chat)
                    actionsBarView

                    // 4. Published Clips Grid
                    publishedClipsSection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 48)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .ignoresSafeArea(edges: .top)
        .hideNavigationBarWithRestore()
        .fullWidthSwipeBack()
        .safeAreaInset(edge: .top, spacing: 0) {
            topNavBarView
        }
        .task {
            // 1. Fetch fresh user profile
            if let fresh = await repo.fetchUser(userId: user.id) {
                await MainActor.run {
                    self.user = fresh
                }
            }

            // 2. Fetch live presence
            let presence = await UserPresenceService.shared.fetchUserPresence(userId: user.id)
            self.livePresence = presence

            // 3. Fetch author's published clips
            let clips = await clipsRepo.fetchClips(forAuthorId: user.id)
            await MainActor.run {
                self.authorClips = clips
                self.isLoadingClips = false
            }

            // 4. Real-time presence polling (every 2.5s)
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
        .preferredColorScheme(.dark)
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Top Navigation Bar (Liquid Glass with Back & Single Share)

    private var topNavBarView: some View {
        HStack {
            // Back Button
            TelegramGlassIconButton(systemName: "chevron.left") {
                dismiss()
            }

            Spacer()

            // Single Share Button in Top Bar (No duplicate on the screen)
            TelegramGlassIconButton(systemName: "square.and.arrow.up") {
                shareUserProfile()
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .background(
            VariableBlurView(tintColor: .black, tintOpacity: 0.88)
                .padding(.bottom, -30)
                .ignoresSafeArea(edges: .top)
        )
    }

    // MARK: - Hero Header View

    private var heroHeaderView: some View {
        VStack(spacing: 14) {
            // Large Avatar with presence badge
            SlooshAvatarView(
                avatarSource: user.avatarUrl,
                fallbackText: user.displayTitle,
                size: 104,
                showOnline: true,
                isOnline: livePresence.isOnline
            )
            .shadow(color: Color.slooshAccent.opacity(0.18), radius: 16, y: 6)

            VStack(spacing: 6) {
                // Name
                Text(user.displayTitle)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                // @tag capsule with tap-to-copy
                if !user.displayTag.isEmpty {
                    Button {
                        UIPasteboard.general.string = user.displayTag
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
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
                                .foregroundStyle(.white.opacity(0.85))

                            Image(systemName: tagCopiedToast ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(tagCopiedToast ? Color.green : Color.white.opacity(0.5))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .glassEffect(.regular.interactive(), in: .capsule)
                    }
                    .buttonStyle(.plain)
                }

                // Live Presence Status
                HStack(spacing: 6) {
                    if livePresence.isOnline {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                            .shadow(color: Color.green.opacity(0.8), radius: 4)
                    }

                    let statusText = PresenceFormatter.formatLastSeen(isOnlineFlag: livePresence.isOnline, lastSeenMs: livePresence.lastSeenMs)
                    Text(statusText)
                        .font(.system(size: 14, weight: livePresence.isOnline ? .medium : .regular))
                        .foregroundStyle(livePresence.isOnline ? Color.green : Color.white.opacity(0.6))
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    // MARK: - Stats Bar View

    private var statsBarView: some View {
        HStack(spacing: 0) {
            statItem(
                title: "Моментов",
                value: "\(authorClips.count)",
                icon: "sparkles.tv.fill",
                iconColor: Color.slooshAccent
            )

            Divider()
                .frame(height: 32)
                .opacity(0.2)

            statItem(
                title: "Лайков",
                value: formatCount(totalLikes),
                icon: "heart.fill",
                iconColor: .red
            )

            Divider()
                .frame(height: 32)
                .opacity(0.2)

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

    private func statItem(title: String, value: String, icon: String, iconColor: Color) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(iconColor)

                Text(value)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
            }

            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions Bar View (No duplicates: single primary action)

    @ViewBuilder
    private var actionsBarView: some View {
        if !isCurrentSessionUser {
            VStack(spacing: 10) {
                // Primary Action Button: "Написать"
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    if chatContext {
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
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.slooshAccent)
                    .clipShape(Capsule())
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
                .buttonStyle(.plain)

                // Delete Chat (if opened from chat context)
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
        } else if chatContext {
            // Current user in chat context
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
        }
    }

    // MARK: - Published Clips Shelf

    private var publishedClipsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 8) {
                Text("Опубликованные моменты")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.white)

                if !isLoadingClips {
                    Text("\(authorClips.count)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .glassEffect(.regular, in: .capsule)
                }

                Spacer()
            }
            .padding(.top, 4)

            // Content
            if isLoadingClips {
                // Skeleton loading state
                LazyVGrid(columns: gridColumns, spacing: 12) {
                    ForEach(0..<4, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                            .aspectRatio(9/16, contentMode: .fit)
                            .shimmer()
                    }
                }
            } else if authorClips.isEmpty {
                // Empty state
                VStack(spacing: 12) {
                    Image(systemName: "sparkles.tv")
                        .font(.system(size: 38))
                        .foregroundStyle(.white.opacity(0.35))

                    Text("Нет опубликованных моментов")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)

                    Text("Пользователь пока не публиковал моменты из фильмов и сериалов")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .glassEffect(.regular, in: .rect(cornerRadius: 20))
            } else {
                // Vertical 9:16 grid of clips
                LazyVGrid(columns: gridColumns, spacing: 12) {
                    ForEach(authorClips) { clip in
                        AuthorClipCardView(clip: clip) {
                            // Directly launch existing flagship PlayerView starting from the moment's timecode!
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
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
                            self.fullPlayerConfig = config
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
                        Color.white.opacity(0.06)
                    } content: { img in
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } fallback: {
                        Color.white.opacity(0.06)
                            .overlay(
                                Image(systemName: "film")
                                    .font(.system(size: 24))
                                    .foregroundStyle(.white.opacity(0.35))
                            )
                    }
                } else {
                    Color.white.opacity(0.06)
                        .overlay(
                            Image(systemName: "film")
                                .font(.system(size: 24))
                                .foregroundStyle(.white.opacity(0.35))
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

                // 4. Center Play Pill Indicator
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Image(systemName: "play.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.85))
                            .frame(width: 32, height: 32)
                            .glassEffect(.regular, in: .circle)
                        Spacer()
                    }
                    Spacer()
                }

                // 5. Bottom Info: Title, Caption, Stats
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
