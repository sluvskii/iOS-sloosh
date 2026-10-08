import SwiftUI
import UIKit
import AVKit
import Combine

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
    let iframeUrl: String?
    let kpId: Int?
    let tmdbId: Int?
    let onPublished: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var authRepo = AuthRepository.shared
    @StateObject private var clipsRepo = ClipsRepository.shared

    @State private var startTime: Double
    @State private var endTime: Double
    @State private var caption: String = ""
    @State private var isPublishing: Bool = false
    @State private var previewPlayer: AVPlayer?
    @State private var pipController: AVPictureInPictureController? = nil
    @State private var timeObserver: Any?
    @State private var isMuted: Bool = false
    @State private var isPlaying: Bool = true

    private let minDuration: Double = 5.0
    private let maxDuration: Double = 60.0
    private let sampleTags = ["#эпик", "#цитата", "#лучшиймомент", "#юмор", "#шедевр", "#топ"]

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
        self.iframeUrl = iframeUrl
        self.kpId = kpId
        self.tmdbId = tmdbId
        self.onPublished = onPublished

        // Default window: ±15 sec around current playback time
        let defaultStart = max(0.0, currentPlaybackTime - 15.0)
        let defaultEnd = min(totalDuration > 0 ? totalDuration : currentPlaybackTime + 15.0, defaultStart + 30.0)
        _startTime = State(initialValue: defaultStart)
        _endTime = State(initialValue: max(defaultStart + 10.0, defaultEnd))
    }

    private var clipDuration: Double {
        max(1.0, endTime - startTime)
    }

    private var formattedRange: String {
        let sMin = Int(startTime) / 60
        let sSec = Int(startTime) % 60
        let eMin = Int(endTime) / 60
        let eSec = Int(endTime) % 60
        return String(format: "%02d:%02d – %02d:%02d", sMin, sSec, eMin, eSec)
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // 1. Live Preview Video Box
                        previewVideoCard
                            .frame(height: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )
                            .padding(.horizontal, 16)

                        // 2. Trimmer Controls
                        VStack(spacing: 14) {
                            HStack {
                                Text("Отрезок момента")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white)
                                Spacer()
                                Text("\(formattedRange) (\(Int(clipDuration)) сек)")
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Color.slooshAccent)
                            }

                            // Range Slider UI
                            VStack(spacing: 12) {
                                // Start Time Slider
                                HStack(spacing: 10) {
                                    Text("Начало")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.6))
                                        .frame(width: 55, alignment: .leading)

                                    Slider(
                                        value: $startTime,
                                        in: 0...max(0, endTime - minDuration),
                                        step: 0.5
                                    ) {
                                        Text("Начало")
                                    }
                                    .tint(Color.slooshAccent)
                                    .onChange(of: startTime) { _, newStart in
                                        if endTime - newStart > maxDuration {
                                            endTime = newStart + maxDuration
                                        }
                                        seekPreviewToStart()
                                    }

                                    Text(formatSeconds(startTime))
                                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                                        .foregroundStyle(.white)
                                        .frame(width: 48, alignment: .trailing)
                                }

                                // End Time Slider
                                HStack(spacing: 10) {
                                    Text("Конец")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.6))
                                        .frame(width: 55, alignment: .leading)

                                    Slider(
                                        value: $endTime,
                                        in: (startTime + minDuration)...(totalDuration > 0 ? totalDuration : startTime + maxDuration),
                                        step: 0.5
                                    ) {
                                        Text("Конец")
                                    }
                                    .tint(Color.slooshAccent)
                                    .onChange(of: endTime) { _, newEnd in
                                        if newEnd - startTime > maxDuration {
                                            startTime = max(0, newEnd - maxDuration)
                                        }
                                    }

                                    Text(formatSeconds(endTime))
                                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                                        .foregroundStyle(.white)
                                        .frame(width: 48, alignment: .trailing)
                                }
                            }
                            .padding(14)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .padding(.horizontal, 16)

                        // 3. Caption & Tags Input
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Подпись к моменту")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)

                            TextField("Напишите цитату или почему этот момент лучший...", text: $caption, axis: .vertical)
                                .lineLimit(2...4)
                                .font(.system(size: 15))
                                .foregroundStyle(.white)
                                .padding(12)
                                .background(Color.white.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                            // Quick tag chips
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
                                                .font(.system(size: 13, weight: .medium))
                                                .foregroundStyle(.white.opacity(0.85))
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(Color.white.opacity(0.08))
                                                .clipShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)

                        // 4. Movie Info Badge
                        HStack(spacing: 12) {
                            if let poster = posterPath, let url = URL(string: poster) {
                                AsyncCachedImage(url: url) {
                                    Color.white.opacity(0.1)
                                } content: { img in
                                    Image(uiImage: img)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } fallback: {
                                    Color.white.opacity(0.1)
                                }
                                .frame(width: 40, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(title)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)

                                if let s = season, let e = episode {
                                    Text("\(s) сезон, \(e) серия")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.6))
                                }

                                if let voice = translationName, !voice.isEmpty {
                                    Text(voice)
                                        .font(.system(size: 12, weight: .regular))
                                        .foregroundStyle(Color.slooshAccent)
                                        .lineLimit(1)
                                }
                            }

                            Spacer()
                        }
                        .padding(12)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.horizontal, 16)

                        // 5. Publish Button
                        Button {
                            publishMoment()
                        } label: {
                            HStack(spacing: 8) {
                                if isPublishing {
                                    ProgressView()
                                        .tint(.black)
                                } else {
                                    Image(systemName: "sparkles.tv.fill")
                                        .font(.system(size: 16, weight: .semibold))
                                    Text("Опубликовать в Моменты")
                                        .font(.system(size: 16, weight: .semibold))
                                }
                            }
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.slooshAccent)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .disabled(isPublishing)
                        .padding(.horizontal, 16)
                        .padding(.top, 6)
                        .padding(.bottom, 30)
                    }
                    .padding(.top, 16)
                }
            }
            .navigationTitle("Создать момент")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") {
                        dismiss()
                    }
                    .foregroundStyle(.white.opacity(0.8))
                }
            }
            .onAppear {
                setupPreviewPlayer()
            }
            .onDisappear {
                cleanupPlayer()
            }
        }
        .preferredColorScheme(.dark)
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Preview Video Card

    private var previewVideoCard: some View {
        ZStack {
            if let player = previewPlayer {
                VideoLayerView(player: player, pipController: $pipController, videoGravity: .resizeAspectFill)
                    .allowsHitTesting(false)
            } else {
                Color.black
                ProgressView()
                    .tint(.white)
            }

            // Overlay controls
            VStack {
                HStack {
                    Spacer()
                    Button {
                        isMuted.toggle()
                        previewPlayer?.isMuted = isMuted
                    } label: {
                        Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.glassPress)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .padding(10)
                }
                Spacer()
            }
        }
    }

    // MARK: - Playback Helpers

    private func setupPreviewPlayer() {
        guard let urlString = streamUrl, let url = URL(string: urlString) else { return }
        let playerItem = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: playerItem)
        player.isMuted = isMuted
        self.previewPlayer = player

        let startCM = CMTime(seconds: startTime, preferredTimescale: 600)
        player.seek(to: startCM, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            player.play()
        }

        // Loop observer
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak player] time in
            guard let player = player else { return }
            let currentSec = CMTimeGetSeconds(time)
            if currentSec >= self.endTime || currentSec < self.startTime {
                let sTime = CMTime(seconds: self.startTime, preferredTimescale: 600)
                player.seek(to: sTime, toleranceBefore: .zero, toleranceAfter: .zero)
            }
        }
    }

    private func seekPreviewToStart() {
        guard let player = previewPlayer else { return }
        let startCM = CMTime(seconds: startTime, preferredTimescale: 600)
        player.seek(to: startCM, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func cleanupPlayer() {
        if let observer = timeObserver, let player = previewPlayer {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
        previewPlayer?.pause()
        previewPlayer = nil
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
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        let user = authRepo.currentUser
        let authorId = user?.id ?? "guest_\(UIDevice.current.identifierForVendor?.uuidString ?? "user")"
        let authorName = (user?.displayName.isEmpty == false) ? user!.displayName : (user?.email.components(separatedBy: "@").first ?? "Зритель")
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
                ToastManager.shared.show("Момент успешно опубликован!", type: .success)
                onPublished?()
                dismiss()
            } catch {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                ToastManager.shared.show("Ошибка публикации момента", type: .error)
                isPublishing = false
            }
        }
    }
}
