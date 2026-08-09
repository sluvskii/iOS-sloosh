import SwiftUI

public struct MediaMessageCardView: View {
    public let media: MediaCardPayload
    public var onOpenDetails: ((String) -> Void)?
    public var onPlayDirectly: ((MediaCardPayload) -> Void)?
    public var transitionNamespace: Namespace.ID?

    @State private var cardBgColor: Color = Color(white: 0.14)

    public init(
        media: MediaCardPayload,
        onOpenDetails: ((String) -> Void)? = nil,
        onPlayDirectly: ((MediaCardPayload) -> Void)? = nil,
        transitionNamespace: Namespace.ID? = nil
    ) {
        self.media = media
        self.onOpenDetails = onOpenDetails
        self.onPlayDirectly = onPlayDirectly
        self.transitionNamespace = transitionNamespace
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
                    .font(.system(size: 14, weight: .black))
                Text("Смотреть")
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
            // Постер и заголовок карточки — клик по ним открывает экран деталей (DetailsView)
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
                                    .fill(Color.white.opacity(0.1))
                                    .aspectRatio(2/3, contentMode: .fit)
                            } content: { image in
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(2/3, contentMode: .fit)
                                    .onAppear {
                                        if let avg = image.averageColor {
                                            let blended = avg.blended(with: .black, fraction: 0.65)
                                            withAnimation(.easeInOut(duration: 0.3)) {
                                                cardBgColor = Color(blended)
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

                        // Плашка рейтинга с Главного экрана (HomeView)
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

                    // Название и год
                    VStack(alignment: .leading, spacing: 2) {
                        Text(media.title)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(2)

                        if let year = media.year, !year.isEmpty {
                            Text(year)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
            .buttonStyle(.plain)

            // Белая кнопка "Смотреть" (открывает панель озвучек / запуск плеера напрямую)
            if let transitionNamespace {
                playButton
                    .matchedTransitionSource(id: media.mediaId, in: transitionNamespace)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)
            } else {
                playButton
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)
            }
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
