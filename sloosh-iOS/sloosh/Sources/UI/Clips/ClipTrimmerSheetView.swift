import SwiftUI
import UIKit
import AVFoundation
import Combine

// MARK: - Native Minimalist Moment Creator Screen (Portrait, Live Video Preview, Tactile Trimmer)

public struct ClipTrimmerSheetView: View {
    let mediaId: Int
    let mediaType: String
    let title: String
    let posterPath: String?
    let backdropPath: String?
    let logoPath: String?
    let season: Int?
    let episode: Int?
    let translationName: String?
    let currentPlaybackTime: Double
    let totalDuration: Double
    let streamUrl: String?
    let headers: [String: String]
    let iframeUrl: String?
    let kpId: Int?
    let tmdbId: Int?
    let onPublished: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var authRepo = AuthRepository.shared
    @StateObject private var clipsRepo = ClipsRepository.shared

    // Range Selection & Timeline Window
    @State private var startTime: Double
    @State private var endTime: Double
    @State private var windowStart: Double
    @State private var windowEnd: Double
    @State private var caption: String = ""

    // Player State
    @State private var player: AVPlayer? = nil
    @State private var isPlaying: Bool = false
    @State private var isPlayerReady: Bool = false
    @State private var isSeeking: Bool = false
    @State private var playbackSec: Double = 0.0
    @State private var timeObserverToken: Any? = nil

    // Publishing State
    @State private var isPublishing: Bool = false
    @State private var publishErrorMessage: String? = nil

    private let minDuration: Double = 5.0
    private let maxDuration: Double = 60.0

    public init(
        mediaId: Int,
        mediaType: String = "movie",
        title: String,
        posterPath: String? = nil,
        backdropPath: String? = nil,
        logoPath: String? = nil,
        season: Int? = nil,
        episode: Int? = nil,
        translationName: String? = nil,
        currentPlaybackTime: Double,
        totalDuration: Double,
        streamUrl: String? = nil,
        headers: [String: String] = [:],
        iframeUrl: String? = nil,
        kpId: Int? = nil,
        tmdbId: Int? = nil,
        onPublished: (() -> Void)? = nil
    ) {
        self.mediaId = mediaId
        self.mediaType = mediaType
        self.title = title
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.logoPath = logoPath
        self.season = season
        self.episode = episode
        self.translationName = translationName
        self.currentPlaybackTime = currentPlaybackTime
        self.totalDuration = totalDuration
        self.streamUrl = streamUrl
        self.headers = headers
        self.iframeUrl = iframeUrl
        self.kpId = kpId
        self.tmdbId = tmdbId
        self.onPublished = onPublished

        // Default: 30-second window centered around current playback time
        let initialStart = max(0.0, currentPlaybackTime - 12.0)
        let resolvedTotal = totalDuration > 0 ? totalDuration : max(currentPlaybackTime + 180.0, 300.0)
        let initialEnd = min(resolvedTotal, initialStart + 30.0)

        _startTime = State(initialValue: initialStart)
        _endTime = State(initialValue: max(initialStart + 5.0, initialEnd))
        _playbackSec = State(initialValue: initialStart)

        // Visible timeline scene window (approx. 3-4 minutes around the scene)
        let wStart = max(0.0, initialStart - 45.0)
        let wEnd = min(resolvedTotal, max(initialEnd + 45.0, wStart + 180.0))
        _windowStart = State(initialValue: wStart)
        _windowEnd = State(initialValue: max(wStart + 60.0, wEnd))
    }

    private var clipDuration: Double {
        max(1.0, endTime - startTime)
    }

    private var formattedDuration: String {
        "\(Int(round(clipDuration))) сек"
    }

