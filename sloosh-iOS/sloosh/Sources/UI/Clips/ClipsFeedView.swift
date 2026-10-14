import SwiftUI
import UIKit
import AVKit
import Combine

// MARK: - Isolated Clip Progress Observer (Prevents full-feed re-renders during playback)

@MainActor
final class ClipProgressObserver: ObservableObject {
    @Published var progress: Double = 0.0
}

// MARK: - Dedicated Playback Coordinator for Feed

@MainActor
final class ClipPlaybackCoordinator: ObservableObject {
    @Published var activePlayer: AVPlayer?
    @Published var isVideoReady: Bool = false
    @Published var isResolving: Bool = false
    @Published var isPlaying: Bool = true
    let progressObserver = ClipProgressObserver()
    var clipProgress: Double {
        get { progressObserver.progress }
        set { progressObserver.progress = newValue }
    }
    @Published var isScrubbing: Bool = false
    @Published var isFastForwarding: Bool = false
    @Published var hasError: Bool = false
    @Published var availableQualities: [String] = ["Авто", "1080p", "720p", "480p", "360p"]
    @Published var currentQuality: String = UserDefaults.standard.string(forKey: "sloosh_moments_quality") ?? "Авто"
    @Published var playbackSpeed: Float = 1.0

    var speedLabel: String {
        if playbackSpeed == 1.0 {
            return "1.0x"
        } else if playbackSpeed == Float(Int(playbackSpeed)) {
            return "\(Int(playbackSpeed)).0x"
        } else {
            return String(format: "%.2gx", playbackSpeed)
        }
    }

