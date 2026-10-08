import SwiftUI
import UIKit
import AVKit
import Combine

public struct ClipsFeedView: View {
    @StateObject private var clipsRepo = ClipsRepository.shared
    @StateObject private var authRepo = AuthRepository.shared

    @State private var currentClipId: String?
    @State private var activePlayer: AVPlayer?
    @State private var pipController: AVPictureInPictureController? = nil
    @State private var timeObserver: Any?
    @State private var playerStatusObserver: NSKeyValueObservation?
    @State private var playerTimeStatusObserver: NSKeyValueObservation?
    @State private var resolvePlaybackTask: Task<Void, Never>?

    @State private var isVideoReady: Bool = false
    @State private var isResolving: Bool = false
    @State private var isMuted: Bool = false
    @State private var isPlaying: Bool = true
    @State private var showCommentsForClip: MovieClip?
    @State private var fullPlayerConfig: PlayerConfig?
    @State private var showBigHeart: Bool = false
    @State private var bigHeartPosition: CGPoint = .zero
    @State private var isTextExpanded: Bool = false

    public init() {}

    public var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.ignoresSafeArea()

                if clipsRepo.isLoading && clipsRepo.clips.isEmpty {
                    VStack(spacing: 16) {
                        ProgressView()
                            .tint(.white)
                        Text("Загрузка моментов...")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                } else if clipsRepo.clips.isEmpty {
                    emptyStateView
                } else {
                    feedScrollView(proxy: proxy)
                }
            }
        }
        .preferredColorScheme(.dark)
        .environment(\.colorScheme, .dark)
        .task {
            await clipsRepo.fetchFeed()
            if currentClipId == nil, let first = clipsRepo.clips.first {
                currentClipId = first.id
                setupPlayer(for: first)
            }
        }
        .sheet(item: $showCommentsForClip) { clip in
            ClipCommentsSheetView(clip: clip)
        }
        .fullScreenCover(item: $fullPlayerConfig, onDismiss: {
            fullPlayerConfig = nil
            resumeActivePlayer()
        }) { config in
            PlayerView(config: config)
                .preferredColorScheme(.dark)
                .environment(\.colorScheme, .dark)
        }
        .onDisappear {
            pauseActivePlayer()
        }
        .onAppear {
            resumeActivePlayer()
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles.tv")
                .font(.system(size: 54))
                .foregroundStyle(Color.slooshAccent)

            Text("Здесь будут моменты из фильмов")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)

            Text("Смотрите фильмы и сериалы в sloosh, нажимайте ✂️ в плеере и делитесь любимыми сценами!")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                Task {
                    await clipsRepo.fetchFeed(forceRefresh: true)
                    if let first = clipsRepo.clips.first {
                        currentClipId = first.id
                        setupPlayer(for: first)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text("Обновить")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.slooshAccent)
                .clipShape(Capsule())
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Feed Scroll View

    private func feedScrollView(proxy: GeometryProxy) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(clipsRepo.clips) { clip in
                    clipCard(clip, size: proxy.size, safeArea: proxy.safeAreaInsets)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .id(clip.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $currentClipId)
        .ignoresSafeArea()
        .onChange(of: currentClipId) { _, newId in
            guard let newId = newId, let clip = clipsRepo.clips.first(where: { $0.id == newId }) else { return }
            setupPlayer(for: clip)
        }
    }

    // MARK: - Clip Card

    private func clipCard(_ clip: MovieClip, size: CGSize, safeArea: EdgeInsets) -> some View {
        let isCurrent = (currentClipId == clip.id)

        return ZStack {
            // 1. Base Layer: High-Res Backdrop/Poster (Always rendered underneath to eliminate black screen)
            if let backdrop = clip.backdropPath ?? clip.posterPath, let url = URL(string: backdrop) {
                AsyncCachedImage(url: url) {
                    Color.black
                } content: { img in
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } fallback: {
                    Color.black
                }
                .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }

            // 2. Hardware Video Player Layer (Fades in smoothly when ready to play)
            if isCurrent, let player = activePlayer {
                VideoLayerView(player: player, pipController: $pipController, videoGravity: .resizeAspectFill)
                    .ignoresSafeArea()
                    .opacity(isVideoReady ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 0.25), value: isVideoReady)
            }

            // 3. Loading spinner indicator while resolving or buffering
            if isCurrent && (isResolving || !isVideoReady) {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.3)
                    .shadow(color: .black.opacity(0.8), radius: 6)
            }

            // 4. Subtle Dark Gradient for top and bottom readability
            VStack {
                LinearGradient(
                    colors: [.black.opacity(0.65), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
                .frame(height: 120)
                .ignoresSafeArea(edges: .top)

                Spacer()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.4), .black.opacity(0.88)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 340)
                .ignoresSafeArea(edges: .bottom)
            }
            .allowsHitTesting(false)

            // 5. Double-tap gesture layer for like & single-tap for pause/play
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2, coordinateSpace: .local) { location in
                    triggerDoubleTapLike(for: clip, at: location)
                }
                .onTapGesture(count: 1) {
                    togglePlayPause()
                }

            // 6. Play/Pause Indicator
            if !isPlaying && isCurrent && isVideoReady {
                Image(systemName: "play.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(20)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
                    .transition(.scale.combined(with: .opacity))
                    .allowsHitTesting(false)
            }

            // 7. Big Heart Animation on Double-Tap
            if showBigHeart {
                Image(systemName: "heart.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.red)
                    .shadow(color: .red.opacity(0.5), radius: 20)
                    .position(bigHeartPosition)
                    .scaleEffect(showBigHeart ? 1.2 : 0.4)
                    .opacity(showBigHeart ? 1.0 : 0.0)
                    .animation(.spring(response: 0.35, dampingFraction: 0.6), value: showBigHeart)
                    .allowsHitTesting(false)
            }

            // 8. UI Overlays (Top Bar + Bottom Info + Right Rail Actions)
            VStack {
                // Top Bar
                HStack {
                    Image("LogoText")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(.white)
                        .frame(height: 14)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Capsule())

                    Spacer()

                    // Mute Button
                    Button {
                        isMuted.toggle()
                        activePlayer?.isMuted = isMuted
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.glassPress)
                    .glassEffect(.regular.interactive(), in: .circle)
                }
                .padding(.top, safeArea.top + 8)
                .padding(.horizontal, 16)

                Spacer()

                // Bottom Content
                HStack(alignment: .bottom, spacing: 16) {
                    // Left Info: Title, season/ep tags, caption, author, CTA button
                    VStack(alignment: .leading, spacing: 10) {
                        // Film title & tags
                        VStack(alignment: .leading, spacing: 4) {
                            Text(clip.title)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.8), radius: 4)

                            HStack(spacing: 6) {
                                Text(clip.subtitleInfo)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.9))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.black.opacity(0.5))
                                    .clipShape(Capsule())

                                Text(clip.formattedDuration)
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Color.slooshAccent)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.black.opacity(0.5))
                                    .clipShape(Capsule())
                            }
                        }

                        // Caption text
                        if !clip.caption.isEmpty {
                            Text(clip.caption)
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.95))
                                .lineLimit(isTextExpanded ? 8 : 2)
                                .shadow(color: .black.opacity(0.8), radius: 3)
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        isTextExpanded.toggle()
                                    }
                                }
                        }

                        // Author attribution
                        HStack(spacing: 6) {
                            Text("Автор: @\(clip.authorName)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.65))
                        }

                        // KILLER BUTTON: «Смотреть с этого момента»
                        Button {
                            openFullMovie(clip: clip)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 12, weight: .bold))
                                Text("Смотреть с этого момента")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundStyle(.black)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.slooshAccent)
                            .clipShape(Capsule())
                            .shadow(color: Color.slooshAccent.opacity(0.4), radius: 8, y: 2)
                        }
                        .padding(.top, 4)
                    }

                    Spacer()

                    // Right Rail Action Buttons (Author Avatar, Like, Comments, Share)
                    VStack(spacing: 18) {
                        // Author Avatar
                        authorAvatarView(clip)

                        // Like Button
                        likeButtonView(clip)

                        // Comments Button
                        commentButtonView(clip)

                        // Share Button
                        shareButtonView(clip)
                    }
                    .padding(.bottom, 6)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, safeArea.bottom + 65) // Space above tab bar capsule
            }
        }
    }

    // MARK: - Author Avatar

    private func authorAvatarView(_ clip: MovieClip) -> some View {
        Group {
            if let avatar = clip.authorAvatar, let url = URL(string: avatar) {
                AsyncCachedImage(url: url) {
                    Circle().fill(Color.white.opacity(0.2))
                } content: { img in
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } fallback: {
                    Circle().fill(Color.white.opacity(0.2))
                }
                .frame(width: 44, height: 44)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1.5))
            } else {
                Circle()
                    .fill(Color.slooshAccent.opacity(0.3))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Text(String(clip.authorName.prefix(1)).uppercased())
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                    )
                    .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1.5))
            }
        }
    }

    // MARK: - Action Buttons

    private func likeButtonView(_ clip: MovieClip) -> some View {
        let isLiked = clipsRepo.isLiked(clipId: clip.id)

        return Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            Task {
                _ = await clipsRepo.toggleLike(for: clip.id)
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: isLiked ? "heart.fill" : "heart")
                    .font(.system(size: 26))
                    .foregroundStyle(isLiked ? .red : .white)
                    .scaleEffect(isLiked ? 1.1 : 1.0)
                    .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isLiked)

                Text("\(clip.likesCount)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
    }

    private func commentButtonView(_ clip: MovieClip) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showCommentsForClip = clip
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.white)

                Text("\(clip.commentsCount)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
    }

    private func shareButtonView(_ clip: MovieClip) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            shareClip(clip)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "arrowshape.turn.up.right.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.white)

                Text("Поделиться")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
    }

    // MARK: - Dynamic Playback Logic

    private func setupPlayer(for clip: MovieClip) {
        cleanupActivePlayer()
        isResolving = true
        isVideoReady = false

        resolvePlaybackTask = Task { @MainActor in
            guard let playUrl = await ClipStreamResolver.shared.resolveStreamUrl(for: clip) else {
                self.isResolving = false
                return
            }
            guard !Task.isCancelled, currentClipId == clip.id else { return }

            let item = AVPlayerItem(url: playUrl)
            item.preferredForwardBufferDuration = 10.0
            let player = AVPlayer(playerItem: item)
            player.isMuted = isMuted
            player.automaticallyWaitsToMinimizeStalling = true
            self.activePlayer = player
            self.isPlaying = true

            let startCM = CMTime(seconds: clip.startTime, preferredTimescale: 600)
            player.seek(to: startCM, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                if !Task.isCancelled {
                    player.play()
                }
            }

            // Observe item status
            playerStatusObserver = item.observe(\.status, options: [.new]) { [weak self] observedItem, _ in
                Task { @MainActor [weak self] in
                    guard let self, self.currentClipId == clip.id else { return }
                    if observedItem.status == .readyToPlay {
                        self.isVideoReady = true
                        self.isResolving = false
                    }
                }
            }

            // Observe timeControlStatus
            playerTimeStatusObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] observedPlayer, _ in
                Task { @MainActor [weak self] in
                    guard let self, self.currentClipId == clip.id else { return }
                    if observedPlayer.timeControlStatus == .playing {
                        self.isVideoReady = true
                        self.isResolving = false
                    }
                }
            }

            // Loop observer strictly within clip range [startTime, endTime]
            let interval = CMTime(seconds: 0.2, preferredTimescale: 600)
            timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self, weak player] time in
                guard let self, let player else { return }
                let currentSec = CMTimeGetSeconds(time)
                if currentSec >= clip.endTime || currentSec < max(0, clip.startTime - 1.0) {
                    let sTime = CMTime(seconds: clip.startTime, preferredTimescale: 600)
                    player.seek(to: sTime, toleranceBefore: .zero, toleranceAfter: .zero)
                }
            }
        }
    }

    private func togglePlayPause() {
        guard let player = activePlayer else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func pauseActivePlayer() {
        activePlayer?.pause()
        isPlaying = false
    }

    private func resumeActivePlayer() {
        if let clipId = currentClipId, let clip = clipsRepo.clips.first(where: { $0.id == clipId }) {
            if activePlayer == nil {
                setupPlayer(for: clip)
            } else {
                activePlayer?.play()
                isPlaying = true
            }
        }
    }

    private func cleanupActivePlayer() {
        resolvePlaybackTask?.cancel()
        resolvePlaybackTask = nil
        playerStatusObserver?.invalidate()
        playerStatusObserver = nil
        playerTimeStatusObserver?.invalidate()
        playerTimeStatusObserver = nil

        if let observer = timeObserver, let player = activePlayer {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
        activePlayer?.pause()
        activePlayer = nil
        isVideoReady = false
        isResolving = false
    }

    private func triggerDoubleTapLike(for clip: MovieClip, at location: CGPoint) {
        bigHeartPosition = location
        withAnimation {
            showBigHeart = true
        }
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()

        Task {
            if !clipsRepo.isLiked(clipId: clip.id) {
                _ = await clipsRepo.toggleLike(for: clip.id)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation {
                showBigHeart = false
            }
        }
    }

    private func shareClip(_ clip: MovieClip) {
        let shareText = "Смотри лучший момент из «\(clip.title)» в sloosh! 🔥\n\(clip.caption)"
        let av = UIActivityViewController(activityItems: [shareText], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(av, animated: true)
        }
    }

    // MARK: - Open Full Movie

    private func openFullMovie(clip: MovieClip) {
        pauseActivePlayer()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        let config = PlayerConfig(
            iframeUrl: clip.iframeUrl,
            title: clip.title,
            kpId: clip.kpId,
            season: clip.season,
            episode: clip.episode,
            voiceover: clip.translationName,
            streamUrl: nil, // Clear direct streamUrl so PlayerView resolves fresh session without 403 errors
            voices: clip.translationName != nil ? [clip.translationName!] : [],
            posterUrl: clip.posterPath,
            backdropUrl: clip.backdropPath,
            logoUrl: clip.logoPath,
            initialPlaybackTime: clip.startTime
        )
        self.fullPlayerConfig = config
    }
}
