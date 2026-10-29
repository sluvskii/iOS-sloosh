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
    @State private var sharingClip: MovieClip? = nil
    @State private var showDirectChat: Bool = false
    @State private var scrollOffsetY: CGFloat = 0.0

    @AppStorage("cardDensity") private var cardDensity: CardDensity = .regular
    @AppStorage("cardStyle") private var cardStyle: CardStyle = .classic

    @Environment(\.dismiss) private var dismiss
    @StateObject private var repo = MessengerRepository.shared
    @StateObject private var authRepo = AuthRepository.shared
    @StateObject private var clipsRepo = ClipsRepository.shared

    private var columns: [GridItem] {
        let spacing: CGFloat = cardDensity == .compact ? 8 : 16
        let minWidth: CGFloat = cardDensity == .compact ? 95 : 105
        return [GridItem(.adaptive(minimum: minWidth), spacing: spacing)]
    }

    private var gridSpacing: CGFloat {
        cardDensity == .compact ? 8 : 16
    }

    private var contentPadding: CGFloat {
        cardDensity == .compact ? 12 : 16
    }

    private var navBarBlurOpacity: Double {
        let progress = max(0, scrollOffsetY) / 30.0
        return min(1.0, Double(progress))
    }

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
                .padding(.horizontal, contentPadding)
                .padding(.bottom, 100)
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { _, newOffset in
                scrollOffsetY = newOffset
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable {
                async let userTask = repo.fetchUser(userId: user.id)
                async let presenceTask = UserPresenceService.shared.fetchUserPresence(userId: user.id)
                async let clipsTask = clipsRepo.fetchClips(forAuthorId: user.id, forceRefresh: true)

                let (freshUser, freshPresence, freshClips) = await (userTask, presenceTask, clipsTask)
                if let freshUser {
                    self.user = freshUser
                }
                self.livePresence = freshPresence
                self.authorClips = freshClips
            }
            .scrollEdgeEffectStyle(.soft, for: .bottom)
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

            // 3. Fetch author's published clips (show cached immediately, then refresh from network)
            let cached = clipsRepo.clips.filter { $0.authorId == user.id }.sorted { $0.createdAtMs > $1.createdAtMs }
            if !cached.isEmpty {
                self.authorClips = cached
                self.isLoadingClips = false
            }
            let clips = await clipsRepo.fetchClips(forAuthorId: user.id, forceRefresh: true)
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
        .fullScreenCover(item: $activeMomentClip, onDismiss: {
            activeMomentClip = nil
            Task {
                let fresh = await clipsRepo.fetchClips(forAuthorId: user.id, forceRefresh: true)
                await MainActor.run {
                    self.authorClips = fresh
                }
            }
        }) { clip in
            ClipsFeedView(customClips: authorClips, initialClipId: clip.id, isModal: true)
                .preferredColorScheme(.dark)
                .environment(\.colorScheme, .dark)
        }
        .sheet(item: $sharingClip) { clip in
            ShareToFriendSheet(clip: clip)
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
                .opacity(navBarBlurOpacity)
                .animation(.easeInOut(duration: 0.2), value: navBarBlurOpacity)
                .allowsHitTesting(false)
        )
    }

    // MARK: - Hero Header View (Clean, Direct on Dark Background)

    private var heroHeaderView: some View {
        VStack(spacing: 12) {
            // Large Avatar without online indicator (status is displayed in text below)
            SlooshAvatarView(
                avatarSource: user.avatarUrl,
                fallbackText: user.displayTitle,
                size: 96,
                showOnline: false,
                isOnline: false
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
                // Primary Action Button: "Написать" (matching DetailsView playButton style)
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
                            .font(.system(size: 16, weight: .heavy))
                    }
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 28)
                    .frame(height: 48)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.94))
                    )
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .shadow(color: Color.black.opacity(0.22), radius: 10, x: 0, y: 4)
                }
                .buttonStyle(.glassPress)

                // Delete Chat (if opened from chat context)
                if chatContext {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.red)
                            .frame(width: 48, height: 48)
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
                .frame(height: 42)
                .glassEffect(.regular.interactive(), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
    }

    // MARK: - Published Clips Shelf (Adaptive Poster Grid Matching App Catalog)

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
                LazyVGrid(columns: columns, spacing: gridSpacing) {
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
                // Adaptive grid respecting cardDensity & cardStyle
                LazyVGrid(columns: columns, spacing: gridSpacing) {
                    ForEach(authorClips) { clip in
                        AuthorMomentPosterCard(clip: clip, cardStyle: cardStyle) {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            self.activeMomentClip = clip
                        }
                        .contextMenu {
                            Button {
                                self.sharingClip = clip
                            } label: {
                                Label("Поделиться", systemImage: "paperplane")
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Author Moment Poster Card (Standard Movie Poster Design with Views & Catalog Style)

private struct AuthorMomentPosterCard: View {
    let clip: MovieClip
    let cardStyle: CardStyle
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

    private func formatViewsCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000.0)
        } else {
            return "\(count)"
        }
    }

    var body: some View {
        Button {
            onTap()
        } label: {
            switch cardStyle {
            case .classic:
                classicBody
            case .overlay:
                overlayBody
            }
        }
        .buttonStyle(.cardPress)
    }

    private var posterImageView: some View {
        Group {
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
                    posterFallback
                }
            } else {
                posterFallback
            }
        }
    }

    private var posterFallback: some View {
        Color.white.opacity(0.06)
            .aspectRatio(2/3, contentMode: .fit)
            .overlay(
                Image(systemName: "film")
                    .font(.system(size: 22))
                    .foregroundStyle(.white.opacity(0.3))
            )
    }

    // Views badge pill
    private var viewsBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "eye.fill")
                .font(.system(size: 8, weight: .bold))
            Text(formatViewsCount(clip.viewsCount))
                .font(.system(size: 9.5, weight: .bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 5.5)
        .padding(.vertical, 2.5)
        .glassEffect(.regular, in: Capsule())
        .padding(6)
    }

    // MARK: - Classic Layout (Metadata below poster)

    private var classicBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 1. Poster Container
            ZStack(alignment: .bottomLeading) {
                posterImageView
                    .aspectRatio(2/3, contentMode: .fill)

                // Scrim at bottom of poster for views badge contrast
                LinearGradient(
                    colors: [.clear, .black.opacity(0.45)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)

                // Views badge at bottom-leading
                viewsBadge
            }
            .aspectRatio(2/3, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            // 2. Metadata Below Poster
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

    // MARK: - Overlay Layout (Metadata inside poster matching HomeView overlay style)

    private var overlayBody: some View {
        ZStack(alignment: .bottomLeading) {
            posterImageView
                .aspectRatio(2/3, contentMode: .fill)

            // Views badge at top-trailing
            VStack {
                HStack {
                    Spacer()
                    viewsBadge
                }
                Spacer()
            }

            // Progressive blur and dark gradient at bottom of poster
            VariableBlurView(
                maxBlurRadius: 6,
                direction: .blurredBottomClearTop,
                tintColor: .black,
                tintOpacity: 0.82,
                style: .dark,
                haloIntensity: 0
            )
            .frame(height: 72)
            .frame(maxWidth: .infinity, alignment: .bottom)
            .allowsHitTesting(false)

            // Metadata inside poster
            VStack(alignment: .leading, spacing: 2) {
                Text(clip.title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.95))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(clip.subtitleInfo)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.65))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 6)
        }
        .aspectRatio(2/3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
