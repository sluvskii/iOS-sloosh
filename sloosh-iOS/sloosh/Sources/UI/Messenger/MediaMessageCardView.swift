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
                // Постер с градиентным наложением
                ZStack(alignment: .topLeading) {
                    if let posterUrl = media.posterUrl, !posterUrl.isEmpty {
                        AsyncCachedImage(urlString: posterUrl) {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.2))
                        } content: { image in
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        }
                        .frame(height: 150)
                        .clipped()
                    } else {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.2))
                            .frame(height: 150)
                    }

                    LinearGradient(
                        colors: [.black.opacity(0.4), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 50)

                    if let rating = media.rating, rating > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 9, weight: .bold))
                            Text(String(format: "%.1f", rating))
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundColor(.black)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.slooshAccent))
                        .padding(8)
                    }
                }

                // Инфо о фильме + кнопка просмотра в Sloosh
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
                        Text("Смотреть в Sloosh")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.slooshAccent))
                    .padding(.top, 4)
                }
                .padding(10)
            }
            .frame(width: 220)
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }
}
