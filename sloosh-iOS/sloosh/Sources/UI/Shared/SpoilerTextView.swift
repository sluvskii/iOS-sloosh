import SwiftUI

// MARK: - SpoilerTextView (frosted glass)

/// Текст под спойлером: размыт, накрыт стеклянной плиткой с мягким бликом
/// и бейджем «Спойлер». Тап раскрывает текст пружиной. Стейт живёт в блоке.
struct SpoilerTextView: View {
    let text: String
    var font: Font = .system(size: 14)
    var contentColor: Color = .white.opacity(0.85)
    var badgeSize: BadgeSize = .full

    enum BadgeSize {
        case full
        case preview
    }

    @State private var revealed = false

    var body: some View {
        Text(text)
            .font(font)
            .foregroundColor(revealed ? contentColor : .white.opacity(0.5))
            .lineLimit(badgeSize == .preview ? 1 : nil)
            .fixedSize(horizontal: false, vertical: true)
            .blur(radius: revealed ? 0 : 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay {
                if !revealed {
                    SpoilerGlassPlate()
                        .transition(.opacity)
                }
            }
            .overlay {
                if !revealed {
                    badge
                        .transition(.opacity.combined(with: .scale(scale: 0.94)))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard !revealed else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                    revealed = true
                }
            }
            .textSelection(.enabled)
            .accessibilityLabel(revealed ? text : "Скрытый спойлер. Нажмите, чтобы показать")
    }

    private var badge: some View {
        HStack(spacing: badgeSize == .full ? 5 : 4) {
            Image(systemName: "eye.slash.fill")
                .font(.system(size: badgeSize == .full ? 11 : 9, weight: .semibold))

            Text("Спойлер")
                .font(.system(size: badgeSize == .full ? 11.5 : 9.5, weight: .semibold))
        }
        .foregroundStyle(.white.opacity(0.95))
        .padding(.horizontal, badgeSize == .full ? 10 : 7)
        .frame(height: badgeSize == .full ? 26 : 20)
        .background(Capsule().fill(Color.black.opacity(0.4)))
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.6)
        )
        .shadow(color: .black.opacity(0.28), radius: 6, y: 2)
    }
}

// MARK: - Redacted Preview Block

/// Компактный «закрытый» блок для превью в секции на экране детали:
/// размытые полоски под тем же стеклом и мини-бейджем.
struct SpoilerRedactedView: View {
    var lines: Int = 2

    var body: some View {
        ZStack {
            SpoilerGlassPlate()

            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .fill(Color.white.opacity(0.2))
                    .frame(width: lines > 1 ? 190 : 150, height: 8)
                if lines > 1 {
                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 124, height: 8)
                }
            }
            .blur(radius: 2.5)
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 9, weight: .semibold))
                    Text("Спойлер")
                        .font(.system(size: 9.5, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.95))
                .padding(.horizontal, 7)
                .frame(height: 20)
                .background(Capsule().fill(Color.black.opacity(0.4)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.6))
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Glass Plate

/// Плитка «замороженного стекла»: мягкий градиентный блик сверху,
/// тонкая светлая кромка и лёгкая внутренняя тень. Никакой анимации —
/// спойлер должен выглядеть спокойно, а не как загрузка.
private struct SpoilerGlassPlate: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.white.opacity(0.055))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.10),
                                Color.white.opacity(0.015),
                                Color.black.opacity(0.04)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.26),
                                Color.white.opacity(0.07)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.7
                    )
            )
            .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
            .allowsHitTesting(false)
    }
}