    private var currentClipId: String?
    private var currentClip: MovieClip?
    private var currentQualityUrls: [String: URL] = [:]
    private var currentHeaders: [String: String] = [:]
    private var currentPlayingUrl: URL?
    private var timeObserver: Any?
    private var playerStatusObserver: NSKeyValueObservation?
    private var playerTimeStatusObserver: NSKeyValueObservation?
    private var resolvePlaybackTask: Task<Void, Never>?
    private var didPerformInitialSeek: Bool = false
    private var retryCount: Int = 0
    private(set) var wasUserPaused: Bool = false

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        let savedQuality = UserDefaults.standard.string(forKey: "sloosh_moments_quality") ?? "Авто"
        self.currentQuality = savedQuality
    }

    func setupPlayer(for clip: MovieClip, isRetry: Bool = false) {
        cleanup()
        currentClip = clip
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
            wasUserPaused = false
        }
        isPlaying = true
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
            guard self.isPlaying else {
                self.isResolving = false
                return
            }

            self.currentQualityUrls = playbackInfo.qualityUrls
            self.currentHeaders = playbackInfo.headers
            self.currentPlayingUrl = playbackInfo.url

            // Обновляем доступные качества из полученных потоков
            if !playbackInfo.qualityUrls.isEmpty {
                let sortedKeys = playbackInfo.qualityUrls.keys.sorted {
                    let h1 = Int($0.replacingOccurrences(of: "p", with: "")) ?? 0
                    let h2 = Int($1.replacingOccurrences(of: "p", with: "")) ?? 0
                    return h1 > h2
                }
                self.availableQualities = ["Авто"] + sortedKeys
            }

            let asset = AVURLAsset(url: playbackInfo.url, options: ["AVURLAssetHTTPHeaderFieldsKey": playbackInfo.headers])
            let item = AVPlayerItem(asset: asset)
            item.preferredForwardBufferDuration = 10.0
            self.applyQuality(self.currentQuality, to: item)

            if playbackInfo.qualityUrls.isEmpty {
                Task { [weak self] in
                    await self?.fetchMasterPlaylistQualities(url: playbackInfo.url, headers: playbackInfo.headers)
                }
            }

            try? AVAudioSession.sharedInstance().setActive(true)

            let player = AVPlayer(playerItem: item)
            player.actionAtItemEnd = .none
            player.automaticallyWaitsToMinimizeStalling = true
            self.activePlayer = player
            if !self.isPlaying {
                player.pause()
            }

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
                                player.seek(to: sTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                                    guard let self, self.isPlaying, !self.wasUserPaused else { return }
                                    self.playWithCurrentSpeed()
                                }
                            } else {
                                guard self.isPlaying, !self.wasUserPaused else { return }
                                self.playWithCurrentSpeed()
                            }
                        } else {
                            guard self.isPlaying, !self.wasUserPaused else { return }
                            self.playWithCurrentSpeed()
                        }
                    } else if observedItem.status == .failed {
                        let errorDesc = String(describing: observedItem.error)
                        AppDiagnostics.shared.log("[ClipPlayback] AVPlayerItem failed for clip=\(clip.id): \(errorDesc)")
                        
                        let isUnsupportedFormat = errorDesc.contains("-11848") || errorDesc.contains("-15517")
                        if isUnsupportedFormat && !self.currentQualityUrls.isEmpty {
                            if let fallback = self.currentQualityUrls.first(where: { $0.value != self.currentPlayingUrl }) {
                                AppDiagnostics.shared.log("[ClipPlayback] Unsupported format detected, falling back to quality=\(fallback.key)")
                                self.switchStream(to: fallback.value, qualityKey: fallback.key)
                                return
                            }
                        }

                        if self.retryCount < 2 {
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
                    player.seek(to: sTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                        guard let self else { return }
                        if self.isPlaying {
                            self.playWithCurrentSpeed()
                        }
                    }
                }
            }
        }
    }

    func playWithCurrentSpeed() {
        guard let player = activePlayer else { return }
        if isFastForwarding {
            player.rate = 2.0
        } else {
            player.rate = playbackSpeed
        }
        isPlaying = true
    }

    func setQuality(_ quality: String) {
        currentQuality = quality
        UserDefaults.standard.set(quality, forKey: "sloosh_moments_quality")
        ToastManager.shared.show(title: "Качество: \(quality)", icon: "gearshape.fill", iconColor: .white)

        // Если для выбранного качества есть отдельный URL (например, 1080p или 720p), переключаем поток с сохранением таймкода
        if let targetUrl = currentQualityUrls[quality], targetUrl != currentPlayingUrl {
            switchStream(to: targetUrl, qualityKey: quality)
            return
        }

        applyQuality(quality, to: activePlayer?.currentItem)
    }

    private func switchStream(to newUrl: URL, qualityKey: String) {
        guard let player = activePlayer, let clip = currentClip else { return }
        let currentTime = player.currentTime()
        let isCurrentlyPlaying = isPlaying

        currentPlayingUrl = newUrl
        let asset = AVURLAsset(url: newUrl, options: ["AVURLAssetHTTPHeaderFieldsKey": currentHeaders])
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 10.0
        applyQuality(qualityKey, to: item)

        playerStatusObserver?.invalidate()
        playerStatusObserver = item.observe(\.status, options: [.new]) { [weak self, weak player] observedItem, _ in
            Task { @MainActor [weak self] in
                guard let self, let player, self.currentClipId == clip.id else { return }
                if observedItem.status == .readyToPlay {
                    self.isVideoReady = true
                    player.seek(to: currentTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                        if isCurrentlyPlaying {
                            self?.playWithCurrentSpeed()
                        }
                    }
                } else if observedItem.status == .failed {
                    AppDiagnostics.shared.log("[ClipPlayback] Quality switch failed for quality=\(qualityKey): \(String(describing: observedItem.error))")
                }
            }
        }

        player.replaceCurrentItem(with: item)
    }

    func applyQuality(_ quality: String, to item: AVPlayerItem?) {
        guard let item else { return }
        switch quality {
        case "2160p", "4K":
            item.preferredMaximumResolution = CGSize(width: 3840, height: 2160)
            item.preferredPeakBitRate = 0
        case "1440p":
            item.preferredMaximumResolution = CGSize(width: 2560, height: 1440)
            item.preferredPeakBitRate = 0
        case "1080p":
            item.preferredMaximumResolution = CGSize(width: 1920, height: 1080)
            item.preferredPeakBitRate = 0
        case "720p":
            item.preferredMaximumResolution = CGSize(width: 1280, height: 720)
            item.preferredPeakBitRate = 4_500_000
        case "480p":
            item.preferredMaximumResolution = CGSize(width: 854, height: 480)
            item.preferredPeakBitRate = 2_000_000
        case "360p":
            item.preferredMaximumResolution = CGSize(width: 640, height: 360)
            item.preferredPeakBitRate = 1_000_000
        default: // "Авто" or unparsed
            if quality.hasSuffix("p"), let h = Int(quality.replacingOccurrences(of: "p", with: "")) {
                let w = Int(Double(h) * (16.0 / 9.0))
                item.preferredMaximumResolution = CGSize(width: w, height: h)
                item.preferredPeakBitRate = 0
            } else {
                item.preferredMaximumResolution = .zero
                item.preferredPeakBitRate = 0
            }
        }
    }

    func setSpeed(_ speed: Float) {
        playbackSpeed = speed
        if isPlaying && !isFastForwarding {
            activePlayer?.rate = speed
        }
        let label = speed == 1.0 ? "1.0x (Обычная)" : (speed == Float(Int(speed)) ? "\(Int(speed)).0x" : String(format: "%.2gx", speed))
        ToastManager.shared.show(title: "Скорость: \(label)", icon: "gauge.with.needle.fill", iconColor: .white)
    }

    func fetchMasterPlaylistQualities(url: URL, headers: [String: String]) async {
        guard url.path.hasSuffix(".m3u8") || url.absoluteString.contains(".m3u8") else { return }
        var request = URLRequest(url: url)
        for (k, v) in headers {
            request.setValue(v, forHTTPHeaderField: k)
        }
        request.timeoutInterval = 4.0
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let text = String(data: data, encoding: .utf8) else {
            return
        }
        let regex = try? NSRegularExpression(pattern: "RESOLUTION=\\d+x(\\d+)", options: [])
        let matches = regex?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? []
        var heights: Set<Int> = []
        for match in matches {
            if match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: text),
               let h = Int(text[range]) {
                heights.insert(h)
            }
        }
        if !heights.isEmpty {
            let sortedHeights = heights.sorted(by: >)
            var list = ["Авто"]
            for h in sortedHeights {
                list.append("\(h)p")
            }
            await MainActor.run {
                self.availableQualities = list
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
                self.playWithCurrentSpeed()
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
            wasUserPaused = true
        } else {
            wasUserPaused = false
            playWithCurrentSpeed()
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
            player.rate = playbackSpeed
        } else {
            player.pause()
        }
    }

    func pause(userInitiated: Bool = false) {
        activePlayer?.pause()
        isPlaying = false
        isFastForwarding = false
        if userInitiated {
            wasUserPaused = true
        }
    }

    func resume(for clip: MovieClip?) {
        guard let clip else { return }
        wasUserPaused = false
        if activePlayer == nil || currentClipId != clip.id {
            setupPlayer(for: clip)
        } else {
            playWithCurrentSpeed()
        }
    }

    func resumeIfAppropriate(for clip: MovieClip?) {
        guard !wasUserPaused else { return }
        resume(for: clip)
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
        currentQualityUrls = [:]
        currentHeaders = [:]
        currentPlayingUrl = nil
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
    @ObservedObject private var messengerRepo = MessengerRepository.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var showsMessenger: Bool = false
    @State private var commentsSheetDetent: PresentationDetent = .fraction(0.65)
    @State private var selectedDetailsMedia: (movieId: String, mediaType: String)? = nil

    @AppStorage("clipsVideoScaleMode") private var clipScaleModeRaw: String = ClipScalingMode.fit.rawValue

    private var currentScaleMode: ClipScalingMode {
        ClipScalingMode(rawValue: clipScaleModeRaw) ?? .fit
    }

    @State private var currentClipId: String? = ClipsRepository.shared.clips.first?.id
    @State private var clipToDelete: MovieClip?
    @State private var showDeleteConfirmation: Bool = false
    @State private var isDeletingClip: Bool = false
    @State private var showCommentsForClip: MovieClip?
    @State private var fullPlayerConfig: PlayerConfig?
    @State private var showBigHeart: Bool = false
    @State private var bigHeartPosition: CGPoint = .zero
    @State private var isTextExpanded: Bool = false
    @State private var isScrubbing: Bool = false
    @State private var scrollOffsetY: CGFloat = 0.0
    @State private var lastTapTime: Date = Date.distantPast

    private var currentVisibleClip: MovieClip? {
        if let currentClipId {
            return clipsRepo.clips.first(where: { $0.id == currentClipId })
        }
        return clipsRepo.clips.first
    }

    public init() {}

    public var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let topSafeArea = proxy.safeAreaInsets.top
                let bottomSafeArea = proxy.safeAreaInsets.bottom
                let fullWidth = proxy.size.width
                let fullHeight = proxy.size.height + topSafeArea + bottomSafeArea

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
                        feedScrollView(width: fullWidth, height: fullHeight, topSafeArea: topSafeArea, bottomSafeArea: bottomSafeArea)

                        momentsHeaderView(width: fullWidth, topSafeArea: topSafeArea, fullHeight: fullHeight)
                    }
                }
                .ignoresSafeArea()
            }
            .toolbarVisibility(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showsMessenger) {
                MessengerView()
            }
            .navigationDestination(isPresented: Binding(
                get: { selectedDetailsMedia != nil },
                set: { if !$0 { selectedDetailsMedia = nil } }
            )) {
                if let media = selectedDetailsMedia {
                    DetailsView(movieId: media.movieId, mediaType: media.mediaType)
                }
            }
        }
        .preferredColorScheme(.dark)
        .environment(\.colorScheme, .dark)
        .task {
            if clipsRepo.clips.isEmpty {
                await clipsRepo.fetchFeed()
            }
            ensurePlaybackStarted()
        }
        .sheet(item: $showCommentsForClip) { clip in
            ClipCommentsSheetView(clip: clip)
                .presentationDetents([.fraction(0.65)], selection: $commentsSheetDetent)
                .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.65)))
        }
        .fullScreenCover(item: $fullPlayerConfig, onDismiss: {
            fullPlayerConfig = nil
            ensurePlaybackStarted()
        }) { config in
            PlayerView(config: config)
                .preferredColorScheme(.dark)
                .environment(\.colorScheme, .dark)
        }
        .onChange(of: fullPlayerConfig != nil) { _, isOpened in
            if isOpened {
                playback.pause(userInitiated: true)
            }
        }
        .onChange(of: showsMessenger) { _, isPresented in
            if isPresented {
                playback.pause(userInitiated: true)
            } else {
                ensurePlaybackStarted()
            }
        }
        .onChange(of: selectedDetailsMedia != nil) { _, isOpened in
            if isOpened {
                playback.pause(userInitiated: true)
            } else {
                ensurePlaybackStarted()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                playback.pause(userInitiated: false)
            } else {
                if !showsMessenger && selectedDetailsMedia == nil && fullPlayerConfig == nil && showCommentsForClip == nil {
                    if let clipId = currentClipId, let clip = clipsRepo.clips.first(where: { $0.id == clipId }) {
                        playback.resumeIfAppropriate(for: clip)
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            playback.pause(userInitiated: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            playback.pause(userInitiated: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SlooshPauseClipsPlayback"))) { _ in
            playback.pause(userInitiated: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SlooshMainPlayerWillStart"))) { _ in
            playback.pause(userInitiated: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SlooshResumeClipsPlayback"))) { _ in
            ensurePlaybackStarted()
        }
        .alert("Удалить момент?", isPresented: $showDeleteConfirmation, presenting: clipToDelete) { clip in
            Button("Отмена", role: .cancel) {
                clipToDelete = nil
            }
            Button("Удалить", role: .destructive) {
                executeDeleteClip(clip)
            }
        } message: { _ in
            Text("Вы уверены, что хотите удалить этот момент? Это действие нельзя отменить.")
        }
        .onDisappear {
            playback.pause(userInitiated: true)
        }
        .onAppear {
            ensurePlaybackStarted()
        }
    }

    // MARK: - Dynamic Header Scroll Blur (Matches HomeView liquid glass style)

    private func headerBlurOpacity(height: CGFloat) -> Double {
        guard height > 0 else { return 0.0 }
        let offset = scrollOffsetY
        let distFromPage: CGFloat
        if offset < 0 {
            distFromPage = abs(offset)
        } else {
            let remainder = offset.truncatingRemainder(dividingBy: height)
            distFromPage = min(remainder, height - remainder)
        }
        // At rest, distance is 0 (< 1.5pt threshold). No blur when player is idle.
        guard distFromPage > 1.5 else { return 0.0 }
        let progress = min(1.0, Double((distFromPage - 1.5) / 32.0))
        return progress
    }

    private func momentsHeaderView(width: CGFloat, topSafeArea: CGFloat, fullHeight: CGFloat) -> some View {
        let statusBarClearance = max(topSafeArea, 47.0) + 16.0
        let blurOpacity = headerBlurOpacity(height: fullHeight)

        return VStack(spacing: 0) {
            // Status bar clearance (keeps title comfortable below Dynamic Island / notch)
            Color.clear
                .frame(height: statusBarClearance)
                .allowsHitTesting(false)

            // Header title bar (perfectly symmetrical with matching 44x44 balances on left and right)
            HStack(spacing: 0) {
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.prepare()
                    generator.impactOccurred()
                    showsMessenger = true
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())

                        if messengerRepo.totalUnreadCount > 0 {
                            Text("\(messengerRepo.totalUnreadCount)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.red)
                                .clipShape(Capsule())
                                .offset(x: -2, y: 4)
                        }
                    }
                }
                .buttonStyle(.glassPress)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("Чаты")
                .padding(.leading, 16)

                Spacer(minLength: 0)

                Text("Моменты")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .allowsHitTesting(false)

                Spacer(minLength: 0)

                if let clip = currentVisibleClip {
                    actionsMenuView(for: clip)
                        .padding(.trailing, 16)
                } else {
                    Color.clear
                        .frame(width: 44, height: 44)
                        .padding(.trailing, 16)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
        }
        .frame(width: width)
        .background(
            VariableBlurView(tintOpacity: 1.0)
                .padding(.bottom, -30)
                .ignoresSafeArea(edges: .top)
                .opacity(blurOpacity)
                .animation(.easeInOut(duration: 0.2), value: blurOpacity)
                .allowsHitTesting(false)
        )
        .ignoresSafeArea(edges: .top)
        .opacity(showCommentsForClip != nil ? 0.0 : 1.0)
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: showCommentsForClip != nil)
    }

    // MARK: - Actions Menu (Quality, Speed, Scale, Share, Delete for author)

    private func actionsMenuView(for clip: MovieClip) -> some View {
        Menu {
            // 1. Качество
            Menu {
                ForEach(playback.availableQualities, id: \.self) { quality in
                    Button {
                        playback.setQuality(quality)
                    } label: {
                        HStack {
                            Text(quality)
                            if playback.currentQuality == quality {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Label("Качество (\(playback.currentQuality))", systemImage: "gearshape")
            }

            // 2. Скорость
            Menu {
                ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { (speed: Double) in
                    let s = Float(speed)
                    Button {
                        playback.setSpeed(s)
                    } label: {
                        HStack {
                            Text(speedLabel(for: s))
                            if abs(playback.playbackSpeed - s) < 0.01 {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Label("Скорость (\(playback.speedLabel))", systemImage: "gauge.with.needle")
            }

            // 3. Масштаб видео
            Menu {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        clipScaleModeRaw = ClipScalingMode.fit.rawValue
                    }
                } label: {
                    HStack {
                        Text("В кадре (16:9)")
                        if currentScaleMode == .fit {
                            Image(systemName: "checkmark")
                        }
                    }
                }

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        clipScaleModeRaw = ClipScalingMode.fill.rawValue
                    }
                } label: {
                    HStack {
                        Text("Во весь экран (9:16)")
                        if currentScaleMode == .fill {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            } label: {
                Label("Масштаб", systemImage: "aspectratio")
            }

            // 4. Удалить момент (только для автора)
            if isAuthor(of: clip) {
                Divider()

                Button(role: .destructive) {
                    confirmDelete(clip: clip)
                } label: {
                    Label {
                        Text("Удалить момент")
                    } icon: {
                        if let img = UIImage(systemName: "trash")?.withTintColor(.systemRed, renderingMode: .alwaysOriginal) {
                            Image(uiImage: img)
                        } else {
                            Image(systemName: "trash")
                        }
                    }
                }
                .tint(.red)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .glassEffect(.regular.interactive(), in: .circle)
                .contentShape(Circle())
        }
        .tint(.white)
        .buttonStyle(.plain)
    }

    private func speedLabel(for speed: Float) -> String {
        if speed == 1.0 {
            return "1.0x (Обычная)"
        } else if speed == Float(Int(speed)) {
            return "\(Int(speed)).0x"
        } else {
            return String(format: "%.2gx", speed)
        }
    }

    private func isAuthor(of clip: MovieClip) -> Bool {
        let currentUserId = authRepo.currentUser?.id
        let guestId = "guest_\(UIDevice.current.identifierForVendor?.uuidString ?? "user")"
        if let currentUserId, !currentUserId.isEmpty, clip.authorId == currentUserId {
            return true
        }
        if clip.authorId == guestId {
            return true
        }
        if authRepo.isAdmin {
            return true
        }
        return false
    }

    private func confirmDelete(clip: MovieClip) {
        clipToDelete = clip
        showDeleteConfirmation = true
    }

    private func executeDeleteClip(_ clip: MovieClip) {
        isDeletingClip = true
        Task {
            do {
                let nextClip = clipsRepo.clips.first(where: { $0.id != clip.id })
                try await clipsRepo.deleteClip(clipId: clip.id)
                ToastManager.shared.show(title: "Момент удалён", icon: "trash.fill", iconColor: .red)
                if currentClipId == clip.id {
                    if let nextClip {
                        currentClipId = nextClip.id
                        playback.setupPlayer(for: nextClip)
                    } else {
                        currentClipId = nil
                        playback.cleanup()
                    }
                }
            } catch {
                ToastManager.shared.show(title: "Не удалось удалить", icon: "exclamationmark.triangle.fill", iconColor: .orange)
            }
            isDeletingClip = false
            clipToDelete = nil
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

    private func feedScrollView(width: CGFloat, height: CGFloat, topSafeArea: CGFloat, bottomSafeArea: CGFloat) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(clipsRepo.clips) { clip in
                    clipCard(clip, width: width, height: height, topSafeArea: topSafeArea, bottomSafeArea: bottomSafeArea)
                        .frame(width: width, height: height)
                        .id(clip.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $currentClipId)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y
        } action: { oldOffset, newOffset in
            if abs(newOffset - scrollOffsetY) > 0.1 {
                scrollOffsetY = newOffset
            }
        }
        .ignoresSafeArea()
        .refreshable {
            await clipsRepo.fetchFeed(forceRefresh: true)
        }
        .onChange(of: currentClipId) { oldId, newId in
            AppDiagnostics.shared.log("[ClipsFeedView] currentClipId changed from \(String(describing: oldId)) to \(String(describing: newId))")
            isTextExpanded = false
            guard let newId = newId, newId != oldId, let clip = clipsRepo.clips.first(where: { $0.id == newId }) else { return }
            playback.setupPlayer(for: clip)
            prewarmNextClip(after: clip)
        }
    }

    private func prewarmNextClip(after currentClip: MovieClip) {
        guard let currentIndex = clipsRepo.clips.firstIndex(where: { $0.id == currentClip.id }),
              currentIndex + 1 < clipsRepo.clips.count else { return }
        let nextClip = clipsRepo.clips[currentIndex + 1]
        Task {
            _ = await ClipStreamResolver.shared.resolveClip(for: nextClip)
        }
    }

    // MARK: - Clip Card

    private func clipCard(_ clip: MovieClip, width: CGFloat, height: CGFloat, topSafeArea: CGFloat, bottomSafeArea: CGFloat) -> some View {
        let isCurrent = (currentClipId == clip.id) || (currentClipId == nil && clip.id == clipsRepo.clips.first?.id)

        // The vertical player area extends precisely to the phone's status bar
        let topClearance: CGFloat = topSafeArea

        // Floating Liquid Glass tab bar clearance ensuring progress bar never touches or overlaps navbar
        let tabBarClearance: CGFloat = (bottomSafeArea > 20) ? 84.0 : 52.0
        let scrubberHeight: CGFloat = 16.0
        let symmetricalGap: CGFloat = 12.0

        // Strictly symmetrical gaps: symmetricalGap between player and scrubber, and symmetricalGap between scrubber and navbar
        let totalBottomClearance = tabBarClearance + (symmetricalGap * 2) + scrubberHeight
        let availableHeight = max(200.0, height - topClearance - totalBottomClearance)

        return VStack(spacing: 0) {
            // 1. Top clearance under status bar
            Color.clear
                .frame(width: width, height: topClearance)

            // 2. Video Container with smooth concentric corner radius (38pt = 22pt button radius + 16pt margin)
            videoCardContainer(clip, width: width, height: availableHeight, isCurrent: isCurrent)
                .clipShape(RoundedRectangle(cornerRadius: 38, style: .continuous))

            // 3. Symmetrical gap between video card and progress bar
            Color.clear
                .frame(width: width, height: symmetricalGap)

            // 4. Progress bar (полоса перемотки)
            if isCurrent {
                ClipProgressBarView(
                    progressObserver: playback.progressObserver,
                    clip: clip,
                    playback: playback,
                    isResolving: playback.isResolving,
                    isVideoReady: playback.isVideoReady,
                    isScrubbing: $isScrubbing
                )
                .padding(.horizontal, 16)
                .frame(height: scrubberHeight)
                .opacity(showCommentsForClip != nil ? 0.0 : 1.0)
                .animation(.spring(response: 0.28, dampingFraction: 0.85), value: showCommentsForClip != nil)
            } else {
                Color.clear
                    .frame(height: scrubberHeight)
            }

            // 5. Symmetrical gap between progress bar and floating tab bar
            Color.clear
                .frame(width: width, height: symmetricalGap)

            // 6. Bottom Tab Bar clearance (safely above the floating Liquid Glass tab bar)
            Color.clear
                .frame(width: width, height: tabBarClearance)
        }
        .frame(width: width, height: height)
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
            // 1. Sharp Video Player Layer (Single Dedicated AVPlayerLayer, always attached to hardware compositor)
            if isCurrent, let player = playback.activePlayer {
                VideoLayerView(
                    player: player,
                    videoGravity: effectiveVideoGravity
                )
                .frame(width: width, height: height)
                .offset(y: commentsShift)
                .clipped()
                .animation(.spring(response: 0.38, dampingFraction: 0.82), value: isCommentsOpen)
            }

            // 2. Initial Poster Placeholder (fades out smoothly when video is ready to play)
            if !playback.isVideoReady {
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
                    .allowsHitTesting(false)
                    .transition(.opacity)
                } else {
                    Color.black
                }
            }

            // 3. Touch & Gesture Zones: Both Edges 2x Speed, Center Instant 0ms Play/Pause
            HStack(spacing: 0) {
                // Left Edge 2x Speed Zone (88pt)
                edgeAccelerationZone(for: clip)
                    .frame(width: 88)

                // Center Instant Play/Pause & Double-Tap Heart Zone
                centerTapZone(clip: clip)
                    .frame(maxWidth: .infinity)

                // Right Edge 2x Speed Zone (88pt)
                edgeAccelerationZone(for: clip)
                    .frame(width: 88)
            }
            .frame(width: width, height: height)
            .zIndex(1)

            // 6. Play / Pause Indicator in Center (Liquid Glass with Spring Animation, perfectly centered)
            if !playback.isPlaying && isCurrent && playback.isVideoReady && !isOverlayHidden {
                Image(systemName: "play.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 72)
                    .glassEffect(in: .circle)
                    .clipShape(Circle())
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.5).combined(with: .opacity),
                            removal: .scale(scale: 1.25).combined(with: .opacity)
                        )
                    )
                    .allowsHitTesting(false)
            }

            // 7. 2x Fast-Forward Indicator Badge (Matches scrubbing time capsule style and animation)
            VStack {
                Spacer()

                if playback.isFastForwarding {
                    HStack(spacing: 7) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 14, weight: .bold))

                        Text("2X")
                            .font(.system(size: 17, weight: .bold).monospacedDigit())
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .glassEffect(in: .capsule)
                    .padding(.bottom, 24)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.75).combined(with: .opacity).combined(with: .offset(y: 12)),
                            removal: .scale(scale: 0.85).combined(with: .opacity).combined(with: .offset(y: -8))
                        )
                    )
                }
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.72), value: playback.isFastForwarding)
            .allowsHitTesting(false)
            .zIndex(5)

            // 6. Big Heart Explosion on Double-Tap
            if showBigHeart {
                Image(systemName: "heart.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(Color.red)
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
                            .foregroundStyle(.white.opacity(0.8))
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
                .padding(.leading, 16)
                .padding(.trailing, 16)
                .padding(.bottom, 16)
            }
            .opacity(isOverlayHidden ? 0.0 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.85), value: isOverlayHidden)
            .allowsHitTesting(!isOverlayHidden)
            .zIndex(10)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 38, style: .continuous))
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
        if showCommentsForClip != nil {
            showCommentsForClip = nil
            return
        }
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
        VStack(alignment: .leading, spacing: 7) {
            // Movie / Series Logo (with text fallback) - Tapping opens Movie Details
            logoOrTitleView(clip: clip)
                .contentShape(Rectangle())
                .onTapGesture {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    selectedDetailsMedia = (movieId: String(clip.mediaId), mediaType: clip.mediaType)
                }

            // Season, Episode & Voiceover Capsule
            subtitleInfoView(clip: clip)

            // Author Caption / Description Capsule (Expandable on tap)
            authorCaptionView(clip: clip)

            // Pure Liquid Glass "Смотреть" Button (Bold, styled like Main Screen, pure Liquid Glass)
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                openFullMovie(clip: clip)
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 13, weight: .bold))

                    Text("Смотреть")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(height: 38)
                .glassEffect(.regular.interactive(), in: .capsule)
            }
            .buttonStyle(.glassPress)
            .padding(.top, 2)
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
            .lineLimit(1)
    }

    @ViewBuilder
    private func subtitleInfoView(clip: MovieClip) -> some View {
        let hasSeries = clip.season != nil && clip.episode != nil
        let hasTranslation = clip.translationName != nil && !(clip.translationName?.isEmpty ?? true)

        if hasSeries || hasTranslation {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                selectedDetailsMedia = (movieId: String(clip.mediaId), mediaType: clip.mediaType)
            } label: {
                HStack(spacing: 5) {
                    if let s = clip.season, let e = clip.episode {
                        Text("\(s) сезон, \(e) серия")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.white)

                        if let tr = clip.translationName, !tr.isEmpty {
                            Text("•")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.45))

                            Text(cleanTranslationName(tr))
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(.white.opacity(0.92))
                                .lineLimit(1)
                        }
                    } else if let tr = clip.translationName, !tr.isEmpty {
                        Text(cleanTranslationName(tr))
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.95))
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .glassEffect(.regular.interactive(), in: .capsule)
            }
            .buttonStyle(.glassPress)
        }
    }

    @ViewBuilder
    private func authorCaptionView(clip: MovieClip) -> some View {
        let caption = clip.caption.trimmingCharacters(in: .whitespacesAndNewlines)
        if !caption.isEmpty {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                    isTextExpanded.toggle()
                }
            } label: {
                HStack(alignment: .bottom, spacing: 6) {
                    Text(caption)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.95))
                        .lineLimit(isTextExpanded ? 6 : 2)
                        .multilineTextAlignment(.leading)

                    if caption.count > 55 {
                        Text(isTextExpanded ? "скрыть" : "ещё")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.55))
                            .padding(.bottom, 1)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: isTextExpanded ? 16 : 18))
            }
            .buttonStyle(.glassPress)
        }
    }

    // MARK: - Right Rail View

    private func rightRailView(clip: MovieClip) -> some View {
        VStack(spacing: 12) {
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

            // Circular Movie Poster Button (Opens DetailsView)
            moviePosterButtonView(clip: clip)
        }
        .frame(width: 36)
        .contentShape(Rectangle())
    }

    // MARK: - Movie Poster Circular Button (Opens DetailsView)

    private func moviePosterButtonView(clip: MovieClip) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            selectedDetailsMedia = (movieId: String(clip.mediaId), mediaType: clip.mediaType)
        } label: {
            Group {
                if let path = clip.posterPath, let url = resolveImageUrl(path: path) {
                    AsyncCachedImage(url: url) {
                        Circle().fill(Color.white.opacity(0.12))
                    } content: { img in
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 36, height: 36)
                            .clipShape(Circle())
                    } fallback: {
                        Image(systemName: "film")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(width: 36, height: 36)
                    }
                } else {
                    Image(systemName: "film")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 36, height: 36)
                }
            }
            .frame(width: 36, height: 36)
            .contentShape(Circle())
        }
        .buttonStyle(.glassPress)
        .glassEffect(.regular.interactive(), in: .circle)
        .frame(width: 36, height: 36)
    }

    // MARK: - Author Avatar

    private func authorAvatarView(_ clip: MovieClip) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            SlooshAvatarView(
                avatarSource: clip.authorAvatar,
                fallbackText: clip.authorName,
                size: 36
            )
            .frame(width: 36, height: 36)
            .contentShape(Circle())
        }
        .buttonStyle(.glassPress)
        .glassEffect(.regular.interactive(), in: .circle)
        .frame(width: 36, height: 36)
    }

    // MARK: - Action Buttons

    private func likeButtonView(_ clip: MovieClip) -> some View {
        let isLiked = clipsRepo.isLiked(clipId: clip.id)

        return VStack(spacing: 4) {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                Task {
                    _ = await clipsRepo.toggleLike(for: clip.id)
                }
            } label: {
                HeartShape()
                    .fill(isLiked ? Color.red.opacity(0.92) : Color.white.opacity(0.001))
                    .frame(width: 36, height: 36)
                    .contentShape(HeartShape())
            }
            .buttonStyle(.glassPress)
            .contentShape(HeartShape())
            .glassEffect(.regular.interactive(), in: HeartShape())

            Text("\(clip.likesCount)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.28, dampingFraction: 0.7), value: clip.likesCount)
                .contentShape(Rectangle())
                .onTapGesture {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    Task {
                        _ = await clipsRepo.toggleLike(for: clip.id)
                    }
                }
        }
        .frame(width: 36)
    }

    private func commentButtonView(_ clip: MovieClip) -> some View {
        VStack(spacing: 4) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showCommentsForClip = clip
            } label: {
                SpeechBubbleShape()
                    .fill(Color.white.opacity(0.001), style: FillStyle(eoFill: true))
                    .frame(width: 36, height: 36)
                    .contentShape(SpeechBubbleShape(), eoFill: true)
            }
            .buttonStyle(.glassPress)
            .contentShape(SpeechBubbleShape(), eoFill: true)
            .glassEffect(.regular.interactive(), in: SpeechBubbleShape())

            Text("\(clip.commentsCount)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .contentShape(Rectangle())
                .onTapGesture {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showCommentsForClip = clip
                }
        }
        .frame(width: 36)
    }

    private func shareButtonView(_ clip: MovieClip) -> some View {
        VStack(spacing: 4) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                shareClip(clip)
            } label: {
                ShareArrowShape()
                    .fill(Color.white.opacity(0.001))
                    .frame(width: 36, height: 36)
                    .contentShape(ShareArrowShape())
            }
            .buttonStyle(.glassPress)
            .contentShape(ShareArrowShape())
            .glassEffect(.regular.interactive(), in: ShareArrowShape())

            Text("Поделиться")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: true, vertical: false)
                .contentShape(Rectangle())
                .onTapGesture {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    shareClip(clip)
                }
        }
        .frame(width: 36)
    }

    private var scaleModeButtonView: some View {
        VStack(spacing: 4) {
            Button {
                toggleScaleMode()
            } label: {
                AspectExpandShape()
                    .fill(Color.white.opacity(0.001))
                    .frame(width: 36, height: 36)
                    .contentShape(AspectExpandShape())
            }
            .buttonStyle(.glassPress)
            .contentShape(AspectExpandShape())
            .glassEffect(.regular.interactive(), in: AspectExpandShape())

            Text(currentScaleMode == .fit ? "9:16" : "В кадре")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: true, vertical: false)
                .animation(.spring(response: 0.35, dampingFraction: 0.75), value: currentScaleMode)
                .contentShape(Rectangle())
                .onTapGesture {
                    toggleScaleMode()
                }
        }
        .frame(width: 36)
    }

    private func toggleScaleMode() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            if currentScaleMode == .fit {
                clipScaleModeRaw = ClipScalingMode.fill.rawValue
                ToastManager.shared.show(title: "Режим: Во весь экран (9:16)", icon: "arrow.up.left.and.arrow.down.right", iconColor: .white)
            } else {
                clipScaleModeRaw = ClipScalingMode.fit.rawValue
                ToastManager.shared.show(title: "Режим: В кадре", icon: "arrow.down.right.and.arrow.up.left", iconColor: .white)
            }
        }
    }
}

