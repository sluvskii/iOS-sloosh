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
    @State private var activeMomentClip: MovieClip? = nil
    @State private var showDirectChat: Bool = false

    @Environment(\.dismiss) private var dismiss
    @StateObject private var repo = MessengerRepository.shared
    @StateObject private var authRepo = AuthRepository.shared
    @StateObject private var clipsRepo = ClipsRepository.shared

    private let gridColumns = [
        GridItem(.flexible(), spacing: 12),
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

    public var body: some View {
        ZStack(alignment: .top) {
            // Dark Cinema Background
            Color.black.ignoresSafeArea()

            // Main Scrollable Content
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 20) {
                    // Spacer for top safe area bar
                    Color.clear.frame(height: 52)

                    // 1. Clean Hero Header (Direct on background, no artificial glass podlozhka, no glows)
                    heroHeaderView

                    // 2. Action Button (Primary: "Написать", or Delete Chat)
                    actionsBarView

                    // 3. Published Moments Grid (Standard 3-column poster grid matching app design)
                    publishedClipsSection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 100)
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
        .fullScreenCover(item: $activeMomentClip) { clip in
            ClipsFeedView(customClips: authorClips, initialClipId: clip.id, isModal: true)
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

    // MARK: - Top Navigation Bar (Clean Back Button Only, No Share)

    private var topNavBarView: some View {
        HStack {
            TelegramGlassIconButton(systemName: "chevron.left") {
                dismiss()
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .background(
            VariableBlurView(tintColor: .black, tintOpacity: 0.88)
                .padding(.bottom, -30)
                .ignoresSafeArea(edges: .top)
        )
    }

    // MARK: - Hero Header View (Clean, Direct on Dark Background)

    private var heroHeaderView: some View {
        VStack(spacing: 12) {
            // Large Avatar with presence badge
            SlooshAvatarView(
                avatarSource: user.avatarUrl,
                fallbackText: user.displayTitle,
                size: 96,
                showOnline: true,
                isOnline: livePresence.isOnline
            )

            VStack(spacing: 5) {
                // Name
                Text(user.displayTitle)
                    .font(.system(size: 22, weight: .bold))
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
                        HStack(spacing: 4) {
                            Text(user.displayTag)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.6))

                            Image(systemName: tagCopiedToast ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(tagCopiedToast ? Color.green : Color.white.opacity(0.4))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .glassEffect(.regular.interactive(), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 1)
                }

                // Live Presence Status
                HStack(spacing: 5) {
                    if livePresence.isOnline {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 7, height: 7)
                    }

                    let statusText = PresenceFormatter.formatLastSeen(isOnlineFlag: livePresence.isOnline, lastSeenMs: livePresence.lastSeenMs)
                    Text(statusText)
                        .font(.system(size: 13, weight: livePresence.isOnline ? .medium : .regular))
                        .foregroundStyle(livePresence.isOnline ? Color.green : Color.white.opacity(0.5))
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    // MARK: - Actions Bar View

    @ViewBuilder
    private var actionsBarView: some View {
        if !isCurrentSessionUser {
            HStack(spacing: 12) {
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
                            .font(.system(size: 14, weight: .bold))

                        Text("Написать")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .frame(height: 42)
                    .background(Color.slooshAccent)
                    .clipShape(Capsule())
                    .glassEffect(.regular.interactive(), in: Capsule())
                }
                .buttonStyle(.plain)

                // Delete Chat (if opened from chat context)
                if chatContext {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.red)
                            .frame(width: 42, height: 42)
                            .glassEffect(.regular.interactive(), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 2)
        } else if chatContext {
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
                .padding(.horizontal, 20)
                .frame(height: 40)
                .glassEffect(.regular.interactive(), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
    }

    // MARK: - Published Clips Shelf (3-Column Poster Grid)

    private var publishedClipsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 8) {
                Text("Моменты")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)

                if !isLoadingClips {
                    Text("\(authorClips.count)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .glassEffect(.regular, in: Capsule())
                }

                Spacer()
            }
            .padding(.top, 6)

            // Content
            if isLoadingClips {
                // Skeleton loading state
                LazyVGrid(columns: gridColumns, spacing: 14) {
                    ForEach(0..<6, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 6) {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                                .aspectRatio(2/3, contentMode: .fit)
                                .shimmer()

                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                                .frame(height: 12)
                                .shimmer()

                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.white.opacity(0.04))
                                .frame(width: 60, height: 10)
                                .shimmer()
                        }
                    }
                }
            } else if authorClips.isEmpty {
                // Empty state
                VStack(spacing: 12) {
                    Image(systemName: "sparkles.tv")
                        .font(.system(size: 36))
                        .foregroundStyle(.white.opacity(0.3))

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
            } else {
                // Standard 3-column poster grid matching app design
                LazyVGrid(columns: gridColumns, spacing: 14) {
                    ForEach(authorClips) { clip in
                        AuthorMomentPosterCard(clip: clip) {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            self.activeMomentClip = clip
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Author Moment Poster Card (Standard 2:3 Movie Poster Design)

private struct AuthorMomentPosterCard: View {
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
            VStack(alignment: .leading, spacing: 6) {
                // 1. Poster Container (2:3 Aspect Ratio)
                ZStack(alignment: .topTrailing) {
                    // Image
                    if let url = thumbnailURL {
                        AsyncCachedImage(url: url) {
                            Color.white.opacity(0.06)
                                .aspectRatio(2/3, contentMode: .fit)
                                .shimmer()
                        } content: { img in
                            Image(uiImage: img)
                                .resizable()
                                .aspectRatio(2/3, contentMode: .fill)
                        } fallback: {
                            Color.white.opacity(0.06)
                                .aspectRatio(2/3, contentMode: .fit)
                                .overlay(
                                    Image(systemName: "film")
                                        .font(.system(size: 22))
                                        .foregroundStyle(.white.opacity(0.3))
                                )
                        }
                    } else {
                        Color.white.opacity(0.06)
                            .aspectRatio(2/3, contentMode: .fit)
                            .overlay(
                                Image(systemName: "film")
                                    .font(.system(size: 22))
                                    .foregroundStyle(.white.opacity(0.3))
                            )
                    }

                    // Scrim gradient for contrast
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.4), location: 0.0),
                            .init(color: .clear, location: 0.35),
                            .init(color: .clear, location: 0.65),
                            .init(color: .black.opacity(0.6), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    // Top-Right Duration Pill
                    Text(clip.formattedDuration)
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2.5)
                        .glassEffect(.regular, in: Capsule())
                        .padding(5)

                    // Bottom Row: Center Play & Bottom-Left Likes
                    VStack {
                        Spacer()
                        HStack {
                            if clip.likesCount > 0 {
                                HStack(spacing: 2.5) {
                                    Image(systemName: "heart.fill")
                                        .font(.system(size: 8))
                                        .foregroundStyle(.red)
                                    Text("\(clip.likesCount)")
                                        .font(.system(size: 9.5, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .glassEffect(.regular, in: Capsule())
                                .padding(5)
                            }

                            Spacer()

                            Image(systemName: "play.fill")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 20, height: 20)
                                .glassEffect(.regular, in: Circle())
                                .padding(5)
                        }
                    }
                }
                .aspectRatio(2/3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                // 2. Metadata Below Poster (Standard sloosh typography)
                VStack(alignment: .leading, spacing: 2) {
                    Text(clip.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(clip.subtitleInfo)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(.horizontal, 2)
            }
        }
        .buttonStyle(.cardPress)
    }
}
