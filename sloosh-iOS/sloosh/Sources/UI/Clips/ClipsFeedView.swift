import SwiftUI
import UIKit
import AVKit
import Combine

// MARK: - Dedicated Playback Coordinator for Feed

@MainActor
final class ClipPlaybackCoordinator: ObservableObject {
    @Published var activePlayer: AVPlayer?
    @Published var isVideoReady: Bool = false
    @Published var isResolving: Bool = false
    @Published var isPlaying: Bool = true
    @Published var isMuted: Bool = false
    @Published var clipProgress: Double = 0.0

    private var currentClipId: String?
    private var timeObserver: Any?
    private var playerStatusObserver: NSKeyValueObservation?
    private var playerTimeStatusObserver: NSKeyValueObservation?
    private var resolvePlaybackTask: Task<Void, Never>?

    func setupPlayer(for clip: MovieClip) {
        cleanup()
        currentClipId = clip.id
        isResolving = true
        isVideoReady = false
        clipProgress = 0.0

        resolvePlaybackTask = Task { [weak self] in
            guard let self else { return }
            guard let playUrl = await ClipStreamResolver.shared.resolveStreamUrl(for: clip) else {
                self.isResolving = false
                return
            }
            guard !Task.isCancelled, self.currentClipId == clip.id else { return }

            let item = AVPlayerItem(url: playUrl)
            item.preferredForwardBufferDuration = 10.0
            let player = AVPlayer(playerItem: item)
            player.isMuted = self.isMuted
            player.automaticallyWaitsToMinimizeStalling = true
            self.activePlayer = player
            self.isPlaying = true

            let startCM = CMTime(seconds: clip.startTime, preferredTimescale: 600)
            player.seek(to: startCM, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                if !Task.isCancelled {
                    player.play()
                }
            }

            self.playerStatusObserver = item.observe(\.status, options: [.new]) { [weak self] observedItem, _ in
                Task { @MainActor [weak self] in
                    guard let self, self.currentClipId == clip.id else { return }
                    if observedItem.status == .readyToPlay {
                        self.isVideoReady = true
                        self.isResolving = false
                    }
                }
            }

            self.playerTimeStatusObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] observedPlayer, _ in
                Task { @MainActor [weak self] in
                    guard let self, self.currentClipId == clip.id else { return }
                    if observedPlayer.timeControlStatus == .playing {
                        self.isVideoReady = true
                        self.isResolving = false
                    }
                }
            }

            let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
            self.timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self, weak player] time in
                guard let self, let player else { return }
                let currentSec = CMTimeGetSeconds(time)
                let clipDur = max(1.0, clip.endTime - clip.startTime)
                let elapsed = max(0.0, currentSec - clip.startTime)
                self.clipProgress = min(1.0, max(0.0, elapsed / clipDur))

                if currentSec >= clip.endTime || currentSec < max(0, clip.startTime - 1.0) {
                    let sTime = CMTime(seconds: clip.startTime, preferredTimescale: 600)
                    player.seek(to: sTime, toleranceBefore: .zero, toleranceAfter: .zero)
                }
            }
        }
    }

    func togglePlayPause() {
        guard let player = activePlayer else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    func toggleMute() {
        isMuted.toggle()
        activePlayer?.isMuted = isMuted
    }

    func pause() {
        activePlayer?.pause()
        isPlaying = false
    }

    func resume(for clip: MovieClip?) {
        guard let clip else { return }
        if activePlayer == nil || currentClipId != clip.id {
            setupPlayer(for: clip)
        } else {
            activePlayer?.play()
            isPlaying = true
        }
    }

    func cleanup() {
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
        clipProgress = 0.0
    }

    deinit {
        resolvePlaybackTask?.cancel()
        playerStatusObserver?.invalidate()
        playerTimeStatusObserver?.invalidate()
    }
}

// MARK: - Clips Feed View

public struct ClipsFeedView: View {
    @StateObject private var clipsRepo = ClipsRepository.shared
    @StateObject private var authRepo = AuthRepository.shared
    @StateObject private var playback = ClipPlaybackCoordinator()