// MARK: - Native UIKit Scrubber for Movie Clips

final class ClipCustomSlider: UISlider {
    var isInteracting: Bool = false {
        didSet {
            setNeedsLayout()
            layoutIfNeeded()
        }
    }

    override func trackRect(forBounds bounds: CGRect) -> CGRect {
        var rect = super.trackRect(forBounds: bounds)
        let h: CGFloat = isInteracting ? 7.0 : 4.0
        rect.size.height = h
        rect.origin.y = bounds.midY - (h / 2.0)
        return rect
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let touchArea = bounds.insetBy(dx: 0, dy: -16)
        return touchArea.contains(point)
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let width = bounds.width
        if width > 0 {
            let loc = touch.location(in: self)
            let pct = Float(max(0.0, min(1.0, loc.x / width)))
            setValue(pct, animated: false)
            sendActions(for: .valueChanged)
        }
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let width = bounds.width
        if width > 0 {
            let loc = touch.location(in: self)
            let pct = Float(max(0.0, min(1.0, loc.x / width)))
            setValue(pct, animated: false)
            sendActions(for: .valueChanged)
        }
        return true
    }
}

struct ClipNativeSliderView: UIViewRepresentable {
    @ObservedObject var progressObserver: ClipProgressObserver
    let clip: MovieClip
    let playback: ClipPlaybackCoordinator
    @Binding var isScrubbing: Bool
    @Binding var scrubProgress: Double

