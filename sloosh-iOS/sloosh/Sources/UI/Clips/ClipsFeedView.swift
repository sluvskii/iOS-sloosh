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
    private var didPerformInitialSeek: Bool = false

    func setupPlayer(for clip: MovieClip) {
        cleanup()
        currentClipId = clip.id
        isResolving = true
        isVideoReady = false
        clipProgress = 0.0
        didPerformInitialSeek = false

        resolvePlaybackTask = Task { [weak self] in
            guard let self else { return }
            guard let playUrl = await ClipStreamResolver.shared.resolveStreamUrl(for: clip) else {
                self.isResolving = false
                return
            }
            guard !Task.isCancelled, self.currentClipId == clip.id else { return }

            let asset = AVURLAsset(url: playUrl)
            let item = AVPlayerItem(asset: asset)
            item.preferredForwardBufferDuration = 5.0

            let player = AVPlayer(playerItem: item)
            player.isMuted = self.isMuted
            player.actionAtItemEnd = .none
            player.automaticallyWaitsToMinimizeStalling = true
            self.activePlayer = player
            self.isPlaying = true

            // Observe item status for ready to play & initial seek
            self.playerStatusObserver = item.observe(\.status, options: [.new, .initial]) { [weak self, weak player] observedItem, _ in
                Task { @MainActor [weak self] in
                    guard let self, self.currentClipId == clip.id, let player else { return }
                    if observedItem.status == .readyToPlay {
                        self.isResolving = false
                        self.isVideoReady = true

                        if !self.didPerformInitialSeek {
                            self.didPerformInitialSeek = true
                            if clip.startTime > 0.5 {
                                let sTime = CMTime(seconds: clip.startTime, preferredTimescale: 600)
                                player.seek(to: sTime, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                                    player.play()
                                }
                            } else {
                                player.play()
                            }
                        } else {
                            player.play()
                        }
                    } else if observedItem.status == .failed {
                        print("[ClipPlayback] AVPlayerItem failed: \(String(describing: observedItem.error))")
                        self.isResolving = false
                    }
                }
            }

            // Observe time control status
            self.playerTimeStatusObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] observedPlayer, _ in
                Task { @MainActor [weak self] in
                    guard let self, self.currentClipId == clip.id else { return }
                    if observedPlayer.timeControlStatus == .playing {
                        self.isVideoReady = true
                        self.isResolving = false
                    }
                }
            }

            // Periodic time observer for progress and looping
            let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
            self.timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self, weak player] time in
                guard let self, let player else { return }
                let currentSec = CMTimeGetSeconds(time)
                guard currentSec.isFinite else { return }

                let clipDur = max(1.0, clip.endTime - clip.startTime)
                let elapsed = max(0.0, currentSec - clip.startTime)
                self.clipProgress = min(1.0, max(0.0, elapsed / clipDur))

                // Loop back to start ONLY when video reaches or exceeds clip.endTime
                if currentSec >= clip.endTime {
                    let sTime = CMTime(seconds: clip.startTime, preferredTimescale: 600)
                    player.seek(to: sTime, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                        player.play()
                    }
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
        didPerformInitialSeek = false
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
        let topSafeArea = max(safeArea.top, (UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.windows.first?.safeAreaInsets.top }.first ?? 47.0))
        let bottomSafeArea = max(safeArea.bottom, (UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.windows.first?.safeAreaInsets.bottom }.first ?? 34.0))

        return ZStack {
            // 1. Base Layer: High-Res Backdrop/Poster
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

            // 2. Hardware Video Player Layer
            if isCurrent, let player = playback.activePlayer {
                VideoLayerView(player: player, pipController: $pipController, videoGravity: .resizeAspectFill)
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .ignoresSafeArea()
                    .opacity(playback.isVideoReady ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 0.2), value: playback.isVideoReady)
            }

            // 3. Loading Spinner Indicator (subtle, centered)
            if isCurrent && (playback.isResolving || !playback.isVideoReady) {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.2)
                    .shadow(color: .black.opacity(0.8), radius: 6)
            }

            // 4. Cinematic Dark Gradients for Readability
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [.black.opacity(0.55), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: topSafeArea + 50)
                .ignoresSafeArea(edges: .top)

                Spacer()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.4), .black.opacity(0.9)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: bottomSafeArea + 240)
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

            // 6. Play / Pause Centered Indicator
            if !playback.isPlaying && isCurrent && playback.isVideoReady {
                Image(systemName: "play.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 60, height: 60)
                    .background(Color.black.opacity(0.45))
                    .glassEffect(.regular.interactive(), in: .circle)
                    .clipShape(Circle())
                    .transition(.scale.combined(with: .opacity))
                    .allowsHitTesting(false)
            }

            // 7. Big Heart Explosion on Double-Tap
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

            // 8. Top Bar: Discreet Glass Mute Button
            VStack {
                HStack {
                    Spacer()

                    Button {
                        playback.toggleMute()
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Image(systemName: playback.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.black.opacity(0.4))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.glassPress)
                    .glassEffect(.regular.interactive(), in: .circle)
                }
                .padding(.top, topSafeArea + 8)
                .padding(.trailing, 16)

                Spacer()
            }

            // 9. Bottom Overlays (Info, Right Rail, Scrubber)
            VStack(spacing: 0) {
                Spacer()

                // Content Row: Info on left, Actions on right
                HStack(alignment: .bottom, spacing: 12) {
                    leftInfoView(clip: clip)

                    Spacer(minLength: 4)

                    rightRailView(clip: clip)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                // Real-Time Scrubber Progress Bar
                if isCurrent {
                    progressBarView
                        .padding(.horizontal, 16)
                        .padding(.bottom, bottomSafeArea + 58)
                } else {
                    Spacer().frame(height: bottomSafeArea + 58)
                }
            }
        }
    }

    // MARK: - Left Info View

    private func leftInfoView(clip: MovieClip) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Author Username
            Text("@\(clip.authorName)")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.8), radius: 4)

            // Film / Series Title & Info
            HStack(spacing: 6) {
                Image(systemName: "film")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))

                Text(clip.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)

                if let s = clip.season, let e = clip.episode {
                    Text("• \(s) сезон, \(e) серия")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                }
            }
            .shadow(color: .black.opacity(0.8), radius: 4)

            // Caption Text (Expandable on tap)
            if !clip.caption.isEmpty {
                Text(clip.caption)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(isTextExpanded ? 6 : 2)
                    .shadow(color: .black.opacity(0.8), radius: 4)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isTextExpanded.toggle()
                        }
                    }
                    .padding(.vertical, 1)
            }

            // Pure Liquid Glass Watch Full Movie Button
            Button {
                openFullMovie(clip: clip)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11, weight: .bold))

                    Text("Смотреть с этого момента")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
            }
            .glassEffect(.regular.interactive(), in: .capsule)
            .buttonStyle(.glassPress)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        .frame(width: 50)
    }

    // MARK: - Scrubber Progress Bar

    private var progressBarView: some View {
        GeometryReader { barProxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.25))
                    .frame(height: 2.5)

                Capsule()
                    .fill(Color.white)
                    .frame(width: max(0, barProxy.size.width * playback.clipProgress), height: 2.5)
            }
        }
        .frame(height: 2.5)
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
                .frame(width: 38, height: 38)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1.5))
            } else {
                Circle()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 38, height: 38)
                    .overlay(
                        Text(String(clip.authorName.prefix(1)).uppercased())
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    )
                    .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1.5))
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
            VStack(spacing: 3) {
                Image(systemName: isLiked ? "heart.fill" : "heart")
                    .font(.system(size: 26))
                    .foregroundStyle(isLiked ? .red : .white)
                    .scaleEffect(isLiked ? 1.15 : 1.0)
                    .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isLiked)
                    .shadow(color: isLiked ? .red.opacity(0.6) : .black.opacity(0.7), radius: 6)

                Text("\(clip.likesCount)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
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
            VStack(spacing: 3) {
                Image(systemName: "bubble.right.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.7), radius: 6)

                Text("\(clip.commentsCount)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
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
            Image(systemName: "arrowshape.turn.up.right.fill")
                .font(.system(size: 24))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.7), radius: 6)
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
            streamUrl: nil,
            voices: clip.translationName != nil ? [clip.translationName!] : [],
            posterUrl: clip.posterPath,
            backdropUrl: clip.backdropPath,
            logoUrl: clip.logoPath,
            initialPlaybackTime: clip.startTime
        )
        self.fullPlayerConfig = config
    }
}
