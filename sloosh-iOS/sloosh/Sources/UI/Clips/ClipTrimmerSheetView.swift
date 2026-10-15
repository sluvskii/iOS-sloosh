import SwiftUI
import UIKit
import AVFoundation
import Combine

// MARK: - Apple Photos Gallery-Style Moment Trimmer & Creator
// Full portrait, real live video preview, iconic yellow frame with dual grip handles,
// pinch-to-zoom timeline (0.5x - 5x), 1-minute default duration, up to 10-minute max.

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
    @State private var zoomLevel: Double = 1.0
    @State private var caption: String = ""

    // Pinch-to-zoom interactive state
    @State private var pinchBaseSpan: Double? = nil

    // Player State
    @State private var player: AVPlayer? = nil
    @State private var isPlaying: Bool = false
    @State private var isPlayerReady: Bool = false
    @State private var playbackSec: Double = 0.0
    @State private var timeObserverToken: Any? = nil

    // Publishing State
    @State private var isPublishing: Bool = false
    @State private var publishErrorMessage: String? = nil

    private let minDuration: Double = 3.0
    private let maxDuration: Double = 600.0 // 10 minutes maximum

    // Iconic Apple Photos Trim Yellow Accent
    private let trimYellow = Color(red: 1.0, green: 0.82, blue: 0.15)

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

        // Default duration: 1 minute (60s) centered on current playback time
        let initialStart = max(0.0, currentPlaybackTime - 10.0)
        let resolvedTotal = totalDuration > 0 ? totalDuration : max(currentPlaybackTime + 600.0, 1200.0)
        let initialEnd = min(resolvedTotal, initialStart + 60.0)

        _startTime = State(initialValue: initialStart)
        _endTime = State(initialValue: max(initialStart + 3.0, initialEnd))
        _playbackSec = State(initialValue: initialStart)

        // Visible timeline scene window (approx. 2.5x the initial duration, ~150-180 seconds at 1x)
        let span = 180.0
        let wStart = max(0.0, initialStart - 30.0)
        let wEnd = min(resolvedTotal, wStart + span)
        _windowStart = State(initialValue: wStart)
        _windowEnd = State(initialValue: max(wStart + 60.0, wEnd))
    }

    private var clipDuration: Double {
        max(1.0, endTime - startTime)
    }

    private var formattedDuration: String {
        let total = Int(round(clipDuration))
        let m = total / 60
        let s = total % 60
        if m > 0 {
            return s > 0 ? "\(m) мин \(s) сек" : "\(m) мин"
        }
        return "\(s) сек"
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
                        // 1. Subtle movie context
                        movieContextBar

                        // 2. Video Preview Player (16:9, live stream, looped playback)
                        videoPreviewCard

                        // 3. Apple Photos-style Video Trimmer
                        galleryTrimmerSection

                        // 4. Caption Input
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
                .foregroundStyle(trimYellow)

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

    // MARK: - Apple Photos Gallery-Style Trimmer Section

    private var galleryTrimmerSection: some View {
        VStack(spacing: 14) {
            // Header: Timestamps, Duration Pill, and Zoom Controls
            HStack(alignment: .center) {
                // Start Time
                VStack(alignment: .leading, spacing: 2) {
                    Text("НАЧАЛО")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.white.opacity(0.45))

                    Text(formatSeconds(startTime))
                        .font(.system(size: 14, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                }

                Spacer()

                // Center Duration Badge
                VStack(spacing: 2) {
                    HStack(spacing: 5) {
                        Image(systemName: "scissors")
                            .font(.system(size: 11, weight: .bold))
                        Text(formattedDuration)
                            .font(.system(size: 13, weight: .bold).monospacedDigit())
                    }
                    .foregroundStyle(trimYellow)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.08)))

                    Text("макс. 10 мин")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }

                Spacer()

                // End Time
                VStack(alignment: .trailing, spacing: 2) {
                    Text("КОНЕЦ")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.white.opacity(0.45))

                    Text(formatSeconds(endTime))
                        .font(.system(size: 14, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 4)

            // Zoom Scale Switcher (0.5x, 1x, 2x, 5x)
            HStack(spacing: 6) {
                Text("Масштаб:")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))

                Spacer()

                ForEach([0.5, 1.0, 2.0, 5.0], id: \.self) { z in
                    Button {
                        setZoom(z)
                    } label: {
                        Text(zoomLabel(z))
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                            .foregroundStyle(zoomLevel == z ? Color.black : Color.white.opacity(0.8))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3.5)
                            .background(
                                Capsule()
                                    .fill(zoomLevel == z ? trimYellow : Color.white.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)

            // The Iconic Yellow Frame Trimmer Bar
            photosFilmstripTrackView
                .frame(height: 64)
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged { val in
                            handlePinchZoom(scale: val)
                        }
                        .onEnded { _ in
                            pinchBaseSpan = nil
                        }
                )
        }
        .padding(14)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Photos Filmstrip Track View (Iconic Apple Trim Box)

    private var photosFilmstripTrackView: some View {
        GeometryReader { geo in
            let totalW = geo.size.width
            let span = max(10.0, windowEnd - windowStart)

            let startX = CGFloat((startTime - windowStart) / span) * totalW
            let endX = CGFloat((endTime - windowStart) / span) * totalW
            let playheadX = CGFloat((playbackSec - windowStart) / span) * totalW

            let handleWidth: CGFloat = 20.0
            let clampedStartX = max(0, min(totalW - (handleWidth * 2), startX))
            let clampedEndX = max(clampedStartX + (handleWidth * 2), min(totalW, endX))
            let clampedPlayheadX = max(0, min(totalW, playheadX))

            ZStack(alignment: .leading) {
                // 1. Filmstrip Track with Ruler Ticks
                rulerBackgroundTrack(width: totalW, span: span)
                    .contentShape(Rectangle())
                    .onTapGesture { loc in
                        // Tap anywhere on track to seek playhead
                        let tappedTime = windowStart + Double(max(0, min(1, loc.x / totalW))) * span
                        seekTo(tappedTime, andPause: true)
                    }

                // 2. Dimmed Scrim Outside Selection (Left & Right)
                // Left Scrim
                Rectangle()
                    .fill(Color.black.opacity(0.68))
                    .frame(width: clampedStartX, height: 64)
                    .allowsHitTesting(false)

                // Right Scrim
                Rectangle()
                    .fill(Color.black.opacity(0.68))
                    .frame(width: max(0, totalW - clampedEndX), height: 64)
                    .offset(x: clampedEndX)
                    .allowsHitTesting(false)

                // 3. Highlighted Center Area (Draggable to shift whole window)
                Rectangle()
                    .fill(trimYellow.opacity(0.12))
                    .frame(width: max(handleWidth * 2, clampedEndX - clampedStartX), height: 64)
                    .offset(x: clampedStartX)
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { val in
                                handleCenterBoxDrag(translationX: val.translation.width, totalWidth: totalW, span: span)
                            }
                    )

                // 4. Top & Bottom Connecting Yellow Bars
                VStack {
                    Rectangle()
                        .fill(trimYellow)
                        .frame(width: max(handleWidth * 2, clampedEndX - clampedStartX), height: 3.5)
                        .offset(x: clampedStartX)

                    Spacer()

                    Rectangle()
                        .fill(trimYellow)
                        .frame(width: max(handleWidth * 2, clampedEndX - clampedStartX), height: 3.5)
                        .offset(x: clampedStartX)
                }
                .frame(height: 64)
                .allowsHitTesting(false)

                // 5. Playhead Needle (White Line with Glow)
                Capsule()
                    .fill(Color.white)
                    .frame(width: 3, height: 64)
                    .shadow(color: Color.black.opacity(0.7), radius: 2)
                    .offset(x: clampedPlayheadX - 1.5)
                    .allowsHitTesting(false)

                // 6. Left Handle (Start Handle: Rounded Left with Dual Grip Bars)
                leftHandleView(handleWidth: handleWidth)
                    .offset(x: clampedStartX)
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { val in
                                handleStartHandleDrag(locationDragX: val.location.x, totalWidth: totalW, span: span)
                            }
                    )

                // 7. Right Handle (End Handle: Rounded Right with Dual Grip Bars)
                rightHandleView(handleWidth: handleWidth)
                    .offset(x: clampedEndX - handleWidth)
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { val in
                                handleEndHandleDrag(locationDragX: val.location.x, totalWidth: totalW, span: span)
                            }
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
    }

    // MARK: - Left & Right Handles (Apple Photos Style)

    private func leftHandleView(handleWidth: CGFloat) -> some View {
        ZStack {
            // Expanded invisible touch area for easy grabbing
            Rectangle()
                .fill(Color.clear)
                .frame(width: 44, height: 64)
                .contentShape(Rectangle())

            // Visible Handle Shape
            UnevenRoundedRectangle(
                topLeadingRadius: 10,
                bottomLeadingRadius: 10,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0
            )
            .fill(trimYellow)
            .frame(width: handleWidth, height: 64)

            // Dual Vertical Grip Bars
            HStack(spacing: 2.5) {
                Capsule()
                    .fill(Color.black.opacity(0.65))
                    .frame(width: 2, height: 22)
                Capsule()
                    .fill(Color.black.opacity(0.65))
                    .frame(width: 2, height: 22)
            }
        }
    }

    private func rightHandleView(handleWidth: CGFloat) -> some View {
        ZStack {
            // Expanded invisible touch area for easy grabbing
            Rectangle()
                .fill(Color.clear)
                .frame(width: 44, height: 64)
                .contentShape(Rectangle())

            // Visible Handle Shape
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 10,
                topTrailingRadius: 10
            )
            .fill(trimYellow)
            .frame(width: handleWidth, height: 64)

            // Dual Vertical Grip Bars
            HStack(spacing: 2.5) {
                Capsule()
                    .fill(Color.black.opacity(0.65))
                    .frame(width: 2, height: 22)
                Capsule()
                    .fill(Color.black.opacity(0.65))
                    .frame(width: 2, height: 22)
            }
        }
    }

    // MARK: - Ruler Background Track

    private func rulerBackgroundTrack(width: CGFloat, span: Double) -> some View {
        ZStack(alignment: .leading) {
            Color.white.opacity(0.06)

            // Tick marks based on span
            let step: Double = span > 300 ? 30.0 : (span > 120 ? 15.0 : 5.0)
            let tickCount = max(2, Int(span / step))

            HStack(spacing: 0) {
                ForEach(0..<tickCount, id: \.self) { idx in
                    let t = windowStart + Double(idx) * step
                    VStack(spacing: 2) {
                        Rectangle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 1, height: idx % 2 == 0 ? 18 : 10)

                        if idx % 2 == 0 && span <= 360 {
                            Text(formatSeconds(t))
                                .font(.system(size: 7.5, weight: .regular).monospacedDigit())
                                .foregroundStyle(.white.opacity(0.35))
                        }
                    }
                    if idx < tickCount - 1 {
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 8)
            .allowsHitTesting(false)
        }
        .frame(height: 64)
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

    // MARK: - Gestures: Left Handle, Right Handle, Center Box

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

        // Auto-expand/pan window when near left edge
        if locationDragX < 24.0 && windowStart > 0 {
            let shift = span * 0.1
            windowStart = max(0.0, windowStart - shift)
            windowEnd = windowStart + span
        }
    }

    private func handleEndHandleDrag(locationDragX: CGFloat, totalWidth: CGFloat, span: Double) {
        guard totalWidth > 0 else { return }
        let timeAtLocation = windowStart + Double(max(0, min(1, locationDragX / totalWidth))) * span
        let maxLimit = totalDuration > 0 ? totalDuration : max(windowEnd + 600.0, 3600.0)
        let newEnd = max(startTime + minDuration, min(maxLimit, timeAtLocation))

        if newEnd - startTime > maxDuration {
            startTime = max(0.0, newEnd - maxDuration)
        }
        endTime = newEnd
        seekTo(newEnd, andPause: true)
        UISelectionFeedbackGenerator().selectionChanged()

        // Auto-expand/pan window when near right edge
        if locationDragX > totalWidth - 24.0 {
            let shift = span * 0.1
            windowEnd = min(maxLimit, windowEnd + shift)
            windowStart = max(0.0, windowEnd - span)
        }
    }

    private func handleCenterBoxDrag(translationX: CGFloat, totalWidth: CGFloat, span: Double) {
        guard totalWidth > 0 else { return }
        let deltaSec = Double(translationX / totalWidth) * span
        guard abs(deltaSec) >= 0.3 else { return }

        let currentLen = endTime - startTime
        let maxLimit = totalDuration > 0 ? totalDuration : max(windowEnd + 600.0, 3600.0)

        let targetStart = max(0.0, min(maxLimit - currentLen, startTime + deltaSec))
        let targetEnd = targetStart + currentLen

        startTime = targetStart
        endTime = targetEnd
        seekTo(targetStart, andPause: true)
        UISelectionFeedbackGenerator().selectionChanged()
    }

    // MARK: - Zooming & Navigation

    private func zoomLabel(_ z: Double) -> String {
        if z == 0.5 { return "0.5x" }
        if z == 1.0 { return "1x" }
        if z == 2.0 { return "2x" }
        return "5x"
    }

    private func setZoom(_ level: Double) {
        withAnimation(.easeInOut(duration: 0.25)) {
            zoomLevel = level
            let center = (startTime + endTime) / 2.0
            let baseDuration = max(60.0, clipDuration)
            let newSpan: Double

            switch level {
            case 0.5:
                newSpan = max(baseDuration * 3.5, 360.0)
            case 2.0:
                newSpan = max(baseDuration * 1.3, 90.0)
            case 5.0:
                newSpan = max(baseDuration * 1.1, 45.0)
            default: // 1.0
                newSpan = max(baseDuration * 1.8, 180.0)
            }

            let maxLimit = totalDuration > 0 ? totalDuration : max(center + newSpan, 3600.0)
            let wStart = max(0.0, center - newSpan / 2.0)
            let wEnd = min(maxLimit, wStart + newSpan)

            windowStart = wStart
            windowEnd = max(wStart + 30.0, wEnd)
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func handlePinchZoom(scale: CGFloat) {
        let currentSpan = windowEnd - windowStart
        if pinchBaseSpan == nil {
            pinchBaseSpan = currentSpan
        }
        guard let base = pinchBaseSpan, scale > 0.05 else { return }

        let targetSpan = max(30.0, min(1800.0, base / Double(scale)))
        let center = (startTime + endTime) / 2.0
        let maxLimit = totalDuration > 0 ? totalDuration : max(center + targetSpan, 3600.0)

        let wStart = max(0.0, center - targetSpan / 2.0)
        let wEnd = min(maxLimit, wStart + targetSpan)

        windowStart = wStart
        windowEnd = max(wStart + 20.0, wEnd)
    }

    // MARK: - Player Operations

    private func initializePlayer() async {
        var resolvedUrl: URL? = nil
        var resolvedHeaders = headers

        if resolvedHeaders["Referer"] == nil && resolvedHeaders["referer"] == nil {
            resolvedHeaders["Referer"] = "https://api.alloha.tv/"
        }

        // 1. Try direct streamUrl
        if let directStr = streamUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
           let directUrl = URL(string: directStr) {
            resolvedUrl = directUrl
        }

        // 2. Fallback to ClipStreamResolver
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

        // Periodic time observer for looping between startTime and endTime
        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        timeObserverToken = p.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak p] time in
            guard let p else { return }
            let sec = time.seconds
            guard sec.isFinite && !sec.isNaN else { return }
            self.playbackSec = sec

            // Loop back to start when end is reached
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

        // Initial seek to startTime and auto-play loop
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
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
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