    func makeUIView(context: Context) -> ClipCustomSlider {
        let slider = ClipCustomSlider()
        slider.minimumValue = 0
        slider.maximumValue = 1
        slider.setThumbImage(UIImage(), for: .normal)
        slider.setThumbImage(UIImage(), for: .highlighted)
        slider.tintColor = .white
        slider.minimumTrackTintColor = .white
        slider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.25)

        slider.addTarget(context.coordinator, action: #selector(Coordinator.valueChanged(_:)), for: .valueChanged)
        slider.addTarget(context.coordinator, action: #selector(Coordinator.editingDidBegin(_:)), for: .touchDown)
        slider.addTarget(context.coordinator, action: #selector(Coordinator.editingDidEnd(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel])

        return slider
    }

    func updateUIView(_ uiView: ClipCustomSlider, context: Context) {
        if !context.coordinator.isEditing {
            uiView.value = Float(progressObserver.progress)
        }
        if uiView.isInteracting != isScrubbing {
            UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut]) {
                uiView.isInteracting = self.isScrubbing
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject {
        let parent: ClipNativeSliderView
        var isEditing = false

        init(parent: ClipNativeSliderView) {
            self.parent = parent
        }

        @objc func valueChanged(_ sender: UISlider) {
            let pct = max(0.0, min(1.0, Double(sender.value)))
            parent.scrubProgress = pct
            parent.playback.scrubToProgress(pct, for: parent.clip)
        }

        @objc func editingDidBegin(_ sender: UISlider) {
            isEditing = true
            parent.isScrubbing = true
            if let custom = sender as? ClipCustomSlider {
                UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut]) {
                    custom.isInteracting = true
                }
            }
            parent.playback.beginScrubbing()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }

        @objc func editingDidEnd(_ sender: UISlider) {
            isEditing = false
            let pct = max(0.0, min(1.0, Double(sender.value)))
            parent.scrubProgress = pct
            parent.playback.endScrubbing(at: pct, for: parent.clip)
            parent.isScrubbing = false
            if let custom = sender as? ClipCustomSlider {
                UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut]) {
                    custom.isInteracting = false
                }
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}

// MARK: - Isolated Clip Progress Bar View (Only redrawn when progress ticks)

private struct ClipProgressBarView: View {
    @ObservedObject var progressObserver: ClipProgressObserver
    let clip: MovieClip
    let playback: ClipPlaybackCoordinator
    let isResolving: Bool
    let isVideoReady: Bool
    @Binding var isScrubbing: Bool

    @State private var scrubProgress: Double = 0.0

    var body: some View {
        ZStack {
            if isResolving || !isVideoReady {
                // Shimmering animated light beam during buffering
                TimelineView(.animation) { timeline in
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    let phase = CGFloat(time.truncatingRemainder(dividingBy: 1.4) / 1.4)

                    GeometryReader { p in
                        let w = p.size.width
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
                            .frame(width: w, height: 4.0)
                    }
                }
                .frame(height: 16)
                .clipShape(Capsule())
            } else {
                ClipNativeSliderView(
                    progressObserver: progressObserver,
                    clip: clip,
                    playback: playback,
                    isScrubbing: $isScrubbing,
                    scrubProgress: $scrubProgress
                )
                .frame(height: 16)
            }
        }
        .frame(height: 16)
        .overlay(alignment: .top) {
            if isScrubbing {
                let clipDur = clip.duration
                let currentSec = clip.startTime + (clipDur * scrubProgress)
                let elapsedSec = max(0, currentSec - clip.startTime)
                HStack(spacing: 6) {
                    Text(formatClipTime(elapsedSec))
                        .font(.system(size: 17, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)

                    Text("/")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))

                    Text(formatClipTime(clipDur))
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .glassEffect(in: .capsule)
                .offset(y: -64)
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
}

extension ClipsFeedView {

    private func ensurePlaybackStarted() {
        if let clipId = currentClipId, let clip = clipsRepo.clips.first(where: { $0.id == clipId }) {
            playback.resume(for: clip)
        } else if let first = clipsRepo.clips.first {
            currentClipId = first.id
            playback.setupPlayer(for: first)
        }
    }

    private func resumeActiveClip() {
        ensurePlaybackStarted()
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

// MARK: - Native Liquid Glass Shapes for Action Rail

/// Векторное скругленное сердце Безье для нативного Apple Liquid Glass (.glassEffect)
public struct HeartShape: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let side = min(rect.width, rect.height)
        let x = rect.midX - side / 2
        let y = rect.midY - side / 2
        let w = side
        let h = side

        // Верхняя центральная выемка сердца
        let topNotch = CGPoint(x: x + w * 0.50, y: y + h * 0.26)
        path.move(to: topNotch)

        // Правая верхняя дуга
        path.addCurve(
            to: CGPoint(x: x + w * 0.96, y: y + h * 0.40),
            control1: CGPoint(x: x + w * 0.72, y: y + h * 0.04),
            control2: CGPoint(x: x + w * 1.00, y: y + h * 0.18)
        )

        // Правая сторона вниз к нижнему кончику
        path.addCurve(
            to: CGPoint(x: x + w * 0.50, y: y + h * 0.94),
            control1: CGPoint(x: x + w * 0.92, y: y + h * 0.64),
            control2: CGPoint(x: x + w * 0.68, y: y + h * 0.82)
        )

        // Левая сторона вверх от кончика к левой дуге
        path.addCurve(
            to: CGPoint(x: x + w * 0.04, y: y + h * 0.40),
            control1: CGPoint(x: x + w * 0.32, y: y + h * 0.82),
            control2: CGPoint(x: x + w * 0.08, y: y + h * 0.64)
        )

        // Левая верхняя дуга обратно к выемке
        path.addCurve(
            to: topNotch,
            control1: CGPoint(x: x + w * 0.00, y: y + h * 0.18),
            control2: CGPoint(x: x + w * 0.28, y: y + h * 0.04)
        )

        path.closeSubpath()
        return path
    }
}

/// Нативный круглый бабл с аккуратным хвостиком и 3 точками (комментарии) для Liquid Glass (.glassEffect)
public struct SpeechBubbleShape: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let side = min(rect.width, rect.height)
        let x = rect.midX - side / 2
        let y = rect.midY - side / 2
        let w = side
        let h = side

        let cx = x + w * 0.48
        let cy = y + h * 0.44
        let r = w * 0.38

        let rad20 = 20.0 * Double.pi / 180.0
        let rad85 = 85.0 * Double.pi / 180.0

        let p20 = CGPoint(x: cx + r * CGFloat(cos(rad20)), y: cy + r * CGFloat(sin(rad20)))
        let p85 = CGPoint(x: cx + r * CGFloat(cos(rad85)), y: cy + r * CGFloat(sin(rad85)))
        let tip = CGPoint(x: x + w * 0.88, y: y + h * 0.86)

        // 1. Дуга круга от 85° (снизу) через лево и верх к 20° (справа)
        path.addArc(
            center: CGPoint(x: cx, y: cy),
            radius: r,
            startAngle: Angle(degrees: 85),
            endAngle: Angle(degrees: 20),
            clockwise: false
        )

        // 2. Плавная дуга от 20° к кончику хвостика
        path.addCurve(
            to: tip,
            control1: CGPoint(x: x + w * 0.84, y: y + h * 0.64),
            control2: CGPoint(x: x + w * 0.84, y: y + h * 0.76)
        )

        // 3. Линия от кончика хвостика обратно к нижнему краю круга (к 85°)
        path.addLine(to: p85)
        path.closeSubpath()

        // 4. Три круглые дырочки (Three dot holes) с противоположным направлением (clockwise: true)
        let dotR = w * 0.048
        let sp = w * 0.155

        path.addArc(center: CGPoint(x: cx - sp, y: cy), radius: dotR, startAngle: .zero, endAngle: Angle(degrees: 360), clockwise: true)
        path.closeSubpath()

        path.addArc(center: CGPoint(x: cx, y: cy), radius: dotR, startAngle: .zero, endAngle: Angle(degrees: 360), clockwise: true)
        path.closeSubpath()

        path.addArc(center: CGPoint(x: cx + sp, y: cy), radius: dotR, startAngle: .zero, endAngle: Angle(degrees: 360), clockwise: true)
        path.closeSubpath()

        return path
    }
}

/// Нативная изогнутая стрелка «Поделиться» для Liquid Glass (.glassEffect)
public struct ShareArrowShape: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let side = min(rect.width, rect.height)
        let x = rect.midX - side / 2
        let y = rect.midY - side / 2
        let w = side
        let h = side

        // Наконечник стрелки сверху справа (вершина)
        let apex = CGPoint(x: x + w * 0.94, y: y + h * 0.28)
        path.move(to: apex)

        // Верхнее крыло наконечника
        path.addLine(to: CGPoint(x: x + w * 0.58, y: y + h * 0.06))

        // Верхняя внутренняя выемка наконечника
        path.addLine(to: CGPoint(x: x + w * 0.62, y: y + h * 0.22))

        // Верхний дугообразный край изогнутого тела стрелки
        path.addCurve(
            to: CGPoint(x: x + w * 0.08, y: y + h * 0.74),
            control1: CGPoint(x: x + w * 0.36, y: y + h * 0.24),
            control2: CGPoint(x: x + w * 0.14, y: y + h * 0.42)
        )

        // Нижнее основание тела стрелки
        path.addLine(to: CGPoint(x: x + w * 0.16, y: y + h * 0.92))

        // Нижний дугообразный край тела стрелки
        path.addCurve(
            to: CGPoint(x: x + w * 0.62, y: y + h * 0.52),
            control1: CGPoint(x: x + w * 0.22, y: y + h * 0.66),
            control2: CGPoint(x: x + w * 0.40, y: y + h * 0.52)
        )

        // Нижнее крыло наконечника
        path.addLine(to: CGPoint(x: x + w * 0.58, y: y + h * 0.70))

        // Возврат к вершине наконечника
        path.addLine(to: apex)

        path.closeSubpath()
        return path
    }
}

/// Нативная диагональная двойная стрелка масштабирования для Liquid Glass (.glassEffect)
public struct AspectExpandShape: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let side = min(rect.width, rect.height)
        let x = rect.midX - side / 2
        let y = rect.midY - side / 2
        let w = side
        let h = side

