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
    @Published var clipProgress: Double = 0.0
    @Published var isScrubbing: Bool = false
    @Published var isFastForwarding: Bool = false
    @Published var hasError: Bool = false

    private var currentClipId: String?
    private var timeObserver: Any?
    private var playerStatusObserver: NSKeyValueObservation?
    private var playerTimeStatusObserver: NSKeyValueObservation?
    private var resolvePlaybackTask: Task<Void, Never>?
    private var didPerformInitialSeek: Bool = false
    private var retryCount: Int = 0

    func setupPlayer(for clip: MovieClip, isRetry: Bool = false) {
        cleanup()
        currentClipId = clip.id
        isResolving = true
        isVideoReady = false
        hasError = false
        clipProgress = 0.0
        isScrubbing = false
        isFastForwarding = false
        didPerformInitialSeek = false
        if !isRetry {
            retryCount = 0
        }
        AppDiagnostics.shared.log("[ClipPlayback] setupPlayer clip=\(clip.id) title=\(clip.title) startTime=\(clip.startTime)")

        resolvePlaybackTask = Task { [weak self] in
            guard let self else { return }
            guard let playbackInfo = await ClipStreamResolver.shared.resolveClip(for: clip) else {
                self.isResolving = false
                self.hasError = true
                AppDiagnostics.shared.log("[ClipPlayback] Failed to resolve clip=\(clip.id)")
                return
            }
            guard !Task.isCancelled, self.currentClipId == clip.id else { return }

            let asset = AVURLAsset(url: playbackInfo.url, options: ["AVURLAssetHTTPHeaderFieldsKey": playbackInfo.headers])
            let item = AVPlayerItem(asset: asset)
            item.preferredForwardBufferDuration = 3.0

            let player = AVPlayer(playerItem: item)
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
                        self.hasError = false
                        AppDiagnostics.shared.log("[ClipPlayback] readyToPlay clip=\(clip.id)")

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
                        AppDiagnostics.shared.log("[ClipPlayback] AVPlayerItem failed for clip=\(clip.id): \(String(describing: observedItem.error))")
                        if self.retryCount < 1 {
                            self.retryCount += 1
                            ClipStreamResolver.shared.invalidate(clipId: clip.id)
                            self.setupPlayer(for: clip, isRetry: true)
                        } else {
                            self.isResolving = false
                            self.hasError = true
                        }
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
                        self.hasError = false
                    }
                }
            }

            // Periodic time observer for progress and looping
            let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
            self.timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self, weak player] time in
                guard let self, let player, !self.isScrubbing else { return }
                let currentSec = CMTimeGetSeconds(time)
                guard currentSec.isFinite else { return }

                let clipDur = max(1.0, clip.endTime - clip.startTime)
                let elapsed = max(0.0, currentSec - clip.startTime)
                self.clipProgress = min(1.0, max(0.0, elapsed / clipDur))

                // Loop back to start ONLY when video reaches or exceeds clip.endTime
                if currentSec >= clip.endTime {
                    let sTime = CMTime(seconds: clip.startTime, preferredTimescale: 600)
                    player.seek(to: sTime, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                        if self.isPlaying {
                            if self.isFastForwarding {
                                player.rate = 2.0
                            } else {
                                player.play()
                            }
                        }
                    }
                }
            }
        }
    }

    func beginScrubbing() {
        isScrubbing = true
        activePlayer?.pause()
    }

    func scrubToProgress(_ progress: Double, for clip: MovieClip) {
        guard let player = activePlayer else { return }
        let clipDur = max(1.0, clip.endTime - clip.startTime)
        let targetSec = clip.startTime + (clipDur * max(0.0, min(1.0, progress)))
        let time = CMTime(seconds: targetSec, preferredTimescale: 600)
        clipProgress = progress
        // Fast seek during drag for silky smooth preview without freezing
        player.seek(to: time, toleranceBefore: CMTime(seconds: 0.15, preferredTimescale: 600), toleranceAfter: CMTime(seconds: 0.15, preferredTimescale: 600))
    }

    func endScrubbing(at progress: Double, for clip: MovieClip) {
        guard let player = activePlayer else {
            isScrubbing = false
            return
        }
        let clipDur = max(1.0, clip.endTime - clip.startTime)
        let targetSec = clip.startTime + (clipDur * max(0.0, min(1.0, progress)))
        let time = CMTime(seconds: targetSec, preferredTimescale: 600)
        clipProgress = progress
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self, weak player] _ in
            guard let self, let player else { return }
            self.isScrubbing = false
            if self.isPlaying {
                player.play()
            }
        }
    }

    func seekToProgress(_ progress: Double, for clip: MovieClip) {
        endScrubbing(at: progress, for: clip)
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

    func startFastForward() {
        guard let player = activePlayer, isPlaying else { return }
        isFastForwarding = true
        player.rate = 2.0
    }

    func stopFastForward() {
        guard let player = activePlayer else {
            isFastForwarding = false
            return
        }
        isFastForwarding = false
        if isPlaying {
            player.rate = 1.0
        } else {
            player.pause()
        }
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
        hasError = false
        clipProgress = 0.0
        isFastForwarding = false
        didPerformInitialSeek = false
    }

    deinit {
        resolvePlaybackTask?.cancel()
        playerStatusObserver?.invalidate()
        playerTimeStatusObserver?.invalidate()
    }
}

