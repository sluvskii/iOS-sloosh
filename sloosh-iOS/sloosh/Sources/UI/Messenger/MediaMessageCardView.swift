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
            VStack(alignment: .leading, spacing: 8) {
                // Постер с полным соотношением сторон 2:3 и плашкой рейтинга из HomeView
                ZStack(alignment: .topLeading) {
                    if let posterUrl = media.posterUrl, !posterUrl.isEmpty {
                        AsyncCachedImage(urlString: posterUrl) {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.15))
                                .aspectRatio(2/3, contentMode: .fit)
                        } content: { image in
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(2/3, contentMode: .fit)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    } else {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.15))
                            .aspectRatio(2/3, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    // Плашка рейтинга точь-в-точь с Главного экрана (HomeView)
                    if let rating = media.rating, rating > 0 {
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

                // Название фильма, год и нативная кнопка "Смотреть" с экрана деталей (DetailsView)
                VStack(alignment: .leading, spacing: 6) {
                    Text(media.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(2)

                    if let year = media.year, !year.isEmpty {
                        Text(year)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                    }

                    // Кнопка "Смотреть" точно в стиле DetailsView
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 14, weight: .black))
                        Text("Смотреть")
                            .font(.system(size: 15, weight: .heavy))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(Capsule().fill(Color.slooshAccent))
                    .glassEffect(in: Capsule())
                    .padding(.top, 4)
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
            }
            .padding(8)
            .frame(width: 220)
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