        // 1. Верхний правый наконечник
        let topApex = CGPoint(x: x + w * 0.90, y: y + h * 0.10)
        path.move(to: topApex)

        // Левое крыло верхнего наконечника
        path.addLine(to: CGPoint(x: x + w * 0.54, y: y + h * 0.12))

        // Внутренняя выемка верхнего наконечника
        path.addLine(to: CGPoint(x: x + w * 0.64, y: y + h * 0.22))

        // Верхний диагональный край соединительного моста
        path.addLine(to: CGPoint(x: x + w * 0.22, y: y + h * 0.64))

        // Верхнее крыло нижнего левого наконечника
        path.addLine(to: CGPoint(x: x + w * 0.12, y: y + h * 0.54))

        // 2. Нижний левый наконечник (вершина)
        let bottomApex = CGPoint(x: x + w * 0.10, y: y + h * 0.90)
        path.addLine(to: bottomApex)

        // Правое крыло нижнего наконечника
        path.addLine(to: CGPoint(x: x + w * 0.46, y: y + h * 0.88))

        // Внутренняя выемка нижнего наконечника
        path.addLine(to: CGPoint(x: x + w * 0.36, y: y + h * 0.78))

        // Нижний диагональный край соединительного моста
        path.addLine(to: CGPoint(x: x + w * 0.78, y: y + h * 0.36))

        // Нижнее крыло верхнего правого наконечника
        path.addLine(to: CGPoint(x: x + w * 0.88, y: y + h * 0.46))

        // Возврат к вершине верхнего наконечника
        path.addLine(to: topApex)

        path.closeSubpath()
        return path
    }
}




