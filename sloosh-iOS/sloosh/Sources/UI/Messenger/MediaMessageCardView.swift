import SwiftUI

public struct MediaMessageCardView: View {
    public let media: MediaCardPayload
    public var onOpenDetails: ((String) -> Void)?

    public init(media: MediaCardPayload, onOpenDetails: ((String) -> Void)? = nil) {
        self.media = media
        self.onOpenDetails = onOpenDetails
    }

    public var body: some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            onOpenDetails?(media.mediaId)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                // Постер + плашка рейтинга
                ZStack(alignment: .topLeading) {
                    if let posterUrl = media.posterUrl, !posterUrl.isEmpty {
                        AsyncCachedImage(url: posterUrl) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.2))
                        }
                        .frame(height: 140)
                        .clipped()
                    } else {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.2))
                            .frame(height: 140)
                    }

                    if let rating = media.rating, rating > 0 {
                        Text(String(format: "%.1f", rating))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(Color.slooshAccent)
                            )
                            .padding(8)
                    }
                }

                // Инфо о фильме + кнопка просмотра
                VStack(alignment: .leading, spacing: 6) {
                    Text(media.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(2)

                    if let year = media.year, !year.isEmpty {
                        Text(year)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text("Смотреть")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(Color.slooshAccent)
                    )
                    .padding(.top, 4)
                }
                .padding(10)
            }
            .frame(width: 210)
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
