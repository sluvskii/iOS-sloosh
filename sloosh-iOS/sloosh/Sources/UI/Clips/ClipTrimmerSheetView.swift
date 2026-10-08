import SwiftUI
import UIKit
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
    @State private var publishErrorMessage: String? = nil

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
        let resolvedTotal = totalDuration > 0 ? totalDuration : max(currentPlaybackTime + 60.0, 120.0)
        let defaultEnd = min(resolvedTotal, defaultStart + 30.0)
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

    private var maxSliderBound: Double {
        totalDuration > 0 ? totalDuration : max(currentPlaybackTime + 120.0, 300.0)
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // 1. Hero Artwork Card
                        heroArtworkCard
                            .frame(height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
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
                            VStack(spacing: 14) {
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
                                    )
                                    .tint(Color.slooshAccent)
                                    .onChange(of: startTime) { _, newStart in
                                        publishErrorMessage = nil
                                        if endTime - newStart > maxDuration {
                                            endTime = newStart + maxDuration
                                        }
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
                                        in: (startTime + minDuration)...maxSliderBound,
                                        step: 0.5
                                    )
                                    .tint(Color.slooshAccent)
                                    .onChange(of: endTime) { _, newEnd in
                                        publishErrorMessage = nil
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
                                .frame(width: 44, height: 64)
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

                        // 5. Error Banner (if any)
                        if let error = publishErrorMessage {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 15))
                                    .foregroundStyle(.red)
                                Text(error)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.red.opacity(0.9))
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer()
                            }
                            .padding(12)
                            .background(Color.red.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .padding(.horizontal, 16)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        }

                        // 6. Publish Button
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
                        .padding(.top, 4)
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
        }
        .presentationDetents([.large])
        .preferredColorScheme(.dark)
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Hero Artwork Card

    private var heroArtworkCard: some View {
        ZStack {
            if let backdrop = backdropPath ?? posterPath, let url = URL(string: backdrop) {
                AsyncCachedImage(url: url) {
                    Color.white.opacity(0.08)
                } content: { img in
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } fallback: {
                    Color.white.opacity(0.08)
                }
            } else {
                Color.white.opacity(0.08)
            }

            // Cinematic Dark Gradients
            LinearGradient(
                colors: [Color.black.opacity(0.2), Color.black.opacity(0.75)],
                startPoint: .top,
                endPoint: .bottom
            )

            // Center Info Overlay
            VStack(spacing: 8) {
                Spacer()

                if let logo = logoPath, let url = URL(string: logo) {
                    AsyncCachedImage(url: url) {
                        Text(title)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                    } content: { img in
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 44)
                    } fallback: {
                        Text(title)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                    }
                } else {
                    Text(title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.8), radius: 4)
                }

                // Timecode pill badge
                HStack(spacing: 6) {
                    Image(systemName: "scissors")
                        .font(.system(size: 12, weight: .semibold))
                    Text(formattedRange)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    Text("• \(Int(clipDuration)) сек")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(Color.slooshAccent)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.65))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
                .padding(.bottom, 14)
            }
            .padding(.horizontal, 16)
        }
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