    @State private var currentClipId: String?
    @State private var pipController: AVPictureInPictureController? = nil
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
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .environment(\.colorScheme, .dark)
        .task {
            await clipsRepo.fetchFeed()
            if currentClipId == nil, let first = clipsRepo.clips.first {
                currentClipId = first.id
                playback.setupPlayer(for: first)
            }
        }
        .sheet(item: $showCommentsForClip) { clip in
            ClipCommentsSheetView(clip: clip)
        }
        .fullScreenCover(item: $fullPlayerConfig, onDismiss: {
            fullPlayerConfig = nil
            resumeActiveClip()
        }) { config in
            PlayerView(config: config)
                .preferredColorScheme(.dark)
                .environment(\.colorScheme, .dark)
        }
        .onDisappear {
            playback.pause()
        }
        .onAppear {
            resumeActiveClip()
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
                        playback.setupPlayer(for: first)
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
            playback.setupPlayer(for: clip)
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
                .frame(width: size.width, height: size.height)
                .clipped()
                .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }

            // 2. Hardware Video Player Layer (Fades in smoothly when ready to play)
            if isCurrent, let player = playback.activePlayer {
                VideoLayerView(player: player, pipController: $pipController, videoGravity: .resizeAspectFill)
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .ignoresSafeArea()
                    .opacity(playback.isVideoReady ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 0.25), value: playback.isVideoReady)
            }

            // 3. Loading spinner indicator while resolving or buffering
            if isCurrent && (playback.isResolving || !playback.isVideoReady) {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.3)
                    .shadow(color: .black.opacity(0.8), radius: 6)
            }

            // 4. Subtle Dark Gradient for top and bottom readability
            VStack {
                LinearGradient(
                    colors: [.black.opacity(0.7), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
                .frame(height: 140)
                .ignoresSafeArea(edges: .top)

                Spacer()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.4), .black.opacity(0.92)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 380)
                .ignoresSafeArea(edges: .bottom)
            }
            .allowsHitTesting(false)

            // 5. Full Screen Tap Area (Single tap: play/pause, Double tap: like)
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2, coordinateSpace: .local) { location in
                    triggerDoubleTapLike(for: clip, at: location)
                }
                .onTapGesture(count: 1) {
                    playback.togglePlayPause()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }

            // 6. Big Center Pause Indicator
            if !playback.isPlaying && isCurrent && playback.isVideoReady {
                Image(systemName: "play.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(24)
                    .background(Color.black.opacity(0.55))
                    .glassEffect(.regular.interactive(), in: .circle)
                    .clipShape(Circle())
                    .transition(.scale.combined(with: .opacity))
                    .allowsHitTesting(false)
            }

            // 7. Big Heart Animation on Double-Tap
            if showBigHeart {
                Image(systemName: "heart.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.red)
                    .shadow(color: .red.opacity(0.6), radius: 24)
                    .position(bigHeartPosition)
                    .scaleEffect(showBigHeart ? 1.25 : 0.4)
                    .opacity(showBigHeart ? 1.0 : 0.0)
                    .animation(.spring(response: 0.35, dampingFraction: 0.6), value: showBigHeart)
                    .allowsHitTesting(false)
            }

            // 8. Main Overlay UI Layer (Top Bar + Bottom Content + Right Rail Actions)
            VStack(spacing: 0) {
                // Top Bar: Pill Title + Mute Button
                topBarView(safeArea: safeArea)

                Spacer()

                // Bottom Area: Left Info + Right Buttons
                HStack(alignment: .bottom, spacing: 14) {
                    // Left Column: Film Title, Badges, Caption, Author, Watch CTA
                    leftInfoView(clip: clip)

                    Spacer(minLength: 8)

                    // Right Rail Action Buttons
                    rightRailView(clip: clip)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

                // 9. Real-Time Scrubber Progress Bar
                if isCurrent {
                    progressBarView
                        .padding(.horizontal, 16)
                        .padding(.bottom, max(safeArea.bottom, 16) + 54) // Strictly floats above the tab bar capsule
                } else {
                    Spacer().frame(height: max(safeArea.bottom, 16) + 54)
                }
            }
        }
    }

    // MARK: - Top Bar

    private func topBarView(safeArea: EdgeInsets) -> some View {
        HStack {
            // Glass Feed Badge
            HStack(spacing: 6) {
                Image(systemName: "sparkles.tv.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.slooshAccent)

                Text("Моменты")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Color.black.opacity(0.45))
            .glassEffect(.regular.interactive(), in: .capsule)

            Spacer()

            // Mute Button
            Button {
                playback.toggleMute()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: playback.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Color.black.opacity(0.45))
                    .clipShape(Circle())
            }
            .buttonStyle(.glassPress)
            .glassEffect(.regular.interactive(), in: .circle)
        }
        .padding(.top, max(safeArea.top, 20) + 6)
        .padding(.horizontal, 16)
    }

    // MARK: - Left Info View

    private func leftInfoView(clip: MovieClip) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title & Badges
            VStack(alignment: .leading, spacing: 4) {
                Text(clip.title)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.9), radius: 6)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(clip.subtitleInfo)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.55))
                        .glassEffect(.regular.interactive(), in: .capsule)

                    Text(clip.formattedDuration)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.slooshAccent)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.55))
                        .glassEffect(.regular.interactive(), in: .capsule)

                    Text(clip.mediaType == "tv" ? "Сериал" : "Фильм")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            // Caption text (Expandable)
            if !clip.caption.isEmpty {
                Text(clip.caption)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(isTextExpanded ? 8 : 2)
                    .shadow(color: .black.opacity(0.9), radius: 4)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isTextExpanded.toggle()
                        }
                    }
            }

            // Author attribution
            HStack(spacing: 5) {
                Text("Опубликовал:")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))

                Text("@\(clip.authorName)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.slooshAccent)
            }

            // CTA Button: «Смотреть фильм с этого момента»
            Button {
                openFullMovie(clip: clip)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 13, weight: .bold))

                    Text("Смотреть с этого момента")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Color.slooshAccent)
                .clipShape(Capsule())
                .shadow(color: Color.slooshAccent.opacity(0.45), radius: 10, y: 3)
            }
            .buttonStyle(.glassPress)
            .padding(.top, 2)
        }
    }

    // MARK: - Right Rail View

    private func rightRailView(clip: MovieClip) -> some View {
        VStack(spacing: 16) {
            // Author Avatar
            authorAvatarView(clip)

            // Like Button
            likeButtonView(clip)

            // Comments Button
            commentButtonView(clip)

            // Share Button
            shareButtonView(clip)
        }
        .padding(.bottom, 4)
    }

    // MARK: - Scrubber Progress Bar

    private var progressBarView: some View {
        GeometryReader { barProxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.2))
                    .frame(height: 3)

                Capsule()
                    .fill(Color.slooshAccent)
                    .frame(width: max(0, barProxy.size.width * playback.clipProgress), height: 3)
            }
        }
        .frame(height: 3)
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
                .overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 1.5))
            } else {
                Circle()
                    .fill(Color.slooshAccent.opacity(0.35))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Text(String(clip.authorName.prefix(1)).uppercased())
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                    )
                    .overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 1.5))
            }
        }
        .shadow(color: .black.opacity(0.5), radius: 4)
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
                    .scaleEffect(isLiked ? 1.15 : 1.0)
                    .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isLiked)
                    .shadow(color: isLiked ? .red.opacity(0.6) : .black.opacity(0.7), radius: 6)

                Text("\(clip.likesCount)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.8), radius: 3)
            }
        }
        .buttonStyle(.glassPress)
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
                    .shadow(color: .black.opacity(0.7), radius: 6)

                Text("\(clip.commentsCount)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.8), radius: 3)
            }
        }
        .buttonStyle(.glassPress)
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
                    .shadow(color: .black.opacity(0.7), radius: 6)

                Text("Поделиться")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .shadow(color: .black.opacity(0.8), radius: 3)
            }
        }
        .buttonStyle(.glassPress)
    }

    // MARK: - Helper Actions

    private func resumeActiveClip() {
        if let clipId = currentClipId, let clip = clipsRepo.clips.first(where: { $0.id == clipId }) {
            playback.resume(for: clip)
        }
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
        playback.pause()
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
