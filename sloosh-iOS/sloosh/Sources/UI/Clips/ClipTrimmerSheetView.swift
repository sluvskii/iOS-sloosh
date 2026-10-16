import SwiftUI
import UIKit
import AVFoundation
import Combine

// MARK: - Flagship Moment Creator (Создание момента)
// Clean, intuitive, and tactile:
// 1. Live looping video preview of the chosen moment with play/pause on tap.
// 2. 1-tap duration presets (15 сек | 30 сек | 60 сек | 2 мин).
// 3. Focused scene timeline with draggable start/end handles and whole-clip shifting.
// 4. Precision step buttons ([-1с] / [+1с]) for exact frame-level accuracy.
// 5. Minimalist Liquid Glass styling without visual clutter or tiny 2-hour sliders.

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
    @State private var activePreset: Int? = 30
    @State private var caption: String = ""

    // Drag Tracking State
    @State private var centerDragInitialStart: Double? = nil

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

    private let sampleTags = ["#эпик", "#цитата", "#лучшиймомент", "#юмор", "#шедевр", "#мурашки"]

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

        let resolvedTotal = totalDuration > 0 ? totalDuration : max(currentPlaybackTime + 600.0, 1800.0)

        // Default: 30-second window centered around current playback time
        let initialStart = max(0.0, currentPlaybackTime - 15.0)
        let initialEnd = min(resolvedTotal, initialStart + 30.0)

        _startTime = State(initialValue: initialStart)
        _endTime = State(initialValue: max(initialStart + 3.0, initialEnd))
        _playbackSec = State(initialValue: initialStart)

        // Focused scene window: ±45 seconds around the initial selection
        let wStart = max(0.0, initialStart - 30.0)
        let wEnd = min(resolvedTotal, initialEnd + 45.0)
        _windowStart = State(initialValue: wStart)
        _windowEnd = State(initialValue: max(wStart + 60.0, wEnd))
    }

    private var totalMovieDuration: Double {
        totalDuration > 0 ? totalDuration : max(currentPlaybackTime + 600.0, 1800.0)
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
                        // 1. Clean Movie Context Card
                        movieContextBar

                        // 2. Live Video Preview (16:9, Looped Playback)
                        videoPreviewCard

                        // 3. Quick Duration Presets (15с | 30с | 60с | 2 мин)
                        durationPresetsBar

                        // 4. Precision Trimmer Section with Step Nudge Buttons
                        focusedTrimmerSection

                        // 5. Caption Input & Hashtags
                        captionSection

                        // 6. Error Banner if any
                        if let error = publishErrorMessage {
                            errorBanner(error)
                        }

                        // 7. Prominent Publish Button
                        publishButton
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
        HStack(spacing: 10) {
            if let logoPath, !logoPath.isEmpty, let url = resolveImageUrl(logoPath) {
                AsyncCachedImage(url: url) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                } content: { img in
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 26, alignment: .leading)
                } fallback: {
                    Text(title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                }
            } else {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }

            if !movieSubtitle.isEmpty {
                Text("•")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.35))

                Text(movieSubtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Video Preview Card (16:9 Looped Playback)

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
                    Text("Подготовка видео...")
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
                            .frame(width: 54, height: 54)
                            .glassEffect(.regular.interactive(), in: Circle())

                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                            .offset(x: isPlaying ? 0 : 2)
                    }
                }
                .buttonStyle(.plain)
                .opacity(isPlaying ? 0.0 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: isPlaying)
            }

            // Top-Right Time Badge
            VStack {
                HStack {
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 10, weight: .medium))
                        Text(formatSeconds(playbackSec))
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4.5)
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

    // MARK: - Duration Presets Bar

    private var durationPresetsBar: some View {
        HStack(spacing: 8) {
            Text("Длительность:")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))

            Spacer()

            durationPresetChip(title: "15 сек", seconds: 15)
            durationPresetChip(title: "30 сек", seconds: 30)
            durationPresetChip(title: "60 сек", seconds: 60)
            durationPresetChip(title: "2 мин", seconds: 120)
        }
        .padding(.horizontal, 4)
    }

    private func durationPresetChip(title: String, seconds: Int) -> some View {
        let isSelected = (activePreset == seconds)
        return Button {
            applyDurationPreset(seconds: Double(seconds))
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(isSelected ? Color.black : Color.white.opacity(0.85))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.slooshAccent : Color.white.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
    }

    private func applyDurationPreset(seconds: Double) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            activePreset = Int(seconds)
            let newEnd = min(totalMovieDuration, startTime + seconds)
            endTime = newEnd

            // Adjust window comfortably around the selection
            ensureWindowComfortable()
            seekTo(startTime, andPause: false)
        }
    }

    // MARK: - Focused Trimmer Section

    private var focusedTrimmerSection: some View {
        VStack(spacing: 12) {
            // Header with Start / Duration / End & Step Nudge Buttons
            HStack(alignment: .center) {
                // START TIME BLOCK WITH [-1с] / [+1с]
                VStack(alignment: .leading, spacing: 4) {
                    Text("НАЧАЛО")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.white.opacity(0.45))

                    HStack(spacing: 5) {
                        Button {
                            nudgeStart(delta: -1.0)
                        } label: {
                            Text("-1с")
                                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                                .foregroundStyle(.white.opacity(0.85))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.white.opacity(0.1)))
                        }
                        .buttonStyle(.plain)

                        Text(formatSeconds(startTime))
                            .font(.system(size: 13.5, weight: .bold).monospacedDigit())
                            .foregroundStyle(.white)

                        Button {
                            nudgeStart(delta: 1.0)
                        } label: {
                            Text("+1с")
                                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                                .foregroundStyle(.white.opacity(0.85))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.white.opacity(0.1)))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()

                // CENTER DURATION PILL
                VStack(spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "scissors")
                            .font(.system(size: 11, weight: .bold))
                        Text(formattedDuration)
                            .font(.system(size: 12.5, weight: .bold).monospacedDigit())
                    }
                    .foregroundStyle(Color.slooshAccent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4.5)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                }

                Spacer()

                // END TIME BLOCK WITH [-1с] / [+1с]
                VStack(alignment: .trailing, spacing: 4) {
                    Text("КОНЕЦ")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.white.opacity(0.45))

                    HStack(spacing: 5) {
                        Button {
                            nudgeEnd(delta: -1.0)
                        } label: {
                            Text("-1с")
                                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                                .foregroundStyle(.white.opacity(0.85))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.white.opacity(0.1)))
                        }
                        .buttonStyle(.plain)

                        Text(formatSeconds(endTime))
                            .font(.system(size: 13.5, weight: .bold).monospacedDigit())
                            .foregroundStyle(.white)

                        Button {
                            nudgeEnd(delta: 1.0)
                        } label: {
                            Text("+1с")
                                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                                .foregroundStyle(.white.opacity(0.85))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.white.opacity(0.1)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 4)

            // Timeline Track
            timelineTrackView
                .frame(height: 54)
                .coordinateSpace(name: "trimmerTrack")
        }
        .padding(14)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Timeline Track View

    private var timelineTrackView: some View {
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
                // 1. Background Track with Subtle Hash Marks
                rulerBackgroundTrack(width: totalW)
                    .contentShape(Rectangle())
                    .onTapGesture { loc in
                        let tappedTime = windowStart + Double(max(0, min(1, loc.x / totalW))) * span
                        seekTo(tappedTime, andPause: true)
                    }

                // 2. Dimmed Outside Scrims
                Rectangle()
                    .fill(Color.black.opacity(0.70))
                    .frame(width: clampedStartX, height: 54)
                    .allowsHitTesting(false)

                Rectangle()
                    .fill(Color.black.opacity(0.70))
                    .frame(width: max(0, totalW - clampedEndX), height: 54)
                    .offset(x: clampedEndX)
                    .allowsHitTesting(false)

                // 3. Highlighted Selected Region (Draggable to shift whole clip)
                Rectangle()
                    .fill(Color.slooshAccent.opacity(0.15))
                    .frame(width: max(handleWidth * 2, clampedEndX - clampedStartX), height: 54)
                    .offset(x: clampedStartX)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .named("trimmerTrack"))
                            .onChanged { val in
                                handleCenterBoxDrag(translationX: val.translation.width, totalWidth: totalW, span: span)
                            }
                            .onEnded { _ in
                                centerDragInitialStart = nil
                            }
                    )

                // 4. Top & Bottom Border Lines
                VStack {
                    Rectangle()
                        .fill(Color.slooshAccent)
                        .frame(width: max(handleWidth * 2, clampedEndX - clampedStartX), height: 2.5)
                        .offset(x: clampedStartX)

                    Spacer()

                    Rectangle()
                        .fill(Color.slooshAccent)
                        .frame(width: max(handleWidth * 2, clampedEndX - clampedStartX), height: 2.5)
                        .offset(x: clampedStartX)
                }
                .frame(height: 54)
                .allowsHitTesting(false)

                // 5. White Needle Playhead
                Capsule()
                    .fill(Color.white)
                    .frame(width: 2.5, height: 54)
                    .shadow(color: Color.black.opacity(0.8), radius: 2)
                    .offset(x: clampedPlayheadX - 1.25)
                    .allowsHitTesting(false)

                // 6. Left Handle (Start)
                handleView(isLeft: true, handleWidth: handleWidth)
                    .offset(x: clampedStartX)
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .named("trimmerTrack"))
                            .onChanged { val in
                                handleStartHandleDrag(trackLocationX: val.location.x, totalWidth: totalW, span: span)
                            }
                    )

                // 7. Right Handle (End)
                handleView(isLeft: false, handleWidth: handleWidth)
                    .offset(x: clampedEndX - handleWidth)
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .named("trimmerTrack"))
                            .onChanged { val in
                                handleEndHandleDrag(trackLocationX: val.location.x, totalWidth: totalW, span: span)
                            }
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
        }
    }

    private func handleView(isLeft: Bool, handleWidth: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.clear)
                .frame(width: 40, height: 54)
                .contentShape(Rectangle())

            UnevenRoundedRectangle(
                topLeadingRadius: isLeft ? 8 : 0,
                bottomLeadingRadius: isLeft ? 8 : 0,
                bottomTrailingRadius: isLeft ? 0 : 8,
                topTrailingRadius: isLeft ? 0 : 8
            )
            .fill(Color.slooshAccent)
            .frame(width: handleWidth, height: 54)

            HStack(spacing: 2) {
                Capsule()
                    .fill(Color.black.opacity(0.65))
                    .frame(width: 1.5, height: 18)
                Capsule()
                    .fill(Color.black.opacity(0.65))
                    .frame(width: 1.5, height: 18)
            }
        }
    }

    private func rulerBackgroundTrack(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Color.white.opacity(0.04)

            HStack(spacing: 0) {
                let segments = 24
                ForEach(0..<segments, id: \.self) { i in
                    VStack {
                        Capsule()
                            .fill(Color.white.opacity(i % 4 == 0 ? 0.35 : 0.15))
                            .frame(width: 1, height: i % 4 == 0 ? 16 : 8)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Drag Handlers

    private func handleStartHandleDrag(trackLocationX: CGFloat, totalWidth: CGFloat, span: Double) {
        let clampedX = max(0, min(totalWidth, trackLocationX))
        let targetTime = windowStart + (Double(clampedX / totalWidth) * span)
        let maxStart = max(windowStart, endTime - minDuration)
        let resolvedStart = max(0.0, min(maxStart, targetTime))

        startTime = resolvedStart
        activePreset = nil

        // Auto-expand window if handle touches boundary
        if startTime <= windowStart + 3.0 && windowStart > 0 {
            windowStart = max(0.0, windowStart - 15.0)
        }

        seekTo(startTime, andPause: true)
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func handleEndHandleDrag(trackLocationX: CGFloat, totalWidth: CGFloat, span: Double) {
        let clampedX = max(0, min(totalWidth, trackLocationX))
        let targetTime = windowStart + (Double(clampedX / totalWidth) * span)
        let minEnd = startTime + minDuration
        let maxEnd = min(totalMovieDuration, startTime + maxDuration)
        let resolvedEnd = max(minEnd, min(maxEnd, targetTime))

        endTime = resolvedEnd
        activePreset = nil

        // Auto-expand window if handle touches boundary
        if endTime >= windowEnd - 3.0 && windowEnd < totalMovieDuration {
            windowEnd = min(totalMovieDuration, windowEnd + 15.0)
        }

        seekTo(endTime, andPause: true)
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func handleCenterBoxDrag(translationX: CGFloat, totalWidth: CGFloat, span: Double) {
        if centerDragInitialStart == nil {
            centerDragInitialStart = startTime
            player?.pause()
            isPlaying = false
        }
        guard let baseStart = centerDragInitialStart else { return }

        let deltaSeconds = Double(translationX / totalWidth) * span
        let clipLen = clipDuration
        let maxStart = totalMovieDuration - clipLen
        let targetStart = max(0.0, min(maxStart, baseStart + deltaSeconds))

        startTime = targetStart
        endTime = targetStart + clipLen

        ensureWindowComfortable()
        seekTo(startTime, andPause: true)
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func nudgeStart(delta: Double) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        activePreset = nil
        let newStart = max(0.0, min(endTime - minDuration, startTime + delta))
        startTime = newStart
        ensureWindowComfortable()
        seekTo(startTime, andPause: true)
    }

    private func nudgeEnd(delta: Double) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        activePreset = nil
        let newEnd = min(totalMovieDuration, max(startTime + minDuration, endTime + delta))
        endTime = newEnd
        ensureWindowComfortable()
        seekTo(endTime, andPause: true)
    }

    private func ensureWindowComfortable() {
        let span = max(60.0, (endTime - startTime) * 1.8)
        let center = (startTime + endTime) / 2.0
        var wStart = max(0.0, center - (span / 2.0))
        var wEnd = min(totalMovieDuration, wStart + span)

        if wStart > startTime {
            wStart = max(0.0, startTime - 15.0)
            wEnd = min(totalMovieDuration, wStart + span)
        }
        if wEnd < endTime {
            wEnd = min(totalMovieDuration, endTime + 15.0)
            wStart = max(0.0, wEnd - span)
        }

        windowStart = wStart
        windowEnd = max(wStart + 30.0, wEnd)
    }

    // MARK: - Caption & Tags Section

    private var captionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Подпись к моменту")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))

            TextField("Добавьте подпись или цитату...", text: $caption, axis: .vertical)
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .lineLimit(2...4)
                .padding(12)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            // Quick Tag Chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(sampleTags, id: \.self) { tag in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            if !caption.contains(tag) {
                                caption = caption.isEmpty ? tag : "\(caption) \(tag)"
                            }
                        } label: {
                            Text(tag)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.8))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.white.opacity(0.08))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.red)

            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.red.opacity(0.95))

            Spacer()
        }
        .padding(12)
        .background(Color.red.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Publish Button

    private var publishButton: some View {
        Button {
            publishMoment()
        } label: {
            HStack(spacing: 8) {
                if isPublishing {
                    ProgressView()
                        .tint(.black)
                } else {
                    Image(systemName: "sparkles.tv.fill")
                        .font(.system(size: 16, weight: .bold))

                    Text("Опубликовать в Моменты")
                        .font(.system(size: 15, weight: .bold))
                }
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color.white)
            .clipShape(Capsule())
            .shadow(color: Color.white.opacity(0.15), radius: 10, y: 3)
        }
        .buttonStyle(.glassPress)
        .disabled(isPublishing)
        .padding(.top, 4)
    }

    // MARK: - Player Operations

    private func initializePlayer() async {
        var resolvedUrl: URL? = nil
        var resolvedHeaders = headers

        if resolvedHeaders["Referer"] == nil && resolvedHeaders["referer"] == nil {
            resolvedHeaders["Referer"] = "https://api.alloha.tv/"
        }

        if let directStr = streamUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
           let directUrl = URL(string: directStr) {
            resolvedUrl = directUrl
        }

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

    private func resolveImageUrl(_ path: String) -> URL? {
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return URL(string: path)
        }
        if let normalized = normalizeImageUrl(path: path) {
            return URL(string: normalized)
        }
        return nil
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