    private var movieSubtitle: String {
        var parts: [String] = []
        if let s = season, let e = episode {
            parts.append("\(s) сезон, \(e) серия")
        }
        if let voice = translationName, !voice.isEmpty {
            parts.append(voice)
        }
        return parts.joined(separator: " • ")
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        // 1. Subtle movie context header
                        movieContextBar

                        // 2. Video Preview Player (16:9, interactive, live loop)
                        videoPreviewCard

                        // 3. Native Trimmer Scrubber & Stepper Controls
                        trimmerSection

                        // 4. Clean Caption Input (no spammy tags, minimal)
                        captionSection

                        // 5. Error banner if any
                        if let error = publishErrorMessage {
                            errorBanner(error)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 36)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Создать момент")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") {
                        dismiss()
                    }
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.85))
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        publishMoment()
                    } label: {
                        if isPublishing {
                            ProgressView()
                                .tint(.black)
                                .frame(width: 72, height: 32)
                        } else {
                            Text("Опубликовать")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.black)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(Color.white))
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isPublishing)
                }
            }
        }
        .preferredColorScheme(.dark)
        .environment(\.colorScheme, .dark)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            AppDelegate.lockToPortrait()
        }
        .task {
            await initializePlayer()
        }
        .onDisappear {
            cleanupPlayer()
            AppDelegate.lockToLandscape()
        }
    }

    // MARK: - Movie Context Bar

    private var movieContextBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "film")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.slooshAccent)

            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            if !movieSubtitle.isEmpty {
                Text("•")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))

                Text(movieSubtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Video Preview Card

    private var videoPreviewCard: some View {
        ZStack {
            // Video Layer
            if let player {
                TrimmerVideoLayerRepresentable(player: player)
                    .aspectRatio(16/9, contentMode: .fit)
                    .background(Color.black)
            } else {
                Color.black
                    .aspectRatio(16/9, contentMode: .fit)
            }

            // Buffering / Loading Indicator
            if !isPlayerReady {
                VStack(spacing: 10) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.2)
                    Text("Загрузка видео...")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            // Play/Pause Overlay Icon
            if isPlayerReady {
                Button {
                    togglePlayback()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.45))
                            .frame(width: 56, height: 56)
                            .glassEffect(.regular.interactive(), in: Circle())

                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.white)
                            .offset(x: isPlaying ? 0 : 2)
                    }
                }
                .buttonStyle(.plain)
                .opacity(isPlaying ? 0.0 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: isPlaying)
            }

            // Top-Right Current Position Pill
            VStack {
                HStack {
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 10))
                        Text(formatSeconds(playbackSec))
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .glassEffect(.regular, in: Capsule())
                    .padding(10)
                }
                Spacer()
            }
        }
        .aspectRatio(16/9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {
            togglePlayback()
        }
    }

    // MARK: - Trimmer Section

    private var trimmerSection: some View {
        VStack(spacing: 12) {
            // Header with Scene Jump & Window Shifter
            HStack {
                Text("Отрезок момента")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer()

                // Shift scene window buttons (-30s / +30s)
                HStack(spacing: 6) {
                    Button {
                        shiftSceneWindow(by: -30.0)
                    } label: {
                        Text("−30с")
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.75))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3.5)
                            .glassEffect(.regular.interactive(), in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        shiftSceneWindow(by: +30.0)
                    } label: {
                        Text("+30с")
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.75))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3.5)
                            .glassEffect(.regular.interactive(), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)

            // Tactile Range Scrubber Bar
            scrubberTrackView
                .frame(height: 52)

            // Stepper and Timestamp Controls
            stepperControlsRow
        }
        .padding(14)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Scrubber Track View

    private var scrubberTrackView: some View {
        GeometryReader { geo in
            let totalW = geo.size.width
            let span = max(10.0, windowEnd - windowStart)

            let startX = CGFloat((startTime - windowStart) / span) * totalW
            let endX = CGFloat((endTime - windowStart) / span) * totalW
            let playheadX = CGFloat((playbackSec - windowStart) / span) * totalW

            let clampedStartX = max(0, min(totalW - 20, startX))
            let clampedEndX = max(clampedStartX + 20, min(totalW, endX))
            let clampedPlayheadX = max(0, min(totalW, playheadX))

            ZStack(alignment: .leading) {
                // Background Track
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 48)

                // Tick marks (every 10 seconds in the window)
                HStack(spacing: 0) {
                    let tickCount = Int(span / 10.0)
                    ForEach(0..<max(1, tickCount), id: \.self) { _ in
                        Spacer()
                        Rectangle()
                            .fill(Color.white.opacity(0.12))
                            .frame(width: 1, height: 16)
                    }
                    Spacer()
                }
                .frame(height: 48)
                .allowsHitTesting(false)

                // Highlighted Active Range
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.slooshAccent.opacity(0.24))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.slooshAccent, lineWidth: 2)
                    )
                    .frame(width: max(20, clampedEndX - clampedStartX), height: 48)
                    .offset(x: clampedStartX)
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { val in
                                handleCenterDrag(translationX: val.translation.width, totalWidth: totalW, span: span)
                            }
                    )

                // Playhead indicator
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2.5, height: 48)
                    .shadow(color: .black.opacity(0.5), radius: 2)
                    .offset(x: clampedPlayheadX)
                    .allowsHitTesting(false)

                // Left Handle (Start Time)
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white)
                        .frame(width: 18, height: 48)
                        .overlay(
                            Image(systemName: "chevron.compact.left")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.black)
                        )
                        .contentShape(Rectangle())
                        .offset(x: clampedStartX)
                        .gesture(
                            DragGesture(minimumDistance: 1)
                                .onChanged { val in
                                    handleStartHandleDrag(locationDragX: val.location.x, totalWidth: totalW, span: span)
                                }
                        )
                }

                // Right Handle (End Time)
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white)
                        .frame(width: 18, height: 48)
                        .overlay(
                            Image(systemName: "chevron.compact.right")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.black)
                        )
                        .contentShape(Rectangle())
                        .offset(x: max(clampedStartX + 18, clampedEndX - 18))
                        .gesture(
                            DragGesture(minimumDistance: 1)
                                .onChanged { val in
                                    handleEndHandleDrag(locationDragX: val.location.x, totalWidth: totalW, span: span)
                                }
                        )
                }
            }
        }
    }

    // MARK: - Stepper and Timestamp Controls Row

    private var stepperControlsRow: some View {
        HStack(alignment: .center) {
            // Left Column: START
            VStack(alignment: .leading, spacing: 4) {
                Text("НАЧАЛО")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.45))

                Text(formatSeconds(startTime))
                    .font(.system(size: 14, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)

                HStack(spacing: 4) {
                    Button {
                        adjustStart(by: -1.0)
                    } label: {
                        Text("−1с")
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .glassEffect(.regular.interactive(), in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        adjustStart(by: +1.0)
                    } label: {
                        Text("+1с")
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .glassEffect(.regular.interactive(), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Center Column: DURATION PILL
            VStack(spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: "scissors")
                        .font(.system(size: 11, weight: .bold))
                    Text(formattedDuration)
                        .font(.system(size: 13, weight: .bold).monospacedDigit())
                }
                .foregroundStyle(Color.slooshAccent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .glassEffect(.regular, in: Capsule())

                Text("мин. 5с • макс. 60с")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .frame(maxWidth: .infinity, alignment: .center)

            // Right Column: END
            VStack(alignment: .trailing, spacing: 4) {
                Text("КОНЕЦ")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.45))

                Text(formatSeconds(endTime))
                    .font(.system(size: 14, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)

                HStack(spacing: 4) {
                    Button {
                        adjustEnd(by: -1.0)
                    } label: {
                        Text("−1с")
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .glassEffect(.regular.interactive(), in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        adjustEnd(by: +1.0)
                    } label: {
                        Text("+1с")
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .glassEffect(.regular.interactive(), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.top, 4)
    }

    // MARK: - Caption Section

    private var captionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Описание к моменту")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)

            TextField("Добавьте подпись или цитату (необязательно)...", text: $caption, axis: .vertical)
                .lineLimit(2...3)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .padding(12)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(14)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 15))
                .foregroundStyle(.red)

            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.red.opacity(0.95))
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(12)
        .background(Color.red.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    // MARK: - Scrubber Drag Handlers

    private func handleStartHandleDrag(locationDragX: CGFloat, totalWidth: CGFloat, span: Double) {
        guard totalWidth > 0 else { return }
        let timeAtLocation = windowStart + Double(max(0, min(1, locationDragX / totalWidth))) * span
        let newStart = max(0.0, min(endTime - minDuration, timeAtLocation))

        if endTime - newStart > maxDuration {
            endTime = newStart + maxDuration
        }
        startTime = newStart
        seekTo(newStart, andPause: true)
        UISelectionFeedbackGenerator().selectionChanged()

        // Auto-expand window if dragging near left boundary
        if newStart - windowStart < 10.0 && windowStart > 0 {
            windowStart = max(0.0, windowStart - 25.0)
        }
    }

    private func handleEndHandleDrag(locationDragX: CGFloat, totalWidth: CGFloat, span: Double) {
        guard totalWidth > 0 else { return }
        let timeAtLocation = windowStart + Double(max(0, min(1, locationDragX / totalWidth))) * span
        let maxLimit = totalDuration > 0 ? totalDuration : windowEnd
        let newEnd = max(startTime + minDuration, min(maxLimit, timeAtLocation))

        if newEnd - startTime > maxDuration {
            startTime = max(0.0, newEnd - maxDuration)
        }
        endTime = newEnd
        seekTo(newEnd, andPause: true)
        UISelectionFeedbackGenerator().selectionChanged()

        // Auto-expand window if dragging near right boundary
        if windowEnd - newEnd < 10.0 {
            windowEnd = min(maxLimit, windowEnd + 25.0)
        }
    }

    private func handleCenterDrag(translationX: CGFloat, totalWidth: CGFloat, span: Double) {
        guard totalWidth > 0 else { return }
        let deltaSec = Double(translationX / totalWidth) * span
        guard abs(deltaSec) >= 0.5 else { return }

        let currentLen = endTime - startTime
        let maxLimit = totalDuration > 0 ? totalDuration : windowEnd

        let targetStart = max(0.0, min(maxLimit - currentLen, startTime + deltaSec))
        let targetEnd = targetStart + currentLen

        startTime = targetStart
        endTime = targetEnd
        seekTo(targetStart, andPause: true)
        UISelectionFeedbackGenerator().selectionChanged()
    }

    // MARK: - Fine Steppers

    private func adjustStart(by delta: Double) {
        let newStart = max(0.0, min(endTime - minDuration, startTime + delta))
        if endTime - newStart > maxDuration {
            endTime = newStart + maxDuration
        }
        startTime = newStart
        seekTo(newStart, andPause: true)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        if newStart < windowStart {
            windowStart = max(0.0, newStart - 15.0)
        }
    }

    private func adjustEnd(by delta: Double) {
        let maxLimit = totalDuration > 0 ? totalDuration : windowEnd
        let newEnd = max(startTime + minDuration, min(maxLimit, endTime + delta))
        if newEnd - startTime > maxDuration {
            startTime = max(0.0, newEnd - maxDuration)
        }
        endTime = newEnd
        seekTo(newEnd, andPause: true)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        if newEnd > windowEnd {
            windowEnd = min(maxLimit, newEnd + 15.0)
        }
    }

    private func shiftSceneWindow(by delta: Double) {
        let maxLimit = totalDuration > 0 ? totalDuration : max(windowEnd + 180.0, 300.0)
        let newWindowStart = max(0.0, min(maxLimit - 60.0, windowStart + delta))
        let windowSpan = windowEnd - windowStart
        let newWindowEnd = min(maxLimit, newWindowStart + windowSpan)

        windowStart = newWindowStart
        windowEnd = max(newWindowStart + 30.0, newWindowEnd)

        let currentLen = endTime - startTime
        let newStart = max(newWindowStart, min(newWindowEnd - currentLen, startTime + delta))
        startTime = newStart
        endTime = newStart + currentLen

        seekTo(newStart, andPause: true)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    // MARK: - Player Operations

    private func initializePlayer() async {
        var resolvedUrl: URL? = nil
        var resolvedHeaders = headers

        if resolvedHeaders["Referer"] == nil && resolvedHeaders["referer"] == nil {
            resolvedHeaders["Referer"] = "https://api.alloha.tv/"
        }

        // 1. Try provided activeStreamUrlString
        if let directStr = streamUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
           let directUrl = URL(string: directStr) {
            resolvedUrl = directUrl
        }

        // 2. Fallback to ClipStreamResolver if direct stream unavailable
        if resolvedUrl == nil {
            let dummy = MovieClip(
                mediaId: mediaId,
                mediaType: mediaType,
                title: title,
                season: season,
                episode: episode,
                translationName: translationName,
                startTime: startTime,
                endTime: endTime,
                caption: "",
                authorId: "",
                authorName: "",
                streamUrl: streamUrl,
                iframeUrl: iframeUrl,
                kpId: kpId,
                tmdbId: tmdbId
            )
            if let resolved = await ClipStreamResolver.shared.resolveClip(for: dummy) {
                resolvedUrl = resolved.url
                resolvedHeaders = resolved.headers
            }
        }

        guard let targetUrl = resolvedUrl else {
            publishErrorMessage = "Не удалось загрузить видеопоток для предпросмотра."
            return
        }

        let asset = AVURLAsset(url: targetUrl, options: ["AVURLAssetHTTPHeaderFieldsKey": resolvedHeaders])
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 5.0

        try? AVAudioSession.sharedInstance().setActive(true)

        let p = AVPlayer(playerItem: item)
        p.actionAtItemEnd = .none
        p.automaticallyWaitsToMinimizeStalling = true

        // Periodic time observer for looping
        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        timeObserverToken = p.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak p] time in
            guard let p else { return }
            let sec = time.seconds
            guard sec.isFinite && !sec.isNaN else { return }
            self.playbackSec = sec

            // Check if end of clip reached -> seamless loop back to start
            if sec >= self.endTime - 0.05 {
                let sTime = CMTime(seconds: self.startTime, preferredTimescale: 600)
                p.seek(to: sTime, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                    if self.isPlaying {
                        p.play()
                    }
                }
            }
        }

        self.player = p

        // Initial seek to startTime and auto-play
        let sTime = CMTime(seconds: startTime, preferredTimescale: 600)
        p.seek(to: sTime, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            self.isPlayerReady = true
            self.isPlaying = true
            p.play()
        }
    }

    private func togglePlayback() {
        guard let player else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            if playbackSec >= endTime - 0.1 || playbackSec < startTime {
                seekTo(startTime)
            }
            player.play()
            isPlaying = true
        }
    }

    private func seekTo(_ seconds: Double, andPause: Bool = false) {
        guard let player else { return }
        if andPause {
            player.pause()
            isPlaying = false
        }
        let clamped = max(0.0, seconds)
        playbackSec = clamped
        let time = CMTime(seconds: clamped, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func cleanupPlayer() {
        if let token = timeObserverToken, let player {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
        player?.pause()
        self.player = nil
    }

    private func formatSeconds(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%02d:%02d", m, s)
    }

    // MARK: - Publish Action

    private func publishMoment() {
        guard !isPublishing else { return }
        isPublishing = true
        publishErrorMessage = nil
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        let user = authRepo.currentUser
        let authorId = user?.id ?? "guest_\(UIDevice.current.identifierForVendor?.uuidString ?? "user")"
        let authorName = (user?.displayName?.isEmpty == false ? user?.displayName : nil) ?? user?.displayTitle ?? "Зритель"
        let authorAvatar = user?.photoURL

        let clip = MovieClip(
            mediaId: mediaId,
            mediaType: mediaType,
            title: title,
            posterPath: posterPath,
            backdropPath: backdropPath,
            logoPath: logoPath,
            season: season,
            episode: episode,
            translationName: translationName,
            startTime: startTime,
            endTime: endTime,
            caption: caption.trimmingCharacters(in: .whitespacesAndNewlines),
            authorId: authorId,
            authorName: authorName,
            authorAvatar: authorAvatar,
            streamUrl: streamUrl,
            iframeUrl: iframeUrl,
            kpId: kpId,
            tmdbId: tmdbId
        )

        Task {
            do {
                try await clipsRepo.publishClip(clip)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                cleanupPlayer()
                dismiss()
                onPublished?()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    ToastManager.shared.show(title: "Момент опубликован в ленту! ✨", icon: "sparkles.tv.fill", iconColor: Color.slooshAccent)
                }
            } catch {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                withAnimation {
                    publishErrorMessage = "Не удалось сохранить момент. Проверьте подключение к сети."
                }
                isPublishing = false
            }
        }
    }
}

// MARK: - Trimmer Video Layer Representable

private struct TrimmerVideoLayerRepresentable: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> TrimmerPlayerContainerView {
        let view = TrimmerPlayerContainerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: TrimmerPlayerContainerView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
    }
}

private final class TrimmerPlayerContainerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .black
    }
}
