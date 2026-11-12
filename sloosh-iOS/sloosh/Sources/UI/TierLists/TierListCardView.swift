import SwiftUI

/// Обложка тир-листа для сеток (Мои / Шаблоны / Популярные / профиль):
/// коллаж 2×2 из первых постеров + название + метаданные. Нативные цвета.
struct TierListCardView: View {
    let title: String
    let subtitle: String?
    let posterUrls: [String]
    var badge: String?
    var likesCount: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            cover
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            HStack(spacing: 5) {
                if let badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.orange, in: Capsule())
                }
                if let likes = likesCount, likes > 0 {
                    Label("\(likes)", systemImage: "heart.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var cover: some View {
        let posters = Array(posterUrls.prefix(4))
        Group {
            if posters.count >= 2 {
                let columns = [GridItem(.flexible(), spacing: 3), GridItem(.flexible(), spacing: 3)]
                LazyVGrid(columns: columns, spacing: 3) {
                    ForEach(Array(posters.prefix(4).enumerated()), id: \.offset) { _, url in
                        poster(url)
                            .frame(height: posters.count <= 2 ? 92 : 68)
                    }
                    if posters.count < 4 {
                        ForEach(0..<(4 - posters.count), id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(UIColor.tertiarySystemFill))
                                .frame(height: posters.count <= 2 ? 92 : 68)
                        }
                    }
                }
            } else if let first = posters.first {
                poster(first)
                    .frame(height: 190)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(UIColor.tertiarySystemFill))
                    Image(systemName: "list.star")
                        .font(.system(size: 26))
                        .foregroundStyle(.secondary)
                }
                .frame(height: 120)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(UIColor.separator).opacity(0.35), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func poster(_ urlString: String) -> some View {
        AsyncCachedImage(
            url: URL(string: urlString),
            placeholder: { Rectangle().fill(Color(UIColor.tertiarySystemFill)) },
            content: { image in
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            },
            fallback: { Rectangle().fill(Color(UIColor.tertiarySystemFill)) }
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
