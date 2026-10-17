import SwiftUI

public struct MediaMessageCardView: View {
    public let media: MediaCardPayload
    public var onOpenDetails: ((String) -> Void)?
    public var onPlayDirectly: ((MediaCardPayload) -> Void)?

    @State private var cardBgColor: Color = Color(white: 0.14)

    public init(
        media: MediaCardPayload,
        onOpenDetails: ((String) -> Void)? = nil,
        onPlayDirectly: ((MediaCardPayload) -> Void)? = nil
    ) {
        self.media = media
        self.onOpenDetails = onOpenDetails
        self.onPlayDirectly = onPlayDirectly
    }

    private var effectiveDuration: Double? {
        if let d = media.duration, d > 0 {
            return d
        }
        if let end = media.endTime, let start = media.startTime, end > start {
            return end - start
        }
        return nil
    }

    private func formatTimecode(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }

    private var clipSubtitle: String? {
        if let s = media.season, let e = media.episode {
            if let t = media.translationName, !t.isEmpty {
                return "\(s) сезон, \(e) серия • \(t)"
            }
            return "\(s) сезон, \(e) серия"
        } else if let year = media.year, !year.isEmpty {
            return year
        }
        return nil
    }

    private var playButton: some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            if let onPlayDirectly = onPlayDirectly {
                onPlayDirectly(media)
            } else {
                onOpenDetails?(media.mediaId)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "play.fill")
                    .font(.system(size: 13, weight: .black))
                Text("Смотреть")
                    .font(.system(size: 14.5, weight: .heavy))
            }
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.94))
            )
            .glassEffect(in: Capsule())
        }
        .buttonStyle(.plain)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Постер и метаданные — клик открывает плеер момента или детали фильма
            Button {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                if media.isClip {
                    onPlayDirectly?(media)
                } else {
                    onOpenDetails?(media.mediaId)
                }
            } label: {
                VStack(alignment: .leading, spacing: 7) {
                    // Постер фильма / момента (соотношение сторон 2:3)
                    ZStack(alignment: .topLeading) {
                        if let posterUrl = media.posterUrl, !posterUrl.isEmpty {
                            AsyncCachedImage(urlString: posterUrl) {
                                Rectangle()
                                    .fill(Color.white.opacity(0.1))
                                    .aspectRatio(2/3, contentMode: .fit)
                            } content: { image in
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(2/3, contentMode: .fit)
                                    .onAppear {
                                        if let avg = image.averageColor {
                                            let blended = avg.blended(with: .black, fraction: 0.65)
                                            let newColor = Color(blended)
                                            if cardBgColor != newColor {
                                                cardBgColor = newColor
                                            }
                                        }
                                    }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        } else {
                            Rectangle()
                                .fill(Color.white.opacity(0.1))
                                .aspectRatio(2/3, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }

                        // Верхний бейдж: Момент ИЛИ рейтинг фильма
                        if media.isClip {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles.tv")
                                    .font(.system(size: 9.5, weight: .semibold))
                                Text("Момент")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3.5)
                            .glassEffect(.regular, in: Capsule())
                            .padding(7)

                            // Длительность в стандартном видео-таймкоде (напр. 10:00, 1:25, 0:45)
                            if let dur = effectiveDuration, dur > 0 {
                                VStack {
                                    Spacer()
                                    HStack {
                                        Spacer()
                                        Text(formatTimecode(dur))
                                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 5.5)
                                            .padding(.vertical, 2.5)
                                            .background(Color.black.opacity(0.72))
                                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                                            .padding(7)
                                    }
                                }
                            }
                        } else if let rating = media.rating, rating > 0 {
                            Text(String(format: "%.1f", rating))
                                .font(.system(size: 12, weight: .heavy))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.rating(rating))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .padding(8)
                        }
                    }

                    // Название и метаданные
                    VStack(alignment: .leading, spacing: 2.5) {
                        Text(media.title)
                            .font(.system(size: 14.5, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        if media.isClip {
                            if let sub = clipSubtitle, !sub.isEmpty {
                                Text(sub)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundColor(.white.opacity(0.6))
                                    .lineLimit(1)
                            }

                            if let caption = media.caption?.trimmingCharacters(in: .whitespacesAndNewlines), !caption.isEmpty {
                                Text("«\(caption)»")
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(.white.opacity(0.85))
                                    .italic()
                                    .lineLimit(2)
                                    .padding(.top, 1)
                            }
                        } else if let year = media.year, !year.isEmpty {
                            Text(year)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
            .buttonStyle(.plain)

            // Кнопка "Смотреть"
            playButton
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
        }
        .padding(8)
        .frame(width: 220)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(cardBgColor)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
    }
}
