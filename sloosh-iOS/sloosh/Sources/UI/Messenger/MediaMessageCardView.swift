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
                Image(systemName: media.isClip ? "sparkles.tv.fill" : "play.fill")
                    .font(.system(size: 14, weight: .black))
                Text(media.isClip ? "Смотреть момент" : "Смотреть")
                    .font(.system(size: 15, weight: .heavy))
            }
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.92))
            )
            .glassEffect(in: Capsule())
        }
        .buttonStyle(.plain)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Постер и заголовок карточки — клик по ним открывает плеер момента или детали фильма
            Button {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                if media.isClip {
                    onPlayDirectly?(media)
                } else {
                    onOpenDetails?(media.mediaId)
                }
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    // Постер или бэкдроп
                    ZStack(alignment: .topLeading) {
                        if let posterUrl = media.posterUrl, !posterUrl.isEmpty {
                            AsyncCachedImage(urlString: posterUrl) {
                                Rectangle()
                                    .fill(Color.white.opacity(0.1))
                                    .aspectRatio(media.isClip ? 16/9 : 2/3, contentMode: .fit)
                            } content: { image in
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(media.isClip ? 16/9 : 2/3, contentMode: .fill)
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
                                .aspectRatio(media.isClip ? 16/9 : 2/3, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }

                        // Бейдж момента ИЛИ рейтинг фильма
                        if media.isClip {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles.tv")
                                    .font(.system(size: 9, weight: .bold))
                                Text("МОМЕНТ")
                                    .font(.system(size: 9.5, weight: .black))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3.5)
                            .glassEffect(.regular, in: Capsule())
                            .padding(8)

                            if let dur = media.duration, dur > 0 {
                                VStack {
                                    Spacer()
                                    HStack {
                                        Spacer()
                                        Text("\(Int(dur.rounded())) сек")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2.5)
                                            .background(Color.black.opacity(0.7))
                                            .clipShape(Capsule())
                                            .padding(8)
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

                    // Название и мета
                    VStack(alignment: .leading, spacing: 3) {
                        Text(media.title)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(2)

                        if media.isClip {
                            if let caption = media.caption, !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(caption)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white.opacity(0.85))
                                    .lineLimit(2)
                            }

                            if let author = media.authorName, !author.isEmpty {
                                Text("от \(author)")
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundColor(.white.opacity(0.55))
                                    .lineLimit(1)
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

            // Кнопка "Смотреть" / "Смотреть момент"
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