// MARK: - Video Scale Mode for Clips

public enum ClipScalingMode: String, CaseIterable {
    case fit = "fit"     // "В кадре" - native aspect ratio with cinema ambient glow
    case fill = "fill"   // "9:16" - zoomed to fill vertical viewport
}

// MARK: - Clips Feed View

public struct ClipsFeedView: View {
    @StateObject private var clipsRepo = ClipsRepository.shared
    @StateObject private var authRepo = AuthRepository.shared
    @StateObject private var playback = ClipPlaybackCoordinator()

    @AppStorage("clipsVideoScaleMode") private var clipScaleModeRaw: String = ClipScalingMode.fit.rawValue

    private var currentScaleMode: ClipScalingMode {
        ClipScalingMode(rawValue: clipScaleModeRaw) ?? .fit
    }

    @State private var currentClipId: String?
    @State private var showCommentsForClip: MovieClip?
    @State private var fullPlayerConfig: PlayerConfig?
    @State private var showBigHeart: Bool = false
    @State private var bigHeartPosition: CGPoint = .zero
    @State private var isTextExpanded: Bool = false
    @State private var isScrubbing: Bool = false
    @State private var scrubProgress: Double = 0.0
    @State private var lastTapTime: Date = Date.distantPast

    public init() {}

    public var body: some View {
        GeometryReader { proxy in
            let safeArea = proxy.safeAreaInsets
            let topSafeArea = max(safeArea.top, (UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.windows.first?.safeAreaInsets.top }.first ?? 47.0))

            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()

                if clipsRepo.isLoading && clipsRepo.clips.isEmpty {
                    VStack(spacing: 16) {
                        ProgressView()
                            .tint(.white)
                        Text("Загрузка моментов...")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if clipsRepo.clips.isEmpty {
                    emptyStateView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    feedScrollView(proxy: proxy)
                }

                // Top Header Bar: "Моменты" with progressive Variable Blur
                if !clipsRepo.clips.isEmpty {
                    topHeaderBar(topSafeArea: topSafeArea)
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
        .onChange(of: currentClipId) { oldId, newId in
            AppDiagnostics.shared.log("[ClipsFeedView] currentClipId changed from \(String(describing: oldId)) to \(String(describing: newId))")
            guard let newId = newId, let clip = clipsRepo.clips.first(where: { $0.id == newId }) else { return }
            playback.setupPlayer(for: clip)
        }
    }

    // MARK: - Top Header Bar

    private func topHeaderBar(topSafeArea: CGFloat) -> some View {
        let isCommentsOpen = (showCommentsForClip != nil)
        let isOverlayHidden = isScrubbing || playback.isFastForwarding || isCommentsOpen

        return VStack(spacing: 0) {
            ZStack {
                Text("Моменты")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.7), radius: 6, x: 0, y: 1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .padding(.top, max(0, topSafeArea - 8))
        }
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                stops: [
                    .init(color: Color.black.opacity(0.85), location: 0.0),
                    .init(color: Color.black.opacity(0.48), location: 0.55),
                    .init(color: Color.black.opacity(0.0), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .padding(.bottom, -24)
            .ignoresSafeArea(edges: .top)
        )
        .opacity(isOverlayHidden ? 0.0 : 1.0)
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: isOverlayHidden)
        .allowsHitTesting(false)
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - Clip Card

    private func clipCard(_ clip: MovieClip, size: CGSize, safeArea: EdgeInsets) -> some View {
        let isCurrent = (currentClipId == clip.id)
        let topSafeArea = max(safeArea.top, (UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.windows.first?.safeAreaInsets.top }.first ?? 47.0))
        let bottomSafeArea = max(safeArea.bottom, (UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.windows.first?.safeAreaInsets.bottom }.first ?? 34.0))

        let bottomTabBarHeight: CGFloat = bottomSafeArea + 52.0
        let scrubberHeight: CGFloat = 24.0
        let scrubberGap: CGFloat = 2.0

        // Calculate available height strictly between top status bar and bottom scrubber
        let availableHeight = max(200.0, size.height - topSafeArea - bottomTabBarHeight - scrubberHeight - scrubberGap)

        return VStack(spacing: 0) {
            // 1. Top status bar clearance
            Spacer()
                .frame(height: topSafeArea)

            // 2. Video Container with smooth corner radius
            videoCardContainer(clip, width: size.width, height: availableHeight, isCurrent: isCurrent)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            // 3. Gap between video card and progress bar
            Spacer()
                .frame(height: scrubberGap)

            // 4. Progress bar (полоса перемотки)
            if isCurrent {
                progressBarView(for: clip)
                    .padding(.horizontal, 14)
                    .frame(height: scrubberHeight)
                    .opacity(showCommentsForClip != nil ? 0.0 : 1.0)
                    .animation(.spring(response: 0.28, dampingFraction: 0.85), value: showCommentsForClip != nil)
            } else {
                Color.clear
                    .frame(height: scrubberHeight)
            }

            // 5. Bottom Tab Bar clearance
            Spacer()
                .frame(height: bottomTabBarHeight)
        }
        .frame(width: size.width, height: size.height)
        .background(Color.black)
    }

    // MARK: - Video Card Container

    private func videoCardContainer(_ clip: MovieClip, width: CGFloat, height: CGFloat, isCurrent: Bool) -> some View {
        let isCommentsOpen = (showCommentsForClip != nil)
        let isOverlayHidden = isScrubbing || playback.isFastForwarding || isCommentsOpen
        let effectiveScaleMode: ClipScalingMode = isCommentsOpen ? .fit : currentScaleMode
        let effectiveVideoGravity: AVLayerVideoGravity = effectiveScaleMode == .fit ? .resizeAspect : .resizeAspectFill
        let commentsShift: CGFloat = isCommentsOpen ? -(height * 0.28) : 0.0

        return ZStack {
            // 1. Ambient Background (Backdrop with cinematic blur in .fit mode or during initial loading)
            if effectiveScaleMode == .fit || !playback.isVideoReady {
                if let backdrop = clip.backdropPath ?? clip.posterPath, let url = resolveImageUrl(path: backdrop) {
                    AsyncCachedImage(url: url) {
                        Color.black
                    } content: { img in
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: width, height: height)
                            .clipped()
                            .scaleEffect(1.25)
                            .saturation(1.4)
                            .blur(radius: 28)
                            .overlay(Color.black.opacity(0.42))
                    } fallback: {
                        Color.black
                    }
                    .frame(width: width, height: height)
                    .clipped()
                    .transition(.opacity)
                } else {
                    Color.black
                }
            } else {
                Color.black
            }

            // 2. Sharp Video Player Layer (Single Dedicated AVPlayerLayer)
            if isCurrent, let player = playback.activePlayer {
                VideoLayerView(
                    player: player,
                    videoGravity: effectiveVideoGravity
                )
                .frame(width: width, height: height)
                .offset(y: commentsShift)
                .clipped()
                .opacity(playback.isVideoReady ? 1.0 : 0.0)
                .animation(.spring(response: 0.38, dampingFraction: 0.82), value: isCommentsOpen)
                .animation(.easeInOut(duration: 0.25), value: playback.isVideoReady)
            }

            // 4. Cinematic Gradients for Contrast and Overlay Readability (hidden when comments or overlays are hidden)
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [.black.opacity(0.55), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 70)

                Spacer()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.45), .black.opacity(0.88)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 190)
            }
            .opacity(isOverlayHidden ? 0.0 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.85), value: isOverlayHidden)
            .allowsHitTesting(false)

            // 5. Touch & Gesture Zones: Edge 2x Speed, Center Instant 0ms Play/Pause
            HStack(spacing: 0) {
                // Left Edge 2x Speed Zone (75pt)
                edgeAccelerationZone(for: clip)
                    .frame(width: 75)

                // Center Instant Play/Pause & Double-Tap Heart Zone
                centerTapZone(clip: clip)
                    .frame(maxWidth: .infinity)

                // Right Edge 2x Speed Zone (75pt)
                edgeAccelerationZone(for: clip)
                    .frame(width: 75)
            }
            .frame(width: width, height: height)

            // 6. Play / Pause Indicator in Center (Liquid Glass with Spring Animation, perfectly centered)
            if !playback.isPlaying && isCurrent && playback.isVideoReady && !isOverlayHidden {
                Image(systemName: "play.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 72)
                    .glassEffect(in: .circle)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.5), radius: 14, y: 3)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.5).combined(with: .opacity),
                            removal: .scale(scale: 1.25).combined(with: .opacity)
                        )
                    )
                    .allowsHitTesting(false)
            }

            // 7. Top 2x Fast-Forward Indicator Badge
            VStack {
                if playback.isFastForwarding {
                    HStack(spacing: 6) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 13, weight: .bold))

                        Text("2x Ускорение")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .glassEffect(in: .capsule)
                    .padding(.top, 14)
                    .transition(.move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.9)))
                }

                Spacer()
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: playback.isFastForwarding)
            .allowsHitTesting(false)

            // 8. Big Heart Explosion on Double-Tap
            if showBigHeart {
                Image(systemName: "heart.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(Color.slooshAccent)
                    .position(bigHeartPosition)
                    .scaleEffect(showBigHeart ? 1.25 : 0.4)
                    .opacity(showBigHeart ? 1.0 : 0.0)
                    .animation(.spring(response: 0.35, dampingFraction: 0.6), value: showBigHeart)
                    .allowsHitTesting(false)
            }

            // 9. Playback Error & Retry Indicator
            if isCurrent && playback.hasError && !isOverlayHidden {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    playback.setupPlayer(for: clip, isRetry: false)
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.system(size: 38))
                            .foregroundStyle(.white)

                        Text("Ошибка загрузки")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)

                        Text("Нажмите, чтобы повторить")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.slooshAccent)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .glassEffect(in: .rect(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }

            // 10. Bottom Overlays (Left Info & Symmetrical Right Action Rail)
            VStack(spacing: 0) {
                Spacer()

                HStack(alignment: .bottom, spacing: 8) {
                    leftInfoView(clip: clip)

                    Spacer(minLength: 4)

                    rightRailView(clip: clip)
                }
                .padding(.leading, 14)
                .padding(.trailing, 14)
                .padding(.bottom, 14)
            }
            .opacity(isOverlayHidden ? 0.0 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.85), value: isOverlayHidden)
            .allowsHitTesting(!isOverlayHidden)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Gesture Handling Zones

    private func edgeAccelerationZone(for clip: MovieClip) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0.28, maximumDistance: 40) {
                // Long press completed
            } onPressingChanged: { isPressing in
                if isPressing {
                    if !playback.isScrubbing && playback.isPlaying {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                            playback.startFastForward()
                        }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                } else {
                    if playback.isFastForwarding {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                            playback.stopFastForward()
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }
            }
            .onTapGesture {
                handleCenterTap(at: .zero, for: clip)
            }
    }

    private func centerTapZone(clip: MovieClip) -> some View {
        GeometryReader { geo in
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    handleCenterTap(at: CGPoint(x: geo.size.width / 2, y: geo.size.height / 2), for: clip)
                }
        }
    }

    private func handleCenterTap(at location: CGPoint, for clip: MovieClip) {
        let now = Date()
        if now.timeIntervalSince(lastTapTime) < 0.28 {
            // Double tap detected: spawn heart like & ensure video plays
            lastTapTime = .distantPast
            triggerDoubleTapLike(for: clip, at: location == .zero ? CGPoint(x: 200, y: 350) : location)
            if !playback.isPlaying {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                    playback.togglePlayPause()
                }
            }
        } else {
            // Instant 0ms Single Tap Play/Pause
            lastTapTime = now
            withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                playback.togglePlayPause()
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    // MARK: - Left Info View

    private func leftInfoView(clip: MovieClip) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Movie / Series Logo (with text fallback)
            logoOrTitleView(clip: clip)

            // Season, Episode & Voiceover Info
            subtitleInfoView(clip: clip)

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
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect(in: .capsule)
            }
            .buttonStyle(.glassPress)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func resolveImageUrl(path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return URL(string: path)
        }
        if let normalized = normalizeImageUrl(path: path) {
            return URL(string: normalized)
        }
        return nil
    }

    @ViewBuilder
    private func logoOrTitleView(clip: MovieClip) -> some View {
        if let url = resolveImageUrl(path: clip.logoPath) {
            AsyncCachedImage(url: url) {
                fallbackTitleText(clip: clip)
            } content: { image in
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 36, alignment: .leading)
                    .shadow(color: .black.opacity(0.85), radius: 6, x: 0, y: 2)
            } fallback: {
                fallbackTitleText(clip: clip)
            }
        } else {
            fallbackTitleText(clip: clip)
        }
    }

    private func fallbackTitleText(clip: MovieClip) -> some View {
        Text(clip.title)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.8), radius: 4)
            .lineLimit(1)
    }

    @ViewBuilder
    private func subtitleInfoView(clip: MovieClip) -> some View {
        if let s = clip.season, let e = clip.episode {
            HStack(spacing: 4) {
                Text("\(s) сезон, \(e) серия")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))

                if let tr = clip.translationName, !tr.isEmpty {
                    Text("• \(tr)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                }
            }
            .shadow(color: .black.opacity(0.8), radius: 3)
        } else if let tr = clip.translationName, !tr.isEmpty {
            Text(tr)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
                .shadow(color: .black.opacity(0.8), radius: 3)
        }
    }

    // MARK: - Right Rail View

    private func rightRailView(clip: MovieClip) -> some View {
        VStack(spacing: 14) {
            // Author Avatar (Liquid Glass Button)
            authorAvatarView(clip)

            // Like Button
            likeButtonView(clip)

            // Comments Button
            commentButtonView(clip)

            // Share Button
            shareButtonView(clip)

            // Scale Mode Toggle ("9:16" vs "В кадре")
            scaleModeButtonView
        }
        .frame(width: 56)
    }

    // MARK: - Author Avatar

    private func authorAvatarView(_ clip: MovieClip) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            SlooshAvatarView(
                avatarSource: clip.authorAvatar,
                fallbackText: clip.authorName,
                size: 38
            )
            .glassEffect(in: .circle)
            .clipShape(Circle())
            .shadow(color: .black.opacity(0.6), radius: 4)
            .frame(width: 52, height: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                Image(systemName: "heart.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(isLiked ? Color.slooshAccent : .white)
                    .scaleEffect(isLiked ? 1.15 : 1.0)
                    .contentTransition(.symbolEffect(.replace))
                    .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isLiked)
                    .shadow(color: .black.opacity(0.7), radius: 6)

                Text("\(clip.likesCount)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.8), radius: 3)
            }
            .frame(width: 52, height: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func commentButtonView(_ clip: MovieClip) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showCommentsForClip = clip
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "bubble.right.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.7), radius: 6)

                Text("\(clip.commentsCount)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.8), radius: 3)
            }
            .frame(width: 52, height: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .shadow(color: .black.opacity(0.8), radius: 3)
            }
            .frame(width: 56, height: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var scaleModeButtonView: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                if currentScaleMode == .fit {
                    clipScaleModeRaw = ClipScalingMode.fill.rawValue
                    ToastManager.shared.show(title: "Режим: Во весь экран (9:16)", icon: "arrow.up.left.and.arrow.down.right", iconColor: Color.slooshAccent)
                } else {
                    clipScaleModeRaw = ClipScalingMode.fit.rawValue
                    ToastManager.shared.show(title: "Режим: В кадре", icon: "arrow.down.right.and.arrow.up.left", iconColor: Color.slooshAccent)
                }
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: currentScaleMode == .fit ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace.downUp.byLayer))
                    .shadow(color: .black.opacity(0.7), radius: 6)

                Text(currentScaleMode == .fit ? "9:16" : "В кадре")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .shadow(color: .black.opacity(0.8), radius: 3)
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: currentScaleMode)
            .frame(width: 56, height: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Scrubber Progress Bar

    private func progressBarView(for clip: MovieClip) -> some View {
        GeometryReader { barProxy in
            let totalWidth = barProxy.size.width
            let displayProgress = isScrubbing ? scrubProgress : playback.clipProgress
            let activeWidth = max(0, min(totalWidth, totalWidth * displayProgress))
            let barHeight: CGFloat = isScrubbing ? 7.0 : 3.0

            ZStack(alignment: .leading) {
                // Background Track
                Capsule()
                    .fill(Color.white.opacity(isScrubbing ? 0.35 : 0.22))
                    .frame(height: barHeight)

                if playback.isResolving || !playback.isVideoReady {
                    // Shimmering animated light beam during buffering
                    TimelineView(.animation) { timeline in
                        let time = timeline.date.timeIntervalSinceReferenceDate
                        let phase = CGFloat(time.truncatingRemainder(dividingBy: 1.4) / 1.4)

                        GeometryReader { p in
                            let w = p.size.width
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            stops: [
                                                .init(color: Color.white.opacity(0.0), location: max(0, phase - 0.25)),
                                                .init(color: Color.white.opacity(0.9), location: phase),
                                                .init(color: Color.white.opacity(0.0), location: min(1, phase + 0.25))
                                            ],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: w)
                            }
                        }
                    }
                    .frame(height: barHeight)
                    .clipShape(Capsule())
                } else {
                    // Active Progress Track
                    Capsule()
                        .fill(Color.white)
                        .frame(width: activeWidth, height: barHeight)

                    // Tactile Scrubber Head (visible while scrubbing)
                    if isScrubbing {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 14, height: 14)
                            .position(x: min(totalWidth - 7, max(7, activeWidth)), y: barProxy.size.height / 2)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let rawPct = value.location.x / totalWidth
                        let pct = max(0.0, min(1.0, rawPct))
                        if !isScrubbing {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                isScrubbing = true
                            }
                            playback.beginScrubbing()
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        }
                        scrubProgress = pct
                        playback.scrubToProgress(pct, for: clip)
                    }
                    .onEnded { value in
                        let rawPct = value.location.x / totalWidth
                        let pct = max(0.0, min(1.0, rawPct))
                        scrubProgress = pct
                        playback.endScrubbing(at: pct, for: clip)
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                            isScrubbing = false
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
            )
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: barHeight)
        }
        .frame(height: 36)
        .overlay(alignment: .top) {
            if isScrubbing {
                let currentSec = clip.startTime + (clip.duration * scrubProgress)
                let elapsedSec = max(0, currentSec - clip.startTime)
                HStack(spacing: 6) {
                    Text(formatClipTime(elapsedSec))
                        .font(.system(size: 17, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)

                    Text("/")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))

                    Text(formatClipTime(clip.duration))
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .glassEffect(in: .capsule)
                .offset(y: -46)
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.75).combined(with: .opacity).combined(with: .offset(y: 12)),
                        removal: .scale(scale: 0.85).combined(with: .opacity).combined(with: .offset(y: -8))
                    )
                )
                .animation(.spring(response: 0.32, dampingFraction: 0.72), value: isScrubbing)
            }
        }
    }

    private func formatClipTime(_ seconds: Double) -> String {
        guard !seconds.isNaN && !seconds.isInfinite else { return "0:00" }
        let total = Int(max(0, seconds))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
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
