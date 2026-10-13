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
                                player.seek(to: sTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                                    self?.playWithCurrentSpeed()
                                }
                            } else {
                                self.playWithCurrentSpeed()
                            }
                        } else {
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
        } else {
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

    func pause() {
        activePlayer?.pause()
        isPlaying = false
    }

    func resume(for clip: MovieClip?) {
        guard let clip else { return }
        if activePlayer == nil || currentClipId != clip.id {
            setupPlayer(for: clip)
        } else {
            playWithCurrentSpeed()
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
        }
        .fullScreenCover(item: $fullPlayerConfig, onDismiss: {
            fullPlayerConfig = nil
            ensurePlaybackStarted()
        }) { config in
            PlayerView(config: config)
                .preferredColorScheme(.dark)
                .environment(\.colorScheme, .dark)
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
            playback.pause()
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
        let statusBarClearance = max(topSafeArea, 47.0) + 8.0
        let blurOpacity = headerBlurOpacity(height: fullHeight)

        return VStack(spacing: 0) {
            // Status bar clearance (keeps title comfortable below Dynamic Island / notch)
            Color.clear
                .frame(height: statusBarClearance)
                .allowsHitTesting(false)

            // Header title bar (perfectly symmetrical with matching 44x44 balances on left and right)
            HStack(spacing: 0) {
                Color.clear
                    .frame(width: 44, height: 44)
                    .padding(.leading, 16)
                    .allowsHitTesting(false)

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

            // 4. Поделиться
            Button {
                shareClip(clip)
            } label: {
                Label("Поделиться", systemImage: "arrowshape.turn.up.right")
            }

            // 5. Удалить момент (только для автора)
            if isAuthor(of: clip) {
                Divider()

                Button(role: .destructive) {
                    confirmDelete(clip: clip)
                } label: {
                    Label("Удалить момент", systemImage: "trash")
                }
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
        .onChange(of: currentClipId) { oldId, newId in
            AppDiagnostics.shared.log("[ClipsFeedView] currentClipId changed from \(String(describing: oldId)) to \(String(describing: newId))")
            guard let newId = newId, newId != oldId, let clip = clipsRepo.clips.first(where: { $0.id == newId }) else { return }
            playback.setupPlayer(for: clip)
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

            // 2. Video Container with smooth corner radius
            videoCardContainer(clip, width: width, height: availableHeight, isCurrent: isCurrent)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

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

            // 5. Touch & Gesture Zones: Left and Right Edge 2x Speed, Center Instant 0ms Play/Pause
            HStack(spacing: 0) {
                // Left Edge 2x Speed Zone (80pt)
                edgeAccelerationZone(for: clip)
                    .frame(width: 80)

                // Center Instant Play/Pause & Double-Tap Heart Zone
                centerTapZone(clip: clip)
                    .frame(maxWidth: .infinity)

                // Right Edge 2x Speed Zone (80pt) — symmetrically accelerates, right rail buttons sit above in zIndex(10)
                edgeAccelerationZone(for: clip)
                    .frame(width: 80)
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
                .padding(.leading, 14)
                .padding(.trailing, 14)
                .padding(.bottom, 14)
            }
            .opacity(isOverlayHidden ? 0.0 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.85), value: isOverlayHidden)
            .allowsHitTesting(!isOverlayHidden)
            .zIndex(10)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
        } else if let tr = clip.translationName, !tr.isEmpty {
            Text(tr)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
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

                Text("\(clip.likesCount)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
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

                Text("\(clip.commentsCount)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
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

                Text("Поделиться")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
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
                    ToastManager.shared.show(title: "Режим: Во весь экран (9:16)", icon: "arrow.up.left.and.arrow.down.right", iconColor: .white)
                } else {
                    clipScaleModeRaw = ClipScalingMode.fit.rawValue
                    ToastManager.shared.show(title: "Режим: В кадре", icon: "arrow.down.right.and.arrow.up.left", iconColor: .white)
                }
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: currentScaleMode == .fit ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace.downUp.byLayer))

                Text(currentScaleMode == .fit ? "9:16" : "В кадре")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: currentScaleMode)
            .frame(width: 56, height: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Scrubber Progress Bar Component (Isolated observation)
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
        GeometryReader { barProxy in
            let totalWidth = barProxy.size.width
            let displayProgress = isScrubbing ? scrubProgress : progressObserver.progress
            let activeWidth = max(0, min(totalWidth, totalWidth * displayProgress))
            let barHeight: CGFloat = isScrubbing ? 6.0 : 3.0

            ZStack(alignment: .leading) {
                // Background Track
                Capsule()
                    .fill(Color.white.opacity(isScrubbing ? 0.35 : 0.22))
                    .frame(height: barHeight)

                if isResolving || !isVideoReady {
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
                            .frame(width: 12, height: 12)
                            .position(x: min(totalWidth - 6, max(6, activeWidth)), y: barProxy.size.height / 2)
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
        .frame(height: 16)
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
