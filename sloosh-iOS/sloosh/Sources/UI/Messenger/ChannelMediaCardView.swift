import SwiftUI

public struct ChannelMediaCardView: View {
    public let media: MediaCardPayload
    public var onOpenDetails: ((String) -> Void)?
    public var onPlayDirectly: ((MediaCardPayload) -> Void)?

    @State private var cardBgColor: Color = Color(white: 0.12)

    public init(
        media: MediaCardPayload,
        onOpenDetails: ((String) -> Void)? = nil,
        onPlayDirectly: ((MediaCardPayload) -> Void)? = nil
    ) {
        self.media = media
        self.onOpenDetails = onOpenDetails
        self.onPlayDirectly = onPlayDirectly
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Poster & metadata tap -> DetailsView
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onOpenDetails?(media.mediaId)
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    // 2:3 Poster with rating badge
                    ZStack(alignment: .topLeading) {
                        if let posterUrl = media.posterUrl, !posterUrl.isEmpty {
                            AsyncCachedImage(urlString: posterUrl) {
                                Rectangle()
                                    .fill(Color.white.opacity(0.08))
                                    .aspectRatio(2/3, contentMode: .fill)
                            } content: { image in
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(2/3, contentMode: .fill)
                                    .onAppear {
                                        if let avg = image.averageColor {
                                            let blended = avg.blended(with: .black, fraction: 0.70)
                                            let newColor = Color(blended)
                                            if cardBgColor != newColor {
                                                cardBgColor = newColor
                                            }
                                        }
                                    }
                            }
                            .frame(width: 80, height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        } else {
                            Rectangle()
                                .fill(Color.white.opacity(0.08))
                                .frame(width: 80, height: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        if let rating = media.rating, rating > 0 {
                            Text(String(format: "%.1f", rating))
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundColor(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.rating(rating))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .padding(4)
                        }
                    }

                    // Metadata details
                    VStack(alignment: .leading, spacing: 6) {
                        Text(media.title)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        HStack(spacing: 6) {
                            if let year = media.year, !year.isEmpty {
                                Text(year)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white.opacity(0.7))
                            }

                            Text(media.type.lowercased().contains("tv") ? "• Сериал" : "• Фильм")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white.opacity(0.5))
                        }

                        Spacer(minLength: 0)

                        HStack(spacing: 4) {
                            Text("Подробнее")
                                .font(.system(size: 12, weight: .semibold))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundColor(Color.slooshAccent)
                    }
                    .frame(height: 120)

                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)

            // Direct "Смотреть" button
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                if let onPlayDirectly = onPlayDirectly {
                    onPlayDirectly(media)
                } else {
                    onOpenDetails?(media.mediaId)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 13, weight: .black))
                    Text("Смотреть")
                        .font(.system(size: 15, weight: .heavy))
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.92))
                )
                .glassEffect(in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(cardBgColor)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
